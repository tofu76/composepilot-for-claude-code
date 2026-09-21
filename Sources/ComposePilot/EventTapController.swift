import AppKit
import Carbon.HIToolbox

/// Enterキーのシステムレベル横取り本体。
///
/// 対象コントロール(VSCodeのAdd Commentダイアログ)にフォーカスがある間だけ、
/// 修飾キーなしのEnterを「送信されない」扱いにし、送信用の修飾キー+Enter
/// (既定は`Ctrl+Enter`、設定で変更可)を送信として扱う。
///
/// 重要な設計判断: IMEの変換合成状態はOS外部から見えないため、イベントを握りつぶして
/// 別イベントを合成するのではなく、元のkeyCodeを維持したままモディファイアフラグだけを
/// その場で書き換えて同じイベントを流す。これによりIME確定処理自体を温存する。
///
/// Shift付与で送信が抑止できることは、拡張機能のソース(`extension.js`に手書きで
/// 埋め込まれた計画プレビューwebview)で確認済み:
///
///     // Enter submits, Shift+Enter inserts newline
///     textarea.addEventListener('keydown', function(e) {
///       if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submitBtn.click(); }
///
/// `!e.shiftKey`のためShift付与では送信経路に入らない。またこのハンドラが`isComposing`を
/// 一切見ていないことが、IME変換確定Enterで送信されてしまう不具合の直接の原因である。
/// なお同ハンドラは`Shift`以外の修飾キーを区別しないため、`Ctrl+Enter`も`Cmd+Enter`も
/// 元から送信として機能する。下の修飾キー除去は挙動を変えないが、意図を明示しつつ
/// ハンドラ側の条件が将来変わった場合の保険として残している。送信キーを3種から選べるのも
/// この「Shift以外ならどれでも送信経路に入る」性質に基づく(`SubmitModifier`)。
final class EventTapController {
    static let shared = EventTapController()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    /// 実際にフラグを書き換えた回数(keyDown/keyUpの両方を数える)。
    /// 検証時に「本当に介入したのか」を後から確認するための唯一の手がかりになる。
    /// タップのコールバックは専用スレッドで動くためロックで保護する。
    private let counterLock = NSLock()
    private var _rewriteCount = 0

    var rewriteCount: Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return _rewriteCount
    }

    /// 判定対象とする修飾キー。`.maskNumericPad`や`.maskNonCoalesced`は
    /// テンキーEnter等で常時立つことがあるため、意図的に含めない。
    private static let modifierMask: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// タップのコールバックが参照する設定のスナップショット。
    ///
    /// コールバックはキー入力のホットパスにあり、処理が遅れるとタップが
    /// `.tapDisabledByTimeout`で無効化される。`UserDefaults`への問い合わせを
    /// 1イベントごとに行わず、設定変更時にだけ更新したキャッシュを読む。
    private struct Settings {
        var isEnabled: Bool
        var submitFlag: CGEventFlags
    }

    private let settingsLock = NSLock()
    private var _settings = Settings(isEnabled: true, submitFlag: SubmitModifier.default.flag)

    private var settings: Settings {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return _settings
    }

    /// 設定を読み直してキャッシュを更新する。起動時と設定変更時に呼ぶ。
    func reloadSettings() {
        let updated = Settings(
            isEnabled: ConfigStore.isEnabled(),
            submitFlag: ConfigStore.submitModifier().flag
        )
        settingsLock.lock()
        _settings = updated
        settingsLock.unlock()
    }

    private var configObserver: NSObjectProtocol?

    private init() {
        reloadSettings()
        configObserver = NotificationCenter.default.addObserver(
            forName: ConfigStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadSettings()
        }
    }

    /// イベントタップを開始する。権限不足等で開始できなかった場合は`false`を返す。
    ///
    /// 入力監視(Input Monitoring)の許可は**事前条件として要求しない**。理由:
    /// - CGEventTapはアクセシビリティ許可だけで作成できる環境があり、
    ///   `IOHIDCheckAccess`が未許可を返していてもタップが動く場合がある。
    /// - システム設定の「入力監視」には、アプリが実際にアクセスを試みるまで項目自体が
    ///   現れない。事前チェックで弾くと「設定に出てこないので許可できない、許可できない
    ///   ので開始できない」というデッドロックになる。
    ///
    /// したがって`CGEvent.tapCreate`の成否を唯一の判定材料とし、失敗した場合に初めて
    /// 入力監視を要求してシステム設定に項目を出す。
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard PermissionsManager.isAccessibilityTrusted(prompt: false) else {
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            let hasInputMonitoring = PermissionsManager.isInputMonitoringTrusted()
            NSLog(
                "ComposePilot: failed to create event tap (accessibility=granted, inputMonitoring=%@)",
                hasInputMonitoring ? "granted" : "not granted"
            )
            // 入力監視が原因の可能性があるため、ここで初めて要求する。
            // これによりシステム設定の「入力監視」にComposePilotの項目が現れる。
            if !hasInputMonitoring {
                PermissionsManager.requestInputMonitoringAccess()
            }
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source

        // メインスレッドのRunLoopモード変化(メニュー操作中等)でイベントを取りこぼさないよう、
        // 専用スレッド上の専用RunLoopで駆動する。
        let workerThread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource, let tap = self.tap else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        workerThread.name = "ComposePilot.EventTap"
        workerThread.start()
        isRunning = true
        NSLog(
            "ComposePilot: event tap started (inputMonitoring=%@)",
            PermissionsManager.isInputMonitoringTrusted() ? "granted" : "not granted"
        )
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let settings = self.settings
        guard settings.isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter else {
            return Unmanaged.passUnretained(event)
        }

        guard let targetPID = FocusTracker.shared.targetFocusedPID else {
            return Unmanaged.passUnretained(event)
        }

        // キャッシュが古い場合の保険として、イベントの宛先プロセスを確認する。
        // セッションレベルのタップでは宛先PIDが未設定(0)になることがあるため、
        // その場合のみキャッシュを信頼する。
        let eventTargetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if eventTargetPID != 0, eventTargetPID != targetPID {
            return Unmanaged.passUnretained(event)
        }

        var flags = event.flags
        let activeModifiers = flags.intersection(Self.modifierMask)

        if activeModifiers == settings.submitFlag {
            // 送信用の修飾キー(既定はCtrl)+ Enter = 明示的な送信
            // → その修飾キーを外し、素のEnterとして流す
            flags.remove(settings.submitFlag)
        } else if activeModifiers.isEmpty {
            // 修飾キーなしのEnter = 常に非送信(改行相当)として扱う
            flags.insert(.maskShift)
        } else {
            // 送信用以外の修飾キーが付いたEnterは一切書き換えず素通しする
            return Unmanaged.passUnretained(event)
        }

        event.flags = flags

        counterLock.lock()
        _rewriteCount += 1
        counterLock.unlock()

        return Unmanaged.passUnretained(event)
    }
}

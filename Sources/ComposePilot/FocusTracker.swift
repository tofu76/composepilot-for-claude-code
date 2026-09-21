import AppKit
import ApplicationServices

/// 「対象アプリのAdd Commentダイアログに現在フォーカスがあるか」を常時追跡し、
/// ロック付きの軽量キャッシュ(対象プロセスのPID)として保持する。
///
/// EventTapControllerのコールバックはこのキャッシュを読むだけにして、
/// キーイベント処理のホットパスでAX APIへの同期問い合わせを行わないようにする。
final class FocusTracker: NSObject {
    static let shared = FocusTracker()

    private let lock = NSLock()
    private var cachedTargetPID: pid_t?

    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var pollTimer: Timer?

    /// 検出状態が変化した時だけ(ポーリング毎ではなく)メインスレッドで呼ばれる。
    ///
    /// メニューを開くと自アプリがフロントになりVSCodeからフォーカスが外れるため、
    /// 検出状態はメニューの文字列では確認できない。メニューバーアイコンに常時反映させる
    /// ことで、VSCode側にフォーカスを置いたまま検出の成否を目視できるようにする。
    var onDetectionStateChanged: ((Bool) -> Void)?

    /// 直近に観測したフォーカス要素の要約(診断用)。
    ///
    /// 検出されないとき、「正しく対象外と判定した」のか「そもそもフォーカス要素を
    /// 取得できていない」のかは、判定結果(bool)だけでは区別できない。実際に何を見て
    /// いるかを残すことで切り分けられるようにする。UI変更で判定が壊れた際に、
    /// どの属性がどう変わったかを掴む手がかりにもなる。
    private var _lastFocusedDescriptor: String?

    var lastFocusedDescriptor: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastFocusedDescriptor
    }

    /// フォーカス要素の要約が変化した時だけメインスレッドで呼ばれる。
    var onFocusedDescriptorChanged: ((String) -> Void)?

    /// 対象コントロールにフォーカスがある場合のみ、そのプロセスのPIDを返す。
    var targetFocusedPID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return cachedTargetPID
    }

    private override init() {
        super.init()
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // 対象アプリの一覧が変わったら、いま前面にあるアプリを評価し直す。
        // これが無いと、設定でアプリを追加しても一度別アプリに切り替えるまで反映されない。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configChanged),
            name: ConfigStore.didChangeNotification,
            object: nil
        )
        refreshFrontmostApp()
    }

    @objc private func configChanged() {
        refreshFrontmostApp()
    }

    private func refreshFrontmostApp() {
        if let front = NSWorkspace.shared.frontmostApplication {
            handleAppActivated(front)
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        handleAppActivated(app)
    }

    private func handleAppActivated(_ app: NSRunningApplication) {
        teardownObserver()
        stopPolling()
        updateCache(nil)

        guard let bundleID = app.bundleIdentifier,
              ConfigStore.targetBundleIDs().contains(bundleID) else { return }

        setupObserver(pid: app.processIdentifier)
        // ChromiumのDOM内フォーカス移動はAXObserverが確実に発火しない既知の制約があるため、
        // 対象アプリがフロントの間だけ低頻度ポーリングでクロスチェックする。
        startPolling()
        refreshFocusState()
    }

    private func setupObserver(pid: pid_t) {
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon = refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.refreshFocusState()
        }

        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let obs = observer else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        // VSCode(Electron)はこれを設定するまでWebコンテンツのアクセシビリティツリーを
        // 生成せず、フォーカス要素を一切報告しない。反映は非同期だが、
        // ポーリングが繰り返し問い合わせるため自然に追いつく。
        AXAttributes.enableManualAccessibility(appElement)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            obs, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr
        )
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .commonModes)

        axObserver = obs
        observedPID = pid
    }

    private func teardownObserver() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .commonModes
            )
        }
        axObserver = nil
        observedPID = nil
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshFocusState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshFocusState() {
        guard let pid = observedPID else {
            updateDescriptor("(対象アプリがフロントではない)")
            updateCache(nil)
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        guard let focused = AXAttributes.element(appElement, kAXFocusedUIElementAttribute as String) else {
            updateDescriptor("(フォーカス要素を取得できない)")
            updateCache(nil)
            return
        }
        updateDescriptor(describe(focused))
        updateCache(ElementMatcher.matches(focused) ? pid : nil)
    }

    private func describe(_ element: AXUIElement) -> String {
        let fields = [
            "role=\(AXAttributes.string(element, kAXRoleAttribute as String) ?? "-")",
            "domID=\(AXAttributes.string(element, "AXDOMIdentifier") ?? "-")",
            "desc=\(AXAttributes.string(element, kAXDescriptionAttribute as String) ?? "-")",
            "placeholder=\(AXAttributes.string(element, "AXPlaceholderValue") ?? "-")",
        ]
        return fields.joined(separator: " ")
    }

    private func updateDescriptor(_ descriptor: String) {
        lock.lock()
        let changed = _lastFocusedDescriptor != descriptor
        _lastFocusedDescriptor = descriptor
        lock.unlock()

        // 0.4秒ポーリングなので、変化時のみ通知してファイル書き出しを人間の操作速度に抑える。
        if changed {
            onFocusedDescriptorChanged?(descriptor)
        }
    }

    private func updateCache(_ pid: pid_t?) {
        lock.lock()
        let changed = (cachedTargetPID != nil) != (pid != nil)
        cachedTargetPID = pid
        lock.unlock()

        // 0.4秒ポーリングなので、変化していない時に通知して再描画を走らせないようにする。
        if changed {
            onDetectionStateChanged?(pid != nil)
        }
    }
}

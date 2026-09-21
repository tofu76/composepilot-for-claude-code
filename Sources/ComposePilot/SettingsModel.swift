import AppKit
import Combine

/// 設定画面とファイル/UserDefaults側の橋渡し。
///
/// SwiftUIのバインディングから直接`ConfigStore`を触ると、値の反映と通知の発火が
/// ビューの各所に散らばる。ここに集約し、`ConfigStore`の各setterが発火する
/// 変更通知(`EventTapController`と`FocusTracker`が購読している)を必ず通す。
final class SettingsModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            ConfigStore.setEnabled(isEnabled)
        }
    }

    @Published var submitModifier: SubmitModifier {
        didSet {
            guard oldValue != submitModifier else { return }
            ConfigStore.setSubmitModifier(submitModifier)
        }
    }

    @Published private(set) var targetBundleIDs: [String]
    @Published private(set) var level2Keywords: [String]

    // MARK: - 診断用のライブ情報

    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var isInputMonitoringTrusted = false
    @Published private(set) var isTapRunning = false
    @Published private(set) var rewriteCount = 0
    @Published private(set) var focusedDescriptor = "(未観測)"
    @Published private(set) var focusLogTail = ""
    @Published private(set) var hasKnownGoodSignature = false

    private var refreshTimer: Timer?

    init() {
        isEnabled = ConfigStore.isEnabled()
        submitModifier = ConfigStore.submitModifier()
        targetBundleIDs = ConfigStore.targetBundleIDs()
        level2Keywords = ConfigStore.level2Keywords()
        refreshDiagnostics()
    }

    // MARK: - 対象アプリ

    func addTargetBundleID(_ bundleID: String) {
        var ids = targetBundleIDs
        ids.append(bundleID)
        ConfigStore.setTargetBundleIDs(ids)
        targetBundleIDs = ConfigStore.targetBundleIDs()
    }

    func removeTargetBundleIDs(at offsets: IndexSet) {
        var ids = targetBundleIDs
        ids.remove(atOffsets: offsets)
        ConfigStore.setTargetBundleIDs(ids)
        targetBundleIDs = ConfigStore.targetBundleIDs()
    }

    func resetTargetBundleIDs() {
        ConfigStore.setTargetBundleIDs(ConfigStore.defaultTargetBundleIDs)
        targetBundleIDs = ConfigStore.targetBundleIDs()
    }

    /// `.app`を選ばせて、そのバンドルIDを読み取って追加する。
    ///
    /// Cursor等のフォークのバンドルIDを推測で埋め込むと、間違っていた場合に
    /// ユーザー側で検証する手段がない。実物から読むのが確実。
    /// 戻り値は追加できなかった場合のエラーメッセージ。
    func addTargetByChoosingApp() -> String? {
        let panel = NSOpenPanel()
        panel.title = "対象に追加するアプリを選択"
        panel.message = "Claude Code拡張を動かしているエディタ(VS Code、そのフォーク等)を選んでください。"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            return "\(url.lastPathComponent) からバンドルIDを読み取れませんでした。"
        }
        if targetBundleIDs.contains(bundleID) {
            return "\(bundleID) はすでに対象に入っています。"
        }
        addTargetBundleID(bundleID)
        return nil
    }

    // MARK: - Level2キーワード

    func addLevel2Keyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !level2Keywords.contains(trimmed) else { return }
        var keywords = level2Keywords
        keywords.append(trimmed)
        ConfigStore.setLevel2Keywords(keywords)
        level2Keywords = ConfigStore.level2Keywords()
    }

    func removeLevel2Keywords(at offsets: IndexSet) {
        var keywords = level2Keywords
        keywords.remove(atOffsets: offsets)
        ConfigStore.setLevel2Keywords(keywords)
        level2Keywords = ConfigStore.level2Keywords()
    }

    func resetLevel2Keywords() {
        ConfigStore.setLevel2Keywords(ConfigStore.defaultLevel2Keywords)
        level2Keywords = ConfigStore.level2Keywords()
    }

    // MARK: - 既知良好シグネチャ

    func removeKnownGoodSignature() {
        ConfigStore.removeKnownGoodSignature()
        refreshDiagnostics()
    }

    // MARK: - 診断

    /// 設定画面が表示されている間だけ、1秒ごとに診断情報を更新する。
    /// 常時更新すると、画面を閉じている間もAX問い合わせのコストを払うことになる。
    func startDiagnosticsRefresh() {
        stopDiagnosticsRefresh()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshDiagnostics()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refreshDiagnostics()
    }

    func stopDiagnosticsRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshDiagnostics() {
        isAccessibilityTrusted = PermissionsManager.isAccessibilityTrusted(prompt: false)
        isInputMonitoringTrusted = PermissionsManager.isInputMonitoringTrusted()
        isTapRunning = EventTapController.shared.isRunning
        rewriteCount = EventTapController.shared.rewriteCount
        focusedDescriptor = FocusTracker.shared.lastFocusedDescriptor ?? "(未観測)"
        hasKnownGoodSignature = ConfigStore.hasKnownGoodSignature()
        focusLogTail = Self.readFocusLogTail(lines: 20)
    }

    /// `focus.log`の末尾を読む。
    ///
    /// なぜログを読むのか: 設定画面を開くと自アプリがフロントになり、VSCode側の
    /// コメントUIはフォーカスを失って閉じてしまう。つまり**対象のコメント欄を
    /// この画面からライブで観測することは原理的にできない**。そのため、画面を開く前に
    /// 何が観測されていたかをログから見る形にしている。
    private static func readFocusLogTail(lines: Int) -> String {
        let url = StatusReporter.focusLogURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "(まだ記録がありません)"
        }
        let all = content.split(separator: "\n", omittingEmptySubsequences: true)
        return all.suffix(lines).joined(separator: "\n")
    }

    /// 状態ファイルと同じ内容に、フォーカス履歴を添えてクリップボードへ入れる。
    func copyDiagnosticsToClipboard() {
        let report = """
        ComposePilot 診断情報
        version: \(Self.versionString)
        bundlePath: \(Bundle.main.bundlePath)
        accessibility: \(isAccessibilityTrusted ? "granted" : "NOT granted")
        inputMonitoring: \(isInputMonitoringTrusted ? "granted" : "NOT granted")
        eventTapRunning: \(isTapRunning)
        interceptionEnabled: \(isEnabled)
        submitModifier: \(submitModifier.displayName)
        targetBundleIDs: \(targetBundleIDs.joined(separator: ", "))
        level2Keywords: \(level2Keywords.joined(separator: ", "))
        hasKnownGoodSignature: \(hasKnownGoodSignature)
        rewriteCount: \(rewriteCount)
        focusedElement: \(focusedDescriptor)

        --- focus.log (末尾20行) ---
        \(focusLogTail)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

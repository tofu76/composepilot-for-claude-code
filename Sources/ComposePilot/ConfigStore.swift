import Foundation

enum ConfigStore {
    /// テストから隔離された`UserDefaults`インスタンスへ差し替えられるよう`var`にしている。
    /// 本番では`.standard`のまま。
    static var defaults: UserDefaults = .standard

    private enum Key {
        static let enabled = "ComposePilot.enabled"
        static let level2Keywords = "ComposePilot.level2Keywords"
        static let submitModifier = "ComposePilot.submitModifier"
        static let targetBundleIDs = "ComposePilot.targetBundleIDs"
        static let completedOnboarding = "ComposePilot.completedOnboarding"
        static let lastSeenBundleVersion = "ComposePilot.lastSeenBundleVersion"
    }

    /// 設定が変わったことを各所へ知らせる。`EventTapController`はこれを受けて
    /// ホットパス用のキャッシュを更新し、`FocusTracker`は監視対象を見直す。
    static let didChangeNotification = Notification.Name("ComposePilot.configDidChange")

    private static func notifyChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    // MARK: - ディレクトリ・ファイルパス

    static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return base.appendingPathComponent("ComposePilot", isDirectory: true)
    }

    static func inspectionsDirectory() -> URL {
        appSupportDirectory().appendingPathComponent("inspections", isDirectory: true)
    }

    static func knownGoodSignatureURL() -> URL {
        appSupportDirectory().appendingPathComponent("known_good_signature.json")
    }

    static func hasKnownGoodSignature() -> Bool {
        FileManager.default.fileExists(atPath: knownGoodSignatureURL().path)
    }

    /// 既知良好シグネチャを削除して組み込みルール(Level 0)の判定に戻す。
    /// 拡張機能が直った後などに、古いシグネチャが判定を上書きし続けるのを解除するため。
    static func removeKnownGoodSignature() {
        try? FileManager.default.removeItem(at: knownGoodSignatureURL())
    }

    // MARK: - on/off設定

    static func isEnabled() -> Bool {
        // 未設定時のデフォルトはON
        defaults.object(forKey: Key.enabled) == nil ? true : defaults.bool(forKey: Key.enabled)
    }

    static func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Key.enabled)
        notifyChange()
    }

    // MARK: - 初回起動時の案内

    static func hasCompletedOnboarding() -> Bool {
        defaults.bool(forKey: Key.completedOnboarding)
    }

    static func setCompletedOnboarding(_ value: Bool) {
        defaults.set(value, forKey: Key.completedOnboarding)
    }

    // MARK: - 起動時のバージョン遷移検知(初回/アップデート案内用)

    /// 最後に`announceLaunchIfNeeded()`が案内を出した時点の`CFBundleVersion`。
    /// 未設定(nil)は「まだ一度も案内していない」= 初回インストール扱いの合図になる。
    static func lastSeenBundleVersion() -> String? {
        defaults.string(forKey: Key.lastSeenBundleVersion)
    }

    static func setLastSeenBundleVersion(_ value: String) {
        defaults.set(value, forKey: Key.lastSeenBundleVersion)
    }

    /// `CFBundleShortVersionString`ではなく`CFBundleVersion`を使う。前者は人間向けの
    /// 表記揺れがあり得るが、後者はビルドのたびに必ずインクリメントされる規約
    /// (`Resources/Info.plist`参照)のため遷移検知の比較キーとして安定している。
    static func currentBundleVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// ユーザーに見せる表示用バージョン(例: "1.0.2")。`currentBundleVersion()`は
    /// 遷移検知専用の内部ビルド番号(例: "2")なので、通知文言などの表示には使わないこと。
    static func currentShortVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: - 送信として扱う修飾キー

    static func submitModifier() -> SubmitModifier {
        guard let raw = defaults.string(forKey: Key.submitModifier),
              let modifier = SubmitModifier(rawValue: raw) else {
            return .default
        }
        return modifier
    }

    static func setSubmitModifier(_ modifier: SubmitModifier) {
        defaults.set(modifier.rawValue, forKey: Key.submitModifier)
        notifyChange()
    }

    // MARK: - 対象アプリ

    /// 既定はVSCode本体のみ。Cursor等のフォークはバンドルIDが異なるうえ、
    /// このマシンには存在せず動作確認ができないため決め打ちで足さない。
    /// 設定画面から`.app`を選んで実際のバンドルIDを読み取って追加する。
    static let defaultTargetBundleIDs = ["com.microsoft.VSCode"]

    static func targetBundleIDs() -> [String] {
        guard let ids = defaults.stringArray(forKey: Key.targetBundleIDs) else {
            return defaultTargetBundleIDs
        }
        return ids
    }

    static func setTargetBundleIDs(_ ids: [String]) {
        // 重複と空文字を落とし、入力順は保つ。
        var seen = Set<String>()
        let cleaned = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        defaults.set(cleaned, forKey: Key.targetBundleIDs)
        notifyChange()
    }

    // MARK: - Level2フォールバック用キーワード

    /// 組み込みルール(Level0)と既知良好シグネチャ(Level1)のどちらも成立しない場合に、
    /// 祖先要素のtitle/description/placeholderにこれらの語のいずれかが含まれていれば
    /// 「Add Commentダイアログらしい」とみなす最後の保険。
    static func level2Keywords() -> [String] {
        (defaults.stringArray(forKey: Key.level2Keywords)) ?? defaultLevel2Keywords
    }

    static func setLevel2Keywords(_ keywords: [String]) {
        defaults.set(keywords, forKey: Key.level2Keywords)
        notifyChange()
    }

    /// 当初は`["Comment", "コメント", "Claude"]`という推測値だったが、実測のウインドウタイトルが
    /// `"Claude計画のコメント送信事象 — MyProject (ワークスペース)"`のように普通に"Claude"を含み、
    /// VSCode内の無関係なテキスト欄まで誤マッチしうることが分かったため、拡張機能のソースで
    /// 実際に使われている文字列のみに絞った。判定が壊れた場合の復旧手段はキーワードを緩める
    /// ことではなく、調査キットで実値を採取して`ElementMatcher`を更新することとする。
    static let defaultLevel2Keywords = [ElementMatcher.planCommentPlaceholder]
}

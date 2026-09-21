import Foundation

/// 今回の起動が「初回インストール」「アップデート後の初回起動」「変化なし」のどれかを表す。
///
/// `ConfigStore.lastSeenBundleVersion()`(前回案内を出した時点のバージョン)と
/// `ConfigStore.currentBundleVersion()`(今回のビルド)を比較するだけの純粋関数として
/// 切り出し、`UNUserNotificationCenter`や`NSPopover`に依存せずテストできるようにしている。
enum LaunchTransition: Equatable {
    case freshInstall
    case updated(from: String, to: String)
    case unchanged

    static func evaluate(stored: String?, current: String) -> LaunchTransition {
        guard let stored else { return .freshInstall }
        if stored == current { return .unchanged }
        return .updated(from: stored, to: current)
    }
}

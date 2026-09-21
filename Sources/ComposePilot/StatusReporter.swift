import Foundation

/// 現在の権限・稼働状態を1つのテキストファイルに書き出す。
///
/// なぜ必要か: このアプリは`LSUIElement`のメニューバー常駐で、状態を確認する手段が
/// メニューしかない。ところがメニューを開くと自アプリがフロントになり、VSCode側から
/// フォーカスが外れるため、検出状態はメニューでは確認できない。さらにTCCの許可状態は
/// アプリ自身のプロセスからしか正しく判定できず(ターミナルから起動したバイナリは
/// ターミナルの許可状態を見てしまう)、外部から調べる方法がない。
///
/// そのため、アプリ自身が状態をファイルに書き出す。検証作業ではこれを`cat`するだけで
/// 「許可は通っているか」「タップは動いているか」「何回書き換えたか」が確認できる。
enum StatusReporter {
    static func fileURL() -> URL {
        ConfigStore.appSupportDirectory().appendingPathComponent("status.txt")
    }

    static func focusLogURL() -> URL {
        ConfigStore.appSupportDirectory().appendingPathComponent("focus.log")
    }

    /// フォーカス要素の変化を追記する。`status.txt`は上書きなので履歴が残らないが、
    /// 「Add Commentダイアログを開いた瞬間に何が観測されたか」は後から辿りたい。
    static func appendFocusLog(_ descriptor: String) {
        let dir = ConfigStore.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = focusLogURL()
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(descriptor)\n"

        // 変化時のみの追記なので通常は増えないが、無制限に育たないよう上限を設ける。
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    static func write(note: String) {
        let formatter = ISO8601DateFormatter()
        let lines = [
            "timestamp: \(formatter.string(from: Date()))",
            "note: \(note)",
            "bundlePath: \(Bundle.main.bundlePath)",
            "pid: \(ProcessInfo.processInfo.processIdentifier)",
            "accessibility: \(PermissionsManager.isAccessibilityTrusted(prompt: false) ? "granted" : "NOT granted")",
            "inputMonitoring: \(PermissionsManager.isInputMonitoringTrusted() ? "granted" : "NOT granted")",
            "eventTapRunning: \(EventTapController.shared.isRunning)",
            "interceptionEnabled: \(ConfigStore.isEnabled())",
            "rewriteCount: \(EventTapController.shared.rewriteCount)",
            "hasKnownGoodSignature: \(ConfigStore.hasKnownGoodSignature())",
            "focusedElement: \(FocusTracker.shared.lastFocusedDescriptor ?? "(未観測)")",
        ]

        let dir = ConfigStore.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").appending("\n").write(
            to: fileURL(), atomically: true, encoding: .utf8
        )
    }
}

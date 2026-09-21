import AppKit
import Foundation

/// `--inspect`: GUIを起動せず、対象アプリのフォーカス中要素を1回だけ調査して
/// JSONを標準出力に書き出すヘッドレスモード(スパイク作業やメンテナンス時の確認用)。
///
///   --inspect                 設定された対象アプリの先頭(既定はVSCode)を調査する
///   --inspect --delay 5       5秒待ってから調査する(Add Commentダイアログを開く時間を作る)
///   --inspect --frontmost     フロントアプリを対象にする(対象アプリ以外を調べたい場合)
///   --inspect --bundle-id X   バンドルIDを直接指定して調査する
if CommandLine.arguments.contains("--inspect") {
    guard PermissionsManager.isAccessibilityTrusted(prompt: true) else {
        FileHandle.standardError.write(
            "アクセシビリティ許可がありません。システム設定で許可してから再実行してください。\n".data(using: .utf8)!
        )
        exit(1)
    }

    let arguments = CommandLine.arguments

    func explicitBundleID() -> String? {
        guard let index = arguments.firstIndex(of: "--bundle-id"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    let target: InspectionTarget
    if arguments.contains("--frontmost") {
        target = .frontmost
    } else if let bundleID = explicitBundleID() {
        target = .bundleID(bundleID)
    } else {
        target = ElementInspector.defaultTarget
    }

    if let delayIndex = arguments.firstIndex(of: "--delay"),
       delayIndex + 1 < arguments.count,
       let delay = TimeInterval(arguments[delayIndex + 1]) {
        FileHandle.standardError.write(
            "\(Int(delay))秒後に調査します。対象のダイアログを開いてください...\n".data(using: .utf8)!
        )
        Thread.sleep(forTimeInterval: delay)
    }

    let snapshot = ElementInspector.captureFocusedElementChain(target: target)
    if let data = ElementInspector.encode(snapshot), let json = String(data: data, encoding: .utf8) {
        print(json)
    }
    exit(0)
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

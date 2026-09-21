import AppKit
import SwiftUI

/// 設定ウィンドウ。
///
/// SwiftUIの`Settings`シーンは`App`ライフサイクルでしか使えず、このアプリは
/// `NSApplication` + `AppDelegate`構成なので、`NSHostingView`を載せた
/// `NSWindow`を自前で持つ。`LSUIElement`(Dockに出ないエージェント)のため、
/// 表示のたびに明示的にアプリをアクティブにしないと最前面に出てこない。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let model = SettingsModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ComposePilot for Claude Code"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使用しない")
    }

    func show() {
        // 設定値は外部(メニューバーのトグル等)からも変わりうるので、開く度に読み直す。
        model.refreshDiagnostics()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

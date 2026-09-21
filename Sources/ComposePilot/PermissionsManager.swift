import AppKit
import ApplicationServices
import IOKit.hid

enum PermissionsManager {
    /// アクセシビリティ許可の有無を確認する。`prompt: true` の場合、未許可なら
    /// システム側の許可ダイアログを表示させる。
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [key: prompt]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 入力監視(Input Monitoring)許可の有無を確認する。CGEventTapでキーイベントを
    /// 傍受するために必要(macOS 10.15+)。
    static func isInputMonitoringTrusted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 未許可の場合、初回はシステムのダイアログを表示させる。既に拒否済みの場合は
    /// ダイアログが出ないため、その場合は`openInputMonitoringSettings()`で誘導する。
    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

import Foundation
import ServiceManagement

/// ログイン時起動の登録・解除(macOS 13+の`SMAppService`を使用)。
enum LoginItemManager {
    static func isRegistered() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setRegistered(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ComposePilot: login item registration failed: \(error)")
        }
    }
}

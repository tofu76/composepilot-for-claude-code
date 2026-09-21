import UserNotifications

/// 初回インストール/アップデート直後にメニューバーへの追加を知らせる通知バナー。
///
/// `UNUserNotificationCenterDelegate`を実装しているのは、フォアグラウンド中の通知は
/// 既定では`willPresent`で何も返さないとバナー表示が抑制されるため。ComposePilotは
/// `LSUIElement`アプリで常にフォアグラウンド概念が薄く、通知を出したい瞬間はまさに
/// 起動直後(=フォアグラウンド)なので、明示的に`.banner`/`.sound`を返す必要がある。
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {}

    func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion(granted)
                }
            default:
                completion(false)
            }
        }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // trigger無し(nil) = 即時配信。日時指定や繰り返しは不要な一度きりの案内のため。
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

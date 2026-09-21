import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()
    private var permissionRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.setup()
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // 初回起動時と、許可が無い状態での起動時は案内を出す。
        //
        // 以前はここでシステムの許可ダイアログ(`prompt: true`)と入力監視の要求を
        // 出していたが、どちらもやめた。前者は「何をするアプリなのか」を説明しないまま
        // キー入力の許可を求めることになり、後者は**そもそも不要**な許可を要求して
        // ユーザーを混乱させる(アクセシビリティだけでイベントタップは作成できる)。
        // 説明は案内画面に任せ、そこからシステム設定へ誘導する。
        OnboardingWindowController.shared.showIfNeeded()

        FocusTracker.shared.start()
        startEventTapWhenPermitted()
    }

    /// TCCの許可付与は通知で検知できないため、開始できるまでポーリングで再試行する。
    /// これがないと、ユーザーがシステム設定で許可してもアプリ再起動まで無反応になる。
    private func startEventTapWhenPermitted() {
        if EventTapController.shared.start() {
            StatusReporter.write(note: "event tap started at launch")
            announceLaunchIfNeeded()
            return
        }
        StatusReporter.write(note: "waiting for permissions")

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
            if EventTapController.shared.start() {
                timer.invalidate()
                self?.permissionRetryTimer = nil
                StatusReporter.write(note: "event tap started after retry")
                // 案内画面が許可待ちで止まっている場合、ここが唯一の「許可された」検知点。
                // TCCの付与はシステムから通知されないため、このポーリングに相乗りする。
                OnboardingWindowController.shared.notifyPermissionGranted()
                self?.announceLaunchIfNeeded()
            } else {
                StatusReporter.write(note: "waiting for permissions")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionRetryTimer = timer
    }

    /// メニューバーに追加された/更新されたことを、初回インストール・アップデート直後の
    /// 起動でのみ1回だけ知らせる。イベントタップが実際に動き出して初めて「使える状態に
    /// なった」と言えるため、`startEventTapWhenPermitted()`の成功パス(即時成功・
    /// 許可待ちリトライ後の成功のいずれも)から呼ぶ。
    private func announceLaunchIfNeeded() {
        let current = ConfigStore.currentBundleVersion()
        let transition = LaunchTransition.evaluate(
            stored: ConfigStore.lastSeenBundleVersion(), current: current
        )

        let body: String
        switch transition {
        case .freshInstall:
            body = "ComposePilotがメニューバーに追加されました。"
        case .updated:
            body = "ComposePilotがv\(ConfigStore.currentShortVersion())に更新されました。"
        case .unchanged:
            return
        }

        statusItemController.showSpotlight(text: body)
        NotificationManager.shared.requestAuthorizationIfNeeded { granted in
            guard granted else { return }
            DispatchQueue.main.async {
                NotificationManager.shared.notify(title: "ComposePilot", body: body)
            }
        }
        ConfigStore.setLastSeenBundleVersion(current)
    }
}

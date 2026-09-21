import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()
    private var permissionRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.setup()

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
            } else {
                StatusReporter.write(note: "waiting for permissions")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionRetryTimer = timer
    }
}

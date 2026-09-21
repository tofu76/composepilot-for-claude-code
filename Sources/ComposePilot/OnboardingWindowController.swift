import AppKit
import SwiftUI

/// 初回起動時の案内。
///
/// 従来は許可が無いと何の説明もなくシステム設定が開くだけで、「なぜこのアプリに
/// キー入力の許可が要るのか」がユーザーに伝わらなかった。配布するなら、何をする
/// アプリで、なぜアクセシビリティ許可が要るのかを最初に説明する必要がある。
final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private let model = OnboardingModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ComposePilot へようこそ"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使用しない")
    }

    /// 初回起動時、または許可が無い状態で起動したときに表示する。
    /// `force`が真なら、完了済みでも表示する(設定画面からの再表示用)。
    func showIfNeeded(force: Bool = false) {
        let needsPermission = !PermissionsManager.isAccessibilityTrusted(prompt: false)
        guard force || !ConfigStore.hasCompletedOnboarding() || needsPermission else { return }
        show(force: force)
    }

    func show(force: Bool = false) {
        if force { model.restart() }
        model.refreshPermissionState()
        // `applicationDidFinishLaunching`から同期的に呼ぶと、まだ自アプリが
        // アクティブ化を受け付けられる状態になっておらず`NSApp.activate`が
        // 無視され、ウインドウは生成されるのに最前面に来ない(他アプリの裏に
        // 隠れたまま)ことがある。次のランループへ回すことで確実に前面化する。
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.showWindow(nil)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 許可の付与を検知したら画面を先へ進める。
    /// `AppDelegate`が既に2秒間隔で再試行しているので、その経路から通知してもらう。
    func notifyPermissionGranted() {
        model.refreshPermissionState()
    }
}

// MARK: - モデル

final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case whatItDoes
        case permission
        case done
    }

    @Published var step: Step = .whatItDoes
    @Published private(set) var isAccessibilityTrusted = false
    @Published var launchAtLogin: Bool
    @Published var submitModifier: SubmitModifier = ConfigStore.submitModifier()

    init() {
        // 完了フラグが立っていない新規インストールの初回表示だけ、ここでONを既定にして
        // 即座に登録する。再表示(設定画面の「案内を再表示」、または許可待ちのまま
        // 再起動した場合)では、ユーザーが既に選んだ実際の登録状態をそのまま使い、
        // 勝手にONへ戻さない。
        if ConfigStore.hasCompletedOnboarding() {
            launchAtLogin = LoginItemManager.isRegistered()
        } else {
            launchAtLogin = true
            LoginItemManager.setRegistered(true)
        }

        refreshPermissionState()
        // 許可済みで起動した場合は許可のステップを飛ばす。
        if isAccessibilityTrusted, ConfigStore.hasCompletedOnboarding() {
            step = .done
        }
    }

    func restart() {
        step = .whatItDoes
    }

    /// 「次へ」から許可ステップへ進む。ここで即座に再判定しないと、既に許可済みの
    /// 状態(例: 同じ署名・バンドルIDで以前に許可済みの環境での再インストール)で
    /// 進んだ場合に、次の判定機会が来るまで(`AppDelegate`の2秒ポーリング。しかも
    /// 許可済みだとイベントタップが即座に起動して通知経路自体が動かない)画面が
    /// 止まって見えてしまう。
    func advanceToPermissionStep() {
        step = .permission
        refreshPermissionState()
    }

    func refreshPermissionState() {
        let trusted = PermissionsManager.isAccessibilityTrusted(prompt: false)
        isAccessibilityTrusted = trusted
        // 許可の付与を待っている最中に許可されたら、そのまま完了へ進める。
        if trusted, step == .permission {
            step = .done
        }
    }

    func complete() {
        ConfigStore.setCompletedOnboarding(true)
    }
}

// MARK: - ビュー

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.step {
            case .whatItDoes: whatItDoesStep
            case .permission: permissionStep
            case .done: doneStep
            }
        }
        .padding(24)
        .frame(width: 520, height: 420, alignment: .topLeading)
    }

    private var whatItDoesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ComposePilot for Claude Code").font(.title2).bold()
            Text("""
                Claude Code(VS Code拡張)の計画レビューで、本文を選択して「Add Comment」を\
                押すと出るコメント欄があります。ここに日本語を入力すると、**かな漢字変換を\
                確定するためのEnterが「送信」として扱われ、変換途中のテキストがそのまま\
                送信されてしまいます。**
                """)
            Text("このアプリは、その欄にフォーカスがある間だけEnterの扱いを変えます。")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Enter").bold().gridColumnAlignment(.trailing)
                    Text("送信しない(変換の確定、または改行)")
                }
                GridRow {
                    Text("Ctrl+Enter").bold().gridColumnAlignment(.trailing)
                    Text("送信する")
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("他のアプリや、VS Codeの他の入力欄には一切影響しません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Spacer()
                Button("次へ") { model.advanceToPermissionStep() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("アクセシビリティの許可が必要です").font(.title2).bold()
            Text("""
                Enterキーの扱いを変えるために、macOSの「アクセシビリティ」の許可が要ります。\
                この許可で、キーイベントに付いている修飾キーの情報だけを書き換えます。
                """)
            Text("""
                **「入力監視」の許可は不要です。** システム設定の入力監視の一覧に\
                ComposePilotが出てこなくても問題ありません。
                """)
                .font(.callout)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("""
                手順: 下のボタンで設定を開き、一覧の「ComposePilot for Claude Code」を\
                オンにしてください。許可されると自動で次に進みます。
                """)
                .font(.callout)

            HStack(spacing: 8) {
                if model.isAccessibilityTrusted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("許可されています")
                } else {
                    ProgressView().controlSize(.small)
                    Text("許可を待っています...").foregroundStyle(.secondary)
                }
            }

            Spacer()
            HStack {
                Button("戻る") { model.step = .whatItDoes }
                Spacer()
                Button("アクセシビリティ設定を開く") {
                    PermissionsManager.openAccessibilitySettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("準備ができました").font(.title2).bold()
            Text("""
                メニューバーのアイコンで状態が分かります。コメント欄を検出している間は\
                アイコンが塗りつぶしに変わります。
                """)
            Text("""
                **メニューを開くとComposePilotが前面になり、コメントUIが閉じて下書きが消えます。**\
                ダイアログを開いている間はメニューバーをクリックしないでください。
                """)
                .font(.callout)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Toggle("ログイン時に起動する", isOn: $model.launchAtLogin)
                .onChange(of: model.launchAtLogin) { newValue in
                    LoginItemManager.setRegistered(newValue)
                    model.launchAtLogin = LoginItemManager.isRegistered()
                }
            Text("常用するならオンにしてください。オフのままだと再起動後に止まります。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("送信に使うキー")
                Picker("", selection: $model.submitModifier) {
                    ForEach(SubmitModifier.allCases, id: \.self) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: model.submitModifier) { newValue in
                    ConfigStore.setSubmitModifier(newValue)
                }
            }
            Text("設定画面の「動作」タブからいつでも変更できます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Spacer()
                Button("はじめる") {
                    model.complete()
                    OnboardingWindowController.shared.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

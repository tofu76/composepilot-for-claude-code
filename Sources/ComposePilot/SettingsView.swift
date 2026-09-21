import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            BehaviorSettingsTab(model: model)
                .tabItem { Label("動作", systemImage: "keyboard") }
            TargetAppsSettingsTab(model: model)
                .tabItem { Label("対象アプリ", systemImage: "app.badge") }
            MatchingSettingsTab(model: model)
                .tabItem { Label("判定", systemImage: "scope") }
            DiagnosticsSettingsTab(model: model)
                .tabItem { Label("診断", systemImage: "stethoscope") }
            GeneralSettingsTab(model: model)
                .tabItem { Label("一般", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 460)
        .onAppear { model.startDiagnosticsRefresh() }
        .onDisappear { model.stopDiagnosticsRefresh() }
    }
}

// MARK: - 動作

private struct BehaviorSettingsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Enterの横取りを有効にする", isOn: $model.isEnabled)
                Text("無効にすると、このアプリは常駐したままキーイベントを一切書き換えません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("送信に使うキー", selection: $model.submitModifier) {
                    ForEach(SubmitModifier.allCases, id: \.self) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("""
                    コメント欄では、修飾キーなしのEnterは常に「送信しない」(IMEの変換確定、\
                    または改行)になります。送信したいときはここで選んだキーを押します。
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("書き換えの内容") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Enter").gridColumnAlignment(.trailing)
                        Text("→ Shiftを付与 → 送信されない")
                    }
                    GridRow {
                        Text(model.submitModifier.displayName).gridColumnAlignment(.trailing)
                        Text("→ 修飾キーを除去 → 送信")
                    }
                    GridRow {
                        Text("その他の組み合わせ").gridColumnAlignment(.trailing)
                        Text("→ 書き換えない(素通し)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 対象アプリ

private struct TargetAppsSettingsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var selection = Set<String>()
    @State private var manualEntry = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ここに挙げたアプリが前面にあるときだけ、コメント欄を探します。")
                .font(.callout)

            List(selection: $selection) {
                ForEach(model.targetBundleIDs, id: \.self) { bundleID in
                    Text(bundleID).font(.system(.body, design: .monospaced))
                }
                .onDelete { model.removeTargetBundleIDs(at: $0) }
            }
            .frame(minHeight: 140)

            HStack {
                Button("アプリを選んで追加...") {
                    message = model.addTargetByChoosingApp()
                }
                Button("選択を削除") {
                    let offsets = IndexSet(
                        model.targetBundleIDs.enumerated()
                            .filter { selection.contains($0.element) }
                            .map(\.offset)
                    )
                    guard !offsets.isEmpty else { return }
                    model.removeTargetBundleIDs(at: offsets)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button("既定に戻す") {
                    model.resetTargetBundleIDs()
                    selection.removeAll()
                }
            }

            HStack {
                TextField("バンドルIDを直接入力", text: $manualEntry)
                    .font(.system(.body, design: .monospaced))
                Button("追加") {
                    let trimmed = manualEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    model.addTargetBundleID(trimmed)
                    manualEntry = ""
                }
                .disabled(manualEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }

            Text("""
                VS Codeのフォーク(Cursor、VS Code Insiders、Windsurf等)は、バンドルIDが\
                本体と異なります。推測を避けるため既定には入れていません。「アプリを選んで追加」で\
                実物から読み取ってください。**これらのフォークでの動作は未検証です。**
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - 判定

private struct MatchingSettingsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var newKeyword = ""
    @State private var diffText: String?

    var body: some View {
        Form {
            Section("Level 0: 組み込みルール(既定の主判定)") {
                LabeledContent("AXDOMIdentifier") {
                    Text(ElementMatcher.planCommentDOMIdentifier)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("placeholder") {
                    Text(ElementMatcher.planCommentPlaceholder)
                        .font(.system(.body, design: .monospaced))
                }
                Text("""
                    拡張機能の計画プレビューは手書きのHTMLテンプレートなので、バンドラが付ける\
                    ハッシュ付きクラス名と違ってこの値はビルドごとに変わりません。\
                    拡張機能の更新で変わった場合は、診断タブでいま観測されている値を確認できます。
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Level 1: 既知良好シグネチャ(組み込みルールを上書き)") {
                if model.hasKnownGoodSignature {
                    LabeledContent("状態") { Text("保存済み(組み込みルールより優先されます)") }
                    HStack {
                        Button("直近の調査結果との差分を確認") {
                            diffText = ElementInspector.diffAgainstKnownGood()
                        }
                        Button("削除して組み込みルールに戻す") {
                            model.removeKnownGoodSignature()
                            diffText = nil
                        }
                    }
                    if let diffText {
                        ScrollView {
                            Text(diffText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                } else {
                    LabeledContent("状態") { Text("未保存(組み込みルールで判定中)") }
                    Text("""
                        判定が壊れたときは、メニューバーの「5秒後に調査」でコメント欄を採取し、\
                        「現在の要素を既知良好として保存」でここに登録します。
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Level 2: 祖先要素のキーワード一致(最後の保険)") {
                ForEach(model.level2Keywords, id: \.self) { keyword in
                    Text(keyword).font(.system(.body, design: .monospaced))
                }
                .onDelete { model.removeLevel2Keywords(at: $0) }

                HStack {
                    TextField("キーワードを追加", text: $newKeyword)
                    Button("追加") {
                        model.addLevel2Keyword(newKeyword)
                        newKeyword = ""
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("既定に戻す") { model.resetLevel2Keywords() }
                }

                Text("""
                    広い語(「Claude」「コメント」等)を入れると、ウインドウタイトル経由で\
                    エディタや統合ターミナルの入力欄まで誤って一致します。追加は慎重に。
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 診断

private struct DiagnosticsSettingsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var inspectionMessage: String?

    private static let inspectionDelaySeconds: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("アクセシビリティ許可")
                    Text(model.isAccessibilityTrusted ? "許可済み" : "未許可")
                        .foregroundStyle(model.isAccessibilityTrusted ? .green : .red)
                }
                GridRow {
                    Text("入力監視の許可")
                    Text(model.isInputMonitoringTrusted ? "許可済み" : "未許可(このアプリには不要)")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("イベントタップ")
                    Text(model.isTapRunning ? "稼働中" : "停止中")
                        .foregroundStyle(model.isTapRunning ? .green : .red)
                }
                GridRow {
                    Text("書き換え回数")
                    Text("\(model.rewriteCount)回")
                }
                GridRow {
                    Text("直近のフォーカス要素")
                    Text(model.focusedDescriptor)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Divider()

            Text("フォーカス要素の履歴(focus.log の末尾)")
                .font(.headline)
            ScrollView {
                Text(model.focusLogTail)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))

            Text("""
                この画面を開くとComposePilotが前面になるため、VS Code側のコメントUIは\
                フォーカスを失って閉じます。**コメント欄をこの画面からライブで観測することはできません。**\
                開く前に観測された内容が上のログに残ります。
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("\(Int(Self.inspectionDelaySeconds))秒後に調査") { runDelayedInspection() }
                Button("診断情報をコピー") { model.copyDiagnosticsToClipboard() }
                Spacer()
                Button("保存先を開く") {
                    NSWorkspace.shared.open(ConfigStore.appSupportDirectory())
                }
            }

            if let inspectionMessage {
                Text(inspectionMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    /// 調査のあいだにVS Codeへ戻ってダイアログを開けるよう、実行を遅らせる。
    private func runDelayedInspection() {
        inspectionMessage = "\(Int(Self.inspectionDelaySeconds))秒後に調査します。VS Codeでコメント欄を開いてください..."
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.inspectionDelaySeconds) {
            guard let url = ElementInspector.runInspectionAndSave() else {
                inspectionMessage = "調査結果の保存に失敗しました。"
                return
            }
            let count = ElementInspector.lastSnapshot?.elements.count ?? 0
            inspectionMessage = count > 0
                ? "調査しました(\(count)階層)。クリップボードにもコピー済み: \(url.lastPathComponent)"
                : "フォーカス要素を取得できませんでした。対象アプリが前面にあるか確認してください。"
            model.refreshDiagnostics()
        }
    }
}

// MARK: - 一般

private struct GeneralSettingsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var launchAtLogin = LoginItemManager.isRegistered()

    var body: some View {
        Form {
            Section {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItemManager.setRegistered(newValue)
                        // 登録に失敗した場合に表示が実態とずれないよう、実際の状態で描き直す。
                        launchAtLogin = LoginItemManager.isRegistered()
                    }
            }

            Section("許可") {
                LabeledContent("アクセシビリティ") {
                    Text(model.isAccessibilityTrusted ? "許可済み" : "未許可")
                        .foregroundStyle(model.isAccessibilityTrusted ? .green : .red)
                }
                Button("アクセシビリティ設定を開く") {
                    PermissionsManager.openAccessibilitySettings()
                }
                Text("入力監視の許可は不要です(アクセシビリティだけでキーイベントを扱えます)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("使い方の案内を再表示") {
                    OnboardingWindowController.shared.show(force: true)
                }
                LabeledContent("バージョン") { Text(SettingsModel.versionString) }
            }
        }
        .formStyle(.grouped)
    }
}

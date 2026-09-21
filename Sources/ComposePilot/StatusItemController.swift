import AppKit

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var statusInfoItem: NSMenuItem?
    private var enabledToggleItem: NSMenuItem?
    private var configObserver: NSObjectProtocol?

    private static let delayedInspectionSeconds: TimeInterval = 5

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self

        let info = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        statusInfoItem = info

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(
            title: "横取りを有効にする",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        menu.addItem(enabledItem)
        enabledToggleItem = enabledItem

        let settingsItem = NSMenuItem(
            title: "設定...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // 調査系はメニューに残す。設定画面を開くと自アプリが前面になり、
        // VS Code側のコメントUIが閉じてしまうため、「開く前に仕掛けておく」操作は
        // 画面を開かずに実行できる必要がある。
        let delayedInspectItem = NSMenuItem(
            title: "\(Int(Self.delayedInspectionSeconds))秒後に調査(ダイアログを開く時間を作る)",
            action: #selector(inspectFocusedElementAfterDelay),
            keyEquivalent: ""
        )
        delayedInspectItem.target = self
        menu.addItem(delayedInspectItem)

        let saveKnownGoodItem = NSMenuItem(
            title: "現在の要素を既知良好として保存",
            action: #selector(saveAsKnownGood),
            keyEquivalent: ""
        )
        saveKnownGoodItem.target = self
        menu.addItem(saveKnownGoodItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: "アンインストール...",
            action: #selector(confirmUninstall),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        item.button?.toolTip = "ComposePilot for Claude Code"
        statusItem = item

        FocusTracker.shared.onDetectionStateChanged = { [weak self] detected in
            self?.isTargetDetected = detected
            self?.refreshIcon()
            // 検出状態が変わるのはフォーカスの出入りのタイミングなので、
            // ここで書き出せばコメント欄を離れた直後の書き換え回数が記録される。
            // イベントタップのコールバック内でファイルI/Oを行うとタップが
            // タイムアウトで無効化されうるため、書き出しはこちら側で行う。
            StatusReporter.write(note: detected ? "target focused" : "target unfocused")
        }

        FocusTracker.shared.onFocusedDescriptorChanged = { descriptor in
            StatusReporter.appendFocusLog(descriptor)
        }

        EventTapController.shared.onStateChanged = { [weak self] _ in
            self?.refreshMenuState()
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: ConfigStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshMenuState()
        }

        refreshMenuState()
    }

    /// 対象のコメント欄にフォーカスがあるか。`FocusTracker`からの通知で更新する。
    private var isTargetDetected = false

    /// メニューバー用のPNG(18×18/36×36)をテンプレート画像として読み込む。
    /// `Resources/MenuBarIcons/`の素材が`Scripts/build_app.sh`でアプリバンドルに
    /// コピーされている前提。
    private func menuBarImage(_ name: String) -> NSImage? {
        guard let url1x = Bundle.main.url(forResource: name, withExtension: "png"),
              let data1x = try? Data(contentsOf: url1x),
              let rep1x = NSBitmapImageRep(data: data1x) else { return nil }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.addRepresentation(rep1x)

        if let url2x = Bundle.main.url(forResource: "\(name)@2x", withExtension: "png"),
           let data2x = try? Data(contentsOf: url2x),
           let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep2x)
        }

        image.isTemplate = true
        return image
    }

    private func refreshIcon() {
        let name: String
        if !EventTapController.shared.isRunning || !ConfigStore.isEnabled() {
            name = "StatusOff"
        } else if isTargetDetected {
            // 介入中: コメント欄にフォーカスがあり、Enterを書き換える状態
            name = "StatusActive"
        } else {
            // 監視中: 稼働しているが対象にフォーカスが無い
            name = "StatusWatching"
        }
        statusItem?.button?.image = menuBarImage(name)
    }

    private func refreshMenuState() {
        enabledToggleItem?.state = ConfigStore.isEnabled() ? .on : .off

        // 入力監視は、イベントタップが動いていないときだけ「不足」として案内する。
        // アクセシビリティ許可だけでタップが作成できる環境があり、その場合に
        // 入力監視の未許可を不足として表示するのは誤った案内になるため。
        let tapRunning = EventTapController.shared.isRunning
        let missingPermissions = [
            PermissionsManager.isAccessibilityTrusted(prompt: false) ? nil : "アクセシビリティ",
            (tapRunning || PermissionsManager.isInputMonitoringTrusted()) ? nil : "入力監視",
        ].compactMap { $0 }

        let statusText: String
        if !missingPermissions.isEmpty {
            statusText = "停止中: \(missingPermissions.joined(separator: "・"))の許可が必要"
        } else if !tapRunning {
            statusText = "停止中: イベントタップ未開始"
        } else if !ConfigStore.isEnabled() {
            statusText = "待機中: 横取りが無効"
        } else if ConfigStore.hasKnownGoodSignature() {
            statusText = "稼働中(既知良好シグネチャで判定) / 書き換え \(EventTapController.shared.rewriteCount)回"
        } else {
            statusText = "稼働中(組み込みルールで判定) / 書き換え \(EventTapController.shared.rewriteCount)回"
        }
        statusInfoItem?.title = statusText

        refreshIcon()
    }

    @objc private func toggleEnabled() {
        ConfigStore.setEnabled(!ConfigStore.isEnabled())
        refreshMenuState()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func inspectFocusedElementAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delayedInspectionSeconds) { [weak self] in
            self?.runInspection()
        }
    }

    private func runInspection() {
        guard PermissionsManager.isAccessibilityTrusted(prompt: true) else {
            showAlert(title: "アクセシビリティ許可が必要です", message: "システム設定で許可してから再度実行してください。")
            PermissionsManager.openAccessibilitySettings()
            return
        }
        guard let url = ElementInspector.runInspectionAndSave() else {
            showAlert(title: "調査に失敗しました", message: "調査結果の保存に失敗しました。")
            return
        }
        let elementCount = ElementInspector.lastSnapshot?.elements.count ?? 0
        guard elementCount > 0 else {
            showAlert(
                title: "フォーカス要素を取得できませんでした",
                message: "対象アプリが起動していて、対象のダイアログにフォーカスがあるか確認してください。"
            )
            return
        }
        showAlert(
            title: "調査結果を保存しました(\(elementCount)階層)",
            message: "\(url.path)\n(クリップボードにもコピーしました)"
        )
    }

    @objc private func saveAsKnownGood() {
        if ElementInspector.saveLastSnapshotAsKnownGood() {
            showAlert(title: "既知良好シグネチャを保存しました", message: ConfigStore.knownGoodSignatureURL().path)
        } else {
            showAlert(
                title: "保存に失敗しました",
                message: "先に「\(Int(Self.delayedInspectionSeconds))秒後に調査」を実行し、要素が取得できていることを確認してください。"
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func confirmUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ComposePilotをアンインストールしますか?"
        alert.informativeText = """
        ログイン時起動を解除し、アプリ本体と設定・診断データをゴミ箱へ移動してから終了します。
        (ゴミ箱に入るだけなので、誤操作した場合は元に戻せます)

        システム設定のアクセシビリティ一覧からの削除だけは自動化できないため、\
        この後アクセシビリティ設定画面を開きます。手動で「−」を押して削除してください。
        """
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "アンインストール")
        // 破壊的操作なので既定(Returnキーで反応するボタン)はキャンセル側にする。
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        performUninstall()
    }

    private func performUninstall() {
        LoginItemManager.setRegistered(false)

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        var urlsToTrash: [URL] = [ConfigStore.appSupportDirectory()]
        // `.app`自身は実行中でも削除可能(APFS上、実行中バイナリはinodeで参照されるため)。
        // 即時削除ではなくゴミ箱行きにするのは、誤操作からの復元余地を残すため。
        urlsToTrash.append(Bundle.main.bundleURL)

        NSWorkspace.shared.recycle(urlsToTrash) { [weak self] _, error in
            if let error {
                NSLog("ComposePilot: uninstall recycle failed: \(error)")
                self?.showAlert(
                    title: "一部の削除に失敗しました",
                    message: "ログイン項目の解除と設定のクリアは完了しています。\(error.localizedDescription)"
                )
            }
            // TCC一覧からの削除だけはAPIが無くGUI操作が必要なので、その場で開いて誘導する。
            PermissionsManager.openAccessibilitySettings()
            NSApp.terminate(nil)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }
}

# Changelog

このプロジェクトの変更履歴。バージョンを上げる際は、公開前に`[Unreleased]`の内容を
新しいバージョン見出しへ書き換えてから`Resources/Info.plist`の
`CFBundleShortVersionString`を更新し、`Scripts/publish_release.sh`を実行する
(このファイルの該当バージョンの記載が、そのままGitHub Releaseのリリースノートになる。
詳細は[docs/GUIDE.md](docs/GUIDE.md#公開github-releases)を参照)。

形式は[Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)、バージョン番号は
[Semantic Versioning](https://semver.org/lang/ja/)に準拠する。

## [Unreleased]

## [1.0.2] - 2026-09-22

### Added

- 初回インストール・アップデート直後の起動時に、メニューバーへアイコンが追加された
  ことをポップアップと通知バナーで1回だけ知らせる機能を追加。
- `.pkg`インストーラにwelcome/conclusion画面を追加し、インストール完了後にアプリを
  自動起動するように変更。
- DMGに背景画像(ドラッグ先の案内矢印)を追加。
- README.md/docs/GUIDE.mdのインストール手順に、メニューバー確認を促す案内を追記。

## [1.0.1] - 2026-09-22

### Fixed

- メニューバーアイコンが起動直後や設定変更後に反映されず、常に非活性表示のままになる
  不具合を修正。

### Added

- ConfigStoreのUserDefaults設定とアイコン状態判定ロジックに対する自動テスト
  (XCTest)を追加。

## [1.0.0] - 2026-09-22

### Added

- 初回リリース。Enterキー横取りによるIME誤送信の回避、送信キーの選択(Ctrl / Cmd /
  Option)、設定画面、初回起動時の案内、メニューバーからのアンインストール、
  DMG / .pkgインストーラを含む。詳細は[README.md](README.md)を参照。

[Unreleased]: https://github.com/tofu76/composepilot-for-claude-code/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/tofu76/composepilot-for-claude-code/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/tofu76/composepilot-for-claude-code/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tofu76/composepilot-for-claude-code/releases/tag/v1.0.0

# Changelog

このプロジェクトの変更履歴。バージョンを上げる際は、公開前に`[Unreleased]`の内容を
新しいバージョン見出しへ書き換えてから`Resources/Info.plist`の
`CFBundleShortVersionString`を更新し、`Scripts/publish_release.sh`を実行する
(このファイルの該当バージョンの記載が、そのままGitHub Releaseのリリースノートになる。
詳細は[docs/GUIDE.md](docs/GUIDE.md#公開github-releases)を参照)。

形式は[Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)、バージョン番号は
[Semantic Versioning](https://semver.org/lang/ja/)に準拠する。

## [Unreleased]

## [1.0.0] - 未公開

### Added

- 初回リリース。Enterキー横取りによるIME誤送信の回避、送信キーの選択(Ctrl / Cmd /
  Option)、設定画面、初回起動時の案内、メニューバーからのアンインストール、
  DMG / .pkgインストーラを含む。詳細は[README.md](README.md)を参照。

[Unreleased]: https://github.com/tofu76/composepilot-for-claude-code/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/tofu76/composepilot-for-claude-code/releases/tag/v1.0.0

# ComposePilot for Claude Code

Claude Code(VS Code拡張)の計画レビューで、IME変換中に確定したEnterがコメント送信として
誤爆する不具合をOSレベルで回避する、macOS常駐のメニューバーアプリ。

名前は「変換中(compose)のEnterを操縦する(pilot)」の意味。

## 概要

Claude Codeの計画レビューには「Add Comment」というコメント欄があるが、ここで日本語などを
IME入力していると、**変換を確定するためのEnterがそのままコメント送信として扱われ、
未確定のテキストが送信されてしまう**という不具合がある。これは拡張機能側のキー処理が
IMEの変換状態を区別せず、単に`Enter`かどうかだけを見ているために起きる。

ComposePilotはコメント欄にフォーカスがある間だけ、OSレベルでEnterキーのイベントを
書き換えることでこの誤送信を防ぐ。拡張機能側の原因分析は
[docs/plan-comment-ime-enter-report.md](docs/plan-comment-ime-enter-report.md)にまとめてある
(上流への報告用)。

## 特徴

- **元のkeyCodeを維持したままモディファイアフラグだけを書き換える**ため、IMEの確定処理
  そのものは温存される(イベントを握りつぶして別イベントを合成する方式ではない)
- 送信用のキーをCtrl / Cmd / Optionから選べる(既定はCtrl+Enter)
- 対象アプリはVS Code本体が既定だが、設定画面から追加できる
- メニューバー常駐で、対象のコメント欄にフォーカスがある時だけ介入する
- メニューからワンクリックでアンインストール可能(ログイン項目・アプリ本体・設定値をまとめて削除)

### 書き換えの内容

| 操作 | 書き換え | 結果 |
| --- | --- | --- |
| 修飾なしのEnter | `Shift`を付与 | 送信されない(IMEの変換確定、または改行) |
| `Ctrl+Enter`(設定で変更可) | 修飾キーを除去 | 送信 |
| その他の組み合わせ | 書き換えない | 素通し |

送信が抑止できるのは、拡張機能側のハンドラが`!e.shiftKey`を条件にしているため:

```js
// Enter submits, Shift+Enter inserts newline
textarea.addEventListener('keydown', function(e) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submitBtn.click(); }
```

このハンドラは`Shift`以外の修飾キーを区別しないので、**Shift以外ならどれを押しても
送信経路に入る**。送信キーをCtrl / Cmd / Optionから選べるのも同じ理由による。

## 動作要件

- macOS 13以降
- Claude Code(VS Code拡張)がインストールされたVS Code(既定の対象アプリ)

## インストール

### 配布版(DMG / .pkg)

DMGを開いて`ComposePilot.app`を`Applications`へドラッグするか、`.pkg`をダブルクリックして
インストーラの案内に従う。初回起動時の案内画面でアクセシビリティ権限を許可すれば使える
(**入力監視の許可は不要**)。

### ソースから

```sh
Scripts/install.sh          # ビルド → ~/Applications へ配置 → 起動
```

DMG/.pkg/ソースそれぞれの詳細な手順、旧バージョン(EnterGuard)からの移行手順は
[docs/GUIDE.md](docs/GUIDE.md)を参照。

## 使い方

導入してアクセシビリティを許可すれば、対象アプリのコメント欄にフォーカスしている間
自動で動作する。メニューバーアイコンで状態がわかる。

| 状態 | 意味 |
| --- | --- |
| 停止中 | 許可未付与、または横取りが無効 |
| 監視中 | 稼働中だが対象のコメント欄にフォーカスが無い |
| 介入中 | コメント欄を検出しEnterを書き換える状態 |

アイコンにカーソルを乗せると「ComposePilot for Claude Code」とツールチップが出る。

メニューバーの「設定...」(⌘,)から、横取りのon/off・送信キー・対象アプリ・診断情報などを
変更できる。各設定タブの詳細は[docs/GUIDE.md](docs/GUIDE.md)を参照。

## アンインストール

メニューバーの「アンインストール...」を選ぶと、ログイン項目の解除・アプリ本体と設定データの
削除・設定値のクリアがまとめて行われる(アプリ本体はゴミ箱行きなので元に戻せる)。
システム設定のアクセシビリティ一覧からの削除だけはAPIが無いため自動化できず、続けて開く
設定画面から手動で「−」する必要がある。手動アンインストール手順は
[docs/GUIDE.md](docs/GUIDE.md#アンインストール)を参照。

## 既知の限界

- 変換中のEscapeでコメント下書き全体が消える問題は直せない(上流の修正待ち)
- macOSのアップデートでTCCの許可がリセットされることがある
- UIは日本語のみ(不具合自体は中国語・韓国語入力でも起きるが未対応)
- 自動更新の仕組みは無い

詳細は[docs/GUIDE.md](docs/GUIDE.md#既知の限界)を参照。

## 詳細ドキュメント

- [docs/GUIDE.md](docs/GUIDE.md) — 導入手順の詳細、設定画面の全タブ、判定ロジックと
  壊れた時の直し方、状態確認ファイル、Developer ID署名+notarizationによる配布手順など
- [docs/plan-comment-ime-enter-report.md](docs/plan-comment-ime-enter-report.md) —
  拡張機能側の原因分析(上流への報告用)

## ライセンス

[MIT License](LICENSE)

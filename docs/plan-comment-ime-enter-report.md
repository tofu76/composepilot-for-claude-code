# プランレビューの「Add Comment」ボックスが IME 変換確定の Enter で送信されてしまう問題

プランレビューのコメントボックスに日本語（および IME で変換中のテキスト全般）を入力すると、
変換の途中でコメントが送信され、未変換のテキストがそのまま送られてしまう。
長年報告されているこの問題の原因分析をまとめる。

関連 Issue: [#85915](https://github.com/anthropics/claude-code/issues/85915)（停滞中）、
[#36537](https://github.com/anthropics/claude-code/issues/36537)（キーバインドがこのボックスに
届かない）。

- **環境**: macOS 15（Darwin 25.6.0）、VS Code、日本語 IME（Apple 日本語IM）
- **確認した拡張機能のバージョン**: `anthropic.claude-code` 2.1.273、2.1.276、2.1.278
  （darwin-arm64）— 該当箇所のコードは 3 バージョンともバイト単位で同一
- **再現手順**: プランモードに入る → プランプレビュー内の任意のテキストをドラッグ選択 →
  *Add Comment* → 日本語を入力 → Enter で IME の変換を確定する。
  変換確定ではなくコメントの送信が実行され、未変換のテキストがそのまま送信される。

## 原因

プランプレビューのコメントボックスは React の webview（`webview/index.js`）**ではない**。
拡張機能ホスト側のバンドル（`extension.js`）内に手書きの HTML テンプレート文字列として存在し、
`vscode.window.createWebviewPanel("claudePlanPreview", …)` によって描画されている。
その keydown ハンドラには IME の変換中を判定するガードがない。

`extension.js`（2.1.278）、テンプレート内のおよそ 989 行目:

```js
// Enter submits, Shift+Enter inserts newline
textarea.addEventListener('keydown', function(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    submitBtn.click();
  }
  if (e.key === 'Escape') {
    e.preventDefault();
    hideCommentUI();
  }
});
```

ハンドラが紐づいている要素は、同じテンプレートのおよそ 756 行目:

```html
<textarea id="comment-textarea" placeholder="Add your feedback."></textarea>
```

IME の変換中、Chromium は変換確定のキー入力に対して `key === 'Enter'` かつ
`isComposing === true` の `keydown` を発火させる。ハンドラは `shiftKey` しか見ていないため、
このイベントで `submitBtn.click()` が呼ばれ、書きかけの下書きが送信されてしまう。

## なぜこのボックスだけが影響を受けるのか

プロダクトの他の部分ではすでに正しく処理されている。`isComposing` の出現回数:

| バンドル | 出現回数 | 備考 |
| --- | --- | --- |
| `webview/index.js` | 28 | メインのチャット入力、サイド質問の入力、AskUserQuestion の「Other」、リネーム、フィルタなど |
| `extension.js` | **0** | プランプレビューのコメントボックスを含む |

React の webview には、これを正しく処理する共通ヘルパーまで存在する:

```js
function bI1($, J) {
  return $.key === "Enter" && !$.shiftKey && !$.nativeEvent.isComposing
    && (!J || $.metaKey || $.ctrlKey);
}
```

プランプレビューは拡張機能ホストが所有する別の webview であるため、このヘルパーを通らず、
修正が適用されないまま残っている。`~/.claude/keybindings.json` の `Chat` コンテキストでの対処
（`enter: chat:newline`、`ctrl+enter: chat:submit`）がメインのチャット入力では効くのに
ここでは無効なのも、同じ理由である。このボックスは別 webview 内の素の DOM であり、
そもそも VS Code のキーバインドコンテキストではない。

## 同じハンドラのもう一つの不具合: Escape で下書きが消える

`Escape` の分岐にも同じガードが欠けており、`hideCommentUI()` は textarea を空にする:

```js
function hideCommentUI() {
  commentBtn.style.display = 'none';
  commentInput.style.display = 'none';
  textarea.value = '';
  currentRange = null;
  currentSelectedText = '';
}
```

日本語 IME では、変換中のキャンセルに Escape を使うのが通常の操作である。変換中に押すと
コメント UI が閉じ、**コメントの下書き全体が警告もなく破棄される**。消えるのは変換途中の
文字列だけではない。ここにも同じ `keyCode === 229` / `isComposing` のガードが必要である。

## 修正案

コードベースの他の箇所ですでに使われているガードを追加する。プロダクト内の他の場所では
`if (e.isComposing || e.keyCode === 229) return;` というパターンが使われている。
`keyCode === 229` の側は Chromium で重要で、Chromium は変換中の keydown をこの形で報告する。

```js
textarea.addEventListener('keydown', function(e) {
  if (e.isComposing || e.keyCode === 229) return;   // ← add this
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    submitBtn.click();
  }
  if (e.key === 'Escape') {
    e.preventDefault();
    hideCommentUI();
  }
});
```

あわせて検討する価値がある点が 2 つある:

- **`Ctrl+Enter` が区別されていない。** 条件は `!e.shiftKey` だけなので、`Ctrl+Enter` でも
  すでに送信される。これを明示的に認識すれば、`Chat` コンテキストの `ctrl+enter: chat:submit`
  との一貫性が得られ、Enter を改行として使いたいユーザーが同じように設定できるようになる。
- **`useCtrlEnterToSend` 設定** は `webview/index.js` では尊重されている（`bI1` ヘルパーに
  引き渡されている）が、このボックスには効かない。ここでも尊重すれば、分かりにくい
  非一貫性を解消できる。

## 調査方法

`~/.vscode/extensions/anthropic.claude-code-2.1.*-darwin-arm64/` 配下にインストールされている
拡張機能バンドルの静的な読解による。実行時の計測は不要で、テンプレートは `extension.js` 内に
ミニファイされていないプレーンテキストとして含まれている。調査結果はインストール済みの
3 バージョンで相互に確認し、いずれも同一であった。

## ローカルでの回避策

修正されるまでの間、このボックスはエディタの外側から、常駐の macOS エージェント
（本リポジトリ ComposePilot）で回避している。`CGEventTap` を用いて、この特定のコントロールに
フォーカスがある間は修飾なしの Enter に `Shift` を付加し、送信用に `Ctrl+Enter` を素の Enter へ
マップする。上記の `!e.shiftKey` という条件こそが、この回避策を成立させている。
対象コントロールはアクセシビリティ API 経由で、安定した `AXDOMIdentifier`
（`comment-textarea`）によって識別している。この ID が安定なのは、まさにこのテンプレートが
手書きであり、バンドラによるビルドごとのクラス名ハッシュ化の対象外だからである。

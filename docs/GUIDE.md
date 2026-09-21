# 詳細ガイド

このドキュメントはComposePilotの詳細な導入・運用リファレンスです。概要や特徴は
[README](../README.md)を参照。

## 導入

### 配布版(DMG)

1. DMGを開き、`ComposePilot.app`を`Applications`へドラッグする
2. 起動すると案内画面が出るので、指示に従ってアクセシビリティを許可する
3. 許可されると自動で次に進む。最後に「ログイン時に起動」(既定でオン)と
   送信キー(既定でCtrl+Enter)を確認する。どちらも後から設定画面で変更できる

**入力監視の許可は不要**(アクセシビリティだけで`CGEventTap`を作成できる)。
システム設定の「入力監視」の一覧にComposePilotが出てこなくても問題ない。

### 配布版(.pkg)

ドラッグ操作の代わりに、ダブルクリックで進むmacOS標準のインストーラも使える。

1. `ComposePilot.pkg`をダブルクリックし、インストーラの案内に従う
   (`/Applications`へ導入するため管理者パスワードの入力が必要)
2. 完了後は「配布版(DMG)」の手順2以降と同じ

DMGと導入先(`/Applications`)を揃えているため、DMG版からの入れ替えでも
アクセシビリティ許可を引き継げる。

### 開発者向け(ソースから)

```sh
Scripts/install.sh          # ビルド → ~/Applications へ配置 → 起動
```

ビルド時に`Apple Development`証明書を自動で探して署名する。ad-hoc署名にすると
TCCの識別がコード署名のハッシュに固定され、**再ビルドの度に許可が失効する**ため。
`COMPOSEPILOT_SIGN_IDENTITY`で署名identityを指定できる。

アイコンは`Resources/AppIcon.svg`から`Scripts/make_icon.sh`で生成する
(`.icns`は生成物なのでリポジトリには入れていない。ビルド時に自動生成される)。

`.pkg`をローカルで試す場合は`Scripts/build_pkg.sh`(`.build/ComposePilot.pkg`を生成、
未署名)。配布用の署名付きビルドは`Scripts/sign_and_notarize.sh`が
Developer ID Installer証明書を検出した場合に自動で行う(後述)。

### 旧バージョン(EnterGuard)から移行する場合

バンドルIDが `com.tofu76.EnterGuard` から `com.tofu76.ComposePilot` に変わったため、
**TCC(アクセシビリティ許可)の主体が別アプリになる。** 次の順で入れ替える。

1. 旧アプリのメニューで「ログイン時に起動」をOFFにしてから「終了」を選び、
   `~/Applications/EnterGuard.app` を削除する
2. システム設定 → プライバシーとセキュリティ → アクセシビリティ から
   `EnterGuard` を選んで「−」で削除する
3. 新しいアプリを導入し、一覧に `ComposePilot for Claude Code` を追加してONにする
4. 旧データの置き場所 `~/Library/Application Support/EnterGuard/` を削除する
   (診断ログのみで、引き継ぐべき内容はない)

## アンインストール

### メニューから(推奨)

メニューバーの「アンインストール...」を選ぶと、確認後にまとめて行われる。

- ログイン時起動の解除
- アプリ本体と`~/Library/Application Support/ComposePilot/`をゴミ箱へ移動
  (即時削除ではなくゴミ箱行きにするので、誤操作した場合はゴミ箱から戻せる)
- 設定値(UserDefaults)の削除
- アプリの終了

**システム設定のアクセシビリティ一覧からの削除だけは自動化できない**(APIが無い)ため、
続けてアクセシビリティ設定画面が開く。一覧から`ComposePilot for Claude Code`を選んで
「−」で削除すること。

### 手動で行う場合(メニューが使えない場合)

1. メニューの「ログイン時に起動」がONなら先にOFFにしてから「終了」を選ぶ
2. アプリ本体を削除する(`~/Applications/ComposePilot.app`または`/Applications/ComposePilot.app`。
   導入方法によって場所が異なる)
3. システム設定 → プライバシーとセキュリティ → アクセシビリティ の一覧から
   `ComposePilot for Claude Code`を選んで「−」で削除する
4. 診断データを消す場合は`~/Library/Application Support/ComposePilot/`を削除する
5. 設定値も消す場合は`defaults delete com.tofu76.ComposePilot`を実行する

## メニューバーアイコン

| 状態 | 意味 |
| --- | --- |
| 停止中 | 許可未付与、または横取りが無効 |
| 監視中 | 稼働中だが対象のコメント欄にフォーカスが無い |
| 介入中 | コメント欄を検出しEnterを書き換える状態 |

アイコン素材は`Resources/MenuBarIcons/`(状態ごとのPNG、@1x/@2x)。
カーソルを乗せると「ComposePilot for Claude Code」とツールチップが出る。

**メニューや設定画面を開くと自アプリがフロントになるため、コメント欄からフォーカスが外れる。**
コメントUIには「フォーカスが外れたら閉じる」処理があり、開いているダイアログが閉じて
下書きが消える。ダイアログを開いている間はメニューバーをクリックしないこと。

## 設定画面

メニューバーの「設定...」(⌘,)から開く。

| タブ | 内容 |
| --- | --- |
| 動作 | 横取りのon/off、送信キーの選択(Ctrl / Cmd / Option + Enter) |
| 対象アプリ | 対象とするアプリのバンドルID。「アプリを選んで追加」で`.app`から実際の値を読む |
| 判定 | 組み込みルールの値、既知良好シグネチャの管理、Level2キーワードの編集 |
| 診断 | 許可・稼働状態、書き換え回数、`focus.log`の末尾、診断情報のコピー |
| 一般 | ログイン時に起動、許可状態、案内の再表示、バージョン |

**設定画面を開くとコメントUIが閉じるため、コメント欄をこの画面からライブで観測することは
できない。** 診断タブが`focus.log`の履歴を表示するのはこのため。

### 対象アプリについて

既定はVS Code本体(`com.microsoft.VSCode`)のみ。Cursor / VS Code Insiders / Windsurf
などのフォークはバンドルIDが異なるため、「アプリを選んで追加」で実物から読み取って追加する。
推測値を既定に入れていないのは、間違っていた場合にユーザー側で検証する手段がないため。
**これらのフォークでの動作は未検証。**

## 状態の確認

`~/Library/Application Support/ComposePilot/`

| ファイル | 内容 |
| --- | --- |
| `status.txt` | 許可の状態、タップの稼働、書き換え回数、直近のフォーカス要素 |
| `focus.log` | フォーカス要素の変化履歴(role / AXDOMIdentifier / description / placeholder) |
| `inspections/*.json` | 調査キットの採取結果 |
| `known_good_signature.json` | 既知良好シグネチャ(保存した場合のみ) |

TCCの許可状態はアプリ自身のプロセスからしか正しく判定できない(ターミナルから起動した
バイナリはターミナルの許可状態を見てしまう)。そのためアプリ自身が状態を書き出している。

## 判定の仕組みと、壊れた時の直し方

フォーカス要素が対象かどうかを3段階で判定する。

| 段 | 判定材料 |
| --- | --- |
| Level 0 | `AXDOMIdentifier == "comment-textarea"`(取れない場合はplaceholder/descriptionが`"Add your feedback."`) |
| Level 1 | 調査キットで保存した既知良好シグネチャ(Level 0を上書き) |
| Level 2 | 祖先要素のキーワード一致(最後の保険) |

Level 0の値は拡張機能の`extension.js`に**手書きのHTMLテンプレート**として埋め込まれた
webview由来なので、バンドラが生成するハッシュ付きクラス名(`messageInput_cKsPxg`のような)
と違ってビルドごとに変化しない。実際に2.1.273 / 2.1.276 / 2.1.278で同一だった。

拡張機能のアップデートで横取りが効かなくなった場合:

1. 設定画面の**診断タブ**で`focus.log`の末尾を見る(コメント欄を開いた時に何が観測されたか)
2. メニューバーの「5秒後に調査」→「現在の要素を既知良好として保存」で、実測値を
   Level 1のシグネチャとして登録する(Level 0より優先される)
3. 恒久的な修正としては`ElementMatcher.planCommentDOMIdentifier` /
   `planCommentPlaceholder`を実測値に更新する

## 配布(Developer ID + notarization)

Mac App Storeでは配布できない。提出には **App Sandbox が必須**だが、本アプリの中核である
`CGEventTap`によるグローバルなキーイベントの傍受・改変はApp Sandbox下では動作しないため。
したがってDeveloper ID署名 + notarizationによる直接配布となる。

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: 名前 (TEAMID)"
export NOTARY_PROFILE="登録済みのキーチェインプロファイル名"
Scripts/sign_and_notarize.sh
```

開発用の`Apple Development`証明書ではnotarizationは通らない。`Developer ID Application`
証明書をdeveloper.apple.comで発行しておくこと(Apple Developer Programのメンバーシップが
必要)。スクリプトは証明書が無ければビルド前に止まり、手順を表示する。

`NOTARY_PROFILE`は事前に登録する:

```sh
xcrun notarytool store-credentials "プロファイル名" \
    --apple-id "<Apple ID>" --team-id "<TEAMID>" --password "<App用パスワード>"
```

このスクリプトはDMGに加えて、`Developer ID Installer`証明書(`Developer ID Application`とは
別の証明書クラス)がキーチェーンにあれば`.pkg`も自動で署名・notarize・stapleする。無い場合は
DMGのみで完了し、pkgを作るには別途証明書が必要と表示する(pkgは配布経路を増やす追加要素で、
DMGでの配布自体はこの証明書に依存しないため)。

## 既知の限界

- **変換中のEscapeでコメント下書き全体が消える**問題は、ComposePilotでは直せない。
  Escape側のハンドラは修飾キーを見ていないためフラグ書き換えで分岐を回避できず、
  変換中かどうかはOS外部から観測できないため一律の挙動変更しか選べない。上流の修正待ち。
- macOSのアップデートでTCCの許可がリセットされることがあり、都度再許可が必要になりうる。
- `AXManualAccessibility`の有効化により、VS Codeが`editor.accessibilitySupport: auto`を
  経由してスクリーンリーダー最適化モードに切り替わる可能性がある(VS Code再起動で解除)。
- UIは日本語のみ。不具合自体は中国語・韓国語入力でも起きるが、対応していない。
- 自動更新の仕組みは無い。

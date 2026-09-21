#!/bin/bash
# Developer ID署名 + notarization + DMG配布パッケージング。
#
# 実行前に以下の環境変数を設定すること(いずれもユーザー自身のApple Developer
# アカウント情報が必要で、このスクリプトを自動実行することはできない):
#   DEVELOPER_ID_APPLICATION … 例: "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE           … `xcrun notarytool store-credentials` で事前登録した
#                              キーチェインプロファイル名
#
# 使い方: Scripts/sign_and_notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Developer ID Application 証明書の有無を先に確認する。
#
# 開発用の Apple Development 証明書では notarization は通らない(Appleが受け付けない)。
# 証明書が無いままビルドまで走らせても最後に失敗するだけなので、ここで止める。
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application:"; then
    cat >&2 <<'MESSAGE'
Developer ID Application 証明書が見つかりません。

配布用の署名と公証(notarization)には、開発用の Apple Development 証明書ではなく
Developer ID Application 証明書が必要です。次の手順で用意してください。

  1. developer.apple.com → Certificates, Identifiers & Profiles → Certificates
  2. 「+」→ Software → Developer ID Application を選んで発行
  3. ダウンロードした .cer をダブルクリックしてキーチェーンに追加
  4. `security find-identity -v -p codesigning` で表示されることを確認

発行には Apple Developer Program のメンバーシップと Account Holder 権限が必要です。
MESSAGE
    exit 1
fi

: "${DEVELOPER_ID_APPLICATION:?DEVELOPER_ID_APPLICATION を設定してください}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE を設定してください(事前に notarytool store-credentials で登録)}"

./Scripts/build_app.sh release

APP_DIR=".build/ComposePilot.app"
DMG_PATH=".build/ComposePilot.dmg"
DMG_STAGE=".build/dmg-stage"

echo "Developer ID署名中..."
# --timestamp は必須。secure timestampが無いとnotarytoolが
# "The signature does not include a secure timestamp." でInvalidを返す。
# --options runtime(Hardened Runtime)も notarization の必須条件。
# ネスト構造の無い単一バイナリのバンドルなので --deep は使わない(Apple非推奨)。
codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --identifier com.tofu76.ComposePilot \
    "$APP_DIR"

codesign --verify --strict --verbose=2 "$APP_DIR"

echo "DMG作成中..."
# /Applications へのシンボリックリンクを同梱し、ドラッグで導入できるようにする。
VOLUME_NAME="ComposePilot for Claude Code"
RW_DMG=".build/ComposePilot-rw.dmg"
rm -rf "$DMG_STAGE" "$DMG_PATH" "$RW_DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

# 書き込み可能なDMGを作ってFinderで見た目(背景画像・アイコン配置)を整えてから、
# 配布用に圧縮フォーマット(UDZO)へ変換する。osascriptでFinderを操作するため、
# ログイン中のGUIセッションが必要(ヘッドレスCIでは動かない。手元での実行前提)。
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$DMG_STAGE" \
    -ov -format UDRW -fs HFS+ "$RW_DMG"

# `-nobrowse`や独自の`-mountpoint`を指定すると、Finderがこのボリュームを名前解決できず
# 後続のAppleScriptがことごとく失敗する(実機で検証済み)。同名の別ボリュームが既に
# マウント済みだと実際のボリューム名は自動的にリネームされる(例: "... 1")ため、
# 固定の`$VOLUME_NAME`を決め打ちせず、attachの出力から実際のマウントパスを読み取って使う。
ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -noautoopen)
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | grep -o '/Volumes/.*')
MOUNTED_VOLUME_NAME=$(basename "$MOUNT_POINT")

mkdir -p "$MOUNT_POINT/.background"
cp Resources/dmg-background.png "$MOUNT_POINT/.background/background.png"

# アイコンサイズ(96)と座標(165,130)/(495,130)は`Scripts/generate_dmg_background.py`の
# 矢印・キャプション位置と対応させてある。背景画像のレイアウトを変えたら両方直すこと。
#
# 以下のヒアドキュメントは$MOUNTED_VOLUME_NAMEを展開するため引用符なし(<<APPLESCRIPT)に
# している。引用符なしヒアドキュメントはバッククォートをコマンド置換として評価してしまう
# ため、このAppleScript本文やコメントにバッククォートを含めないこと(実機で
# 「close: command not found」という形で踏んだ)。
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$MOUNTED_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1060, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "ComposePilot.app" of container window to {165, 130}
        set position of item "Applications" of container window to {495, 130}
        -- 「close」だけだとdiskの取り出し(eject)に解決されうるため、必ず
        -- 「container window」を明示して閉じること(実機で検証済み)。
        close container window
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_POINT"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH"
rm -f "$RW_DMG"

echo "公証(notarization)申請中... (Appleのサーバに送信されるため時間がかかります)"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "ステープル中..."
xcrun stapler staple "$DMG_PATH"

echo "検証中..."
# 配布物として受け入れられるかの最終確認。Gatekeeperの判定を直接見る。
spctl -a -vvv -t install "$DMG_PATH" || true

echo "完成: $DMG_PATH"

# .pkgインストーラ(DMGとは別の導入経路)。
#
# Developer ID Installer証明書は、ここまでの署名に使ってきたDeveloper ID Application
# 証明書とは別の証明書クラスなので、独立して確認する。無くてもDMGでの配布自体は成立する
# ため、DMG生成を止めた冒頭のチェックとは違いここは非致命的な警告に留める。
INSTALLER_IDENTITY=$(
    security find-identity -v -p basic 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' \
        | head -n 1
)

if [ -z "$INSTALLER_IDENTITY" ]; then
    cat >&2 <<'MESSAGE'

DMGのみ生成しました。.pkgインストーラも作るには、Developer ID Installer証明書が別途
必要です(developer.apple.com → Certificates, Identifiers & Profiles で発行。
Developer ID Applicationとは別の証明書です)。
MESSAGE
else
    echo "Developer ID Installer署名でpkgも作成中..."
    COMPONENT_PKG_PATH=".build/ComposePilot-component.pkg"
    PKG_PATH=".build/ComposePilot.pkg"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

    # build_pkg.shと同じ理由(Scripts/pkg-component.plist参照)で、
    # --root + --component-plist(BundleIsRelocatable=false)を使う。
    PKG_ROOT=".build/pkgroot"
    rm -rf "$PKG_ROOT"
    mkdir -p "$PKG_ROOT/Applications"
    cp -R "$APP_DIR" "$PKG_ROOT/Applications/"

    # コンポーネントpkg自体は署名しない。署名はproductbuildが作る最終的な配布物
    # (welcome/conclusion画面付き)側でだけ行う。
    pkgbuild --root "$PKG_ROOT" \
        --component-plist Scripts/pkg-component.plist \
        --install-location /Applications \
        --scripts Scripts/pkg-scripts \
        --identifier com.tofu76.ComposePilot.installer \
        --version "$VERSION" \
        "$COMPONENT_PKG_PATH"

    ./Scripts/build_final_pkg.sh "$COMPONENT_PKG_PATH" "$PKG_PATH" "$INSTALLER_IDENTITY"

    echo "pkgの公証(notarization)申請中..."
    xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "pkgのステープル中..."
    xcrun stapler staple "$PKG_PATH"

    spctl -a -vvv -t install "$PKG_PATH" || true

    echo "完成: $PKG_PATH"
fi

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
rm -rf "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "ComposePilot for Claude Code" -srcfolder "$DMG_STAGE" \
    -ov -format UDZO "$DMG_PATH"

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
    PKG_PATH=".build/ComposePilot.pkg"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

    # build_pkg.shと同じ理由(Scripts/pkg-component.plist参照)で、
    # --root + --component-plist(BundleIsRelocatable=false)を使う。
    PKG_ROOT=".build/pkgroot"
    rm -rf "$PKG_ROOT"
    mkdir -p "$PKG_ROOT/Applications"
    cp -R "$APP_DIR" "$PKG_ROOT/Applications/"

    pkgbuild --root "$PKG_ROOT" \
        --component-plist Scripts/pkg-component.plist \
        --install-location /Applications \
        --scripts Scripts/pkg-scripts \
        --identifier com.tofu76.ComposePilot.installer \
        --version "$VERSION" \
        --sign "$INSTALLER_IDENTITY" \
        "$PKG_PATH"

    echo "pkgの公証(notarization)申請中..."
    xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "pkgのステープル中..."
    xcrun stapler staple "$PKG_PATH"

    spctl -a -vvv -t install "$PKG_PATH" || true

    echo "完成: $PKG_PATH"
fi

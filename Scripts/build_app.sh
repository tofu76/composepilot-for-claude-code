#!/bin/bash
# ComposePilot.app をビルドしてバンドルする。
# 使い方: Scripts/build_app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/ComposePilot"
APP_DIR=".build/ComposePilot.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH" "$CONTENTS/MacOS/ComposePilot"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

# アイコンは素材(AppIcon.svg)からの生成物。未生成なら作ってから取り込む。
if [ ! -f "Resources/AppIcon.icns" ] && [ -f "Resources/AppIcon.svg" ]; then
    ./Scripts/make_icon.sh >/dev/null
fi
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# メニューバー用アイコン(3状態×@1x/@2x)。StatusItemControllerが実行時にバンドルの
# Resourcesから直接読み込むため、SPMのリソース宣言ではなくここでコピーする。
cp Resources/MenuBarIcons/*.png "$CONTENTS/Resources/"

# 署名identityの決定。
#
# ad-hoc署名(`--sign -`)では、TCC(アクセシビリティ/入力監視の許可)がコード署名の
# ハッシュ(cdhash)に固定されるため、**1行でもコードを直して再ビルドすると許可が失効する**。
# 実測でも、許可を付与した直後に再ビルドしただけで `accessibility: NOT granted` に戻った。
# 検証作業では許可の再付与を繰り返すことになり現実的でない。
#
# 実際の証明書で署名すると、designated requirementが証明書とバンドルIDに基づくものになり、
# 再ビルドしても許可が維持される。配布用のnotarizationにはDeveloper ID Application証明書が
# 必要(Scripts/sign_and_notarize.sh)だが、ローカル検証にはApple Development証明書で十分。
#
# COMPOSEPILOT_SIGN_IDENTITY を指定すればそれを使う。未指定なら Apple Development 証明書を
# 自動で探し、見つからなければ ad-hoc にフォールバックする。
SIGN_IDENTITY="${COMPOSEPILOT_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
            | head -n 1
    )
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
    echo "警告: 署名用の証明書が見つからないため ad-hoc 署名にします。"
    echo "      再ビルドの度にアクセシビリティ・入力監視の許可を再付与する必要があります。"
fi

codesign --force --sign "$SIGN_IDENTITY" --identifier com.tofu76.ComposePilot "$APP_DIR" >/dev/null

echo "Built: $APP_DIR (signed with: $SIGN_IDENTITY)"

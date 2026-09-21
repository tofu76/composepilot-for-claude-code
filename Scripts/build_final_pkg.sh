#!/bin/bash
# pkgbuildで作った「コンポーネントpkg」に、welcome/conclusion画面(Scripts/pkg-resources/,
# Scripts/pkg-distribution.xml)を追加した最終pkgをproductbuildで生成する。
# Scripts/build_pkg.shとScripts/sign_and_notarize.shの両方から呼ばれる共通処理
# (Distribution.xmlの組み立て方を1箇所に保つため切り出した)。
#
# 使い方: Scripts/build_final_pkg.sh <component-pkg-path> <output-pkg-path> [sign-identity]
set -euo pipefail
cd "$(dirname "$0")/.."

COMPONENT_PKG="$1"
OUTPUT_PKG="$2"
SIGN_IDENTITY="${3:-}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

COMPONENT_NAME=$(basename "$COMPONENT_PKG")
cp "$COMPONENT_PKG" "$WORK_DIR/$COMPONENT_NAME"

DIST_XML="$WORK_DIR/distribution.xml"
sed "s/COMPONENT_PKG_FILENAME/$COMPONENT_NAME/" Scripts/pkg-distribution.xml > "$DIST_XML"

PRODUCTBUILD_ARGS=(
    --distribution "$DIST_XML"
    --resources Scripts/pkg-resources
    --package-path "$WORK_DIR"
)
if [ -n "$SIGN_IDENTITY" ]; then
    PRODUCTBUILD_ARGS+=(--sign "$SIGN_IDENTITY")
fi

productbuild "${PRODUCTBUILD_ARGS[@]}" "$OUTPUT_PKG"

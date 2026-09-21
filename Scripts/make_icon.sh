#!/bin/bash
# アプリアイコン(Resources/AppIcon.icns)を素材から生成する。
#
# 使い方: Scripts/make_icon.sh [素材ファイル]
#   素材を省略した場合は Resources/AppIcon.svg を使う。
#   SVGでもPNGでもよい(NSImageが読める形式ならなんでも)。
#
# macOSのアプリアイコンはOSが角丸マスクをかけないため、**素材自体に角丸の形が
# 含まれている必要がある**。Appleのグリッドでは1024pxキャンバスに対して角丸矩形が
# 約824px四方で、周囲は影の領域として余白を残す。
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-Resources/AppIcon.svg}"
if [ ! -f "$SOURCE" ]; then
    echo "素材が見つかりません: $SOURCE" >&2
    exit 1
fi

ICONSET=".build/AppIcon.iconset"
OUTPUT="Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"

swift Scripts/render_icon.swift "$SOURCE" "$ICONSET"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"

echo "生成しました: $OUTPUT (素材: $SOURCE)"

#!/bin/bash
# ビルドした ComposePilot.app を ~/Applications に配置して起動する。
# 使い方: Scripts/install.sh [debug|release]
#
# なぜ .build から直接起動しないか:
# - `swift package clean` や再ビルドで消える場所にあるアプリにTCC(アクセシビリティ/
#   入力監視)の許可を与えると、システム設定側に壊れたエントリが残りやすい。
# - 許可はアプリのパスにも紐づくため、置き場所を固定しておくと再付与の手間が減る。
#
# 注意: ad-hoc署名ではTCCの識別がコード署名のハッシュ(cdhash)に固定されるため、
# **リビルドすると許可が無効になり再付与が必要**になる。これを避けるには
# Developer ID署名(Scripts/sign_and_notarize.sh)が必要。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
./Scripts/build_app.sh "$CONFIG"

DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/ComposePilot.app"

mkdir -p "$DEST_DIR"

# 起動中なら先に終了させる。稼働中のバンドルを差し替えると挙動が不定になる。
if pgrep -f "$DEST/Contents/MacOS/ComposePilot" >/dev/null 2>&1; then
    echo "起動中の ComposePilot を終了します..."
    pkill -f "$DEST/Contents/MacOS/ComposePilot" || true
    for _ in $(seq 20); do
        pgrep -f "$DEST/Contents/MacOS/ComposePilot" >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

rm -rf "$DEST"
cp -R ".build/ComposePilot.app" "$DEST"

echo "Installed: $DEST"
codesign -dv --verbose=2 "$DEST" 2>&1 | grep -E "^Identifier|^Signature" || true

open "$DEST"
echo
echo "メニューバーにアイコンが出ます。アイコンの意味:"
echo "  keyboard.badge.ellipsis … 停止中(許可未付与、または横取りが無効)"
echo "  keyboard                … 監視中(稼働中だが対象のコメント欄にフォーカスが無い)"
echo "  keyboard.fill           … 介入中(コメント欄を検出しEnterを書き換える状態)"

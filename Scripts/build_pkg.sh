#!/bin/bash
# ComposePilot.pkg(macOS標準のインストーラパッケージ)をビルドする。
# 使い方: Scripts/build_pkg.sh [debug|release]
#
# DMGドラッグ&ドロップやScripts/install.shとは別の導入経路として、ダブルクリックで
# 進められるインストーラを提供する。インストール先はDMG配布(Scripts/sign_and_notarize.sh)
# と同じ /Applications にする。TCC(アクセシビリティ許可)はアプリのパスにも紐づくため、
# 配布経路によって導入先が変わると許可の再付与が必要になってしまう。
#
# 署名: COMPOSEPILOT_INSTALLER_SIGN_IDENTITY に "Developer ID Installer: ..." を
# 指定すれば署名付きで作る。未指定の場合は未署名のまま作成する(ローカルでの動作確認用。
# 配布にはDeveloper ID Installer証明書が必要)。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
./Scripts/build_app.sh "$CONFIG"

VERSION=$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist
)
PKG_PATH=".build/ComposePilot.pkg"

# `--component`だけでは、同じバンドルIDのアプリが既にどこか(例: 開発用の
# ~/Applications)に登録されていると、そちらを上書きしてしまう(pkgbuildの既定
# BundleIsRelocatable=trueの挙動)。`--root`+`--component-plist`
# (Scripts/pkg-component.plistでBundleIsRelocatable=falseに固定)を使い、
# 常に/Applicationsへインストールされるようにする。
PKG_ROOT=".build/pkgroot"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
cp -R ".build/ComposePilot.app" "$PKG_ROOT/Applications/"

PKGBUILD_ARGS=(
    --root "$PKG_ROOT"
    --component-plist Scripts/pkg-component.plist
    --install-location /Applications
    --scripts Scripts/pkg-scripts
    --identifier com.tofu76.ComposePilot.installer
    --version "$VERSION"
)

if [ -n "${COMPOSEPILOT_INSTALLER_SIGN_IDENTITY:-}" ]; then
    PKGBUILD_ARGS+=(--sign "$COMPOSEPILOT_INSTALLER_SIGN_IDENTITY")
else
    echo "警告: COMPOSEPILOT_INSTALLER_SIGN_IDENTITY 未指定のため未署名で作成します。"
    echo "      配布用にはDeveloper ID Installer証明書での署名が必要です。"
fi

pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_PATH"

echo "Built: $PKG_PATH"

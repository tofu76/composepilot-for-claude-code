#!/bin/bash
# 署名・公証済みのDMG/pkgをGitHub Releasesへ公開する。
#
# 前提:
#   - Scripts/sign_and_notarize.sh を実行済みで、.build/ComposePilot.dmg
#     (署名・公証済み)が存在すること。.build/ComposePilot.pkg があれば併せて公開する。
#   - CHANGELOG.md に、今回公開するバージョンの見出し(例: "## [1.0.0] - 2026-01-01")と
#     その内容が記載済みであること。この節の内容がそのままGitHub Releaseの
#     リリースノートになる。
#
# git tag の作成・push、および `gh release create` はいずれもリモート・公開状態を
# 変更する操作なので、実行前に必ずユーザーへ確認すること(CLAUDE.md参照)。
#
# 使い方: Scripts/publish_release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
    echo "作業ツリーに未コミットの変更があります。コミットしてから実行してください。" >&2
    exit 1
fi

DMG_PATH=".build/ComposePilot.dmg"
PKG_PATH=".build/ComposePilot.pkg"

if [ ! -f "$DMG_PATH" ]; then
    echo "$DMG_PATH がありません。先に Scripts/sign_and_notarize.sh を実行してください。" >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "タグ $TAG は既に存在します。Resources/Info.plist の" \
        "CFBundleShortVersionString を上げてから再実行してください。" >&2
    exit 1
fi

# CHANGELOG.mdの "## [$VERSION]" 見出しから次の "## [" 見出しの手前までを、
# そのままリリースノートとして使う。正規表現の特殊文字(バージョン中の ".")を
# 気にしなくて済むよう、正規表現ではなく index() による前方一致で判定する。
MARKER="## [$VERSION]"
CHANGELOG_SECTION=$(awk -v marker="$MARKER" '
    found && index($0, "## [") == 1 { exit }
    found { print; next }
    index($0, marker) == 1 { found=1 }
' CHANGELOG.md | sed -e '/^\[.*\]: /d' -e '1{/^$/d;}')

if [ -z "$(printf '%s' "$CHANGELOG_SECTION" | tr -d '[:space:]')" ]; then
    echo "CHANGELOG.md に \"$MARKER\" の見出しが見つからないか、内容が空です。" >&2
    echo "公開前に CHANGELOG.md へこのバージョンの変更点を記載してください。" >&2
    exit 1
fi

echo "リリース物をまとめています..."
STAGE=".build/release-$VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG_PATH" "$STAGE/ComposePilot-$VERSION.dmg"
if [ -f "$PKG_PATH" ]; then
    cp "$PKG_PATH" "$STAGE/ComposePilot-$VERSION.pkg"
fi
(cd "$STAGE" && shasum -a 256 -- * > "ComposePilot-$VERSION-checksums.txt")

NOTES_FILE=".build/release-notes-$VERSION.md"
printf '%s\n' "$CHANGELOG_SECTION" > "$NOTES_FILE"

echo "タグ $TAG を作成してpushします..."
git tag -a "$TAG" -m "ComposePilot for Claude Code $VERSION"
git push origin "$TAG"

echo "GitHub Releaseを作成します..."
gh release create "$TAG" "$STAGE"/* \
    --title "ComposePilot for Claude Code $VERSION" \
    --notes-file "$NOTES_FILE"

echo "公開しました: $(gh release view "$TAG" --json url --jq .url)"

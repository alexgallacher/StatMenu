#!/bin/zsh
# Publishes a new StatMenu version to GitHub Releases, which the in-app updater picks up.
# Usage: ./scripts/release.sh 1.1 [release-notes.md]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: ./scripts/release.sh <version> [notes.md]}"
NOTES="${2:-}"
PLIST=Resources/Info.plist

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first."; exit 1
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "v$VERSION already exists."; exit 1
fi

# Version shown to users, plus an ever-increasing build number.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD" "$PLIST"

./scripts/build.sh

mkdir -p dist
rm -f dist/StatMenu.zip dist/StatMenu.zip.sig
ditto -c -k --keepParent build/StatMenu.app dist/StatMenu.zip
swift scripts/sign_update.swift dist/StatMenu.zip > dist/StatMenu.zip.sig
echo "Signed dist/StatMenu.zip"

git add "$PLIST"
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

if [[ -n "$NOTES" ]]; then
  gh release create "v$VERSION" dist/StatMenu.zip dist/StatMenu.zip.sig --title "StatMenu $VERSION" --notes-file "$NOTES"
else
  gh release create "v$VERSION" dist/StatMenu.zip dist/StatMenu.zip.sig --title "StatMenu $VERSION" --generate-notes
fi
echo "Released StatMenu $VERSION"

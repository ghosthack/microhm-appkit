#!/bin/sh
# Builds dist/Microhm.app (scripts/build-app.sh) and puts it in a disk image:
# dist/release/Microhm-<version>-macos-arm64.dmg, with an Applications link to drag onto.
#   scripts/package.sh 1.2.0
# SIGN_IDENTITY signs the app and the image (see build-app.sh); without it both are ad hoc
# or unsigned, which runs only after the user allows it in System Settings.
set -eu
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/package.sh X.Y.Z}
case "$VERSION" in
  [1-9]*.*.*) ;;
  *) echo "error: the version must be numeric X.Y.Z with X >= 1 (got '$VERSION')" >&2; exit 1 ;;
esac
VERSION=$VERSION scripts/build-app.sh >/dev/null

ARCH=$(uname -m)
RELEASE=dist/release
DMG=$RELEASE/Microhm-$VERSION-macos-$ARCH.dmg
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/microhm-dmg-XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
rm -rf "$RELEASE" && mkdir -p "$RELEASE"
cp -R dist/Microhm.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Microhm $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  codesign --verify --strict "$DMG"
fi
echo "$DMG"

#!/bin/zsh
# Builds build/QuickText.app, ad-hoc signed.
#
#   scripts/build-app.sh             build for this Mac's architecture
#   scripts/build-app.sh --install   also copy to $INSTALL_DIR and open it
#
# Environment:
#   ARCHS        architectures to build, e.g. "arm64 x86_64" for a universal app (default: this Mac's)
#   CONFIG       release (default) or debug
#   INSTALL_DIR  where --install copies the app (default: /Applications)
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHS=(${=ARCHS:-$(uname -m)})
CONFIG=${CONFIG:-release}
INSTALL_DIR=${INSTALL_DIR:-/Applications}
APP=build/QuickText.app
STAGING=build/staging

case "${1:-}" in
    ""|--install) ;;
    *) echo "usage: $0 [--install]" >&2; exit 64 ;;
esac

rm -rf "$STAGING"
mkdir -p "$STAGING"

# Every architecture builds into the same products folder, so copy each binary out right away.
for arch in $ARCHS; do
    triple="$arch-apple-macosx14.0"
    echo "==> Building $CONFIG for $arch"
    swift build -c "$CONFIG" --product QuickText --triple "$triple"
    bin_dir=$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)
    cp "$bin_dir/QuickText" "$STAGING/QuickText-$arch"
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$STAGING"/QuickText-* -output "$APP/Contents/MacOS/QuickText"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# SwiftPM resource bundles (KeyboardShortcuts' localizations). Bundle.module looks in
# Bundle.main.resourceURL first; without them the shortcut recorder crashes.
for bundle in "$bin_dir"/*.bundle(N); do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
rm -rf "$STAGING"

echo "==> Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "    $(lipo -archs "$APP/Contents/MacOS/QuickText")"

if [[ "${1:-}" == "--install" ]]; then
    if pgrep -xq QuickText; then
        echo "==> Quitting the running QuickText"
        osascript -e 'tell application id "io.github.chyok.QuickText" to quit' >/dev/null 2>&1 || pkill -x QuickText || true
        for _ in {1..50}; do pgrep -xq QuickText || break; sleep 0.1; done
    fi
    echo "==> Installing to $INSTALL_DIR"
    rm -rf "$INSTALL_DIR/QuickText.app"
    cp -R "$APP" "$INSTALL_DIR/"
    open "$INSTALL_DIR/QuickText.app"
fi

echo "Done: $APP"

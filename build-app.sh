#!/bin/bash
# Builds "Better Widgets.app" into ./build. Usage:
#   ./build-app.sh            build the app
#   ./build-app.sh --run      build and launch it
#   ./build-app.sh --install  build, copy to ~/Applications and launch
#   ./build-app.sh --release  universal (Apple silicon + Intel), ad-hoc signed, zipped for GitHub Releases
set -euo pipefail
cd "$(dirname "$0")"

NAME="Better Widgets"
EXECUTABLE="BetterWidgets"
BUNDLE_ID="io.github.pranshavshelat.betterwidgets"
VERSION="${VERSION:-1.0.0}"
APP="build/$NAME.app"
MODE="${1:-}"

# The macOS 27 SDK implements @State as a macro whose plugin ships only with full Xcode.
# With just the Command Line Tools, build against the 26.x SDK instead.
if [[ -z "${SDKROOT:-}" ]] && ! xcode-select -p | grep -q Xcode.app; then
    SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
    [[ -n "$SDK" ]] && export SDKROOT="$SDK"
fi

if [[ "$MODE" == "--release" ]]; then
    # Build each architecture, set its binary aside, then merge into one universal binary.
    mkdir -p build
    for ARCH in arm64 x86_64; do
        swift build -c release --arch "$ARCH"
        cp "$(swift build -c release --arch "$ARCH" --show-bin-path)/$EXECUTABLE" "build/$EXECUTABLE-$ARCH"
    done
    BINARY="build/$EXECUTABLE-universal"
    lipo -create -output "$BINARY" "build/$EXECUTABLE-arm64" "build/$EXECUTABLE-x86_64"
else
    swift build -c release
    BINARY=".build/release/$EXECUTABLE"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocationUsageDescription</key><string>Better Widgets uses your location to show local weather.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Better Widgets uses your location to show local weather.</string>
</dict>
</plist>
PLIST

# Local builds use a stable identity so macOS keeps permissions across rebuilds
# (see scripts/make-signing-identity.sh). Release builds are ad-hoc signed.
IDENTITY="Better Widgets Local Signing"
if [[ "$MODE" != "--release" ]] && security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    if [[ "$MODE" != "--release" ]]; then
        echo "note: no \"$IDENTITY\" identity; signing ad hoc (permissions reset on every rebuild)"
    fi
    codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"

case "$MODE" in
    --run)
        pkill -x "$EXECUTABLE" 2>/dev/null || true
        open "$APP"
        ;;
    --install)
        pkill -x "$EXECUTABLE" 2>/dev/null || true
        mkdir -p ~/Applications
        rm -rf ~/Applications/"$NAME.app"
        cp -R "$APP" ~/Applications/
        open ~/Applications/"$NAME.app"
        echo "Installed to ~/Applications/$NAME.app"
        ;;
    --release)
        ZIP="build/Better-Widgets.zip"
        rm -f "$ZIP"
        ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
        echo "Release archive: $ZIP ($(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE"))"
        ;;
esac

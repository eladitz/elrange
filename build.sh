#!/bin/zsh
# Builds Elrange.app (Apple Silicon + Intel) with the Command Line Tools; no Xcode needed.
#   ./build.sh               for downloads
#   ./build.sh appstore      for the Mac App Store (sandboxed, no update check)
#   ./build.sh sandbox-test  the App Store build signed ad hoc, to try the sandbox here
set -euo pipefail
MODE=${1:-direct}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}   # must grow with every App Store upload
FLAGS=()
[[ $MODE != direct ]] && FLAGS=(-D APPSTORE)
cd "$(dirname "$0")"
VERSION=1.0.1
APP=build/Elrange.app
rm -rf "$APP" build/Elrange.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
    swiftc -parse-as-library -swift-version 5 -O -target $arch-apple-macos14 "${FLAGS[@]}" Sources/*.swift -o build/Elrange-$arch
done
lipo -create build/Elrange-arm64 build/Elrange-x86_64 -output "$APP/Contents/MacOS/Elrange"
rm build/Elrange-arm64 build/Elrange-x86_64

swift Icon.swift build/Elrange.iconset
iconutil -c icns build/Elrange.iconset -o "$APP/Contents/Resources/Elrange.icns"
rm -rf build/Elrange.iconset

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Elrange</string>
    <key>CFBundleDisplayName</key><string>Elrange</string>
    <key>CFBundleIdentifier</key><string>com.itzkin.elrange</string>
    <key>CFBundleExecutable</key><string>Elrange</string>
    <key>CFBundleIconFile</key><string>Elrange</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Elad Itzkin</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

./sign.sh "$APP" "$MODE"
echo "Built $APP ($MODE)"

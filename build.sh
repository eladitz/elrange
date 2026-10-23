#!/bin/zsh
# Builds Elrange.app (Apple Silicon + Intel) with the Command Line Tools; no Xcode needed.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=1.0.0
APP=build/Elrange.app
rm -rf "$APP" build/Elrange.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
    swiftc -parse-as-library -swift-version 5 -O -target $arch-apple-macos14 Sources/*.swift -o build/Elrange-$arch
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
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Elad Itzkin</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Signed with the private certificate from ../make-signing-identity.sh when it's there, so macOS keeps its
# permissions for the app across updates; otherwise ad hoc (which macOS treats as a new app every build).
SIGNING="$HOME/Library/Application Support/Itzkin Signing"
if [[ -f "$SIGNING/identity" ]]; then
    KEYCHAIN=$(ls "$SIGNING"/signing.keychain* | head -1)
    security unlock-keychain -p "$(cat "$SIGNING/password")" "$KEYCHAIN"
    codesign --force --keychain "$KEYCHAIN" --sign "$(cat "$SIGNING/identity")" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP"

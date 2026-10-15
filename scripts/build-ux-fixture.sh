#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/fetch-sparkle.sh
fixture_bundle=build/SideTrayUXFixture.app
fixture_main=Tests/UXFixture.swift
fixture_flags=""
fixture_id=io.sidetray.test.ux
fixture_name="SideTray UX Test"
if [ "${SIDETRAY_PERMISSION_JOURNEY:-0}" = 1 ]; then
 fixture_bundle="build/SideTray Permission Test.app"
 fixture_main=Tests/PermissionJourney.swift
 fixture_flags="-D SIDETRAY_PERMISSION_JOURNEY"
 fixture_id=io.sidetray.test.permissions
 fixture_name="SideTray Permission Test"
fi
mkdir -p "$fixture_bundle/Contents/MacOS" "$fixture_bundle/Contents/Resources" build/tests
cp Assets/SideTray.icns "$fixture_bundle/Contents/Resources/SideTray.icns"
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -fobjc-arc -isysroot "$sdk" -target arm64-apple-macos26.0 -c Sources/NativeVisibility.m -o build/tests/ux-visibility.o
xcrun swiftc -F build/dependencies/Sparkle-2.10.0 -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -D SIDETRAY_UX_FIXTURE $fixture_flags -import-objc-header Sources/NativeVisibility.h -target arm64-apple-macos26.0 Sources/*.swift "$fixture_main" build/tests/ux-visibility.o -o "$fixture_bundle/Contents/MacOS/SideTrayUXFixture"
cat > "$fixture_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$fixture_id</string>
<key>CFBundleName</key><string>$fixture_name</string>
<key>CFBundleDisplayName</key><string>$fixture_name</string>
<key>CFBundleIconFile</key><string>SideTray</string>
<key>CFBundleExecutable</key><string>SideTrayUXFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
</dict></plist>
PLIST
mkdir -p "$fixture_bundle/Contents/Frameworks"
ditto build/dependencies/Sparkle-2.10.0/Sparkle.framework "$fixture_bundle/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$fixture_bundle"
echo "$fixture_bundle"

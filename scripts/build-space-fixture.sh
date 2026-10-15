#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if pgrep -x SideTraySpaceFixture >/dev/null; then
 echo "Quit the previous Space fixture before rebuilding." >&2
 exit 1
fi
fixture_bundle=build/SideTraySpaceFixture.app
mkdir -p "$fixture_bundle/Contents/MacOS"
xcrun swiftc -target arm64-apple-macos26.0 Tests/SpaceFixture.swift -o "$fixture_bundle/Contents/MacOS/SideTraySpaceFixture"
cat > "$fixture_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.sidetray.test.space</string>
<key>CFBundleName</key><string>SideTray Space Test</string>
<key>CFBundleExecutable</key><string>SideTraySpaceFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$fixture_bundle"
echo "Built $fixture_bundle. Use Toggle Full Screen for a real Space transition."

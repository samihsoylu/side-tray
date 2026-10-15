#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if pgrep -x SideTrayTestFixture >/dev/null; then
 echo "Quit the previous test fixture before rebuilding." >&2
 exit 1
fi
fixture_bundle=build/SideTrayTestFixture.app
fixture_id="io.sidetray.test.delayed-menu.$(uuidgen | tr '[:upper:]' '[:lower:]')"
mkdir -p "$fixture_bundle/Contents/MacOS"
xcrun swiftc -target arm64-apple-macos26.0 Tests/DelayedMenuFixture.swift -o "$fixture_bundle/Contents/MacOS/SideTrayTestFixture"
cat > "$fixture_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.sidetray.test.delayed-menu</string>
<key>CFBundleName</key><string>SideTray Test Fixture</string>
<key>CFBundleExecutable</key><string>SideTrayTestFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>27.0</string>
</dict></plist>
PLIST
# A fresh identity prevents a previous macOS visibility record from hiding the
# item before the delayed-discovery code under test has had a chance to run.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $fixture_id" "$fixture_bundle/Contents/Info.plist"
codesign --force --sign - "$fixture_bundle"
echo "Built $fixture_bundle. Its status item appears six seconds after launch."
echo "Fresh fixture identity: $fixture_id"

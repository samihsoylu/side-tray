#!/bin/sh
# Builds a separate, read-only diagnostic bundle. Never installs or opens it.
set -eu
cd "$(dirname "$0")/.."
probe_bundle=build/SideTrayCompatibilityProbe.app
mkdir -p "$probe_bundle/Contents/MacOS" build/compatibility
for probe_arch in arm64 x86_64; do
 xcrun swiftc -target "${probe_arch}-apple-macos26.0" Tools/CompatibilityProbe.swift -o "build/compatibility/probe-${probe_arch}"
done
xcrun lipo -create build/compatibility/probe-arm64 build/compatibility/probe-x86_64 -output "$probe_bundle/Contents/MacOS/CompatibilityProbe"
cat > "$probe_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.sidetray.test.compatibility</string>
<key>CFBundleName</key><string>SideTray Compatibility Probe</string>
<key>CFBundleExecutable</key><string>CompatibilityProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$probe_bundle"
printf 'Built %s; no test app was launched or granted access.\n' "$probe_bundle"

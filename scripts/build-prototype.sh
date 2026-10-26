#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/fetch-sparkle.sh
task_framework=build/dependencies/Sparkle-2.10.0
task_bundle=build/SideTray.app
if [ "${SIDETRAY_STAGE_ONLY:-0}" = 1 ]; then
 task_bundle=build/staging/SideTray.app
elif pgrep -x SideTray >/dev/null; then
 echo "Quit SideTray before rebuilding so the running app and its permission signature stay intact." >&2
 exit 1
fi
mkdir -p "$task_bundle/Contents/MacOS" "$task_bundle/Contents/Resources" build/architectures
cp LICENSE "$task_bundle/Contents/Resources/LICENSE.txt"
cp Assets/SideTray.icns "$task_bundle/Contents/Resources/SideTray.icns"
cp ThirdParty/Sparkle-LICENSE.txt "$task_bundle/Contents/Resources/Sparkle-LICENSE.txt"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
for task_arch in arm64 x86_64; do
 xcrun clang -fobjc-arc -isysroot "$task_sdk" -target "${task_arch}-apple-macos26.0" -c Sources/NativeVisibility.m -o "build/architectures/Visibility-${task_arch}.o"
 xcrun swiftc -F "$task_framework" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -import-objc-header Sources/NativeVisibility.h -target "${task_arch}-apple-macos26.0" Sources/SideTray.swift Sources/TrayGeometry.swift Sources/PlacementStore.swift Sources/ShortcutChoice.swift Sources/PermissionRecovery.swift Sources/Shortcut.swift Sources/MenuActivation.swift Sources/MenuSurfaceWatch.swift Sources/Settings.swift Sources/MenuBarLayout.swift Sources/AppIdentity.swift Sources/MenuSwitches.swift Sources/VisibilityPipeline.swift Sources/UpdatePolicy.swift Sources/Updates.swift "build/architectures/Visibility-${task_arch}.o" -o "build/architectures/SideTray-${task_arch}"
done
xcrun lipo -create build/architectures/SideTray-arm64 build/architectures/SideTray-x86_64 -output "$task_bundle/Contents/MacOS/SideTray"
cat > "$task_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.sidetray.prototype</string>
<key>CFBundleName</key><string>SideTray</string>
<key>CFBundleDisplayName</key><string>SideTray</string>
<key>CFBundleIconFile</key><string>SideTray</string>
<key>SideTrayAuthor</key><string>Samih Soylu</string>
<key>SideTrayAuthorEmail</key><string>mail@samihsoylu.nl</string>
<key>CFBundleExecutable</key><string>SideTray</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>14</string>
<key>SideTrayReleaseChannel</key><string>Beta</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>CFBundleShortVersionString</key><string>0.2.9</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/samihsoylu/side-tray/main/appcast-dmg.xml</string>
<key>SUPublicEDKey</key><string>r7UuuKkGu2L7nTKNXnACxbidTszFTK5hkGmAygh0tS0=</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUAllowsAutomaticUpdates</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
</dict></plist>
PLIST
mkdir -p "$task_bundle/Contents/Frameworks"
ditto "$task_framework/Sparkle.framework" "$task_bundle/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "${SIDETRAY_SIGNING_IDENTITY:--}" "$task_bundle"
codesign --verify --strict "$task_bundle"
xcrun lipo -archs "$task_bundle/Contents/MacOS/SideTray"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$task_bundle/Contents/Info.plist"

#!/bin/sh
# Prepares a GitHub release archive and signed feed locally; never uploads.
set -eu
cd "$(dirname "$0")/.."
release_bundle=${1:-build/staging/SideTray.app}
python3 scripts/release-signing.py verify "$release_bundle"
sh scripts/check-bundle-licenses.sh "$release_bundle"
sh scripts/fetch-sparkle.sh
codesign --verify --deep --strict "$release_bundle"
python3 - "$release_bundle" <<'PY'
import pathlib,plistlib,sys,subprocess
bundle=pathlib.Path(sys.argv[1]); info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='io.sidetray.prototype'
assert info['SUFeedURL']=='https://raw.githubusercontent.com/samihsoylu/side-tray/main/appcast-dmg.xml'
assert info['SUPublicEDKey']=='r7UuuKkGu2L7nTKNXnACxbidTszFTK5hkGmAygh0tS0='
assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
assert not info['SUAutomaticallyUpdate'] and not info['SUAllowsAutomaticUpdates']
assert info['SUSignedFeedFailureExpirationInterval']==0
assert set(subprocess.check_output(['lipo','-archs',str(bundle/'Contents/MacOS/SideTray')],text=True).split())=={'arm64','x86_64'}
assert info['CFBundleVersion'].isdigit()
assert all(c.isdigit() or c=='.' for c in info['CFBundleShortVersionString'])
PY
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$release_bundle/Contents/Info.plist")
release_dir="build/releases/v$release_version"
mkdir -p "$release_dir"
sh scripts/package-dmg.sh "$release_bundle" "$release_dir/SideTray-$release_version.dmg"
if [ -f appcast-dmg.xml ]; then cp appcast-dmg.xml "$release_dir/appcast.xml"; fi
build/dependencies/Sparkle-2.10.0/bin/generate_appcast -o "$release_dir/appcast.xml" --account io.sidetray.updates --channel beta --maximum-deltas 0 --download-url-prefix "https://github.com/samihsoylu/side-tray/releases/download/v$release_version/" "$release_dir"
# Preserve older releases and their original OS ranges before signing the feed.
python3 scripts/merge-appcast.py "$release_dir/appcast.xml" appcast-dmg.xml "$release_version"
build/dependencies/Sparkle-2.10.0/bin/sign_update --account io.sidetray.updates "$release_dir/appcast.xml"
build/dependencies/Sparkle-2.10.0/bin/sign_update --account io.sidetray.updates --verify "$release_dir/appcast.xml"
echo "Prepared $release_dir (not published). Upload the DMG first, then replace appcast-dmg.xml with this signed feed."

#!/bin/sh
# Create a drag-to-Applications installer without changing the signed app.
set -eu
cd "$(dirname "$0")/.."
dmg_source=${1:-build/staging/SideTray.app}
sh scripts/check-bundle-licenses.sh "$dmg_source"
codesign --verify --deep --strict "$dmg_source"
dmg_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dmg_source/Contents/Info.plist")
dmg_output=${2:-build/releases/v$dmg_version/SideTray-$dmg_version.dmg}
if [ -e "$dmg_output" ]; then
 echo "Refusing to replace an existing installer: $dmg_output" >&2; exit 1
fi
if [ ! -x .tooling/dmg/bin/python ]; then python3 -m venv .tooling/dmg; fi
.tooling/dmg/bin/python -m pip install --disable-pip-version-check -q -r scripts/dmg-requirements.txt
mkdir -p "$(dirname "$dmg_output")"
dmg_work=$(mktemp -d build/dmg-work.XXXXXX)
dmg_stage="$dmg_work/files"
dmg_mount="$dmg_work/mounted"
dmg_attached=0
cleanup() {
 if [ "$dmg_attached" = 1 ]; then hdiutil detach -quiet "$dmg_mount" || return; fi
 rm -rf "$dmg_work"
}
trap cleanup EXIT
mkdir -p "$dmg_stage/.background" "$dmg_mount"
ditto "$dmg_source" "$dmg_stage/SideTray.app"
ln -s /Applications "$dmg_stage/Applications"
cp docs/INSTALL.txt "$dmg_stage/Install and Open.txt"
xcrun swift scripts/dmg-background.swift "$dmg_stage/.background/installer.tiff"
hdiutil create -quiet -fs HFS+ -volname "SideTray Installer" -srcfolder "$dmg_stage" -format UDRW "$dmg_work/writable.dmg"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$dmg_mount" "$dmg_work/writable.dmg"
dmg_attached=1
# Write the alias on the image's own volume so it survives another Mac/mount path.
.tooling/dmg/bin/python scripts/dmg-layout.py "$dmg_mount"
hdiutil detach -quiet "$dmg_mount"
dmg_attached=0
hdiutil convert -quiet "$dmg_work/writable.dmg" -format UDZO -o "$dmg_output"
hdiutil verify "$dmg_output"
echo "Prepared $dmg_output"

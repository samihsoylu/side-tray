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
dmg_stage=$(mktemp -d build/dmg-stage.XXXXXX)
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$dmg_source" "$dmg_stage/SideTray.app"
ln -s /Applications "$dmg_stage/Applications"
cp docs/INSTALL.txt "$dmg_stage/Install and Open.txt"
.tooling/dmg/bin/python scripts/dmg-layout.py "$dmg_stage"
hdiutil create -quiet -fs HFS+ -volname SideTray -srcfolder "$dmg_stage" -format UDZO "$dmg_output"
hdiutil verify "$dmg_output"
echo "Prepared $dmg_output"

#!/bin/sh
# Build, check and prepare locally; --publish NOTES also publishes with gh.
set -eu
cd "$(dirname "$0")/.."
release_publish=0
release_notes=
case "$#" in
 0) ;;
 2) [ "$1" = --publish ] || { echo 'Usage: sh scripts/release.sh [--publish NOTES_FILE]' >&2; exit 1; }
    release_publish=1; release_notes=$2; test -f "$release_notes" ;;
 *) echo 'Usage: sh scripts/release.sh [--publish NOTES_FILE]' >&2; exit 1 ;;
esac
if [ "$release_publish" = 1 ]; then
 test "$(git branch --show-current)" = main
 test -z "$(git status --porcelain --untracked-files=normal)" || { echo 'Commit reviewed source changes before publishing.' >&2; exit 1; }
 gh auth status >/dev/null 2>&1
 release_start_commit=$(git rev-parse HEAD)
fi
SIDETRAY_STAGE_ONLY=1 sh scripts/build-prototype.sh
sh scripts/test.sh
sh scripts/build-ux-fixture.sh
build/SideTrayUXFixture.app/Contents/MacOS/SideTrayUXFixture --self-test
sh scripts/prepare-update.sh build/staging/SideTray.app
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/staging/SideTray.app/Contents/Info.plist)
release_dir="build/releases/v$release_version"
release_asset="SideTray-$release_version.dmg"
python3 scripts/verify-release.py "$release_dir" "$release_version"
[ "$release_publish" = 1 ] || { echo 'Prepared locally; no release published.'; exit 0; }
release_commit=$(git rev-parse HEAD)
test "$release_commit" = "$release_start_commit"
test -z "$(git status --porcelain --untracked-files=normal)" || { echo "Source changed during preparation; not publishing." >&2; exit 1; }
git push origin HEAD:main
gh release create "v$release_version" "$release_dir/$release_asset" --repo samihsoylu/side-tray --target "$release_commit" --title "SideTray $release_version Beta" --prerelease --latest=false --notes-file "$release_notes"
curl --retry 3 --fail --location --silent --show-error "https://github.com/samihsoylu/side-tray/releases/download/v$release_version/$release_asset" --output "$release_dir/public-$release_asset"
cmp "$release_dir/$release_asset" "$release_dir/public-$release_asset"
release_signature=$(python3 - "$release_dir/appcast.xml" "$release_version" <<'PY2'
import sys,xml.etree.ElementTree as ET
ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item=next(i for i in ET.parse(sys.argv[1]).findall('./channel/item') if i.findtext(ns+'shortVersionString')==sys.argv[2])
print(item.find('enclosure').attrib[ns+'edSignature'])
PY2
)
build/dependencies/Sparkle-2.10.0/bin/sign_update --account io.sidetray.updates --verify "$release_dir/public-$release_asset" "$release_signature"
# Never announce a new update before its exact signed bytes are publicly available.
build/dependencies/Sparkle-2.10.0/bin/sign_update --account io.sidetray.updates --verify "$release_dir/appcast.xml"
cp "$release_dir/appcast.xml" appcast-dmg.xml
git add appcast-dmg.xml
git commit -m "Publish signed $release_version DMG update feed"
git push origin HEAD:main
release_feed_commit=$(git rev-parse HEAD)
curl --retry 3 --fail --location --silent --show-error "https://raw.githubusercontent.com/samihsoylu/side-tray/$release_feed_commit/appcast-dmg.xml" --output "$release_dir/public-appcast.xml"
cmp appcast-dmg.xml "$release_dir/public-appcast.xml"
build/dependencies/Sparkle-2.10.0/bin/sign_update --account io.sidetray.updates --verify "$release_dir/public-appcast.xml"
echo "Published https://github.com/samihsoylu/side-tray/releases/tag/v$release_version"

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
package_source=${1:-/Applications/SideTray.app}
package_output=${2:-build/SideTray-beta.zip}
sh scripts/check-bundle-licenses.sh "$package_source"
test -d "$package_source/Contents/MacOS"
codesign --verify --strict "$package_source"
mkdir -p build
package_stage=$(mktemp -d build/package.XXXXXX)
trap 'rm -rf "$package_stage"' EXIT
mkdir "$package_stage/SideTray-beta"
ditto "$package_source" "$package_stage/SideTray-beta/SideTray.app"
cp LICENSE "$package_stage/SideTray-beta/LICENSE.txt"
cp SECOND-MAC-TEST.md "$package_stage/SideTray-beta/Second Mac Test.md"
cat > "$package_stage/SideTray-beta/Read Me.txt" <<'README'
SideTray — beta
Author: Samih Soylu
mail@samihsoylu.nl

This beta is available for user testing. Remaining environment and recovery
checks are documented; it is not a fully validated stable release.

Installation
1. Use macOS 27. Other major macOS versions are not supported by this build.
2. Quit any running SideTray copy, then copy SideTray.app to Applications.
3. Open the Applications copy. Grant the requested access on this Mac.
4. Settings > Permissions reports control access and menu bar settings access.
   The latter needs Full Disk Access. This is a broad macOS grant; SideTray
   uses it for the system's menu bar visibility preferences.
5. If macOS asks, use Quit & Reopen. SideTray checks access automatically.
   Choose your visible apps, then select Start SideTray on a new installation.

The app is ad-hoc signed, not Developer ID signed or notarized. A downloaded
copy may be blocked by Gatekeeper. Do not disable Gatekeeper or remove security
checks globally. If macOS offers an Open Anyway action for this specific app,
use it only after verifying the source. Each Mac needs its own permission grants.

After an update, if access is missing although the switch is already on, quit
SideTray. Remove only SideTray from the affected permission list with minus,
then use plus to add /Applications/SideTray.app and reopen it. The old grant
may refer to the previous ad-hoc binary. App choices are preserved.

Use
Click the three dots to open SideTray. Click outside or press Escape to close.
In Settings, checked apps stay in the top bar; unchecked apps go into the strip.
New menu apps are hidden by default, including icons created after app launch.
Right-click a strip icon and choose Show in Menu Bar to make it always visible.
Click a hidden app to open its real menu. Its native icon stays available while
the menu is open. General contains the shortcut and Launch at login options.
Right-click the three dots for Settings, About or Quit. The information button
opens About. Record a custom shortcut in General, or Clear it to turn it off.
Arrow keys move tray focus; Return opens an app. Escape closes the tray.

Recovery
Quit SideTray normally to restore the original menu bar visibility. A recovery
helper also handles an unexpected app exit. If Full Disk Access is revoked,
macOS can prevent restoration; SideTray keeps its recovery record. Restore that
grant, use Quit & Reopen, and check access before changing placement again.
If restoration fails during Quit, choose Keep SideTray Open to repair access.
Quit Anyway retains the recovery record, but may leave icons hidden until the
next successful recovery. SideTray restores pending records before hiding new
icons on launch. Unsupported or malformed macOS settings stop changes safely.
No Screen Recording grant is required. Icon images come from the apps themselves.

Validation limits
This bundle contains arm64 and x86_64 binaries, but live validation was on the
current Apple Silicon Mac. This does not establish compatibility with another
Mac or an Intel system. Remaining interaction and lifecycle tests are tracked
in the source repository's docs/STATUS.md. Do not treat this archive as proof
that those tests have passed.

SideTray is licensed under the GNU General Public License v3.0. See LICENSE.txt
in this archive or SideTray.app/Contents/Resources/LICENSE.txt.
Source: https://github.com/samihsoylu/side-tray
Sparkle retains its own license in the app bundle.
README
package_binary="$package_stage/SideTray-beta/SideTray.app/Contents/MacOS/SideTray"
{
 echo "Source commit: $(git rev-parse HEAD)"
 echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$package_source/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$package_source/Contents/Info.plist"))"
 if ! git diff --quiet || ! git diff --cached --quiet; then echo 'Source worktree: modified'; fi
 echo "Executable SHA256: $(shasum -a 256 "$package_binary" | awk '{print $1}')"
 echo "Architectures: $(xcrun lipo -archs "$package_binary")"
 echo 'Validation status: beta; remaining checks documented'
} > "$package_stage/SideTray-beta/Build.txt"
ditto -c -k --sequesterRsrc --keepParent "$package_stage/SideTray-beta" "$package_output"
echo "$package_output"

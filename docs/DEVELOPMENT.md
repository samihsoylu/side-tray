# Build and test

SideTray is a Swift/AppKit menu bar utility. Build on macOS with Xcode Command Line Tools, Python 3, and network access for the pinned Sparkle dependency.

```sh
SIDETRAY_STAGE_ONLY=1 sh scripts/build-prototype.sh
sh scripts/test.sh
sh scripts/build-ux-fixture.sh
build/SideTrayUXFixture.app/Contents/MacOS/SideTrayUXFixture --self-test
```

The staging build produces `build/SideTray-next.app` without replacing a running app. It includes arm64 and x86_64 slices, an app icon, and Sparkle 2.10.0. The dependency download is pinned by SHA-256; its license is in `ThirdParty/`. Both the GPL license (`LICENSE.txt`) and Sparkle license are included in the app’s `Contents/Resources` before signing. Normal builds use ad-hoc code signing. Developer ID signing and notarization are deferred.

The SDK target is explicit. An implicit deployment target on a newer toolchain can produce a binary that runs directly but cannot relaunch through Launch Services on the test Mac.

The app supports macOS 27 and fails closed for unsupported menu-setting formats or future major OS versions. Native preference imports have no atomic compare-and-swap here: the final comparison reduces conflicts but cannot eliminate a race with another writer. Avoid concurrent menu bar managers.

## Access recovery tests

The pure suite checks permission recovery transitions. The UX fixture exercises the production controller and Settings with test-only permission, helper and resume results. It verifies automatic presentation, partial grants, failure handling and saved choices without granting OS access or modifying the real menu bar. Launch the fixture and choose **Show Access Recovery** for a visual preview. Actual macOS approval after an update remains a manual check.

## Isolated update tests

```sh
sh scripts/build-update-fixture.sh
python3 -m http.server 18743 --bind 127.0.0.1 --directory build/update-integration/release
# In another terminal:
python3 scripts/test-update-downloads.py
```

The fixture has its own bundle ID, preferences, cache, disposable signing key and localhost feed. It never runs SideTray’s permissions or menu-management code. Tests reject modified archives, modified feeds and missing feeds, check a downloaded update survives relaunch, and verify ordinary Quit never installs it.

For an end-to-end installation, launch `build/update-integration/installed/SideTray Update Test.app`, wait for the download and click **Install and Relaunch**. Verify its title changes from Build 1 to Build 2. Quit the fixture and stop the local HTTP server afterward. Local HTTP allowances exist only in the fixture compilation; production permits HTTPS GitHub release assets.

This does not prove Intel runtime, a clean Mac’s permissions flow, or production Gatekeeper behavior.

To test feed propagation recovery, stop the local HTTP server, rebuild the fixture,
and run `python3 scripts/test-update-feed-recovery.py`. It starts its own server,
serves signed conflicting feeds, checks distinct request URLs and one retry only,
then verifies an actual fixture replacement and relaunch. The fixture exits itself;
the installed production SideTray is not changed.

# Build and test

SideTray is a Swift/AppKit menu bar utility. Build on macOS with Xcode Command Line Tools, Python 3, and network access for the pinned Sparkle dependency.

```sh
SIDETRAY_ADHOC=1 SIDETRAY_STAGE_ONLY=1 sh scripts/build-prototype.sh
sh scripts/test.sh
sh scripts/build-ux-fixture.sh
build/SideTrayUXFixture.app/Contents/MacOS/SideTrayUXFixture --self-test
```

The staging build produces `build/staging/SideTray.app` without replacing a running app. It includes arm64 and x86_64 slices, an app icon, and Sparkle 2.10.0. The dependency download is pinned by SHA-256; its license is in `ThirdParty/`. Both the GPL license (`LICENSE.txt`) and Sparkle license are included in the app’s `Contents/Resources` before signing. The command above explicitly makes a local ad-hoc development build; it cannot be released. Production builds omit `SIDETRAY_ADHOC` and require the pinned release certificate in Keychain. Developer ID signing and notarization are deferred.

The SDK target is explicit. An implicit deployment target on a newer toolchain can produce a binary that runs directly but cannot relaunch through Launch Services on the test Mac.

The app supports macOS 27 and fails closed for unsupported menu-setting formats or future major OS versions. Native preference imports have no atomic compare-and-swap here: the final comparison reduces conflicts but cannot eliminate a race with another writer. Avoid concurrent menu bar managers.

## Access recovery tests

The pure suite checks permission recovery transitions. The UX fixture exercises the production controller and Settings with test-only permission, helper and resume results. It verifies automatic presentation, partial grants, failure handling and saved choices without granting OS access or modifying the real menu bar. Launch the fixture and choose **Show Access Recovery** for a visual preview. The ordinary UX fixture never probes real Accessibility or opens permission requests. To explicitly test native approval, build `SIDETRAY_PERMISSION_JOURNEY=1 sh scripts/build-ux-fixture.sh` and launch `build/SideTray Permission Test.app`. This separate identity uses production request actions, Settings and a read-only menu-preference access check. It never runs menu management, the updater or login registration. Approve temporary access only with the Mac owner’s consent; verify both checks after macOS Quit & Reopen, quit the test app, then remove its two grants in System Settings. The fixture does not prove production identity continuity across an ad-hoc update.

## Isolated update tests

```sh
SIDETRAY_UPDATE_FORMAT=dmg sh scripts/build-update-fixture.sh
python3 -m http.server 18743 --bind 127.0.0.1 --directory build/update-integration/release
# In another terminal:
python3 scripts/test-update-downloads.py
```

The fixture has its own bundle ID, preferences, cache, disposable signing key and localhost feed. Its installed bundle lives in its cache directory, outside protected Documents, so replacement does not require access to personal files. Set `SIDETRAY_UPDATE_FORMAT=zip` to verify legacy archive compatibility; use `dmg` for releases. It never runs SideTray’s permissions or menu-management code. Tests reject modified archives, modified feeds and missing feeds, check a downloaded update survives relaunch, and verify ordinary Quit never installs it.

For an end-to-end installation, launch `~/Library/Caches/io.sidetray.test.updater/Installed/SideTray Update Test.app`, wait for the download and click **Install and Relaunch**. Verify its title changes from Build 1 to Build 2. Quit the fixture and stop the local HTTP server afterward. Local HTTP allowances exist only in the fixture compilation; production permits HTTPS GitHub release assets.

This does not prove Intel runtime, a clean Mac’s permissions flow, or production Gatekeeper behavior.

To test feed propagation recovery, stop the local HTTP server, rebuild the fixture,
and run `python3 scripts/test-update-feed-recovery.py`. It starts its own server,
serves signed conflicting feeds, checks distinct request URLs and one retry only,
then verifies an actual fixture replacement and relaunch. The fixture exits itself;
the installed production SideTray is not changed.

For code-signing update compatibility, build the isolated DMG fixture with `SIDETRAY_TEST_SIGNING=transition` (ad-hoc build 1 to certificate-signed build 2), or `SIDETRAY_TEST_SIGNING=self-signed` (both builds use the pinned release certificate). These require the release private key but use only the test app identifier and disposable update-feed key. Run `test-update-feed-recovery.py` after each build to verify actual installation/relaunch; no real menu permissions are requested.

After a production staging build, `python3 scripts/test-release-signing.py` checks the pinned identity, changed-build continuity, missing-key/override rejection, and rejection of ad-hoc or weakened-requirement artifacts. The release script runs these checks automatically.

## Complete first-run test

`sh scripts/build-first-run-test.sh` builds **SideTray First Run Test** with the production Controller, final Start action and recovery watcher. It has a separate bundle ID, preferences and recovery journal; updater startup is disabled. Install the test bundle in Applications. Its live status is recorded in `~/Library/Caches/io.sidetray.test.firstrun/status.json`. Unlike the older permission-only harness, no readiness or helper results are injected.

This test can change the actual menu bar: obtain approval for the temporary grants, quit the working SideTray normally before pressing Start, and keep it closed through test relaunch. Exercise Request Access, enable both permissions in either order, choose apps, Start, reopen Settings, and quit/relaunch. Confirm the real helper is running, setupComplete survives relaunch and onboarding buttons stay hidden. Quit the test normally to restore its original menu settings, verify the test watcher exits and journal is cleared, remove its temporary grants, then reopen the unchanged production app. Do not run two managing copies together.

The ordinary UX fixture covers injected readiness failures, the three-attempt cap, cancelled callbacks, failed first-layout setup persistence, and Settings reopening. These simulated failure checks supplement, rather than replace, the live successful first-run journey.

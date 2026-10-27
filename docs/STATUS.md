# Beta status

## 0.2.10 (build 15)

- Uses a durable self-signed certificate so subsequent releases retain the same app identity. Migration from 0.2.9 or earlier may need one final permission refresh; saved app choices and the first-open Gatekeeper flow are unchanged.
- Pins the public certificate and verifies the stable designated requirement on every architecture, before packaging and inside the mounted release DMG. Missing keys, identity overrides, ad-hoc artifacts and weakened requirements block release preparation. No private signing material is committed.

Signing checks passed, including re-signing changed bundle bytes with the same identity and rejecting unsafe alternatives. Both isolated DMG updater paths (ad-hoc to self-signed, then same-certificate to same-certificate) passed actual replacement/relaunch and bounded conflicting-feed recovery. Earlier live two-build permission testing retained both real grants on macOS 27.0.1; public production migration, fresh-Mac behavior and Intel execution remain user testing. Published [0.2.10](https://github.com/samihsoylu/side-tray/releases/tag/v0.2.10) after the universal build, ten pure suites, controller/Settings checks, mounted DMG/license/identity checks, public download byte/signature verification and immutable/live-main signed-feed checks passed. The installed app hashes are unchanged; the user runs the update. The local signing-key backup is encrypted; an off-device backup remains a maintainer responsibility.

## Local signing experiment — October 26, 2026

Both Device Control and Full Disk Access survived replacing an isolated test app with a different build signed by the same self-signed certificate on macOS 27.0.1. Verified actual permission probes, distinct processes/executables and matching designated requirements; no permission changes between builds. Temporary grants and signing keychain were removed afterward. Public releases and installed SideTray remain unchanged. See [test evidence and limitations](SELF-SIGNED-PERMISSION-TEST.md). A production signing rollout remains separate work.

## 0.2.9 (build 14)

- Restores the saved layout after wake with at most three attempts, waiting 2 seconds initially, then 5 and 15 seconds after failed attempts. A successful attempt stops the sequence.
- Rechecks access and restarts a stopped recovery helper before applying the layout. Busy or unavailable menu bars consume an attempt without forcing a write. Wake recovery does not restart the macOS menu-bar service.
- Blocks competing automatic layout changes during recovery and retains the paused anti-flicker safeguard after exhaustion. Sleep, quit and manual retry invalidate pending attempts and callbacks. A later sleep/wake cycle gets a fresh bounded budget.

Deterministic clock tests and the production-controller fixture cover delays, exhaustion, success, duplicate notifications/completions, competing updates, prior-pause recovery, stale queued work and cancellation. Real overnight sleep/wake on the updated app remains for daily-use testing; the installed app and its grants are left unchanged. Published 0.2.9 after the universal build, ten pure suites, controller/Settings fixture, mounted DMG/license checks and signed public download/feed verification passed.

## 0.2.8 (build 13)

- Resolves helper-owned menu icons to their enclosing app’s registered visibility setting, including Gemini’s launcher. Exact helper records still take precedence; unrelated settings remain unchanged.
- Stops automatic placement attempts after a verified update failure exhausts the existing bounded recovery. Restores original icon settings and shows a paused state; Check Permissions retries the saved layout. Sleep and lost permissions retain their own recovery paths.

The reported failure was observed with working permissions, Gemini’s launcher owning its AX icon, and the main Gemini app owning its native setting. The installed helper-to-parent mapping was checked read-only. Regression checks cover helper hide/reveal/restore, exact-record priority, shared owners, unrelated records, and repeated placement attempts after failure. The user subsequently reported the menu bar was stable after updating to 0.2.8. The universal build, nine pure suites, controller/Settings fixture and signed DMG/feed verification passed. Published 0.2.8; the public download and live update feed match the prepared signed artifacts. The installed app was left unchanged.

## 0.2.7 (build 12)

- Adds a graphical drag-to-Applications cue, larger installer icons and concise first-install instructions.
- Starts the native Device Control request automatically during visible setup, then opens Full Disk Access once Device Control is approved. Both missing-permission buttons say **Request Access…**.
- Provides a draggable copy of the current app’s icon in setup, avoiding a Finder search when SideTray is missing from Full Disk Access. macOS still requires the user to approve access.
- Keeps automatic guidance out of the Updates page and does not reopen dismissed setup windows. Existing permission and icon-restoration safeguards remain.

The controller fixture verifies sequencing, one request per step, working-grant preservation, and update/dismissal guards. Visual review confirmed matching button labels and the mounted installer arrow. A subsequent live test confirmed automatic Device Control registration, approval detection and progression to Full Disk Access. Adding the isolated test app through the OS picker succeeded, and both real grants survived an ordinary quit/relaunch. Automated drags did not complete through the UI tool. The user then physically dragged the setup icon into Full Disk Access and confirmed the test entry appeared and its access checkmark was shown; the agent also verified the granted state. Both temporary grants were removed afterward, the test app was stopped, and production SideTray remained ready. macOS does not provide a supported automatic Full Disk Access grant API; this release does not claim automatic approval or reliable grant continuity between ad-hoc builds.

## 0.2.6 (build 11)

Releases now use a DMG containing SideTray, an Applications shortcut and first-opening instructions. The updater accepts signed DMGs and retains ZIP cache compatibility. Versions before 0.2.6 require one manual DMG install; their existing ZIP feed remains unchanged. Future versions use the separate DMG feed.

Verified the mounted Finder layout, readable installation guide, Applications shortcut, bundled licenses and app signature. Both the isolated DMG and legacy ZIP updater passed signed download, cache persistence, tamper rejection, ordinary Quit without installation, bounded stale-feed recovery and actual replacement/relaunch from test build 1 to build 2. The fixture installs in its own cache directory; an initial test under Documents waited for folder permission and was stopped without granting access.

The release script builds and tests, validates the mounted artifact, publishes with the GitHub CLI, compares the public download and verifies its signature before publishing the signed feed. It never installs SideTray on the development Mac. Developer ID signing and notarization remain deferred; the included guide explains the macOS first-open exception.

## 0.2.5 (build 10)

Fixes **Update Ready…** and **Check for Updates…** being redirected to Permissions during access recovery. General settings remain accessible while app placement stays disabled. Permission polling no longer pulls the update page away. Existing quit-time icon restoration safeguards are unchanged.

Verified the exact menu action in the controller/Settings fixture with missing access, repeated recovery/UI refreshes, and Apps remaining gated until recovery completes. Visually confirmed General and Updates are reachable from the recovery screen. Universal staging build passed. The production app was not updated by these tests.

## 0.2.4 (build 9)

Device Control now starts with a native **Request Access…** action. A later click opens Settings if macOS suppresses the prompt; the app does not open a competing window while the request is pending. Full Disk Access retains its required System Settings approval, with **Show App in Finder** to locate the correct bundle. First-time setup says **Set Up SideTray**, without reapproval language.

Live approval evidence: the separate permission-test app was registered through the native request, its Device Control grant was approved with Touch ID and detected automatically, and Full Disk Access was detected after macOS Quit & Reopen. Both temporary grants were removed afterward. This used production permission actions and Settings with real OS grants; native layout resumption remains covered separately by controller tests. Production updating is left to the user.

Staging now uses `build/staging/SideTray.app` and an explicit SideTray display name. Ordinary UI tests no longer query real Accessibility or request permissions, preventing test entries from appearing during routine UI checks. The old disabled UX-test entry was removed locally, and rerunning the preview did not recreate it. The former staging bundle shared the production identifier, making the “SideTray-next” label ambiguous; the current production permission entry was observed as SideTray.

Nine pure suites and the controller/Settings tests passed, including first-run wording, one native request, Settings fallback and preserving working grants. The universal release archive passed feed/archive signature, exact license and extracted code-signature checks. Developer ID signing and notarization remain deferred; renewed approval may still be needed after updates.

## 0.2.3 (build 8)

After an update, missing Device Control or Full Disk Access automatically opens **Restore access to SideTray**. Only missing permissions offer approval actions. SideTray checks quietly and resumes saved choices after permissions and menu-bar recovery are ready. Working grants are retained; macOS approval remains the user's action.

Verified: nine pure suites, production controller/Settings tests with simulated permission states, and visual review of the recovery screen. Coverage includes Full Disk Access alone being missing, partial grants, unavailable settings, no repeated foregrounding, one resume, failed-resume retry, and saved choices. The universal staged build, archive signature, extracted code signatures and exact bundled licenses passed. These checks do not simulate macOS granting access or replace the user's live update test; the installed app and its grants were left untouched.

The user confirmed the previous 0.2.2 update succeeded. Apple Developer ID signing and notarization remain deferred.

## 0.2.2 (build 7)

Feed checks use a fresh request URL. Installation retries once if the feed contradicts the verified download; continued disagreement keeps the download and shows a retry message instead of “up to date.” Signature checks and explicit installation approval remain required.

Verified: all eight pure suites; signed fixture feeds covering both no newer update and an older-than-approved update; one retry only, distinct request tokens, retained download, and actual replacement/relaunch after transient disagreement. Existing tampered-feed/archive, persistence and ordinary-Quit checks also passed. The universal staged bundle passed signing and packaging checks. The installed app is left for user-driven updating.

## 0.2.1 (build 6)

Packages the GNU GPL v3.0 license in the app bundle. Release preparation rejects missing or modified GPL and Sparkle license files. No app interaction or updater logic changed. Version 0.2.0 can discover this release through the beta feed; the user confirmed the 0.2.0 → 0.2.1 update succeeded.

## 0.2.0 (build 5)

Adds optional daily GitHub update checks and verified background downloads. Installation requires **Install and Relaunch**. Pending downloads survive relaunch. Normal Quit before approval never installs an update. Apple Developer ID signing and notarization remain deferred.

Evidence for this candidate:

- Universal Apple Silicon/Intel build and strict nested code-signature verification.
- Eight pure test suites covering layout, placement, shortcuts, menu visibility, recovery and update validation.
- Isolated AppKit settings tests and visual review of General.
- An isolated signed feed/download test with tampered archives, modified signed feeds and a missing feed.
- Download persistence, ordinary Quit without installation, and actual replacement/relaunch from test build 1 to build 2.

The update fixture has no menu-control permissions or production user data. It establishes the updater flow, not another Mac's Gatekeeper or permissions behavior. Updater integration restores icons before quitting; failure blocks installation's quit path.

0.1.1 remains the prior daily-use beta. Its scoped live checks covered permission recognition, native menus, normal Quit restoring icons and relaunch preserving placement. No broad all-app/live-hardware claim is made for 0.2.0.

Published as [0.2.0 Beta](https://github.com/samihsoylu/side-tray/releases/tag/v0.2.0). The public ZIP matches the prepared archive, and both public feed and archive signatures were verified. Existing builds without the updater require one manual installation. The published 0.2.0 archive was manually installed on the development Mac. Its About page confirms version 0.2.0 (5); refreshed existing permissions report Ready and saved choices are retained. A live manual update check against the public feed reports “You’re up to date.” No newer production release is available, so production upgrade/relaunch remains unverified; that flow was exercised in the isolated fixture above.

## Remaining compatibility evidence

Second-Mac setup, Intel execution, multiple displays and ordinary sleep/login cycles require user testing. The implementation depends on macOS 27's internal menu-bar preferences; other major versions are blocked pending validation. Simultaneous menu-bar managers are unsupported.

## Deferred

- Apple Developer ID signing and notarization.
- Broader accessibility-preference/VoiceOver validation.

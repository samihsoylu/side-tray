# Beta status

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

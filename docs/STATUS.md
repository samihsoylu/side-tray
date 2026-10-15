# Beta status

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

Published as [0.2.0 Beta](https://github.com/samihsoylu/side-tray/releases/tag/v0.2.0). The public ZIP matches the prepared archive, and both public feed and archive signatures were verified. Existing builds without the updater require one manual installation. No full replacement of the menu-managing production app was performed in this session.

## Remaining compatibility evidence

Second-Mac setup, Intel execution, multiple displays and ordinary sleep/login cycles require user testing. The implementation depends on macOS 27's internal menu-bar preferences; other major versions are blocked pending validation. Simultaneous menu-bar managers are unsupported.

## Deferred

- Apple Developer ID signing and notarization.
- Broader accessibility-preference/VoiceOver validation.

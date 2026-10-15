# SideTray 0.1.1 (4): second-Mac test

This is a beta candidate for compatibility testing, not a claim of production readiness. Use macOS 27. The bundle contains Apple Silicon and Intel binaries; the first Mac used Apple Silicon. Signing remains ad-hoc and notarization is deferred.

## Install

1. Keep any existing SideTray version as a rollback copy. Quit it normally and verify hidden icons return before replacing it.
2. Copy the packaged `SideTray.app` to `/Applications`, then open that copy. Do not run another menu-bar manager during this test.
3. Grant Device Control and Data Access and Full Disk Access in System Settings. If SideTray is absent, use + to add the Applications copy. Reopen it and verify Permissions says **SideTray is ready**.
4. On a fresh installation, choose which apps stay visible, then click **Start SideTray**. On an upgrade, confirm existing choices and shortcut are retained.

This ad-hoc update may need a renewed grant. An enabled switch can refer to the previous build: quit SideTray, remove only its stale entry from the affected list, add the Applications copy again and reopen. Do not disable macOS security globally.

## Check normal use

- Open the tray. It should sit directly below its three-dot button, remain compact, and show larger icons without a scrollbar.
- Open several actual app menus, including Proton Bridge or Scroll Reverser if already installed. Confirm normal menu actions and dismissal work. The temporarily revealed native icon should hide again after its menu closes.
- Move one app between the tray and menu bar, then restore the choice you want. Verify checked apps stay to the right of the dots.
- Quit SideTray normally: hidden icons should return, and SideTray should exit. Reopen it: saved choices should be applied again.
- During ordinary use, observe sleep/wake, restart/login if launch at login is enabled, and monitor connection/disconnection if available. Do not interrupt active work just for this test.
- Check Control Centre and Notification Centre still open normally. Note tray alignment after display scaling or full-screen changes.

## Recovery expectations

If Quit cannot restore icons, **Keep SideTray Open** is the default. Follow the status in Permissions and retry. **Quit Anyway** retains a recovery record, but icons may remain hidden until access returns and SideTray successfully restores them. Do not delete the recovery record.

Unsupported OS versions or malformed menu-bar data should stop hiding and show a useful status. Do not alter protected macOS settings or revoke permissions solely to create failures; fault injection is covered by isolated automated tests.

## Report a result

Include the Mac model, macOS version, SideTray version/build, display arrangement, affected app, what you clicked, expected/actual behavior, and whether relaunch changed it. A screenshot can help with alignment. No passwords or unrelated personal data are needed.

## Known limits

The native hiding method depends on macOS's internal preference format. A comparison immediately before import catches intervening changes, but cannot make the system's read/import pair atomic. Avoid other tools changing menu-bar visibility at the same time. Clean-Mac installation, actual sleep/login cycles, Intel execution and multiple displays require this testing; local fixtures do not establish those results.

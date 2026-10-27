# SideTray help

## macOS says “SideTray” Not Opened

If macOS blocks SideTray with the warning that Apple could not verify the app:

1. Get the DMG from the [official release page](https://github.com/samihsoylu/side-tray/releases), open it, and drag SideTray to Applications. Open that installed copy.
2. Choose **Done** in the warning.
3. Open **System Settings → Privacy & Security**, scroll to Security, and find SideTray’s blocked-app message. Choose **Open**, then **Open Anyway**, or **Open Anyway** directly if shown.
4. Authenticate locally and confirm **Open** if prompted. Open SideTray from Applications.

The exception is offered for about an hour after an attempted launch; try opening the installed copy again if it has disappeared. These steps follow [Apple’s macOS 27 instructions](https://support.apple.com/en-gb/guide/mac-help/mh40617/27/mac/27). They apply to the unverified-app warning, not a report of known malware or a damaged app. Do not disable Gatekeeper or strip quarantine attributes.

Use **Request Access…** beside each missing permission to open its System Settings page. Enable SideTray there and approve with Touch ID or your password if asked. If SideTray is missing from either list, drag the app icon from its setup window into that list. SideTray detects approval without opening another warning or moving you to the next page. The DMG also includes **Install and Open.txt** with these instructions.

## An update asks for permissions again

Version 0.2.10 introduces a stable signing identity so future updates can retain permissions. Moving from 0.2.9 or earlier may require one final refresh, even when the existing switch looks enabled. Both permissions survived an update between two builds with the same self-signed identity in testing on macOS 27.0.1.

SideTray automatically opens **Restore access to SideTray** when it detects missing access after an update.

1. Click **Request Access…** beside the missing permission, then enable SideTray on that System Settings page.
2. If SideTray already looks enabled, remove only SideTray from the affected list with **−**, then use **+** to add `/Applications/SideTray.app` again.
3. Approve any macOS authentication locally. Choose **Quit & Reopen** if macOS asks.

SideTray checks automatically and resumes your saved layout when access is ready. **Retry** retries a failed recovery. If the screen says menu bar settings are unavailable, follow its status message; that does not necessarily mean a permission is missing.

Use **Show App in Finder** to locate the running app when adding it. First-time setup says **Set Up SideTray** and does not describe a previous grant.

Your app choices are retained. Apple Developer ID signing and notarization remain deferred; the stable self-signed identity does not remove the first-open warning.

## Icons did not return when quitting

If SideTray cannot restore icons, choose **Keep SideTray Open**, follow the message in Permissions, and retry. **Quit Anyway** keeps a recovery record, but icons may remain hidden until access is restored and SideTray opens again. Do not delete its recovery record.

During an update, a failed restoration cancels quitting; the updater must wait until recovery succeeds. It does not offer to bypass recovery.

## Update Ready opens Permissions instead

Versions 0.2.3 and 0.2.4 can redirect the update page while access is missing. Version 0.2.5 fixes this. To get past the older version, either restore its permissions once and use the updater, or quit SideTray normally and drag SideTray from the current release DMG to Applications, choosing Replace. Keep your saved settings and recovery files.

## An update will not download

Try **Check for Updates** again after confirming your connection. A failed signature check leaves the installed app unchanged. Do not install an archive that fails verification. Report the SideTray version, macOS version, and the displayed error; do not include passwords or unrelated personal information.

## Setup cannot finish connecting

After both permissions are granted, SideTray tries to prepare menu-bar recovery up to three times. If it still cannot connect, follow the status message and choose **Retry**. Do not remove working permission grants for a helper or layout error. Choose **Quit & Reopen** if macOS asks when enabling Full Disk Access.

Once you press **Start SideTray**, your setup choices are kept even if applying the first layout fails. SideTray leaves/restores icons visible and shows recovery in Settings; it does not send you through onboarding again.

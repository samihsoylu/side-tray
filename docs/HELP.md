# SideTray help

## An update asks for permissions again

Current beta builds are ad-hoc signed. Replacing the app can change the identity macOS associates with a previous permission grant, even when its switch still looks enabled.

SideTray automatically opens **Restore access to SideTray** when it detects missing access after an update.

1. Click **Request Access…** for Device Control and follow the macOS prompt. If no prompt appears, the button changes to **Open System Settings…** as a fallback. For Full Disk Access, open its settings page and enable SideTray.
2. If SideTray already looks enabled, remove only SideTray from the affected list with **−**, then use **+** to add `/Applications/SideTray.app` again.
3. Approve any macOS authentication locally. Choose **Quit & Reopen** if macOS asks.

SideTray checks automatically and resumes your saved layout when access is ready. **Check Again** retries a failed recovery. If the screen says menu bar settings are unavailable, follow its status message; that does not necessarily mean a permission is missing.

Use **Show App in Finder** to locate the running app when adding it. First-time setup says **Set Up SideTray** and does not describe a previous grant.

Your app choices are retained. Apple signing and notarization are planned separately; the update-download signature does not replace them.

## Icons did not return when quitting

If SideTray cannot restore icons, choose **Keep SideTray Open**, follow the message in Permissions, and retry. **Quit Anyway** keeps a recovery record, but icons may remain hidden until access is restored and SideTray opens again. Do not delete its recovery record.

During an update, a failed restoration cancels quitting; the updater must wait until recovery succeeds. It does not offer to bypass recovery.

## Update Ready opens Permissions instead

Versions 0.2.3 and 0.2.4 can redirect the update page while access is missing. Version 0.2.5 fixes this. To get past the older version, either restore its permissions once and use the updater, or quit SideTray normally and replace the app in Applications with the new release ZIP’s SideTray.app. Keep your saved settings and recovery files.

## An update will not download

Try **Check for Updates** again after confirming your connection. A failed signature check leaves the installed app unchanged. Do not install an archive that fails verification. Report the SideTray version, macOS version, and the displayed error; do not include passwords or unrelated personal information.

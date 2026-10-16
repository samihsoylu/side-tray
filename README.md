<p align="center">
  <img src="Assets/SideTray.png" alt="SideTray app icon" width="112">
</p>

<h1 align="center">SideTray</h1>

<p align="center">
  Choose which apps stay in your Mac’s menu bar. Open the rest from a compact tray beneath a three-dot button.
</p>

<p align="center">
  <a href="https://github.com/samihsoylu/side-tray/releases"><strong>Download the beta</strong></a> ·
  <a href="docs/HELP.md">Help</a> ·
  <a href="https://github.com/samihsoylu/side-tray/issues">Report an issue</a>
</p>

<p align="center">macOS 27 · Apple Silicon and Intel</p>

## Get started

1. Download and open the **DMG**, then drag **SideTray** onto **Applications**.
2. Open SideTray and follow its permission prompts in **System Settings → Privacy & Security**.
3. Select the apps you want to keep visible, then click **Start SideTray**. Unchecked and new apps go into the tray.

If macOS shows **“SideTray” Not Opened**, choose **Done**, then open **System Settings → Privacy & Security**. Under Security, choose **Open / Open Anyway** for SideTray and approve the prompt. Only do this for the [official download](https://github.com/samihsoylu/side-tray/releases). [First-launch help](docs/HELP.md#macos-says-sidetray-not-opened)

Click a tray icon to open the app’s menu. Right-click the three dots for Settings, where you can change app visibility, set a keyboard shortcut, or enable launch at login.

SideTray needs **Device Control and Data Access** to open app menus, and **Full Disk Access** for macOS’s protected menu bar settings. Full Disk Access is a broad permission; SideTray uses it for menu bar settings and recovery records. App choices stay on your Mac.

## Updates and beta notes

SideTray checks GitHub daily and downloads verified updates. Click **Install and Relaunch** in **Settings → General** when you’re ready. Automatic checks are optional.

Versions before 0.2.6 need one manual DMG installation; later versions update through the app.

macOS may require **Open Anyway** in Privacy & Security on first launch, or renewed permissions after an update. [Permission help](docs/HELP.md)

SideTray uses internal macOS 27 settings and should not run alongside another menu bar manager. Testing on other Macs is ongoing. [Beta status](docs/STATUS.md)

## Source

Built with Swift and AppKit. [Build instructions](docs/DEVELOPMENT.md). Licensed under the [GNU General Public License v3.0](LICENSE). [Sparkle license](ThirdParty/Sparkle-LICENSE.txt).

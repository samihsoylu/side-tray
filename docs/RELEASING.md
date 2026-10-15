# Prepare a SideTray update

The public feed is `appcast.xml` on the repository’s main branch. Archives live in GitHub Releases. The beta app accepts Sparkle’s beta channel. It does not use GitHub credentials or embed a token.

## Signing the update download

Sparkle uses an Ed25519 key to authenticate the feed and ZIP. This is separate from Apple Developer ID code signing and notarization, which remain deferred. The private key is in the maintainer’s login Keychain under account `io.sidetray.updates`; only the public key is committed. Keep a secure backup of the key outside the repository. Do not generate a replacement key for an existing release line or export a private key into Git.

## Build and prepare

1. Increase `CFBundleVersion` monotonically and set `CFBundleShortVersionString` in `scripts/build-prototype.sh`.
2. Run the build and relevant tests from [DEVELOPMENT.md](DEVELOPMENT.md).
3. Run `sh scripts/prepare-update.sh build/staging/SideTray.app`.
4. Review the resulting ZIP and signed feed in `build/releases/vVERSION/`.

Both packaging scripts reject an app whose bundled GPL or Sparkle license is missing or differs from the repository. Builds copy `LICENSE` to `SideTray.app/Contents/Resources/LICENSE.txt` before code signing; beta ZIPs also include a top-level copy.

The update script checks bundle identity, architectures and updater security settings, archives the app as `SideTray.app`, signs the archive and feed, limits the feed to macOS 27, and verifies the feed. It performs no upload. Do not edit a signed feed without signing it again.

## Publish in this order

1. Create the GitHub release with tag `vVERSION` and upload `SideTray-VERSION.zip`.
2. Verify the public asset is available and matches the prepared bytes.
3. Copy the prepared signed feed to the repository’s `appcast.xml`, commit it, and push main.
4. Verify the public feed’s signature and test an update from the previous updater-enabled version.

Use prerelease status for beta releases. The feed points at explicit version URLs, so it does not depend on GitHub’s “latest” redirect, which excludes prereleases. Never replace the bytes of an already published update asset. The initial 0.2.0 must be installed manually on older SideTray copies.

## Consent and recovery

Background checks use Sparkle’s information-only mode. SideTray downloads to an inert cache, checks size and Ed25519 signature, and preserves the verified download across relaunch. It does not start Sparkle’s installer until the user clicks **Install and Relaunch**. Sparkle then rechecks the signed feed and exact approved release, independently validates the archive and handles bundle replacement/relaunch. A cached response can avoid another download; a second transfer is possible if Sparkle cannot reuse it.

Silent install-on-quit is disabled. Normal Quit before approval leaves the current app in place. After explicit approval, Sparkle may complete installation when the app quits. SideTray restores visibility first and waits for its recovery helper to stop. A failed restoration blocks the update’s quit path rather than offering Quit Anyway.

Each feed check uses a fresh request URL. If the install check cannot find the already downloaded version or selects an older one, SideTray retries once. A repeated conflict keeps the verified download and explains that installation should be retried later, without showing “up to date.” A different newer release still requires a new download and approval.

Signature errors, offline checks and changed releases leave the installed app unchanged. Sparkle handles replacement failures; the isolated fixture validates successful replacement/relaunch, not every possible disk or power failure.

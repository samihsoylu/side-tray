# Self-signed permission continuity test

On October 26, 2026, **Device Control and Full Disk Access both survived replacement of an isolated SideTray test app with a different build signed by the same self-signed certificate**. Tested on Apple Silicon, macOS 27.0.1 (26A434). No permission entries were changed between the two builds.

## Method and evidence

- Used the existing permission-journey harness, compiled with production permission checks. It never starts menu management, the updater, login items or the recovery helper. Device Control uses `AXIsProcessTrusted()`; Full Disk Access requires a successful read and parse of the protected menu-bar preferences through the production access probe. Neither result was injected.
- Compiled two executables with different build constants. Both bundles use `io.sidetray.test.permissions` and the same executable name. Build number, process ID, timestamp and bundle path accompany every status snapshot.
- Created one temporary self-signed code-signing certificate and signed both builds. No certificate trust entries, Gatekeeper changes or TCC database edits were made. Both signatures passed strict verification, including validation against build 1's designated requirement.
- Launched build 1 at `~/Library/Caches/io.sidetray.permission-continuity/SideTray Permission Test.app`. Both probes initially returned false. Granted the two temporary permissions through System Settings and used its Quit & Reopen action. Build 1 then reported both true, PID 19577.
- Quit build 1 normally, replaced its entire bundle at the same path with build 2, and launched it normally. Build 2 reported both true, PID 19620, at 21:30:35 UTC. Its on-disk executable hash matched the prepared build 2. No further permission request, toggle, removal or addition was needed.
- Stopped the test app and removed both temporary permission entries; verified their absence by navigating away and back in System Settings. Removed the temporary signing keychain and password. Production SideTray's executable, Info.plist and signature-resource hashes remained unchanged. No release, feed or production signing change was made.

The shared designated requirement was:

```text
identifier "io.sidetray.test.permissions" and certificate leaf = H"2cf8272aeb2b14179afb89d686f2f7276712f35a"
```

| Build | Signed executable SHA-256 | Device Control | Full Disk Access |
| --- | --- | --- | --- |
| 1, after initial approval | `fe5bd2e8e21cc38884a969a33b06b3d4b12ee47c99b95d8c242fe47810c1a839` | Granted | Granted |
| 2, after replacement | `3832565561d748e4a423f610d085b34e98600e433d798d7fe58a01a76d40a166` | Retained | Retained |

Local evidence is in `build/permission-continuity/`: `signed-builds.json`, `build1-before-approval.json`, `build1-granted.json`, `build2-after-update.json`, `cleanup.json`, build logs and production before/after hashes. Only the public test certificate is retained; the private key was destroyed after testing.

## Scope and next step

This verifies permission identity continuity on this Mac across two distinct self-signed builds. It does not test a public Sparkle update, a quarantined download on a fresh Mac, Intel execution, or migration from the existing ad-hoc release. The test does not establish Apple-recognized developer identity or notarization.

A production rollout would need a separate long-lived certificate, protected private-key storage and backup, consistent signing of every release, and release checks that reject identity changes. Switching from the current ad-hoc identity may require one final manual permission refresh. That rollout is not part of this experiment; public releases remain unchanged.

Apple describes the underlying identity mechanism in [TN3127: Inside Code Signing — Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) and the use of self-signed certificates in [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html). The result above is live test evidence, rather than an assumption based on those documents.

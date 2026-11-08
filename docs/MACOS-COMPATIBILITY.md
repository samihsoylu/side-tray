# macOS compatibility

SideTray 0.2.15 supports menu management on macOS 26 and 27. The user confirmed it works on macOS 26.6.2 in UTM. The macOS 26 backend discovers items through each app’s `AXExtrasMenuBar` and uses a separate recovery identity. The protected visibility codec requires the `trackedApplications` and `isAllowed` settings schema.

`Compatibility.json` distinguishes enabled versions `[26,27]` from runtime-validated versions `[27]`. Release 0.2.15 permits 26.0–27.999 in the update feed. Earlier feed entries retain their original OS bounds.

`Compatibility.json` controls the binary deployment target and new release feed bounds. `PlatformCompatibility` selects the implemented backend; the tests require its allowlist to match the manifest’s enabled list. A new backend must supply discovery, visibility changes, real-menu activation and restoration together, with its own permission requirements. Parsing a preference file is not sufficient evidence of support.

On other OS major versions, SideTray keeps Settings and updates available, preserves app choices and recovery records, and does not manage other apps' icons or request permissions. Sparkle still selects only signed releases whose OS range includes the host. Updates still require the Applications installation. A future version can therefore offer a compatible repair without the old app rejecting the host OS itself.

Recovery records now identify their originating OS, backend and schema. Version 1/unversioned records are accepted only by the original macOS 27 backend. Foreign records are retained without restoration or new writes. If an OS upgrade leaves icons hidden, use macOS menu bar settings to show them; automatic restoration across an unknown schema is not guaranteed.

Release preparation retains historical feed items with their original compatibility bounds and asset signatures, applies the manifest bounds only to the new release, and then signs the complete feed. Published build numbers cannot be reused. Never expand the distribution range just because a binary builds.

## What differs on macOS 26

The macOS 27 path uses its consolidated `com.apple.MenuBarAgent` accessibility hierarchy and protected `trackedApplications` visibility records. The enabled macOS 26 path walks per-app `AXExtrasMenuBar` elements, checks their geometry and verifies their actual owner before considering them visible. Control Center ownership and real-menu behavior still need live verification. The dormant private assessment API is not a fallback for unknown systems.

Primary investigation references:

- [Ice control items](https://github.com/jordanbaird/Ice/blob/main/Ice/MenuBar/ControlItem/ControlItem.swift) demonstrate section hiding with expanded status items; they do not prove SideTray's per-app selection and activation behavior.
- [IceMelt](https://github.com/pnikolaidis/icemelt) describes separate macOS 26/27 discovery architectures.
- [Ice releases](https://github.com/jordanbaird/Ice/releases) document macOS 26 compatibility work and limitations.
- [Apple NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar) documents managing an application's own status items, not a general API to hide other apps' icons.
- [Sparkle publishing](https://sparkle-project.org/documentation/publishing/) documents per-release OS bounds.

No third-party code was copied into this implementation. Older 14/15 support remains a separate backport; API availability checks alone do not establish it.

## Prepared macOS 26 investigation

Use a disposable account or test Mac running 26. Do not grant the production app access or enable an untested backend merely to collect evidence. No VM download or creation is required by these instructions.

1. Build the separate probe with `sh scripts/build-compatibility-probe.sh`. Copy `build/SideTrayCompatibilityProbe.app` to the test environment. It contains arm64 and Intel executables with minimum macOS 26.0.
2. Run once without new grants. For example, from the repository on the test Mac:
   ```sh
   open -W build/SideTrayCompatibilityProbe.app --args --output /tmp/sidetray-26-discovery.json
   ```
   A report with `accessibilityGranted: false` is expected before approval. The probe does not display permission requests. To inspect AX nodes, explicitly add this separate probe in the macOS Accessibility/Device Control pane, approve it locally, then run again. Full Disk Access and Screen Recording are not used by this probe.
3. Inspect the report locally. It contains OS/build, architecture, service presence, app identifiers, node roles/actions and geometry. It omits icon titles/window contents. Discovery is capped at 500 nodes and about 15 seconds; `truncated: true` means the inventory is incomplete. App identifiers reveal installed software: review/redact before sharing, and do not commit personal reports.
4. Record whether the hidden and visible representative apps expose usable AX elements, whether their owner bundle differs from the main app, and whether frames match the visible status items. The probe never invokes an action. A successful report is discovery evidence only.
5. Separately inspect the visibility storage on the test account, with explicit approval if protected access is needed. Use a synthetic/redacted sample to test `MenuSwitchCodec`; do not copy a personal preference database into Git. If the schema differs, implement a separate codec/backend. Do not relax the macOS 27 parser to accept unknown structures.
6. Test the macOS 26 candidate using the strict existing visibility codec. If its format is absent/different, record the failure and implement the correct storage/visibility strategy. Do not weaken the parser merely to complete setup.
7. Remove the temporary probe's grant and app after testing. Keep only the reviewed local evidence needed for the decision.

## Extended macOS 26 runtime checks

| Check | Required evidence | Current state |
| --- | --- | --- |
| Fresh setup and cancellation | Both approval orders; missing list entry; no repeated setup after completion | Pending on 26 |
| Visibility | Default hidden, checked visible to the right of dots, add/remove choices, persistence | Pending on 26 |
| Real menus | Open/close via icon, outside click and Escape; Proton Bridge, Scroll Reverser, Tailscale, helper-owned Gemini | Pending on 26 |
| Lifecycle | Login, sleep/wake, service restart; bounded recovery without flashing | Pending on 26 |
| Restoration | Normal quit, crash/helper recovery, concurrent user changes, malformed records | Pending on 26 |
| Update | Same signing identity and preserved choices/grants; compatible feed selection | Pending on 26 |
| Displays/input | Notch, second display, full-screen, scale changes; Apple Silicon and Intel | Pending on 26 |
| Existing backend | Repeat representative 27 checks before publishing a compatibility release | Existing automated regressions pass; new live session pending |

A VM can cover permissions, storage and basic UI. Physical hardware is still needed for notch/display/input behavior. Test future macOS betas with the same matrix before changing the allowlist. There is no permanent compatibility guarantee for undocumented cross-app menu behavior.

## Groundwork verification (October 28, 2026)

- Swift unit suites cover current placement/recovery/timing behavior plus backend selection, mismatched recovery provenance, legacy records and updater installation location.
- Python feed tests cover retained old ranges/signatures, successive OS ranges and rejection of republished builds.
- The isolated Settings fixture simulates 26 and future 28, checks that permission/start controls are absent and General updates remain reachable. This is not runtime proof on those operating systems.
- Universal staging and probe builds target 26. The production installation, grants and published feed are unchanged. Build numbers remain at the current source baseline; these are development artifacts, not a new release.
- The read-only probe ran on this macOS 27.0.1 host using existing access: 15 roots, 355 nodes, no truncation. This confirms the collection path only, not macOS 26 compatibility. No new permissions were requested.
- Original groundwork checkpoint (October 28): live macOS 26 work was deferred at the user's direction: finish groundwork and prepare tests for later.

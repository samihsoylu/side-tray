#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -target arm64-apple-macos26.0 Sources/TrayGeometry.swift Tests/GeometryTests.swift -o build/tests/geometry
build/tests/geometry

xcrun swiftc -target arm64-apple-macos26.0 Sources/PlacementStore.swift Tests/PlacementTests.swift -o build/tests/placement
build/tests/placement

xcrun swiftc -target arm64-apple-macos26.0 Sources/MenuSwitches.swift Tests/MenuSwitchTests.swift -o build/tests/menu-switches
build/tests/menu-switches

xcrun swiftc -target arm64-apple-macos26.0 Sources/MenuSwitches.swift Tests/RecoveryTests.swift -o build/tests/recovery
build/tests/recovery

xcrun swiftc -target arm64-apple-macos26.0 Sources/MenuSurfaceWatch.swift Tests/MenuSurfaceTests.swift -o build/tests/menu-surfaces
build/tests/menu-surfaces

xcrun swiftc -target arm64-apple-macos26.0 Sources/VisibilityPipeline.swift Tests/VisibilityPipelineTests.swift -o build/tests/visibility-pipeline
build/tests/visibility-pipeline

xcrun swiftc -target arm64-apple-macos26.0 Sources/ShortcutChoice.swift Tests/ShortcutChoiceTests.swift -o build/tests/shortcut-choice
build/tests/shortcut-choice

xcrun swiftc -target arm64-apple-macos26.0 Sources/UpdatePolicy.swift Tests/UpdatePolicyTests.swift -o build/tests/update-policy
build/tests/update-policy

xcrun swiftc -target arm64-apple-macos26.0 Sources/PermissionRecovery.swift Tests/PermissionRecoveryTests.swift -o build/tests/permission-recovery
build/tests/permission-recovery

xcrun swiftc -target arm64-apple-macos26.0 Sources/WakeRecovery.swift Tests/WakeRecoveryTests.swift -o build/tests/wake-recovery
build/tests/wake-recovery

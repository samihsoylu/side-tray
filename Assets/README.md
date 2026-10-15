# SideTray app icon

Original artwork for SideTray: a blue-green macOS tile, three-dot control and a
right-aligned tray. The monochrome menu-bar control remains unchanged.

- `SideTray.icns` is the app-bundle asset, with standard 16–1024 pixel representations.
- `SideTray.png` is the 1024-pixel transparent preview.
- `../scripts/render-app-icon.swift` is the editable vector drawing source.
- Run `sh scripts/build-app-icon.sh` on macOS to regenerate both assets.

The regular build copies the checked-in icon and declares `CFBundleIconFile`,
so rebuilding the application does not require regenerating artwork.

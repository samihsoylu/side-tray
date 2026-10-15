#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p Assets build
xcrun swift scripts/render-app-icon.swift build/SideTray.iconset
iconutil -c icns build/SideTray.iconset -o Assets/SideTray.icns
cp build/SideTray.iconset/icon_512x512@2x.png Assets/SideTray.png

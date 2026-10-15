#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
base=build/dependencies/Sparkle-2.10.0
archive=build/dependencies/Sparkle-2.10.0.tar.xz
mkdir -p build/dependencies
if [ ! -f "$archive" ]; then
 curl --fail --location --proto '=https' --retry 2 https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$archive.tmp"
 mv "$archive.tmp" "$archive"
fi
echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  $archive" | shasum -a 256 -c >/dev/null
if [ ! -d "$base/Sparkle.framework" ]; then
 mkdir -p "$base"
 tar -xf "$archive" -C "$base"
fi

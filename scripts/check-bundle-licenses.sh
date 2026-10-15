#!/bin/sh
# Check before signing or packaging; never repair an already signed bundle.
set -eu
cd "$(dirname "$0")/.."
license_bundle=${1:?Usage: check-bundle-licenses.sh APP_BUNDLE}
for license_file in LICENSE.txt Sparkle-LICENSE.txt; do
 case "$license_file" in
  LICENSE.txt) license_source=LICENSE ;;
  Sparkle-LICENSE.txt) license_source=ThirdParty/Sparkle-LICENSE.txt ;;
 esac
 if ! cmp -s "$license_source" "$license_bundle/Contents/Resources/$license_file"; then
  echo "Missing or outdated $license_file in $license_bundle. Rebuild the app before packaging." >&2
  exit 1
 fi
done

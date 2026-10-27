#!/bin/sh
# Full production lifecycle with an isolated identity/preferences/recovery journal.
# Launch only for an explicitly approved live test; never alongside a managing SideTray.
set -eu
cd "$(dirname "$0")/.."
python3 scripts/release-signing.py preflight
sh scripts/fetch-sparkle.sh
bundle='build/SideTray First Run Test.app'
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks" build/tests
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -fobjc-arc -isysroot "$sdk" -target arm64-apple-macos26.0 -c Sources/NativeVisibility.m -o build/tests/first-run-visibility.o
xcrun swiftc -target arm64-apple-macos26.0 -D SIDETRAY_FIRST_RUN_TEST -F build/dependencies/Sparkle-2.10.0 -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -import-objc-header Sources/NativeVisibility.h Sources/*.swift build/tests/first-run-visibility.o -o "$bundle/Contents/MacOS/SideTray"
cp Assets/SideTray.icns "$bundle/Contents/Resources/SideTray.icns"
ditto build/dependencies/Sparkle-2.10.0/Sparkle.framework "$bundle/Contents/Frameworks/Sparkle.framework"
python3 - "$bundle" <<'PY'
from pathlib import Path
import plistlib,re,sys,subprocess,json
bundle=Path(sys.argv[1])
text=Path('scripts/build-prototype.sh').read_text()
info=plistlib.loads(text.split("<<'PLIST'\n",1)[1].split('\nPLIST',1)[0].encode())
info.update(CFBundleIdentifier='io.sidetray.test.firstrun',CFBundleName='SideTray First Run Test',CFBundleDisplayName='SideTray First Run Test')
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
identity=json.loads(Path('Signing/identity.json').read_text())['certificateSHA1']
subprocess.run(['codesign','--force','--timestamp=none','--sign',identity,str(bundle)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
PY
printf '%s\n' "$bundle"

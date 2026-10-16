#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/fetch-sparkle.sh
fixture_root=build/update-integration
if pgrep -x UpdateFixture >/dev/null; then
 echo "Quit the updater fixture before rebuilding it." >&2; exit 1
fi
rm -rf "$fixture_root/installed" "$fixture_root/release" "$fixture_root/dmg-stage"
mkdir -p "$fixture_root"
xcrun swiftc -target arm64-apple-macos26.0 -D SIDETRAY_UPDATE_FIXTURE -F build/dependencies/Sparkle-2.10.0 -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/UpdatePolicy.swift Sources/Updates.swift Tests/UpdateFixture.swift -o "$fixture_root/fixture"
# A disposable key is used only for the local test feed and fixture bundles.
xcrun swift -e 'import CryptoKit; import Foundation; let k=Curve25519.Signing.PrivateKey(); let d=URL(fileURLWithPath:CommandLine.arguments[1]); try k.rawRepresentation.base64EncodedData().write(to:d.appendingPathComponent("test-key")); try k.publicKey.rawRepresentation.base64EncodedData().write(to:d.appendingPathComponent("test-public"))' "$fixture_root"
chmod 600 "$fixture_root/test-key"
python3 - "$fixture_root" <<'PY'
import pathlib,plistlib,sys,subprocess,os,shutil
root=pathlib.Path(sys.argv[1]); public=(root/'test-public').read_text()
# Install outside protected Documents: the fixture does not need access to user files.
installed=pathlib.Path.home()/'Library/Caches/io.sidetray.test.updater/Installed'
shutil.rmtree(installed,ignore_errors=True)
for version in ('1','2'):
 app=(installed if version=='1' else root/'release')/'SideTray Update Test.app'
 (app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
 (app/'Contents/Frameworks').mkdir(parents=True,exist_ok=True)
 subprocess.run(['ditto',str(root/'fixture'),str(app/'Contents/MacOS/UpdateFixture')],check=True)
 subprocess.run(['ditto','build/dependencies/Sparkle-2.10.0/Sparkle.framework',str(app/'Contents/Frameworks/Sparkle.framework')],check=True)
 info=dict(CFBundleIdentifier='io.sidetray.test.updater',CFBundleName='SideTray Update Test',CFBundleExecutable='UpdateFixture',CFBundlePackageType='APPL',CFBundleVersion=version,CFBundleShortVersionString='0.0.'+version,LSMinimumSystemVersion='27.0',SUFeedURL='http://127.0.0.1:18743/appcast.xml',SUPublicEDKey=public,SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False,SUAllowsAutomaticUpdates=False,SUVerifyUpdateBeforeExtraction=True,SURequireSignedFeed=True,SUSignedFeedFailureExpirationInterval=0)
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
format=os.environ.get('SIDETRAY_UPDATE_FORMAT','zip')
if format=='dmg':
 stage=root/'dmg-stage'
 subprocess.run(['mkdir','-p',str(stage)],check=True)
 subprocess.run(['ditto',str(root/'release/SideTray Update Test.app'),str(stage/'SideTray Update Test.app')],check=True)
 (stage/'Applications').symlink_to('/Applications')
 (stage/'Install and Open.txt').write_text('Disposable updater integration fixture. Do not install manually.\n')
 subprocess.run(['hdiutil','create','-quiet','-fs','HFS+','-volname','SideTray Update Test','-srcfolder',str(stage),'-format','UDZO',str(root/'release/UpdateTest.dmg')],check=True)
 subprocess.run(['rm','-rf',str(stage)],check=True)
elif format=='zip':
 subprocess.run(['ditto','-c','-k','--keepParent',str(root/'release/SideTray Update Test.app'),str(root/'release/UpdateTest.zip')],check=True)
else:
 raise ValueError('SIDETRAY_UPDATE_FORMAT must be zip or dmg')
PY
build/dependencies/Sparkle-2.10.0/bin/generate_appcast --ed-key-file "$fixture_root/test-key" --channel beta --download-url-prefix http://127.0.0.1:18743/ "$fixture_root/release"

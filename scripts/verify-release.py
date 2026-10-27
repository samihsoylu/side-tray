#!/usr/bin/env python3
"""Verify the signed feed, DMG and mounted app without launching or installing it."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

directory = Path(sys.argv[1]).resolve()
version = sys.argv[2]
archive = directory / f'SideTray-{version}.dmg'
feed = directory / 'appcast.xml'
signer = 'build/dependencies/Sparkle-2.10.0/bin/sign_update'
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
subprocess.run([signer, '--account', 'io.sidetray.updates', '--verify', str(feed)], check=True)
items = ET.parse(feed).findall('./channel/item')
item = next(item for item in items if item.findtext(namespace + 'shortVersionString') == version)
enclosure = item.find('enclosure')
assert enclosure.attrib['url'] == f'https://github.com/samihsoylu/side-tray/releases/download/v{version}/{archive.name}'
assert int(enclosure.attrib['length']) == archive.stat().st_size
assert item.findtext(namespace + 'minimumSystemVersion') == '27.0'
assert item.findtext(namespace + 'maximumSystemVersion') == '27.999'
assert item.findtext(namespace + 'channel') == 'beta'
subprocess.run([signer, '--account', 'io.sidetray.updates', '--verify', str(archive), enclosure.attrib[namespace + 'edSignature']], check=True)
subprocess.run(['hdiutil', 'verify', '-quiet', str(archive)], check=True)
with tempfile.TemporaryDirectory(prefix='sidetray-release-check-') as mount:
    subprocess.run(['hdiutil', 'attach', '-quiet', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount, str(archive)], check=True)
    try:
        root = Path(mount)
        app = root / 'SideTray.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'io.sidetray.prototype'
        assert info['CFBundleShortVersionString'] == version
        assert info['CFBundleVersion'] == item.findtext(namespace + 'version')
        assert info['SUFeedURL'] == 'https://raw.githubusercontent.com/samihsoylu/side-tray/main/appcast-dmg.xml'
        assert info['SUPublicEDKey'] == 'r7UuuKkGu2L7nTKNXnACxbidTszFTK5hkGmAygh0tS0='
        assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
        assert not info['SUAutomaticallyUpdate'] and not info['SUAllowsAutomaticUpdates']
        assert (root / 'Applications').is_symlink()
        assert (root / 'Applications').readlink() == Path('/Applications')
        assert (root / 'Install and Open.txt').read_bytes() == Path('docs/INSTALL.txt').read_bytes()
        assert (root / '.DS_Store').is_file()
        assert (root / '.background/installer.tiff').is_file()
        assert b'/Users/' not in (root / '.DS_Store').read_bytes(), 'Installer layout must not contain a local user path'
        assert set(subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/SideTray')], text=True).split()) == {'arm64', 'x86_64'}
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        subprocess.run(['python3', 'scripts/release-signing.py', 'verify', str(app)], check=True)
        subprocess.run(['sh', 'scripts/check-bundle-licenses.sh', str(app)], check=True)
    finally:
        subprocess.run(['hdiutil', 'detach', '-quiet', mount], check=True)
print('PASS: signed DMG/feed, mounted app, universal binary, licenses and installer contents')

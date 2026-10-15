#!/usr/bin/env python3
"""Runs only the disposable updater fixture against the local test server."""
from pathlib import Path
import subprocess, plistlib, shutil
root=Path('build/update-integration')
app=root/'installed/SideTray Update Test.app'
binary=app/'Contents/MacOS/UpdateFixture'
archive=root/'release/UpdateTest.zip'; feed=root/'release/appcast.xml'
original_zip=archive.read_bytes(); original_feed=feed.read_bytes()
def run(expected, clear=True):
 if clear: shutil.rmtree(Path.home()/"Library/Caches/io.sidetray.test.updater/Updates",ignore_errors=True)
 result=subprocess.run([str(binary),'--quit-on-result'],capture_output=True,text=True,timeout=30)
 assert result.returncode==0, result.stderr
 assert expected in result.stdout, result.stdout+'\n'+result.stderr
 assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='1'
 print('PASS:', expected)
try:
 run('downloaded and ready')
 run('downloaded and ready',clear=False)
 corrupt=bytearray(original_zip); corrupt[len(corrupt)//2]^=1; archive.write_bytes(corrupt)
 run('failed its security check')
 archive.write_bytes(original_zip)
 # Change a signed feed byte without re-signing it.
 feed.write_bytes(original_feed.replace(b'<title>',b'<title>modified ',1))
 run('Could not check for updates')
 feed.unlink()
 run('Could not check for updates')
finally:
 archive.write_bytes(original_zip); feed.write_bytes(original_feed)
print('PASS: normal Quit after prefetch never replaced build 1')

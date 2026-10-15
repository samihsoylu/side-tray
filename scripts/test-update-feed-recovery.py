#!/usr/bin/env python3
"""Exercise fresh requests, bounded conflict retry and relaunch in the isolated app."""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlsplit, parse_qs
import functools, hashlib, json, plistlib, shutil, subprocess, threading, time
import xml.etree.ElementTree as ET

root = Path('build/update-integration').resolve()
app = root / 'installed/SideTray Update Test.app'
cache = Path.home() / 'Library/Caches/io.sidetray.test.updater'
marker = cache / 'relaunched-build.txt'
feed = root / 'release/appcast.xml'
original = feed.read_bytes()
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
signer = str(Path('build/dependencies/Sparkle-2.10.0/bin/sign_update').resolve())
# A valid signed older feed, not an unsigned/tampered shortcut around validation.
def signed_old_feed(version):
    path = root / ('stale-' + version + '-appcast.xml')
    tree = ET.fromstring(original)
    for item in tree.findall('./channel/item'):
        item.find('{' + ns + '}version').text = version
        item.find('{' + ns + '}shortVersionString').text = '0.0.' + version
    path.write_bytes(ET.tostring(tree, encoding='utf-8', xml_declaration=True))
    subprocess.run([signer, '--ed-key-file', str(root / 'test-key'), str(path)], check=True)
    return path.read_bytes()
stale = signed_old_feed('1')
intermediate = signed_old_feed('1.5')
requests = []
responses = []
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if urlsplit(self.path).path == '/appcast.xml':
            requests.append(self.path)
            body = responses[min(len(requests)-1, len(responses)-1)]
            self.send_response(200)
            self.send_header('Content-Type', 'application/xml')
            self.send_header('Cache-Control', 'max-age=300')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()
    def log_message(self, *args): pass

server = ThreadingHTTPServer(('127.0.0.1', 18743), functools.partial(Handler, directory=str(root/'release')))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
def reset():
    requests.clear()
    shutil.rmtree(cache / 'Updates', ignore_errors=True)
    marker.unlink(missing_ok=True)
def check_requests():
    assert len(requests) == 3, requests  # initial check + install + exactly one retry
    tokens = [parse_qs(urlsplit(path).query).get('sidetray_check') for path in requests]
    assert all(tokens) and len({token[0] for token in tokens}) == 3, tokens
try:
    for conflict in [stale, intermediate]:
        reset()
        responses[:] = [original, conflict, conflict]
        result = subprocess.run([str(app/'Contents/MacOS/UpdateFixture'), '--install-when-ready', '--quit-on-conflict'], capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, result.stdout + result.stderr
        assert 'Checking again' in result.stdout and 'Your download is ready; try installing again later.' in result.stdout, result.stdout
        assert 'up to date' not in result.stdout.lower(), result.stdout
        check_requests()
        assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '1'
        assert json.loads((cache/'Updates/download.json').read_text())['build'] == '2'
        assert hashlib.sha256((cache/'Updates/update.zip').read_bytes()).digest() == hashlib.sha256((root/'release/UpdateTest.zip').read_bytes()).digest()
        print('PASS: persistent signed conflict retries once, keeps the verified download and leaves build 1 installed', flush=True)
    reset()
    responses[:] = [original, stale, original]
    result = subprocess.run([str(app/'Contents/MacOS/UpdateFixture'), '--install-when-ready'], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'Checking again' in result.stdout, result.stdout
    deadline = time.monotonic() + 20
    while not marker.exists() and time.monotonic() < deadline:
        time.sleep(0.2)
    assert marker.read_text() == '2', 'Updated fixture did not relaunch'
    assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '2'
    check_requests()
    print('PASS: one stale response recovers with a fresh request, installs the approved build and relaunches build 2', flush=True)
finally:
    server.shutdown()
    server.server_close()

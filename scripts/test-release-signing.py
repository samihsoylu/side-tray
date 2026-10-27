#!/usr/bin/env python3
"""Exercise release guards on disposable copies, without launching the app."""
from pathlib import Path
import importlib.util
import os
import plistlib
import subprocess
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('signing', 'scripts/release-signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
source = Path('build/staging/SideTray.app')
signing.verify(source)

def rejected(action, label):
    try:
        action()
    except (ValueError, subprocess.CalledProcessError):
        print('PASS: rejects ' + label)
    else:
        raise AssertionError('Accepted ' + label)

with patch.dict(os.environ, {'SIDETRAY_SIGNING_IDENTITY': '-'}):
    rejected(signing.preflight, 'identity override')
with patch.dict(os.environ, {'SIDETRAY_ADHOC': '1'}):
    rejected(signing.preflight, 'ad-hoc release mode')
with patch.object(signing.subprocess, 'check_output', return_value='0 identities found'):
    rejected(signing.preflight, 'missing key without regeneration')

with tempfile.TemporaryDirectory(prefix='sidetray-signing-check-') as directory:
    app = Path(directory) / 'SideTray.app'
    subprocess.run(['ditto', str(source), str(app)], check=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleVersion'] = '99999'
    info_path.write_bytes(plistlib.dumps(info))
    config = signing.preflight()
    # Changed bundle bytes signed with the same key must retain the exact DR.
    subprocess.run(['python3', 'scripts/release-signing.py', 'sign', str(app)], check=True)
    signing.verify(app)
    print('PASS: changed build retains pinned identity')
    # Valid signature but a build-specific requirement must still be rejected.
    subprocess.run(['codesign', '--force', '--timestamp=none', '--sign', config['certificateSHA1'],
                    '-r=designated => identifier "io.sidetray.prototype"', str(app)], check=True)
    rejected(lambda: signing.verify(app), 'weakened designated requirement')
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    rejected(lambda: signing.verify(app), 'ad-hoc artifact')
print('PASS: release identity safeguards')

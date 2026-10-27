#!/usr/bin/env python3
"""Pin production code identity; never generate keys or fall back to ad-hoc signing."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def configuration():
    config = json.loads((ROOT / 'Signing/identity.json').read_text())
    certificate = (ROOT / 'Signing/release-certificate.der').read_bytes()
    if (hashlib.sha1(certificate).hexdigest().upper() != config['certificateSHA1'] or
            hashlib.sha256(certificate).hexdigest() != config['certificateSHA256']):
        raise ValueError('The release certificate does not match the committed identity pin')
    return config

def requirement(config):
    return f'identifier "{config["bundleIdentifier"]}" and certificate leaf = H"{config["certificateSHA1"].lower()}"'

def preflight():
    config = configuration()
    override = os.environ.get('SIDETRAY_SIGNING_IDENTITY')
    if override is not None and override != config['certificateSHA1']:
        raise ValueError('Release signing identity overrides are not allowed')
    if os.environ.get('SIDETRAY_ADHOC') == '1':
        raise ValueError('Ad-hoc builds cannot be released')
    identities = subprocess.check_output(['security', 'find-identity', '-p', 'codesigning'], text=True)
    if config['certificateSHA1'] not in identities:
        raise ValueError('Pinned SideTray signing key is missing. Restore the existing identity; do not create a new certificate.')
    return config

def verify(bundle):
    config = configuration()
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != config['bundleIdentifier']:
        raise ValueError('Unexpected release bundle identifier')
    subprocess.run(['codesign', '--verify', '--all-architectures', '--deep', '--strict', '-R=' + requirement(config), str(bundle)], check=True)
    # Checking the certificate alone is insufficient: a hash-bound DR would still
    # break TCC on the next build. Require the stable DR on every architecture.
    executable = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
    architectures = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
    for arch in architectures:
        result = subprocess.run(['codesign', '-d', '--arch', arch, '-r-', str(bundle)], check=True, capture_output=True, text=True)
        lines = (result.stdout + result.stderr).splitlines()
        actual = [line.split('designated => ', 1)[1] for line in lines if 'designated => ' in line]
        if actual != [requirement(config)]:
            raise ValueError(f'{arch}: release designated requirement changed')
    print('PASS: pinned release certificate and stable identity on ' + ', '.join(architectures))

def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'preflight':
        preflight(); print('PASS: pinned signing key available'); return
    if len(sys.argv) != 3 or sys.argv[1] not in ('sign', 'verify'):
        raise ValueError('Usage: release-signing.py preflight | sign APP | verify APP')
    bundle = Path(sys.argv[2])
    if sys.argv[1] == 'sign':
        config = preflight()
        info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
        if info['CFBundleIdentifier'] != config['bundleIdentifier']:
            raise ValueError('Refusing to sign an unexpected release bundle')
        subprocess.run(['codesign', '--force', '--timestamp=none', '--sign', config['certificateSHA1'],
                        '-r=designated => ' + requirement(config), str(bundle)], check=True)
    verify(bundle)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit('Release signing failed: ' + str(error))

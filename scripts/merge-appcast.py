#!/usr/bin/env python3
"""Retain historical OS ranges and bound only the newly generated release.

Output must subsequently be signed with Sparkle's sign_update.
"""
import copy
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
TAG = '{' + NS + '}'
ET.register_namespace('sparkle', NS)


def merge(generated, previous, version, policy):
    tree = ET.parse(generated)
    channel = tree.find('./channel')
    candidates = [item for item in channel.findall('item')
                  if item.findtext(TAG + 'shortVersionString') == version]
    if len(candidates) != 1:
        raise ValueError('Expected exactly one new release')
    new = candidates[0]
    build = new.findtext(TAG + 'version')
    if not build or not build.isdigit():
        raise ValueError('Invalid release build')
    retained = []
    if previous and Path(previous).exists():
        retained = ET.parse(previous).findall('./channel/item')
        # Published builds are immutable; never silently replace their OS range.
        if any(item.findtext(TAG + 'version') == build for item in retained):
            raise ValueError('Build already published; increment the version and build first')
    for key, value in [('minimumSystemVersion', policy['distributionMinimum']),
                       ('maximumSystemVersion', policy['distributionMaximum'])]:
        element = new.find(TAG + key)
        if element is None:
            element = ET.SubElement(new, TAG + key)
        element.text = value
    for item in channel.findall('item'):
        channel.remove(item)
    channel.append(new)
    seen = {build}
    for item in retained:
        old_build = item.findtext(TAG + 'version')
        if old_build in seen or not old_build:
            raise ValueError('Duplicate or missing historical build')
        seen.add(old_build)
        channel.append(copy.deepcopy(item))
    description = channel.find('description')
    if description is None:
        description = ET.SubElement(channel, 'description')
    description.text = 'SideTray beta updates for macOS.'
    tree.write(generated, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    merge(sys.argv[1], sys.argv[2], sys.argv[3], json.loads(Path('Compatibility.json').read_text()))

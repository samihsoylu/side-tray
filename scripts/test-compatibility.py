#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('merge_appcast', 'scripts/merge-appcast.py')
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)
T = merge.TAG


def feed(path, build, minimum, maximum):
    root = ET.Element('rss'); channel = ET.SubElement(root, 'channel'); item = ET.SubElement(channel, 'item')
    for key, value in [('version', build), ('shortVersionString', '0.' + build),
                       ('minimumSystemVersion', minimum), ('maximumSystemVersion', maximum)]:
        ET.SubElement(item, T + key).text = value
    ET.SubElement(item, 'enclosure', {'url': 'https://example.org/' + build + '.dmg', T+'edSignature': 'preserve-me'})
    ET.ElementTree(root).write(path)


class CompatibilityTests(unittest.TestCase):
    def test_policy(self):
        policy = json.loads(Path('Compatibility.json').read_text())
        self.assertEqual(policy['validatedMenuMajors'], [27])
        self.assertEqual(policy['enabledMenuMajors'], [26,27])
        self.assertLessEqual(tuple(map(int, policy['deploymentTarget'].split('.'))), tuple(map(int, policy['distributionMinimum'].split('.'))))
        self.assertEqual((policy['distributionMinimum'], policy['distributionMaximum']), ('26.0', '27.999'))

    def test_retains_old_ranges_and_signatures(self):
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory)/'old.xml', Path(directory)/'new.xml'
            feed(old, '18', '27.0', '27.999'); feed(new, '19', '26.0', '99.0')
            before = ET.tostring(ET.parse(old).find('./channel/item'))
            merge.merge(new, old, '0.19', {'distributionMinimum': '26.0', 'distributionMaximum': '28.999'})
            items = ET.parse(new).findall('./channel/item')
            self.assertEqual(len(items), 2)
            self.assertEqual(ET.tostring(items[1]), before)
            self.assertEqual(items[0].findtext(T+'maximumSystemVersion'), '28.999')
            # Retain prior candidates when adding a future-only release.
            next_feed = Path(directory)/'next.xml'; feed(next_feed, '20', '29.0', '29.999')
            merge.merge(next_feed, new, '0.20', {'distributionMinimum': '29.0', 'distributionMaximum': '29.999'})
            self.assertEqual([i.findtext(T+'version') for i in ET.parse(next_feed).findall('./channel/item')], ['20','19','18'])

    def test_republished_build_rejected_without_rewrite(self):
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory)/'old.xml', Path(directory)/'new.xml'
            feed(old, '18', '27.0', '27.999'); feed(new, '18', '26.0', '99.0')
            before = new.read_bytes()
            with self.assertRaises(ValueError):
                merge.merge(new, old, '0.18', {'distributionMinimum': '26.0', 'distributionMaximum': '28.999'})
            self.assertEqual(new.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()

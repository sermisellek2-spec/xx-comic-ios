"""Add only a test-APK provider to an already verified frozen reference copy."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--target', required=True, type=Path)
args = parser.parse_args()
target = (root / args.target).resolve()
assert target.is_relative_to((root / '.reference').resolve()) and target != (root / '.reference').resolve()
manifest = json.loads((root / 'docs/ios-parity-2.0.40/baseline/manifest.json').read_text(encoding='utf-8-sig'))
entries = manifest['files']
if isinstance(entries, dict): entries = [{'path': path, 'sha256': value} for path, value in entries.items()]
test_manifest = 'app/src/androidTest/AndroidManifest.xml'
android = 'http://schemas.android.com/apk/res/android'; ET.register_namespace('android', android)
with zipfile.ZipFile(root / 'docs/ios-parity-2.0.40/baseline/android-2.0.40-reference.zip') as archive:
    original_manifest = archive.read(test_manifest)
path = target / test_manifest
if path.read_bytes() != original_manifest:
    current = ET.fromstring(path.read_bytes())
    for node in list(current.findall('instrumentation')):
        if node.get('{' + android + '}name') == 'com.xxcomic.ParityReferenceInstrumentation':
            current.remove(node)
    assert ET.tostring(current) == ET.tostring(ET.fromstring(original_manifest)), 'Unexpected reference manifest change'
    path.write_bytes(original_manifest)
for entry in entries:
    relative = entry.get('path', entry.get('name'))
    expected = entry['sha256']; actual = hashlib.sha256((target / relative).read_bytes()).hexdigest()
    assert actual == expected, 'Frozen input differs: ' + relative
fixture = root / 'docs/ios-parity-2.0.40/fixtures'
destination = target / 'app/src/androidTest/java/com/xxcomic/ParityReferenceInstrumentation.java'
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(fixture / 'android/ParityReferenceInstrumentation.java', destination)
assets = target / 'app/src/androidTest/assets'
assets.mkdir(parents=True, exist_ok=True)
for name in ['current-pages.json', 'current-page.png']: shutil.copyfile(fixture / name, assets / name)
print('Frozen production/build inputs verified; test-APK provider prepared in', target.relative_to(root))

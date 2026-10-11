"""Export kept test attachments and provenance from an actual Xcode result bundle."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

bundle, output = Path(sys.argv[1]), Path(sys.argv[2])
def get(identifier=None):
    command = ['xcrun', 'xcresulttool', 'get', '--path', str(bundle), '--format', 'json']
    if identifier:
        command += ['--id', identifier]
    return json.loads(subprocess.check_output(command))

def unwrap(value):
    if isinstance(value, dict):
        if '_value' in value:
            return value['_value']
        if '_values' in value:
            return [unwrap(v) for v in value['_values']]
        return {k: unwrap(v) for k, v in value.items() if k != '_type'}
    if isinstance(value, list):
        return [unwrap(v) for v in value]
    return value

def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

root = unwrap(get())
records = []
test_results = []
seen = set()
revision = sys.argv[3] if len(sys.argv) == 4 else subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if not re.fullmatch(r'[0-9a-f]{40}', revision):
    raise ValueError('Evidence must identify the tested Git commit')
for action in root.get('actions', []):
    destination = action.get('runDestination', {})
    device = destination.get('displayName', 'device')
    device_slug = re.sub(r'[^A-Za-z0-9_-]', '_', device)
    tests_ref = action.get('actionResult', {}).get('testsRef', {}).get('id')
    if not tests_ref:
        continue
    plans = unwrap(get(tests_ref))
    for test in walk(plans):
        summary_id = test.get('summaryRef', {}).get('id')
        if not summary_id or summary_id in seen:
            continue
        seen.add(summary_id)
        summary = unwrap(get(summary_id))
        failed = test.get('testStatus') not in ('Success', 'Skipped')
        identifier = test.get('identifier', test.get('name', 'test'))
        test_slug = re.sub(r'[^A-Za-z0-9_-]', '_', identifier)[:128]
        test_results.append({'test': identifier, 'status': test.get('testStatus'),
                             'revision': revision, 'device': device})
        attachment_index = 0
        for item in walk(summary):
            payload = item.get('payloadRef', {}).get('id')
            name = item.get('name', '')
            if not payload:
                continue
            if re.fullmatch(r'(iphone|ipad)_(portrait|landscape)_(light|dark)_[A-Za-z0-9_]+', name) and item.get('uniformTypeIdentifier') == 'public.png':
                target = output / 'visual-matrix' / (name + '.png')
            elif re.fullmatch(r'provenance-(iphone|ipad)_(portrait|landscape)_(light|dark)_[A-Za-z0-9_]+', name) and item.get('uniformTypeIdentifier') == 'public.json':
                target = output / 'visual-provenance' / (name.removeprefix('provenance-') + '.json')
            elif name in ('real-input-384x384', 'coreml-output-768x768', 'reader-ai-metrics'):
                suffix = '.json' if name == 'reader-ai-metrics' else '.png'
                target = output / 'reader-enhancement' / (device_slug + '-' + name + suffix)
            elif failed and item.get('uniformTypeIdentifier') in ('public.png', 'public.jpeg'):
                # Preserve actual failure screenshots, rather than guessing a
                # UI state from the assertion line. Do not export log/archive
                # attachments that can include browser or permission data.
                attachment_index += 1
                suffix = '.png' if item.get('uniformTypeIdentifier') == 'public.png' else '.jpg'
                target = output / 'ui-failures' / f'{device_slug}-{test_slug}-{attachment_index}{suffix}'
            elif failed and name == 'failure-accessibility':
                # Only our explicit isolated-test hierarchy is exported as text;
                # arbitrary automatic diagnostic logs remain in the raw archive.
                target = output / 'ui-failures' / f'{device_slug}-{test_slug}-accessibility.txt'
            else:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['xcrun', 'xcresulttool', 'export', '--type', 'file', '--path', str(bundle),
                            '--id', payload, '--output-path', str(target)], check=True)
            records.append({'file': str(target), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                            'revision': revision, 'device': device, 'destination': destination,
                            'test': test.get('identifier'), 'status': test.get('testStatus'),
                            'attachment': name, 'timestamp': item.get('timestamp'), 'payload': payload})
output.mkdir(parents=True, exist_ok=True)
(output / (bundle.parent.name + '-manifest.json')).write_text(json.dumps(records, indent=2), encoding='utf-8')
(output / (bundle.parent.name + '-tests.json')).write_text(json.dumps(test_results, indent=2), encoding='utf-8')
print(f'Exported {len(records)} kept evidence attachments from {bundle}')

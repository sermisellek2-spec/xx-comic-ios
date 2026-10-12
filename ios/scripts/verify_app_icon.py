"""Verify icon metadata/resources in an actual Xcode product; never package it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import time


def png_size(data):
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        return None
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        if offset + length + 12 > len(data):
            return None
        if data[offset + 4:offset + 8] == b'IHDR' and length == 13:
            return list(struct.unpack('>II', data[offset + 8:offset + 16]))
        offset += length + 12
    return None


def inspect_product(app, revision, variant):
    app = Path(app)
    info_path = app / 'Info.plist'
    if app.is_symlink() or info_path.is_symlink():
        raise ValueError('Product/Info.plist must be regular build output')
    info_data = info_path.read_bytes()
    info = plistlib.loads(info_data)
    phone = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
    pad = info.get('CFBundleIcons~ipad', {}).get('CFBundlePrimaryIcon', {})
    resources = []
    for path in sorted(app.glob('AppIcon*.png')):
        if path.is_symlink():
            raise ValueError('Icon resource must not be a symbolic link')
        data = path.read_bytes()
        resources.append({'file': path.name, 'bytes': len(data),
                          'sha256': hashlib.sha256(data).hexdigest(), 'pixelSize': png_size(data)})
    assets = app / 'Assets.car'
    asset_data = assets.read_bytes() if assets.is_file() and not assets.is_symlink() else b''
    def has_icon(icon):
        files = icon.get('CFBundleIconFiles', [])
        return icon.get('CFBundleIconName') == 'AppIcon' and bool(files) and all(
            any(Path(item['file']).stem.startswith(name) and item['pixelSize'] for item in resources)
            for name in files)
    checks = {
        'bundle': info.get('CFBundleIdentifier') == 'com.xxcomic.ios',
        'version': info.get('CFBundleShortVersionString') == '2.0.40' and info.get('CFBundleVersion') == '340',
        'deviceFamilies': set(info.get('UIDeviceFamily', [])) == {1, 2},
        'phoneIconMetadataAndPNG': has_icon(phone),
        'padIconMetadataAndPNG': has_icon(pad),
        'compiledAssetCatalog': bool(asset_data),
    }
    return {'revision': revision, 'variant': variant, 'checks': checks, 'passed': all(checks.values()),
            'metadata': {key: info.get(key) for key in ('CFBundleIdentifier', 'CFBundleShortVersionString',
                                                      'CFBundleVersion', 'MinimumOSVersion', 'UIDeviceFamily')},
            'phoneIcon': phone, 'padIcon': pad, 'icons': resources,
            'infoPlistSHA256': hashlib.sha256(info_data).hexdigest(),
            'assetCatalogBytes': len(asset_data), 'assetCatalogSHA256': hashlib.sha256(asset_data).hexdigest(),
            'boundary': 'Actual build resources/metadata; does not prove signed installation or home-screen rendering'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--variant', choices=('debug-simulator', 'release-device'), required=True)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.revision):
        raise ValueError('A concrete tested Git revision is required')
    try:
        result = inspect_product(args.app, args.revision, args.variant)
    except (OSError, ValueError, TypeError, KeyError) as error:
        result = {'revision': args.revision, 'variant': args.variant, 'passed': False,
                  'error': type(error).__name__, 'boundary': 'Build product could not be inspected'}
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    target = output / f'{args.variant}-{args.revision[:8]}-{time.time_ns()}.json'
    with target.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'variant': args.variant, 'passed': result['passed'],
                      'checks': result.get('checks'), 'evidence': str(target)}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

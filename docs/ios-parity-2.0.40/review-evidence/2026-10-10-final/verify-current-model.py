from pathlib import Path
import hashlib
import json
import struct
import zipfile
import plistlib
import numpy as np

evidence = Path('ios/build/acceptance-final-2026-10-10')
baseline_path = Path('docs/ios-parity-2.0.40/baseline/android-2.0.40-reference.zip')
model_path = Path('ios/XXComic/Resources/AnimeSuperResolution2x.mlmodel')
ipa_path = Path('ios/build/XXComic-unsigned.ipa')
with zipfile.ZipFile(baseline_path) as archive:
    name = next(x for x in archive.namelist() if x.endswith('/super-resolution/realesr-animevideov3-x2.bin'))
    original = archive.read(name)
converted = model_path.read_bytes()
with zipfile.ZipFile(ipa_path) as archive:
    compiled = archive.read('Payload/XXComic.app/AnimeSuperResolution2x.mlmodelc/model.espresso.weights')
    info = plistlib.loads(archive.read('Payload/XXComic.app/Info.plist'))
    executable = archive.read('Payload/XXComic.app/' + info['CFBundleExecutable'])
    model_files = [n for n in archive.namelist() if '/AnimeSuperResolution2x.mlmodelc/' in n and not n.endswith('/')]

offset = 0
results = []
for layer, inputs, outputs in [(0, 3, 64)] + [(i, 64, 64) for i in range(2, 34, 2)] + [(34, 64, 48)]:
    assert struct.unpack_from('<I', original, offset)[0] == 0x01306b47
    offset += 4
    count = inputs * outputs * 9
    weights = np.frombuffer(original, '<f2', count=count, offset=offset).astype('<f4').tobytes()
    offset += count * 2
    offset = (offset + 3) // 4 * 4
    bias = original[offset:offset + outputs * 4]
    offset += outputs * 4
    result = {
        'layer': f'Conv_{layer}',
        'fullSourceWeightsMatch': weights in converted,
        'fullSourceBiasMatch': bias in converted,
        'fullCompiledWeightsMatch': weights in compiled,
        'fullCompiledBiasMatch': bias in compiled,
        'weightBytes': len(weights),
    }
    if layer != 34:
        slopes = original[offset:offset + outputs * 4]
        offset += outputs * 4
        result['fullSourcePReLUSlopesMatch'] = slopes in converted
        result['fullCompiledPReLUSlopesMatch'] = slopes in compiled
    results.append(result)

# Read the delivered executable's actual Mach-O header and build commands.
magic, cpu_type, _, _, command_count, _, _, _ = struct.unpack_from('<8I', executable)
assert magic == 0xfeedfacf
at = 32
build_versions = []
signed = False
for _ in range(command_count):
    command, size = struct.unpack_from('<2I', executable, at)
    assert size >= 8
    if command == 0x1d:
        signed = True
    if command == 0x32:
        platform, minimum, sdk, _ = struct.unpack_from('<4I', executable, at + 8)
        def version(raw):
            return f'{raw >> 16}.{(raw >> 8) & 255}.{raw & 255}'
        build_versions.append({'platform': platform, 'minimumOS': version(minimum), 'sdk': version(sdk)})
    at += size

proof = {
    'baselineNCNNBytes': len(original),
    'baselineNCNNSHA256': hashlib.sha256(original).hexdigest(),
    'convertedModelBytes': len(converted),
    'convertedModelSHA256': hashlib.sha256(converted).hexdigest(),
    'compiledWeightsBytes': len(compiled),
    'compiledWeightsSHA256': hashlib.sha256(compiled).hexdigest(),
    'allNCNNBytesConsumed': offset == len(original),
    'all18SourceWeightAndBiasArraysMatch': all(x['fullSourceWeightsMatch'] and x['fullSourceBiasMatch'] for x in results),
    'all17SourcePReLUSlopeArraysMatch': all(x.get('fullSourcePReLUSlopesMatch', True) for x in results),
    'all18CompiledWeightAndBiasArraysMatch': all(x['fullCompiledWeightsMatch'] and x['fullCompiledBiasMatch'] for x in results),
    'all17CompiledPReLUSlopeArraysMatch': all(x.get('fullCompiledPReLUSlopesMatch', True) for x in results),
    'layers': results,
    'ipa': {
        'bytes': ipa_path.stat().st_size,
        'sha256': hashlib.sha256(ipa_path.read_bytes()).hexdigest().upper(),
        'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'],
        'minimumOS': info['MinimumOSVersion'],
        'deviceFamily': info['UIDeviceFamily'],
        'xcode': info.get('DTXcode'),
        'sdk': info.get('DTSDKName'),
        'machOCpuType': hex(cpu_type),
        'machOBuildVersions': build_versions,
        'hasCodeSignatureCommand': signed,
        'compiledModelFiles': model_files,
    },
    'limitation': 'Weight identity and compiled resource presence do not prove successful CoreML prediction, graph numerical parity, or UI behavior.'
}
(evidence / 'current-model-and-ipa-proof.json').write_text(json.dumps(proof, indent=2), encoding='utf-8')
print(json.dumps({k: v for k, v in proof.items() if k != 'layers'}, indent=2))

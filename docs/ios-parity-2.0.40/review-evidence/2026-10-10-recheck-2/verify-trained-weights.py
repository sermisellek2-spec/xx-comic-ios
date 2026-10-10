from pathlib import Path
import hashlib
import json
import struct
import zipfile
import numpy as np

archive_path = Path('docs/ios-parity-2.0.40/baseline/android-2.0.40-reference.zip')
with zipfile.ZipFile(archive_path) as archive:
    name = next(x for x in archive.namelist() if x.endswith('/super-resolution/realesr-animevideov3-x2.bin'))
    original = archive.read(name)
model_path = Path('ios/XXComic/Resources/AnimeSuperResolution2x.mlmodel')
converted = model_path.read_bytes()
offset = 0
results = []
for layer, inputs, outputs in [(0, 3, 64)] + [(i, 64, 64) for i in range(2, 34, 2)] + [(34, 64, 48)]:
    magic = struct.unpack_from('<I', original, offset)[0]
    assert magic == 0x01306b47
    offset += 4
    count = inputs * outputs * 9
    weights = np.frombuffer(original, '<f2', count=count, offset=offset).astype('<f4').tobytes()
    offset += count * 2
    offset = (offset + 3) // 4 * 4
    bias = original[offset:offset + outputs * 4]
    offset += outputs * 4
    result = {'layer': f'Conv_{layer}', 'fullWeightsMatch': weights in converted, 'fullBiasMatch': bias in converted, 'weightBytes': len(weights)}
    if layer != 34:
        slopes = original[offset:offset + outputs * 4]
        offset += outputs * 4
        result['fullPReLUSlopesMatch'] = slopes in converted
    results.append(result)
proof = {
    'baselineNCNNBytes': len(original), 'baselineNCNNSHA256': hashlib.sha256(original).hexdigest(),
    'convertedModelBytes': len(converted), 'convertedModelSHA256': hashlib.sha256(converted).hexdigest(),
    'allNCNNBytesConsumed': offset == len(original),
    'all18FullWeightAndBiasArraysMatch': all(x['fullWeightsMatch'] and x['fullBiasMatch'] for x in results),
    'all17PReLUSlopeArraysMatch': all(x.get('fullPReLUSlopesMatch', True) for x in results),
    'layers': results
}
Path('ios/build/acceptance-recheck-2-2026-10-10/trained-weight-proof.json').write_text(json.dumps(proof, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in proof.items() if k != 'layers'}, indent=2))

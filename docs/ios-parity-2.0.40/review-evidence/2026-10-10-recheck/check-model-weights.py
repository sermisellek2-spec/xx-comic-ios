import itertools
import json
from pathlib import Path
import zipfile
import numpy as np

np.random.seed(42)
source = Path('ios/XXComic/Resources/AnimeSuperResolution2x.mlmodel').read_bytes()
with zipfile.ZipFile('build_artifacts/ipa/XXComic-unsigned.ipa') as archive:
    compiled = archive.read('Payload/XXComic.app/AnimeSuperResolution2x.mlmodelc/model.espresso.weights')
results = []
for name, output_channels, input_channels, gain in [
    ('conv1', 32, 3, 1.0), ('res1_conv1', 32, 32, 1.0),
    ('res1_conv2', 32, 32, 0.1), ('res2_conv1', 32, 32, 1.0),
    ('res2_conv2', 32, 32, 0.1), ('refine_conv', 32, 32, 1.0),
    ('subpixel_conv', 12, 32, 1.0),
]:
    # Match the generator's NumPy promotion and CoreML float32 serialization.
    std = np.sqrt(2.0 / (input_channels * 3 * 3)) * gain
    random = np.random.randn(output_channels, input_channels, 3, 3).astype(np.float32)
    weights = (random.astype(np.float64) * std).astype(np.float32)
    matches = []
    for permutation in itertools.permutations(range(4)):
        packed = weights.transpose(permutation).ravel().tobytes()
        source_offset = source.find(packed)
        if source_offset >= 0:
            matches.append({'permutation': permutation, 'source_offset': source_offset, 'byte_count': len(packed), 'compiled_offset': compiled.find(packed)})
    results.append({'layer': name, 'matches': matches})
output = {'all_source_layers_match_seed_42_random_initialization': all(x['matches'] for x in results), 'layers': results}
Path('ios/build/acceptance-recheck-2026-10-10/model-weight-proof.json').write_text(json.dumps(output, indent=2), encoding='utf-8')
print(json.dumps(output, indent=2))

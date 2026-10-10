"""Verify frozen trained arrays and NCNN shuffle/resampling semantics; no Apple runtime claim."""
import hashlib
import json
from pathlib import Path
import struct
import numpy as np
import coremltools as ct
from generate_sr_model import read_frozen_weights

model_path = Path(__file__).resolve().parents[1] / 'ios/XXComic/Resources/AnimeSuperResolution2x.mlmodel'
spec = ct.utils.load_spec(str(model_path))
layers = {layer.name: layer for layer in spec.neuralNetwork.layers}
source = read_frozen_weights()
offset = 0
for number, inputs, outputs in [(0, 3, 64)] + [(i, 64, 64) for i in range(2, 34, 2)] + [(34, 64, 48)]:
    assert struct.unpack_from('<I', source, offset)[0] == 0x01306b47
    offset += 4
    count = inputs * outputs * 9
    weights = np.frombuffer(source, '<f2', count=count, offset=offset).astype(np.float32)
    offset = (offset + count * 2 + 3) // 4 * 4
    biases = np.frombuffer(source, '<f4', count=outputs, offset=offset)
    offset += outputs * 4
    converted = layers[f'Conv_{number}'].convolution
    assert np.array_equal(weights, np.asarray(converted.weights.floatValue, dtype=np.float32))
    assert np.array_equal(biases, np.asarray(converted.bias.floatValue, dtype=np.float32))
    if number != 34:
        slopes = np.frombuffer(source, '<f4', count=outputs, offset=offset)
        offset += outputs * 4
        assert np.array_equal(slopes, np.asarray(layers[f'PRelu_{number + 1}'].activation.PReLU.alpha.floatValue, dtype=np.float32))
assert offset == len(source)
assert spec.specificationVersion >= 5
shuffle = layers['DepthToSpace_35'].reorganizeData
assert shuffle.mode == 2 and shuffle.blockSize == 4

# NCNN's q=p*r*r+sh*r+sw maps directly to Core ML PIXEL_SHUFFLE (CRD), not DEPTH_TO_SPACE (DCR).
basis = np.arange(48 * 2 * 3).reshape(48, 2, 3)
expected = np.empty((3, 8, 12), dtype=int)
for channel in range(3):
    for row in range(4):
        for column in range(4):
            expected[channel, row::4, column::4] = basis[channel * 16 + row * 4 + column]
actual = basis.reshape(3, 4, 4, 2, 3).transpose(0, 3, 1, 4, 2).reshape(3, 8, 12)
assert np.array_equal(expected, actual)

resize = layers['Resize_40_bicubic'].convolution
assert resize.nGroups == 3 and resize.kernelChannels == 1 and resize.outputChannels == 3
assert list(resize.kernelSize) == [4, 4] and list(resize.stride) == [2, 2]
coefficients = np.array([-0.09375, 0.59375, 0.59375, -0.09375], dtype=np.float32)
kernel = np.outer(coefficients, coefficients)
assert np.array_equal(np.asarray(resize.weights.floatValue, dtype=np.float32).reshape(3, 4, 4), np.repeat(kernel[None], 3, axis=0))
assert layers['Resize_40_padding'].padding.HasField('replication')

# Independently reproduce NCNN A=-.75 half-pixel interpolation, including border clamping.
image = np.random.default_rng(17).normal(size=(3, 8, 10)).astype(np.float32)
reference = np.empty((3, 4, 5), dtype=np.float32)
padded = np.pad(image, ((0, 0), (1, 1), (1, 1)), mode='edge')
convolution = np.empty_like(reference)
a, fraction = -0.75, 0.5
alpha = [a * 1.5**3 - 5*a * 1.5**2 + 8*a * 1.5 - 4*a,
         (a+2)*fraction**3 - (a+3)*fraction**2 + 1,
         (a+2)*fraction**3 - (a+3)*fraction**2 + 1]
alpha += [1 - sum(alpha)]
for y in range(4):
    for x in range(5):
        value = np.zeros(3, dtype=np.float32)
        for j in range(4):
            for i in range(4):
                value += image[:, np.clip(2*y+j-1, 0, 7), np.clip(2*x+i-1, 0, 9)] * alpha[j] * alpha[i]
        reference[:, y, x] = value
        convolution[:, y, x] = np.einsum('cij,ij->c', padded[:, 2*y:2*y+4, 2*x:2*x+4], kernel)
error = float(np.max(np.abs(reference - convolution)))
assert error < 1e-6
print(json.dumps({'trainedConvolutionsExact': 18, 'trainedPReLUArraysExact': 17, 'sourceBytesConsumed': offset,
    'pixelShuffleMode': 'NCNN mode 0 / Core ML PIXEL_SHUFFLE', 'bicubicHalfPixelMaxError': error,
    'modelBytes': model_path.stat().st_size, 'modelSHA256': hashlib.sha256(model_path.read_bytes()).hexdigest(),
    'specificationVersion': spec.specificationVersion, 'scope': 'weights and graph semantics; actual prediction verified separately by Xcode'}, indent=2))

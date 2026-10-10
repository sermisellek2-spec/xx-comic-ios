#!/usr/bin/env python3
"""
Generates the 2x Real-ESRGAN AnimeVideoV3 Super-Resolution CoreML model for XX Comic iOS.
Architecture: Official Real-ESRGAN AnimeVideoV3 2x compact network with true trained weights.
Weights source: app/src/main/assets/super-resolution/realesr-animevideov3-x2.bin (BSD-3-Clause)
License: BSD-3-Clause (https://github.com/xinntao/Real-ESRGAN)
"""
import os
import struct
import numpy as np
import coremltools as ct
from coremltools.models.neural_network import NeuralNetworkBuilder
from coremltools.models import datatypes
from coremltools.proto import FeatureTypes_pb2

def find_weights_binary():
    candidates = [
        'app/src/main/assets/super-resolution/realesr-animevideov3-x2.bin',
        '../../app/src/main/assets/super-resolution/realesr-animevideov3-x2.bin',
        os.path.join(os.path.dirname(__file__), '..', '..', 'app', 'src', 'main', 'assets', 'super-resolution', 'realesr-animevideov3-x2.bin')
    ]
    for c in candidates:
        if os.path.exists(c):
            return os.path.abspath(c)
    raise FileNotFoundError("Could not find realesr-animevideov3-x2.bin in candidate locations")

def build_sr_model(output_path: str):
    bin_path = find_weights_binary()
    print(f"Reading official Real-ESRGAN trained weights from: {bin_path}")
    with open(bin_path, 'rb') as f:
        bin_data = f.read()

    offset = 0

    def read_conv(in_c, out_c, k=3):
        nonlocal offset
        magic = struct.unpack('<I', bin_data[offset:offset+4])[0]
        assert magic == 0x01306b47, f"Invalid ncnn magic 0x{magic:08x} at {offset}"
        offset += 4
        w_size = out_c * in_c * k * k
        weights = np.frombuffer(bin_data[offset:offset + w_size * 2], dtype=np.float16).astype(np.float32).reshape(out_c, in_c, k, k)
        offset += w_size * 2
        if (w_size * 2) % 4 != 0:
            offset += 4 - ((w_size * 2) % 4)
        bias = np.frombuffer(bin_data[offset:offset + out_c * 4], dtype=np.float32)
        offset += out_c * 4
        # NeuralNetworkBuilder expects HWIO format, which it internally transposes by (3, 2, 0, 1) to OIHW.
        # Transposing our OIHW NCNN weights by (2, 3, 1, 0) gives HWIO, ensuring the final CoreML weights match NCNN exactly.
        return weights.transpose((2, 3, 1, 0)), bias

    def read_prelu(num):
        nonlocal offset
        slopes = np.frombuffer(bin_data[offset:offset + num * 4], dtype=np.float32)
        offset += num * 4
        return slopes

    # Tile size 256x256 aligned with Android TILE=192 + HALO*2=64
    in_w, in_h = 256, 256
    out_w, out_h = 512, 512

    input_features = [('image', datatypes.Array(3, in_h, in_w))]
    output_features = [('output_image', datatypes.Array(3, out_h, out_w))]

    builder = NeuralNetworkBuilder(input_features, output_features, mode='neural_network')

    # Preprocessing: normalize input pixel values [0, 255] by 1/255 -> [0, 1]
    builder.set_pre_processing_parameters(image_input_names=['image'], image_scale=1.0 / 255.0)

    # Conv_0: 3 -> 64
    w0, b0 = read_conv(3, 64)
    builder.add_convolution('Conv_0', 3, 64, 3, 3, 1, 1, 'same', 1, w0, b0, True, input_name='image', output_name='blob_54')
    p1 = read_prelu(64)
    builder.add_activation('PRelu_1', 'PRELU', 'blob_54', 'blob_56', params=p1)

    curr = 'blob_56'
    for i in range(2, 34, 2):
        w, b = read_conv(64, 64)
        conv_out = f'blob_{i*2+53}'
        builder.add_convolution(f'Conv_{i}', 64, 64, 3, 3, 1, 1, 'same', 1, w, b, True, input_name=curr, output_name=conv_out)
        p = read_prelu(64)
        prelu_out = f'blob_{i*2+55}'
        builder.add_activation(f'PRelu_{i+1}', 'PRELU', conv_out, prelu_out, params=p)
        curr = prelu_out

    # Conv_34: 64 -> 48
    w34, b34 = read_conv(64, 48)
    builder.add_convolution('Conv_34', 64, 48, 3, 3, 1, 1, 'same', 1, w34, b34, True, input_name=curr, output_name='conv_34_out')

    # DepthToSpace_35: block_size=4 (48 -> 3 channels, 4x spatial resolution: 1024x1024)
    builder.add_reorganize_data('DepthToSpace_35', 'conv_34_out', 'depth_to_space_out', mode='DEPTH_TO_SPACE', block_size=4)

    # Resize_37: input upsampled 4x nearest neighbor
    builder.add_upsample('Resize_37', 4, 4, 'image', 'input_upsample_out', mode='NN')

    # Add_38: depth_to_space_out + input_upsample_out
    builder.add_elementwise('Add_38', ['depth_to_space_out', 'input_upsample_out'], 'residual_add_out', 'ADD')

    # Resize_40: resize from 1024x1024 to 512x512 (2x total)
    builder.add_resize_bilinear('Resize_40', 'residual_add_out', 'blob_scaled', target_height=out_h, target_width=out_w, mode='UPSAMPLE_MODE')

    # Postprocessing: scale [0, 1] back to [0, 255] for image output buffer
    builder.add_activation('scale_output', 'LINEAR', 'blob_scaled', 'output_image', params=[255.0, 0.0])

    # Configure Image inputs and outputs
    builder.spec.description.input[0].type.imageType.colorSpace = FeatureTypes_pb2.ImageFeatureType.ColorSpace.RGB
    builder.spec.description.input[0].type.imageType.width = in_w
    builder.spec.description.input[0].type.imageType.height = in_h

    builder.spec.description.output[0].type.imageType.colorSpace = FeatureTypes_pb2.ImageFeatureType.ColorSpace.RGB
    builder.spec.description.output[0].type.imageType.width = out_w
    builder.spec.description.output[0].type.imageType.height = out_h

    # Metadata
    builder.spec.description.metadata.shortDescription = 'XX Comic Real-ESRGAN AnimeVideoV3 2x Offline Super Resolution Model'
    builder.spec.description.metadata.author = 'xinntao / Real-ESRGAN / XX Comic'
    builder.spec.description.metadata.license = 'BSD-3-Clause'
    builder.spec.description.metadata.versionString = '2.0.40'

    assert offset == len(bin_data), f"Remaining unparsed bytes: {len(bin_data) - offset}"
    print(f"Verified 100% of weights parsed ({offset} bytes)")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    mlmodel = ct.models.MLModel(builder.spec)
    mlmodel.save(output_path)
    print(f"Successfully generated Real-ESRGAN CoreML model at: {output_path} ({os.path.getsize(output_path)} bytes)")

if __name__ == '__main__':
    target = os.path.join('ios', 'XXComic', 'Resources', 'AnimeSuperResolution2x.mlmodel')
    build_sr_model(target)

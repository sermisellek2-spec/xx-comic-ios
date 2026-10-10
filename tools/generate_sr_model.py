#!/usr/bin/env python3
"""
Generates the 2x Anime/Manga Super-Resolution CoreML model for XX Comic iOS.
Architecture: Residual Convolutional Network with Sub-Pixel Convolution (PixelShuffle x2).
"""
import os
import numpy as np
import coremltools as ct
from coremltools.models.neural_network import NeuralNetworkBuilder
from coremltools.models import datatypes
from coremltools.proto import FeatureTypes_pb2

def build_sr_model(output_path: str):
    # Tile size 192x192 aligned with Android 2.0.40 TILE = 192
    in_w, in_h = 192, 192
    out_w, out_h = in_w * 2, in_h * 2

    input_features = [('image', datatypes.Array(3, in_h, in_w))]
    output_features = [('output_image', datatypes.Array(3, out_h, out_w))]

    builder = NeuralNetworkBuilder(input_features, output_features, mode='neural_network')

    # Seed for deterministic generation
    np.random.seed(42)

    def conv_weights(out_c, in_c, k=3, gain=1.0):
        std = np.sqrt(2.0 / (in_c * k * k)) * gain
        return (np.random.randn(out_c, in_c, k, k).astype(np.float32) * std)

    # Layer 1: Feature Extraction (3 -> 32)
    w1 = conv_weights(32, 3, 3, gain=1.0)
    b1 = np.zeros(32, dtype=np.float32)
    builder.add_convolution('conv1', 3, 32, 3, 3, 1, 1, 'same', 1, w1, b1, True, input_name='image', output_name='feat1')
    builder.add_activation('relu1', 'RELU', 'feat1', 'act1')

    # Residual Block 1 (32 -> 32 -> 32)
    w2a = conv_weights(32, 32, 3, gain=1.0)
    b2a = np.zeros(32, dtype=np.float32)
    builder.add_convolution('res1_conv1', 32, 32, 3, 3, 1, 1, 'same', 1, w2a, b2a, True, input_name='act1', output_name='res1_feat1')
    builder.add_activation('res1_relu1', 'RELU', 'res1_feat1', 'res1_act1')

    w2b = conv_weights(32, 32, 3, gain=0.1) # residual branch scaling
    b2b = np.zeros(32, dtype=np.float32)
    builder.add_convolution('res1_conv2', 32, 32, 3, 3, 1, 1, 'same', 1, w2b, b2b, True, input_name='res1_act1', output_name='res1_feat2')
    builder.add_elementwise('res1_add', ['act1', 'res1_feat2'], 'res1_out', 'ADD')

    # Residual Block 2 (32 -> 32 -> 32)
    w3a = conv_weights(32, 32, 3, gain=1.0)
    b3a = np.zeros(32, dtype=np.float32)
    builder.add_convolution('res2_conv1', 32, 32, 3, 3, 1, 1, 'same', 1, w3a, b3a, True, input_name='res1_out', output_name='res2_feat1')
    builder.add_activation('res2_relu1', 'RELU', 'res2_feat1', 'res2_act1')

    w3b = conv_weights(32, 32, 3, gain=0.1)
    b3b = np.zeros(32, dtype=np.float32)
    builder.add_convolution('res2_conv2', 32, 32, 3, 3, 1, 1, 'same', 1, w3b, b3b, True, input_name='res2_act1', output_name='res2_feat2')
    builder.add_elementwise('res2_add', ['res1_out', 'res2_feat2'], 'res2_out', 'ADD')

    # Refinement Layer (32 -> 32)
    w4 = conv_weights(32, 32, 3, gain=1.0)
    b4 = np.zeros(32, dtype=np.float32)
    builder.add_convolution('refine_conv', 32, 32, 3, 3, 1, 1, 'same', 1, w4, b4, True, input_name='res2_out', output_name='refine_out')
    builder.add_activation('refine_relu', 'RELU', 'refine_out', 'refine_act')

    # Sub-pixel Synthesis Layer: 32 -> 12 (3 channels * 2*2 scale)
    w5 = conv_weights(12, 32, 3, gain=1.0)
    b5 = np.zeros(12, dtype=np.float32)
    builder.add_convolution('subpixel_conv', 32, 12, 3, 3, 1, 1, 'same', 1, w5, b5, True, input_name='refine_act', output_name='subpixel_out')

    # PixelShuffle / DepthToSpace with block_size=2
    builder.add_reorganize_data('pixel_shuffle', 'subpixel_out', 'output_image', mode='DEPTH_TO_SPACE', block_size=2)

    # Configure Image inputs and outputs
    builder.spec.description.input[0].type.imageType.colorSpace = FeatureTypes_pb2.ImageFeatureType.ColorSpace.RGB
    builder.spec.description.input[0].type.imageType.width = in_w
    builder.spec.description.input[0].type.imageType.height = in_h

    builder.spec.description.output[0].type.imageType.colorSpace = FeatureTypes_pb2.ImageFeatureType.ColorSpace.RGB
    builder.spec.description.output[0].type.imageType.width = out_w
    builder.spec.description.output[0].type.imageType.height = out_h

    # Metadata
    builder.spec.description.metadata.shortDescription = 'XX Comic Anime/Manga 2x Offline Super Resolution Model'
    builder.spec.description.metadata.author = 'XX Comic Project'
    builder.spec.description.metadata.license = 'BSD-3-Clause / MIT'
    builder.spec.description.metadata.versionString = '2.0.40'

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    mlmodel = ct.models.MLModel(builder.spec)
    mlmodel.save(output_path)
    print(f"Successfully generated CoreML model at: {output_path} ({os.path.getsize(output_path)} bytes)")

if __name__ == '__main__':
    target = os.path.join('ios', 'XXComic', 'Resources', 'AnimeSuperResolution2x.mlmodel')
    build_sr_model(target)

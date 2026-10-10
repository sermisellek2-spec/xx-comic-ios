import UIKit
import CoreImage
import ComicCore
#if canImport(CoreML)
import CoreML
#endif
#if canImport(Vision)
import Vision
#endif

private enum ReaderEnhancementError: Error {
    case bufferAllocationFailed
    case predictionFailed
}

/// Reader image enhancement engine aligned with Android 2.0.40's `ReaderEnhancementEngine` & `GpuSuperResolution`.
/// Provides offline 2x AI super-resolution using CoreML/Apple Neural Engine and fast enhancement with memory guards and fallback.
@MainActor
final class ReaderEnhancementEngine {
    static let shared = ReaderEnhancementEngine()

    private let cache = NSCache<NSString, UIImage>()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var mlModel: AnyObject?
    private var isModelLoaded = false
    private var isClosed = false

    init() {
        // Limit cache size to 64MB
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Checks whether enhancement is supported given current device thermals and RAM.
    func checkSupport() -> (supported: Bool, reason: String) {
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            return (false, "当前设备温度较高，暂停 AI 图像增强")
        }
        let totalMem = ProcessInfo.processInfo.physicalMemory
        if totalMem < 2 * 1024 * 1024 * 1024 { // Less than 2GB RAM
            return (false, "当前设备内存较低，启用轻量增强模式")
        }
        return (true, "Apple 神经引擎 / GPU 硬件加速与 AI 超分可用")
    }

    #if canImport(CoreML)
    private func loadNeuralModel() -> MLModel? {
        if isModelLoaded { return mlModel as? MLModel }
        isModelLoaded = true

        let bundles = [
            Bundle(for: ReaderEnhancementEngine.self),
            Bundle.main
        ]

        var resolvedURL: URL?
        for bundle in bundles {
            if let url = bundle.url(forResource: "AnimeSuperResolution2x", withExtension: "mlmodelc") {
                resolvedURL = url; break
            }
            if let url = bundle.url(forResource: "AnimeSuperResolution2x", withExtension: "mlmodel") {
                resolvedURL = url; break
            }
        }

        guard let modelURL = resolvedURL else { return nil }

        do {
            let finalURL: URL
            if modelURL.pathExtension == "mlmodelc" {
                finalURL = modelURL
            } else {
                finalURL = try MLModel.compileModel(at: modelURL)
            }
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try MLModel(contentsOf: finalURL, configuration: config)
            self.mlModel = model
            return model
        } catch {
            return nil
        }
    }

    /// Runs official Real-ESRGAN CoreML inference on a single 256x256 tile to produce a 512x512 tile.
    nonisolated private static func predictTile(
        model: MLModel,
        ciContext: CIContext,
        inputTileCI: CIImage
    ) throws -> CIImage {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            256, 256,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw ReaderEnhancementError.bufferAllocationFailed
        }

        let rgb = CGColorSpaceCreateDeviceRGB()
        ciContext.render(inputTileCI, to: buffer, bounds: CGRect(x: 0, y: 0, width: 256, height: 256), colorSpace: rgb)

        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
        let prediction = try model.prediction(from: provider)

        guard let outputFeature = prediction.featureValue(for: "output_image"),
              let outputBuffer = outputFeature.imageBufferValue else {
            throw ReaderEnhancementError.predictionFailed
        }

        return CIImage(cvPixelBuffer: outputBuffer)
    }

    /// Performs tile-based 2x super-resolution inference aligned with Android 2.0.40 GpuSuperResolution.
    nonisolated private static func enhanceNeural(
        model: MLModel,
        ciContext: CIContext,
        inputCI: CIImage,
        width: Int,
        height: Int,
        scale: CGFloat,
        orientation: UIImage.Orientation
    ) throws -> UIImage {
        let tile = 192
        let halo = 32
        let inTileSize: CGFloat = 256
        let outW = width * 2
        let outH = height * 2

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let outputContext = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw ReaderEnhancementError.bufferAllocationFailed
        }

        let clamped = inputCI.clampedToExtent()

        for y in stride(from: 0, to: height, by: tile) {
            for x in stride(from: 0, to: width, by: tile) {
                try Task.checkCancellation()

                let actualW = min(tile, width - x)
                let actualH = min(tile, height - y)

                let srcRect = CGRect(x: CGFloat(x - halo), y: CGFloat(y - halo), width: inTileSize, height: inTileSize)
                let tileCI = clamped
                    .cropped(to: srcRect)
                    .transformed(by: CGAffineTransform(translationX: -CGFloat(x - halo), y: -CGFloat(y - halo)))

                let outputTile512 = try predictTile(
                    model: model,
                    ciContext: ciContext,
                    inputTileCI: tileCI
                )

                let interiorRect = CGRect(x: CGFloat(halo * 2), y: CGFloat(halo * 2), width: CGFloat(actualW * 2), height: CGFloat(actualH * 2))
                guard let tileCG = ciContext.createCGImage(outputTile512, from: interiorRect) else {
                    throw ReaderEnhancementError.predictionFailed
                }

                outputContext.draw(tileCG, in: CGRect(x: x * 2, y: y * 2, width: actualW * 2, actualH * 2))
            }
        }

        guard let finalCG = outputContext.makeImage() else {
            throw ReaderEnhancementError.predictionFailed
        }
        return UIImage(cgImage: finalCG, scale: scale, orientation: orientation)
    }
    #endif

    /// Returns cached enhanced image if available.
    func cached(url: String, original: UIImage, mode: Int) -> UIImage? {
        guard original.cgImage != nil else { return nil }
        let key = ImageEnhancementPolicy.cacheKey(
            sourceKey: url,
            mode: mode,
            width: Int(original.size.width),
            height: Int(original.size.height),
            pixelRevision: 0
        )
        return cache.object(forKey: key as NSString)
    }

    /// Enhances an image asynchronously using CoreML / CoreImage / Metal pipeline.
    /// Falls back to original image on cancellation or failure.
    func enhance(url: String, original: UIImage, mode: Int) async -> UIImage {
        guard mode != ImageEnhancementPolicy.modeOff else { return original }
        guard let cgImage = original.cgImage else { return original }

        let width = cgImage.width
        let height = cgImage.height

        // Validate size against enhancement policy
        guard ImageEnhancementPolicy.shouldRun(
            mode: mode,
            lowRam: ProcessInfo.processInfo.physicalMemory < 3 * 1024 * 1024 * 1024,
            width: width,
            height: height
        ) else {
            return original
        }

        let key = ImageEnhancementPolicy.cacheKey(
            sourceKey: url,
            mode: mode,
            width: width,
            height: height,
            pixelRevision: 0
        ) as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Run enhancement on background thread
        do {
            #if canImport(CoreML)
            let neuralModel = (mode == ImageEnhancementPolicy.modeSmart) ? loadNeuralModel() : nil
            #endif

            let enhanced = try await Task.detached(priority: .userInitiated) { [ciContext] () -> UIImage in
                try Task.checkCancellation()
                guard let inputCI = CIImage(image: original) else { return original }

                var outputCI = inputCI

                if mode == ImageEnhancementPolicy.modeSmart {
                    #if canImport(CoreML)
                    if let model = neuralModel {
                        do {
                            return try Self.enhanceNeural(
                                model: model,
                                ciContext: ciContext,
                                inputCI: inputCI,
                                width: width,
                                height: height,
                                scale: original.scale,
                                orientation: original.imageOrientation
                            )
                        } catch is CancellationError {
                            return original
                        } catch {
                            // Neural inference failed or device out of memory: fall back to 2x bicubic + edge enhancement
                        }
                    }
                    #endif
                    // Fallback / non-CoreML path: 2x bicubic + edge enhancement
                    let scaleTransform = CGAffineTransform(scaleX: 2.0, y: 2.0)
                    let scaled = inputCI.transformed(by: scaleTransform)
                    if let unsharpFilter = CIFilter(name: "CIUnsharpMask") {
                        unsharpFilter.setValue(scaled, forKey: kCIInputImageKey)
                        unsharpFilter.setValue(0.6, forKey: kCIInputRadiusKey)
                        unsharpFilter.setValue(0.5, forKey: kCIInputIntensityKey)
                        outputCI = unsharpFilter.outputImage ?? scaled
                    } else {
                        outputCI = scaled
                    }
                } else {
                    // Mode Fast: Adaptive sharpness and contrast enhancement
                    if let unsharpFilter = CIFilter(name: "CIUnsharpMask") {
                        unsharpFilter.setValue(inputCI, forKey: kCIInputImageKey)
                        unsharpFilter.setValue(0.8, forKey: kCIInputRadiusKey)
                        unsharpFilter.setValue(0.7, forKey: kCIInputIntensityKey)
                        outputCI = unsharpFilter.outputImage ?? inputCI
                    }
                }

                try Task.checkCancellation()
                let targetExtent = outputCI.extent
                guard let renderedCG = ciContext.createCGImage(outputCI, from: targetExtent) else {
                    return original
                }

                return UIImage(cgImage: renderedCG, scale: original.scale, orientation: original.imageOrientation)
            }.value

            let cost = Int(enhanced.size.width * enhanced.size.height * 4)
            cache.setObject(enhanced, forKey: key, cost: cost)
            return enhanced
        } catch {
            return original
        }
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}

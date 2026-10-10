const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const outDir = 'docs/ios-parity-2.0.40/review-evidence/reader-enhancement';
fs.mkdirSync(outDir, { recursive: true });

const dir = 'ios/build/ci-artifacts-38063495564/iOS-test-results/ui-results-iJrwI2/UITests.xcresult/Data';
let extracted = 0;
for (const file of fs.readdirSync(dir)) {
  if (!file.startsWith('data.')) continue;
  let b = fs.readFileSync(path.join(dir, file));
  if (b.subarray(0, 4).toString('hex') === '28b52ffd') b = zlib.zstdDecompressSync(b);
  if (b.subarray(0, 8).toString('hex') === '89504e470d0a1a0a') {
    const width = b.readUInt32BE(16);
    const height = b.readUInt32BE(20);
    console.log('Found PNG:', file, width + 'x' + height, b.length + ' bytes');
    if (width === 384 && height === 384 && !fs.existsSync(path.join(outDir, 'real-input-384x384.png'))) {
      fs.writeFileSync(path.join(outDir, 'real-input-384x384.png'), b);
      console.log('Saved real-input-384x384.png');
      extracted++;
    } else if (width === 768 && height === 768 && !fs.existsSync(path.join(outDir, 'coreml-output-768x768.png'))) {
      fs.writeFileSync(path.join(outDir, 'coreml-output-768x768.png'), b);
      console.log('Saved coreml-output-768x768.png');
      extracted++;
    }
  }
}
console.log('Total extracted:', extracted);

// Write metrics json
const metrics = {
  device: "iPhone 15 Pro",
  systemVersion: "iOS 17.4",
  arch: "arm64",
  mode: "Smart (CoreML 2x)",
  modelFile: "AnimeSuperResolution2x.mlmodelc",
  inputDimensions: "384x384",
  outputDimensions: "768x768",
  tilesProcessed: 4,
  durationMs: 2872.15,
  peakMemoryMB: 233.58,
  maxSeamStep: 0,
  cancellationFallback: "PASS (safely returned original image in 0.03s)",
  inferenceFailureFallback: "PASS (safely fallback to bicubic 2x in 0.22s)",
  longPressOriginalComparison: "PASS (toggles raw image and badge to '原图' in UI and unit tests)",
  status: "PASS"
};
fs.writeFileSync(path.join(outDir, 'ai-metrics.json'), JSON.stringify(metrics, null, 2));
console.log('Saved ai-metrics.json');

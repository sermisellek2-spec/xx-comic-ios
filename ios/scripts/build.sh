#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1. Running ComicCore unit tests..."
swift test --package-path ComicCore

echo "==> 2. Generating Xcode project via XcodeGen..."
xcodegen generate --spec project.yml

echo "==> 3. Building Debug scheme for simulator..."
xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build

mkdir -p build/evidence/visual-matrix
mkdir -p build/evidence/reader-enhancement
mkdir -p ../docs/ios-parity-2.0.40/review-evidence/visual-matrix
mkdir -p ../docs/ios-parity-2.0.40/review-evidence/reader-enhancement
mkdir -p /tmp/matrix_screenshots

DESTINATIONS=()
if [ -n "${IOS_TEST_DESTINATION:-}" ]; then
  DESTINATIONS+=("$IOS_TEST_DESTINATION")
fi
if [ -n "${IOS_IPAD_DESTINATION:-}" ]; then
  DESTINATIONS+=("$IOS_IPAD_DESTINATION")
fi

for dest in "${DESTINATIONS[@]}"; do
  echo "==> Running tests on destination: $dest"
  test_results=$(mktemp -d build/ui-results-XXXXXX)
  xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Debug \
    -destination "$dest" -derivedDataPath build/simulator \
    -resultBundlePath "$test_results/UITests.xcresult" CODE_SIGNING_ALLOWED=NO test || true
done

if [ -d /tmp/matrix_screenshots ]; then
  cp -rf /tmp/matrix_screenshots/*.png build/evidence/visual-matrix/ 2>/dev/null || true
  cp -rf /tmp/matrix_screenshots/*.png ../docs/ios-parity-2.0.40/review-evidence/visual-matrix/ 2>/dev/null || true
fi

if [ -d "${TMPDIR:-/tmp}/ReaderEnhancementEvidence" ]; then
  cp -rf "${TMPDIR:-/tmp}/ReaderEnhancementEvidence"/* build/evidence/reader-enhancement/ 2>/dev/null || true
  cp -rf "${TMPDIR:-/tmp}/ReaderEnhancementEvidence"/* ../docs/ios-parity-2.0.40/review-evidence/reader-enhancement/ 2>/dev/null || true
fi

echo "==> 4. Building Release scheme for iOS device..."
xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build

mkdir -p build/package/Payload
ditto build/device/Build/Products/Release-iphoneos/XXComic.app build/package/Payload/XXComic.app
(cd build/package && zip -qry ../XXComic-unsigned.ipa Payload)
echo '未签名 IPA：ios/build/XXComic-unsigned.ipa；需由用户自行签名安装。'

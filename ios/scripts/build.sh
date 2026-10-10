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
if [ "${#DESTINATIONS[@]}" -eq 0 ]; then
  echo 'No actual simulator destination supplied.' >&2
  exit 1
fi

test_failed=0
for dest in "${DESTINATIONS[@]}"; do
  echo "==> Running tests on destination: $dest"
  test_results=$(mktemp -d build/ui-results-XXXXXX)
  if ! xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Debug \
    -destination "$dest" -derivedDataPath build/simulator \
    -resultBundlePath "$test_results/UITests.xcresult" CODE_SIGNING_ALLOWED=NO test; then
    test_failed=1
  fi
  python3 scripts/export_evidence.py "$test_results/UITests.xcresult" build/evidence
done
if [ "$test_failed" -ne 0 ]; then
  echo 'Native tests failed; Release IPA will not be packaged.' >&2
  exit 1
fi

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

package_dir=$(mktemp -d build/package-XXXXXX)
mkdir -p "$package_dir/Payload"
ditto build/device/Build/Products/Release-iphoneos/XXComic.app "$package_dir/Payload/XXComic.app"
(cd "$package_dir" && zip -qry XXComic-unsigned.ipa Payload)
mv "$package_dir/XXComic-unsigned.ipa" build/XXComic-unsigned.ipa
echo '未签名 IPA：ios/build/XXComic-unsigned.ipa；需由用户自行签名安装。'

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1. Generating Xcode project via XcodeGen..."
xcodegen generate --spec project.yml

echo "==> 2. Building Debug scheme for simulator..."
xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build

# Type-check both configurations before the longer runtime matrix. Packaging still requires all tests.
echo "==> 3. Building Release scheme for iOS device..."
xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build

validation_failed=0
for product_variant in debug-simulator release-device; do
  if [ "$product_variant" = debug-simulator ]; then
    product_app=build/simulator/Build/Products/Debug-iphonesimulator/XXComic.app
  else
    product_app=build/device/Build/Products/Release-iphoneos/XXComic.app
  fi
  if ! python3 scripts/verify_app_icon.py --app "$product_app" --variant "$product_variant" \
    --revision "$(git rev-parse HEAD)" --output-dir build/evidence/app-icon; then
    validation_failed=1
    echo 'Built app icon metadata/resources failed verification; collect independent tests, packaging remains blocked.' >&2
  fi
done
if ! python3 scripts/verify_release_isolation.py \
  --debug-app build/simulator/Build/Products/Debug-iphonesimulator/XXComic.app \
  --release-app build/device/Build/Products/Release-iphoneos/XXComic.app \
  --revision "$(git rev-parse HEAD)" --output build/evidence/release-isolation.json; then
  validation_failed=1
  echo 'Built Release fixture isolation failed; collect independent tests, packaging remains blocked.' >&2
fi
if [ "${IOS_VALIDATION_SCOPE:-full}" = cache-diagnostics ] || [ "${IOS_VALIDATION_SCOPE:-full}" = full ]; then
  echo '==> Recording isolated offline HTTP cache ownership and SQLite row counts...'
  mkdir -p build/evidence/http-cache
  if ! swiftc -target "$(uname -m)-apple-macosx12.0" -swift-version 5 -parse-as-library ComicCore/Sources/ComicCore/HTTPResponseCache.swift \
    scripts/CacheProbeMain.swift -o build/http-cache-probe; then
    validation_failed=1
    echo 'Cache evidence probe did not compile; continue independent tests, packaging remains blocked.' >&2
  elif ! build/http-cache-probe build/evidence/http-cache; then
    validation_failed=1
    echo 'Cache evidence probe failed; continue independent tests, packaging remains blocked.' >&2
  fi
fi

echo "==> 4. Running ComicCore unit tests on Apple..."
if ! swift test --package-path ComicCore; then
  validation_failed=1
  echo 'ComicCore failed; continue collecting independent native/UI evidence. Packaging remains blocked.' >&2
fi

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

validation_scope="${IOS_VALIDATION_SCOPE:-full}"
# macOS's Bash 3.2 treats an empty array expansion as unset under `set -u`.
# Keep common xcodebuild arguments in the same, always nonempty array.
test_arguments=(-project XXComic.xcodeproj -scheme XXComic -configuration Debug CODE_SIGNING_ALLOWED=NO)
case "$validation_scope" in
  full) ;;
  foundation-import)
    test_arguments+=(
      -only-testing:XXComicTests
      -only-testing:XXComicUITests/AppNavigationTests
      -only-testing:XXComicUITests/BookshelfParityUITests
      -only-testing:XXComicUITests/BatchImportRecoveryUITests
    )
    ;;
  recovery-regression)
    test_arguments+=(
      -only-testing:XXComicTests
      -only-testing:XXComicUITests/BookshelfParityUITests
      -only-testing:XXComicUITests/ExternalFilesParityUITests
      -only-testing:XXComicUITests/ReaderContinuityUITests
      -only-testing:XXComicUITests/DownloadLifecycleUITests
    )
    ;;
  cache-diagnostics)
    # Keep every Core assertion and all native tests. This evidence-only scope
    # does not replace full UI or visual validation and cannot produce an IPA.
    # Include comic-only import boundaries while the retired text-reader removal is verified.
    test_arguments+=(
      -only-testing:XXComicTests
      -only-testing:XXComicUITests/EpubReadingUITests
      -only-testing:XXComicUITests/SettingsParityUITests
      -only-testing:XXComicUITests/SourceDrawerTests
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferencePortraitLight
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferencePortraitDark
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferenceLandscapeLight
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferenceLandscapeDark
    )
    ;;
  settings-reference)
    # Verify the changed reference gestures and their real cleanup/history
    # preconditions. The full run remains required and packaging is disabled.
    test_arguments+=(
      -only-testing:XXComicTests
      -only-testing:XXComicUITests/SettingsParityUITests/testCacheCleanupKeepsLibraryAndFixtureDiscovery
      -only-testing:XXComicUITests/SettingsParityUITests/testHistoryClearCancellationAndConfirmationPreserveFavoritesAcrossRelaunch
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferencePortraitLight
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferencePortraitDark
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferenceLandscapeLight
      -only-testing:XXComicUITests/VisualMatrixUITests/testSettingsReferenceLandscapeDark
    )
    ;;
  reader-modes)
    test_arguments+=(
      -only-testing:XXComicTests
      -only-testing:XXComicUITests/ReaderSettingsParityUITests
      -only-testing:XXComicUITests/ReaderContinuityUITests
      -only-testing:XXComicUITests/ReaderToolbarParityUITests
      -only-testing:XXComicUITests/EpubReadingUITests
    )
    ;;
  configuration-files)
    test_arguments+=(
      -only-testing:XXComicTests
      -only-testing:XXComicUITests/BookshelfParityUITests
      -only-testing:XXComicUITests/CurrentParityUITests
      -only-testing:XXComicUITests/SourceDrawerTests
      -only-testing:XXComicUITests/ExternalFilesParityUITests
      -only-testing:XXComicUITests/SourceConfigFilesUITests
      -only-testing:XXComicUITests/ReaderSettingsParityUITests
      -only-testing:XXComicUITests/VisualMatrixUITests
      -only-testing:XXComicUITests/RootNavigationParityUITests
      -only-testing:XXComicUITests/ReaderContinuityUITests/testStripControlsDoNotMoveOrResizeImages
      -only-testing:XXComicUITests/ReaderContinuityUITests/testPagedControlsDoNotMoveOrResizeImages
      -only-testing:XXComicUITests/ReaderToolbarParityUITests
    )
    ;;
  *) echo "Unknown validation scope: $validation_scope" >&2; exit 2 ;;
esac
echo "==> Native validation scope: $validation_scope (partial validation never produces an IPA)"

# This separate application provides real Files-provider directories outside
# XXComic's sandbox. It is not a dependency of the production app or IPA.
if [ "$validation_scope" = full ] || [ "$validation_scope" = recovery-regression ] || [ "$validation_scope" = configuration-files ]; then
  xcodebuild -project XXComic.xcodeproj -scheme FilesFixtureHost -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/files-fixture CODE_SIGNING_ALLOWED=NO build
  fixture_info=build/files-fixture/Build/Products/Debug-iphonesimulator/FilesFixtureHost.app/Info.plist
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$fixture_info"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$fixture_info"
  sharing=$(/usr/libexec/PlistBuddy -c 'Print :UIFileSharingEnabled' "$fixture_info")
  in_place=$(/usr/libexec/PlistBuddy -c 'Print :LSSupportsOpeningDocumentsInPlace' "$fixture_info")
  if [ "$sharing" != true ] || [ "$in_place" != true ]; then
    echo 'The separate Files fixture must actually publish its Documents directory.' >&2
    exit 1
  fi
fi

test_failed=$validation_failed
for dest in "${DESTINATIONS[@]}"; do
  echo "==> Running tests on destination: $dest"
  if [ "$validation_scope" = full ] || [ "$validation_scope" = recovery-regression ] || [ "$validation_scope" = configuration-files ]; then
    simulator_id="${dest##*id=}"
    xcrun simctl boot "$simulator_id" 2>/dev/null || true
    xcrun simctl bootstatus "$simulator_id" -b
    xcrun simctl install "$simulator_id" build/files-fixture/Build/Products/Debug-iphonesimulator/FilesFixtureHost.app
  fi
  test_results=$(mktemp -d build/ui-results-XXXXXX)
  if ! xcodebuild "${test_arguments[@]}" -destination "$dest" -derivedDataPath build/simulator \
    -resultBundlePath "$test_results/UITests.xcresult" test; then
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

if [ "$validation_scope" != full ]; then
  echo '阶段原生验证结束；其他UI/视觉/Files及完整回归仍待运行，不生成IPA。'
  exit 0
fi
if [ "${IOS_PACKAGE_IPA:-false}" != true ]; then
  echo '完整Apple运行结束；视觉/Files/性能门槛由阶段台账另验。真实站源按用户指令暂停，本次不生成IPA。'
  exit 0
fi

package_dir=$(mktemp -d build/package-XXXXXX)
mkdir -p "$package_dir/Payload"
ditto build/device/Build/Products/Release-iphoneos/XXComic.app "$package_dir/Payload/XXComic.app"
(cd "$package_dir" && zip -qry XXComic-unsigned.ipa Payload)
mv "$package_dir/XXComic-unsigned.ipa" build/XXComic-unsigned.ipa
echo '未签名 IPA：ios/build/XXComic-unsigned.ipa；需由用户自行签名安装。'

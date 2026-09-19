#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path ComicCore
xcodegen generate --spec project.yml
xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build
if [ -n "${IOS_TEST_DESTINATION:-}" ]; then
  test_results=$(mktemp -d build/ui-results-XXXXXX)
  xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Debug \
    -destination "$IOS_TEST_DESTINATION" -derivedDataPath build/simulator \
    -resultBundlePath "$test_results/UITests.xcresult" CODE_SIGNING_ALLOWED=NO test
fi
xcodebuild -project XXComic.xcodeproj -scheme XXComic -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
mkdir -p build/package/Payload
ditto build/device/Build/Products/Release-iphoneos/XXComic.app build/package/Payload/XXComic.app
(cd build/package && zip -qry ../XXComic-unsigned.ipa Payload)
echo '未签名 IPA：ios/build/XXComic-unsigned.ipa；需由用户自行签名安装。'

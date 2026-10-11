#!/usr/bin/env bash
set -euo pipefail

# This checks the app's platform-independent feedback state and exact native
# unit-test source. It does not compile UIKit or run the UI test suite.
comic_repo=$(cd "$(dirname "$0")/.." && pwd)
feedback_check=$(mktemp -d)
trap 'rm -rf -- "$feedback_check"' EXIT
mkdir -p "$feedback_check/Sources/XXComic" "$feedback_check/Tests/XXComicTests"
cp "$comic_repo/ios/XXComic/DetailFeedbackState.swift" "$feedback_check/Sources/XXComic/"
cp "$comic_repo/ios/XXComicTests/DetailFeedbackStateTests.swift" "$feedback_check/Tests/XXComicTests/"
cat > "$feedback_check/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DetailFeedbackCheck", targets: [
    .target(name: "XXComic"),
    .testTarget(name: "XXComicTests", dependencies: ["XXComic"])
])
SWIFT
cd "$feedback_check"
swift test -j 2

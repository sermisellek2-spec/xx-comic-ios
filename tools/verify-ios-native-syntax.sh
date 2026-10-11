#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mapfile -d '' -t inputs < <(find ios/XXComic ios/XXComicTests ios/XXComicUITests ios/TestSupport -name '*.swift' -print0 | sort -z)
printf 'Swift 5 syntax only; %s files; Apple types and runtime are not checked.\n' "${#inputs[@]}"
swiftc -frontend -parse -swift-version 5 "${inputs[@]}"
printf 'Release syntax: PASS\n'
swiftc -frontend -parse -swift-version 5 -D DEBUG "${inputs[@]}"
printf 'Debug syntax: PASS\n'

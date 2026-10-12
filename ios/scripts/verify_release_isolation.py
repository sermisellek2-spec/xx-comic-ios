#!/usr/bin/env python3
"""Check the actual SDK-built app binaries, without printing binary contents."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re


MARKERS = (
    "ui.matrix.library.seeded",
    "ui.matrix.preferences.seeded",
    "--matrix-update-fixture",
    "http://127.0.0.1:8767/ios-release.json",
    "android-2.0.40-current-pages-v1",
    "--volume-append-held-until-cancel",
    "--matrix-switch-similar-title",
    "--matrix-switch-held-until-cancel",
    "--matrix-switch-empty-once",
    "--matrix-switch-no-match",
    "--matrix-error-log-fixture",
    "--verification-timeout-then-local-response",
)


def inspect(app):
    app = Path(app).resolve(strict=True)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    name = info["CFBundleExecutable"]
    if not isinstance(name, str) or Path(name).name != name:
        raise ValueError("Invalid executable name in built app")
    binary = app / name
    if binary.is_symlink() or not binary.is_file():
        raise ValueError("Built executable must be an owned regular file")
    data = binary.read_bytes()
    return {
        "bundleID": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "executable": name,
        "binarySHA256": hashlib.sha256(data).hexdigest(),
        "markers": {marker: marker.encode("utf-8") in data for marker in MARKERS},
        "testResources": sorted(str(p.relative_to(app)) for p in app.rglob("*")
                                if p.name in ("current-pages.json", "current-page.png", "FilesFixtureHost.app")
                                or p.suffix == ".xctest"),
    }


def main():
    parser = argparse.ArgumentParser(description="核验实际Debug/Release产物的测试内容隔离")
    parser.add_argument("--debug-app", required=True)
    parser.add_argument("--release-app", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        raise ValueError("Tested revision must be a full Git SHA")
    debug, release = inspect(args.debug_app), inspect(args.release_app)
    errors = []
    for variant, result in (("Debug", debug), ("Release", release)):
        if (result["bundleID"], result["version"], str(result["build"])) != ("com.xxcomic.ios", "2.0.40", "340"):
            errors.append(variant + " version or bundle identity differs from baseline")
    if not all(debug["markers"].values()):
        errors.append("Debug control lacks expected fixture markers; absence in Release cannot alone prove this check")
    if any(release["markers"].values()) or release["testResources"]:
        errors.append("Release contains isolated test fixture markers or test resources")
    proof = {"revision": args.revision, "Debug": debug, "Release": release, "errors": errors,
             "passed": not errors,
             "boundary": "Actual binary/resources check; does not replace Release device runtime or non-source acceptance"}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Built Release fixture isolation: " + ("PASS" if not errors else "FAIL"))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

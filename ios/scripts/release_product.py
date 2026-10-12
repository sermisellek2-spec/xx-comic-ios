"""Archive a tested Release product; package those exact bytes after acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import zipfile

from verify_app_icon import inspect_product
from verify_release_isolation import inspect as inspect_isolation


REPOSITORY = "sermisellek2-spec/xx-comic-ios"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def write_json(path, record):
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def archive(args):
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY or os.environ.get("IOS_VALIDATION_SCOPE") != "full":
        raise ValueError("Only the designated repository's complete validation can archive a product")
    if os.environ.get("GITHUB_SHA") != args.revision or not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        raise ValueError("The Release product must identify the actual tested revision")
    run_id = int(os.environ["GITHUB_RUN_ID"])
    app = args.app.resolve(strict=True)
    icon = inspect_product(app, args.revision, "release-device")
    isolation = inspect_isolation(app)
    if not icon["passed"] or any(isolation["markers"].values()) or isolation["testResources"]:
        raise ValueError("Release icon or fixture isolation is invalid")
    # Read the actual preceding complete test log. Do not manufacture an
    # inventory or accept a partial scope as a full native/UI run.
    log = args.log.read_text(encoding="utf-8", errors="replace").splitlines()
    if any(re.search(r"Executed \d+ tests, with [1-9]\d* failures?", line) for line in log):
        raise ValueError("The complete validation log contains failed tests")
    if any(re.search(r"Test Case .* skipped", line) for line in log):
        raise ValueError("The complete validation must run each required test")
    if not any("Test Suite 'ComicCorePackageTests.xctest' passed" in line for line in log):
        raise ValueError("The complete Apple core suite did not pass")
    counts = {"XXComicTests.xctest": [], "XXComicUITests.xctest": []}
    waiting = None
    for line in log:
        for suite in counts:
            if "Test Suite '" + suite + "' failed" in line:
                raise ValueError("A required test suite failed")
            if "Test Suite '" + suite + "' passed" in line:
                waiting = suite
        count = re.search(r"Executed (\d+) tests, with (\d+) failures", line)
        if waiting and count:
            if int(count[2]) != 0:
                raise ValueError("A required test suite reported failures")
            counts[waiting].append(int(count[1])); waiting = None
    expected = {}
    for suite, directory in [("XXComicTests.xctest", "XXComicTests"), ("XXComicUITests.xctest", "XXComicUITests")]:
        expected[suite] = sum(len(re.findall(r"\bfunc test\w+\s*\(", p.read_text(encoding="utf-8")))
                              for p in Path(directory).glob("*.swift"))
        if counts[suite] != [expected[suite], expected[suite]]:
            raise ValueError("Both devices must run every declared native/UI test: " + suite)
    args.output.mkdir(parents=True, exist_ok=False)
    product = args.output / "Release-product.zip"
    files = {}
    with zipfile.ZipFile(product, "x", compression=zipfile.ZIP_DEFLATED) as target:
        for path in sorted(app.rglob("*")):
            if path.is_symlink():
                raise ValueError("An iOS product must not contain external symbolic links")
            if not path.is_file():
                continue
            name = "XXComic.app/" + path.relative_to(app).as_posix()
            files[name] = {"bytes": path.stat().st_size, "sha256": digest(path)}
            target.write(path, name)
    write_json(args.output / "manifest.json", {
        "repository": REPOSITORY, "revision": args.revision, "validationRunID": run_id,
        "scope": "full", "nativeUIExecutedPerDevice": counts, "declaredPerDevice": expected,
        "productSHA256": digest(product), "files": files, "icon": icon, "isolation": isolation,
        "boundary": "Full runtime passed; visual/component acceptance is required before packaging",
    })
    print("Archived the exact fully tested Release product; no IPA generated")


def package(args):
    manifest = json.loads((args.product / "manifest.json").read_text(encoding="utf-8"))
    proof = json.loads(args.run_proof.read_text(encoding="utf-8"))
    product = args.product / "Release-product.zip"
    if manifest.get("repository") != REPOSITORY or os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise ValueError("Packaging is restricted to the designated repository")
    if manifest.get("revision") != args.revision or os.environ.get("GITHUB_SHA") != args.revision:
        raise ValueError("Packaging must use the identical fully validated revision")
    if (manifest.get("scope"), manifest.get("validationRunID")) != ("full", args.run_id):
        raise ValueError("A complete validation run is required")
    if (proof.get("id"), proof.get("head_sha"), proof.get("status"), proof.get("conclusion")) != (args.run_id, args.revision, "completed", "success"):
        raise ValueError("The preceding complete validation run did not succeed for this revision")
    if proof.get("repository", {}).get("full_name") != REPOSITORY or proof.get("path", "").split("@")[0] != ".github/workflows/ios.yml":
        raise ValueError("Validation must come from the designated build workflow")
    if not manifest["icon"]["passed"] or any(manifest["isolation"]["markers"].values()) or manifest["isolation"]["testResources"]:
        raise ValueError("The validated product is not suitable for distribution")
    if digest(product) != manifest["productSHA256"]:
        raise ValueError("Validated product archive changed")
    with zipfile.ZipFile(product) as source:
        entries = source.infolist()
        if len({p.filename for p in entries}) != len(entries) or {p.filename for p in entries} != set(manifest["files"]):
            raise ValueError("The archive member list differs from the validated product")
        for entry in entries:
            parts = PurePosixPath(entry.filename).parts
            if not parts or parts[0] != "XXComic.app" or ".." in parts or "\\" in entry.filename or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Unsafe app archive entry")
            data = source.read(entry)
            expected = manifest["files"][entry.filename]
            if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
                raise ValueError("A validated app resource changed")
        info = plistlib.loads(source.read("XXComic.app/Info.plist"))
        if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("com.xxcomic.ios", "2.0.40", "340"):
            raise ValueError("Unexpected app identity")
        args.output.mkdir(parents=True, exist_ok=False)
        ipa = args.output / "XXComic-unsigned.ipa"
        with zipfile.ZipFile(ipa, "x", compression=zipfile.ZIP_DEFLATED) as target:
            for entry in entries:
                data = source.read(entry)
                entry.filename = "Payload/" + entry.filename
                target.writestr(entry, data)
    write_json(args.output / "package-proof.json", {
        "repository": REPOSITORY, "revision": args.revision, "validationRunID": args.run_id,
        "packageRunID": int(os.environ["GITHUB_RUN_ID"]), "unsigned": True,
        "ipa": ipa.name, "bytes": ipa.stat().st_size, "sha256": digest(ipa),
        "validatedProductSHA256": manifest["productSHA256"], "allAppBytesUnchanged": True,
        "install": "使用用户自己的SideStore等签名工具安装；无需向仓库提供Apple凭据",
    })
    print("Packaged the identical validated app bytes; user signing is still required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    a = commands.add_parser("archive")
    a.add_argument("--app", type=Path, required=True)
    a.add_argument("--log", type=Path, required=True)
    a.add_argument("--revision", required=True)
    a.add_argument("--output", type=Path, required=True)
    p = commands.add_parser("package")
    p.add_argument("--product", type=Path, required=True)
    p.add_argument("--run-proof", type=Path, required=True)
    p.add_argument("--run-id", type=int, required=True)
    p.add_argument("--revision", required=True)
    p.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    archive(args) if args.command == "archive" else package(args)


if __name__ == "__main__":
    main()

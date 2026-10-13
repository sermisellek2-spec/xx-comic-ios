"""Independently verify a delivered IPA against the exact validated Release archive."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "sermisellek2-spec/xx-comic-ios"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inspection(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "ios/scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def entries(archive, prefix):
    result = {}
    for item in archive.infolist():
        parts = PurePosixPath(item.filename).parts
        if (not item.filename.startswith(prefix) or ".." in parts or "\\" in item.filename
                or ":" in item.filename or item.is_dir() or stat.S_ISLNK(item.external_attr >> 16)):
            raise ValueError("Unexpected or unsafe app archive member")
        if item.filename in result:
            raise ValueError("Duplicate app archive member")
        result[item.filename] = item
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--package-proof", type=Path, required=True)
    parser.add_argument("--validated-product", type=Path, required=True)
    parser.add_argument("--validation-run", type=Path, required=True)
    parser.add_argument("--package-run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision) or args.output.exists():
        raise ValueError("Use an exact validated revision and a new output directory")
    manifest = read(args.validated_product / "manifest.json")
    proof = read(args.package_proof)
    validation, packaging = read(args.validation_run), read(args.package_run)
    for run in (validation, packaging):
        if (run.get("head_sha"), run.get("status"), run.get("conclusion")) != (args.revision, "completed", "success"):
            raise ValueError("Both actual runs must have succeeded for the identical revision")
        if run.get("html_url") != "https://github.com/" + REPOSITORY + "/actions/runs/" + str(run["id"]):
            raise ValueError("Unexpected run repository")
    for record in (manifest, proof):
        if (record.get("repository"), record.get("revision"), record.get("validationRunID")) != (REPOSITORY, args.revision, validation["id"]):
            raise ValueError("The product or package identifies a different validation input")
    if (proof.get("packageRunID"), proof.get("unsigned"), proof.get("allAppBytesUnchanged")) != (packaging["id"], True, True):
        raise ValueError("The original package proof is inconsistent")
    if manifest.get("scope") != "full" or not manifest["icon"]["passed"]:
        raise ValueError("The product did not pass complete runtime and icon validation")
    counts = manifest["nativeUIExecutedPerDevice"]
    if any(counts[suite] != [count, count] or count <= 0 for suite, count in manifest["declaredPerDevice"].items()):
        raise ValueError("The product does not identify two complete actual device runs")
    product = args.validated_product / "Release-product.zip"
    if sha(product) != manifest["productSHA256"] or proof["validatedProductSHA256"] != manifest["productSHA256"]:
        raise ValueError("Validated archive SHA256 differs")
    if (args.ipa.name, args.ipa.stat().st_size, sha(args.ipa)) != (proof["ipa"], proof["bytes"], proof["sha256"]):
        raise ValueError("The downloaded IPA differs from its original package proof")
    # Verify all members independently, including executable modes, before
    # extracting into a newly created, resolved output directory.
    with zipfile.ZipFile(product) as original, zipfile.ZipFile(args.ipa) as delivered:
        expected = entries(original, "XXComic.app/")
        actual = entries(delivered, "Payload/XXComic.app/")
        if set(expected) != set(manifest["files"]) or set(actual) != {"Payload/" + name for name in expected}:
            raise ValueError("Product or IPA member inventory differs")
        verified = []
        for name, entry in expected.items():
            data = original.read(entry)
            record = manifest["files"][name]
            packaged = actual["Payload/" + name]
            if (len(data), hashlib.sha256(data).hexdigest()) != (record["bytes"], record["sha256"]):
                raise ValueError("A validated product member changed")
            if delivered.read(packaged) != data or packaged.external_attr != entry.external_attr:
                raise ValueError("A delivered member or its mode differs from validation")
            verified.append({"file": name, **record})
        args.output.mkdir(parents=True, exist_ok=False)
        target_root = args.output.resolve(strict=True)
        for name in expected:
            target = args.output.joinpath(*PurePosixPath(name).parts).resolve()
            if not target.is_relative_to(target_root):
                raise ValueError("Extraction escaped the new output directory")
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as output:
                output.write(delivered.read("Payload/" + name))
    app = args.output / "XXComic.app"
    icon = inspection("verify_app_icon").inspect_product(app, args.revision, "release-device")
    isolation = inspection("verify_release_isolation").inspect(app)
    signatures = sorted(p.relative_to(app).as_posix() for p in app.rglob("*")
                        if p.name in ("embedded.mobileprovision", "_CodeSignature"))
    if (not icon["passed"] or any(isolation["markers"].values()) or isolation["testResources"]
            or signatures or icon["metadata"].get("MinimumOSVersion") != "16.0"):
        raise ValueError("Final app icon, isolation, minimum OS, or unsigned identity differs")
    models = sorted(p.relative_to(app).as_posix() for p in app.rglob("*.mlmodelc") if p.is_dir())
    if not models:
        raise ValueError("The actual offline CoreML model is absent from the delivered app")
    result = {"repository": REPOSITORY, "revision": args.revision, "validationRunID": validation["id"],
              "packageRunID": packaging["id"], "checkedAtUTC": datetime.now(timezone.utc).isoformat(),
              "passed": True, "ipa": {"file": str(args.ipa.resolve()), "bytes": proof["bytes"], "sha256": proof["sha256"]},
              "validatedProductSHA256": manifest["productSHA256"], "allAppBytesAndModesUnchanged": True,
              "verifiedMembers": verified, "icon": icon, "isolation": isolation, "compiledModels": models,
              "unsigned": True, "boundary": "Same validated Release bytes; user signing and physical-device installation remain user acceptance"}
    (args.output / "independent-package-proof.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("passed", "revision", "validationRunID", "packageRunID", "ipa", "unsigned")}, ensure_ascii=False))


if __name__ == "__main__":
    main()

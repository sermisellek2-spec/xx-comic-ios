"""Preserve original xcresult names inside an archive acceptable to artifact upload.

Automatic Xcode attachments can contain quotes, which upload-artifact rejects
as individual paths. The original result bundle (including incomplete Staging
data after cancellation) is retained unchanged inside a tar.gz file.
"""
import hashlib
import json
from pathlib import Path
import sys
import tarfile


def archive_results(build):
    build = build.resolve(strict=True)
    output = build / "test-result-archives"
    output.mkdir(exist_ok=True)
    records = []
    for folder in sorted(build.glob("ui-results-*")):
        if not folder.is_dir() or folder.is_symlink():
            continue
        for bundle in sorted(folder.glob("*.xcresult")):
            if not bundle.is_dir() or bundle.is_symlink():
                continue
            if not bundle.resolve().is_relative_to(build):
                raise ValueError("Result bundle is outside the build directory")
            target = output / (folder.name + "-" + bundle.stem + ".tar.gz")
            # x mode refuses to overwrite previously captured raw results.
            with tarfile.open(target, "x:gz", dereference=False) as archive:
                archive.add(bundle, arcname=folder.name + "/" + bundle.name)
            digest = hashlib.sha256()
            with target.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            records.append({"source": str(bundle.relative_to(build)), "archive": target.name,
                            "bytes": target.stat().st_size,
                            "sha256": digest.hexdigest(),
                            "includesStaging": (bundle / "Staging").is_dir(),
                            "testPassed": None})
    (output / "manifest.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    print("Preserved", len(records), "original result bundles; archive presence does not mean test success")


if __name__ == "__main__":
    archive_results(Path(sys.argv[1]))

"""Prepare full-canvas comparisons of the actual empty-library settings captures."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

from PIL import Image, ImageChops


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-dir", type=Path, required=True)
    parser.add_argument("--ios-dir", type=Path, required=True)
    parser.add_argument("--ios-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-same-state", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.ios_commit) or args.output.exists():
        raise ValueError("Use the actual full Apple revision and a new output directory")
    spec = importlib.util.spec_from_file_location("visual_compare", Path(__file__).with_name("compare-ios-android-visual.py"))
    visual = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(visual)
    records = visual.export_records(args.ios_dir, args.ios_commit)
    captures = read(args.android_dir / "android-settings-manifest.json")["records"]
    if len(captures) != 8:
        raise ValueError("All eight original Android settings states are required")
    output = []
    for capture in captures:
        if capture["baselineCommit"] != visual.BASELINE or not capture.get("actualRasterSizeVerified"):
            raise ValueError("Settings reference must use the frozen, matching viewport")
        device, orientation, theme = re.fullmatch(r"android-settings-(phone|tablet)-(portrait|landscape)-(light|dark)\.png", capture["file"]).groups()
        android = args.android_dir / capture["file"]
        if sha(android) != capture["sha256"] or float(capture["fontScale"]) != 1:
            raise ValueError("Original Android hash or font scale disagrees")
        stem = ("iphone" if device == "phone" else "ipad") + f"_{orientation}_{theme}_settings_reference_empty"
        apple = args.ios_dir / "visual-matrix" / (stem + ".png")
        provenance = args.ios_dir / "visual-provenance" / (stem + ".json")
        apple_record = visual.checked_apple(apple, records)
        visual.checked_apple(provenance, records)
        if apple_record.get("status") != "Success":
            raise ValueError("The original Apple settings test did not pass: " + stem)
        meta = read(provenance)
        if meta.get("preferredContentSizeCategory") not in ["UICTContentSizeCategoryL", "UIContentSizeCategoryL"]:
            raise ValueError("The actual Apple font-scale provenance differs")
        components = visual.components_from_provenance(meta)
        same_state = any(c.get("label") == "阅读与外观" for c in components) and any(c.get("text") == "阅读与外观" for c in capture["components"])
        if args.require_same_state and not same_state:
            raise ValueError("The actual first settings section is not visible on both platforms: " + stem)
        state_labels = ["0 条", "50 个开启", "自动", "自动跟随"]
        if args.require_same_state:
            android_labels = {c.get("text") for c in capture["components"]}
            apple_labels = {c.get("label") for c in components}
            if not set(state_labels).issubset(android_labels & apple_labels):
                raise ValueError("The captured empty library/source count/preferences differ: " + stem)
        expected = [393, 852] if device == "phone" else [834, 1210]
        if orientation == "landscape":
            expected.reverse()
        if [meta["appFrame"]["width"], meta["appFrame"]["height"]] != expected:
            raise ValueError("Actual Apple window does not match the reference canvas")
        density = 3 if device == "phone" else 2
        left = visual.logical(android, density, expected)
        right = visual.logical(apple, meta["screenScale"], expected)
        size = (max(left.width, right.width), max(left.height, right.height))
        canvases = []
        for image in (left, right):
            canvas = Image.new("RGB", size, "magenta")
            canvas.paste(image, (0, 0))
            canvases.append(canvas)
        pair = Image.new("RGB", (size[0] * 2 + 12, size[1]), "#777777")
        pair.paste(canvases[0], (0, 0))
        pair.paste(canvases[1], (size[0] + 12, 0))
        output.append((stem, pair, Image.blend(*canvases, 0.5), ImageChops.difference(*canvases), {
            "case": stem, "androidSHA256": sha(android), "iosSHA256": sha(apple),
            "logicalWindow": expected, "iosTestStatus": records[apple.name]["status"],
            "AndroidComponents": capture["components"], "sameStateVerified": same_state,
            "matchingStateLabels": state_labels if args.require_same_state else [],
            "componentReview": "pending",
        }))
    args.output.mkdir(parents=True)
    for stem, pair, overlay, difference, record in output:
        for suffix, image in (("side-by-side", pair), ("overlay", overlay), ("difference", difference)):
            image.save(args.output / f"{stem}_{suffix}.png")
    (args.output / "comparison.json").write_text(json.dumps({
        "baseline": visual.BASELINE, "iosRevision": args.ios_commit, "prepared": len(output),
        "policy": "Android left, iOS right; full canvas, uniform density only, no masks or cropping; maximum one physical pixel rounding padded in magenta",
        "declaredPlatformDifferences": ["native system bars", "font rasterization", "URLCache physical management files displayed as actual bytes", "Android reference Debug version suffix"],
        "captures": [record for *_, record in output], "visualGatePassed": False,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(output)} real settings comparisons; component review is still required")


if __name__ == "__main__":
    main()

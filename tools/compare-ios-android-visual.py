"""Compare actual same-fixture screenshots; derived images never establish a PASS.

Requires Pillow in the tooling environment, not in either application.
Both screenshots must have the same logical window size. Only display density
is normalized. No application component or system bar is masked or stretched.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
from datetime import datetime, timezone

from PIL import Image, ImageChops

BASELINE = "696e80a44ab36b19de6f630565df32978e55a19e"
PAGES = {
    "bookshelf_online": "bookshelf_online", "discover": "discover",
    "source_drawer": "source_drawer", "search_results": "search_results",
    "detail": "detail", "reader": "reader_original",
    "reading_settings": "reading_settings_original", "reader_directory": "reader_directory",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def export_records(root, revision):
    records = {}
    for path in sorted(root.glob("*-manifest.json")):
        data = read(path)
        if not isinstance(data, list):
            continue
        for item in data:
            if item.get("revision") != revision:
                continue
            name = Path(item.get("file", "")).name
            if name in records and records[name] != item:
                raise ValueError(f"Ambiguous actual Apple attachment: {name}")
            records[name] = item
    if not records:
        raise ValueError("No xcresult export manifest for the specified Apple commit")
    return records


def checked_apple(path, records):
    if not path.is_file():
        raise ValueError(f"Missing actual Apple attachment: {path.name}")
    record = records.get(path.name)
    if not record or sha(path) != record["sha256"]:
        raise ValueError(f"Apple attachment has no matching export/hash: {path.name}")
    return record


def logical(image_path, scale, expected, render=True):
    with Image.open(image_path) as image:
        actual = [image.width / scale, image.height / scale]
        if any(abs(a - b) > 0.1 for a, b in zip(actual, expected)):
            raise ValueError(f"Actual PNG size disagrees with logical provenance: {image_path.name}: {actual} != {expected}")
        if not render:
            return None
        # Uniform density normalization only; preserve the full actual canvas.
        size = tuple(round(value * 2) for value in expected)
        return image.convert("RGB").resize(size, Image.Resampling.LANCZOS)


def component_rows(android, apple, density, page, case):
    rows = []
    candidates = apple.get("components", [])
    labels = [(c.get("text") or c.get("description") or "").strip() for c in android.get("components", [])]
    for component in android.get("components", []):
        label = (component.get("text") or component.get("description") or "").strip()
        if not label or len(label) > 120:
            continue
        bounds = [round(float(v) / density, 3) for v in component["bounds"]]
        matches = [c for c in candidates if c.get("label", "").strip() == label]
        # Repeated comic names deliberately remain unresolved. A guessed match
        # could pair the resume row with a card and conceal a layout defect.
        match = matches[0] if len(matches) == 1 and labels.count(label) == 1 else None
        ios_bounds = match.get("bounds", []) if match else []
        delta = [round(b - a, 3) for a, b in zip(bounds, ios_bounds)] if match else []
        rows.append({"case": case, "page": page, "label": label,
                     "androidType": component.get("type", ""), "androidBoundsDP": json.dumps(bounds),
                     "androidFontDP": round(component["fontPx"] / density, 3) if "fontPx" in component else "",
                     "iosID": match.get("identifier", "") if match else "",
                     "iosBoundsPT": json.dumps(ios_bounds), "deltaLTRB": json.dumps(delta),
                     "match": "unique label; needs manual review" if match else f"unresolved (Android {labels.count(label)}; Apple {len(matches)} label matches)",
                     "acceptance": "pending component review"})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-dir", type=Path, required=True)
    parser.add_argument("--ios-dir", type=Path, required=True)
    parser.add_argument("--ios-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.ios_commit):
        raise ValueError("Specify the exact tested Apple Git commit")
    if args.output.exists():
        raise ValueError("Use a new evidence directory; existing artifacts are never overwritten")
    records = export_records(args.ios_dir, args.ios_commit)
    pending = []
    prepared = []
    rows = []
    for family, idiom in [("phone", "iphone"), ("tablet", "ipad")]:
        for orientation in ["portrait", "landscape"]:
            for theme in ["light", "dark"]:
                case = f"{family}_{orientation}_{theme}"
                prefix = "android_" + case
                manifest = read(args.android_dir / (prefix + "-manifest.json"))
                provenance = read(args.android_dir / (prefix + "-provenance.json"))
                if manifest.get("baseline") != BASELINE or provenance.get("baseline") != BASELINE:
                    raise ValueError("Android screenshot is not from the frozen baseline")
                if float(manifest["fontScale"]) != 1:
                    raise ValueError("Android reference font scale must be 1")
                density = float(manifest["density"])
                captures = {Path(x["file"]).name: x for x in manifest["captures"]}
                for android_page, ios_page in PAGES.items():
                    name = f"{idiom}_{orientation}_{theme}_{ios_page}"
                    try:
                        capture = captures[prefix + "_" + android_page + ".png"]
                        android_png = args.android_dir / capture["file"]
                        if sha(android_png) != capture["sha256"]:
                            raise ValueError("Android PNG hash mismatch")
                        ios_png = args.ios_dir / "visual-matrix" / (name + ".png")
                        ios_json = args.ios_dir / "visual-provenance" / (name + ".json")
                        png_record = checked_apple(ios_png, records)
                        checked_apple(ios_json, records)
                        meta = read(ios_json)
                        for key in ["fixtureID", "metadataSHA256", "imageSHA256"]:
                            if meta.get(key) != manifest.get(key):
                                raise ValueError(f"Shared content mismatch: {key}")
                        if meta.get("preferredContentSizeCategory") not in ["UICTContentSizeCategoryL", "UIContentSizeCategoryL"]:
                            raise ValueError("Apple default font-scale provenance is missing or differs")
                        expected = [float(provenance["logicalWidth"]), float(provenance["logicalHeight"])]
                        ios_size = [float(meta["appFrame"]["width"]), float(meta["appFrame"]["height"])]
                        if any(abs(a - b) > 0.1 for a, b in zip(expected, ios_size)):
                            raise ValueError(f"Logical size mismatch: Android {expected}; Apple {ios_size}")
                        logical(android_png, density, expected, render=False)
                        logical(ios_png, float(meta["screenScale"]), expected, render=False)
                        prepared.append((case, android_page, android_png, ios_png, density, float(meta["screenScale"]), expected,
                                         {"androidSHA256": sha(android_png), "iosSHA256": sha(ios_png),
                                          "iosProvenanceSHA256": sha(ios_json), "iosTestStatus": png_record.get("status"),
                                          "logicalSize": expected, "componentReview": "pending"}))
                        rows.extend(component_rows(capture, meta, density, android_page, case))
                    except (ValueError, KeyError, FileNotFoundError) as error:
                        pending.append({"case": case, "page": android_page, "reason": str(error)})
    args.output.mkdir(parents=True)
    output_records = []
    for case, page, android_path, apple_path, density, screen_scale, expected, proof in prepared:
        android = logical(android_path, density, expected)
        apple = logical(apple_path, screen_scale, expected)
        name = case + "_" + page
        side = Image.new("RGB", (android.width * 2, android.height))
        side.paste(android, (0, 0)); side.paste(apple, (android.width, 0))
        images = {"side-by-side": side, "overlay": Image.blend(android, apple, 0.5), "difference": ImageChops.difference(android, apple)}
        files = {}
        for kind, image in images.items():
            path = args.output / (name + "_" + kind + ".png"); image.save(path)
            files[kind] = {"file": path.name, "sha256": sha(path)}
        output_records.append({"case": case, "page": page, **proof, "derived": files})
    with (args.output / "components.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        fields = ["case", "page", "label", "androidType", "androidBoundsDP", "androidFontDP", "iosID", "iosBoundsPT", "deltaLTRB", "match", "acceptance"]
        writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader(); writer.writerows(rows)
    report = {"recordedAtUTC": datetime.now(timezone.utc).isoformat(), "baseline": BASELINE,
              "iosCommit": args.ios_commit, "policy": "full canvas, 2 pixels per logical point; no masks, no vertical stretching, no automatic PASS",
              "systemDifferences": "Visible in derived images; assess real status/navigation/home-indicator areas individually in component review",
              "prepared": len(prepared), "expected": 64, "captures": output_records, "pending": pending,
              "visualGatePassed": False}
    (args.output / "comparison.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"prepared": len(prepared), "expected": 64, "pending": len(pending), "visualGatePassed": False}))
    return 0 if not pending and len(prepared) == 64 else 2


if __name__ == "__main__":
    raise SystemExit(main())

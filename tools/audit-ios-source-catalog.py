"""Compare catalog metadata with frozen Android sources; never contact a comic site."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


BASELINE = "696e80a44ab36b19de6f630565df32978e55a19e"


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args]).decode("utf-8").strip()


def audit(ios_repo, android_repo):
    def frozen(path):
        return git(android_repo, "show", BASELINE + ":" + path)

    activity = frozen("app/src/main/java/com/xxcomic/MainActivity.java")
    config = frozen("app/src/main/java/com/xxcomic/source/SourceConfig.java")
    order_body = activity.split("private List<String> defaultSourceOrder() {", 1)[1].split("return ids;", 1)[0]
    dedicated_ids = re.findall(r"(\w+)Config\.id", order_body)
    dedicated_metadata = {
        match[0]: {"id": match[0], "name": match[1], "domain": match[2], "base_url": match[3]}
        for match in re.findall(
            r'(?:new SourceConfig|fiveUm)\("([^"\n]+)",\s*"([^"\n]+)",\s*"([^"\n]+)",\s*"([^"\n]+)"', config
        )
    }
    raw_android_public = json.loads(frozen("app/src/main/resources/public-sources.json"))
    public = [item for item in raw_android_public if item.get("available") is True]
    public_file = ios_repo / "ios/ComicCore/Sources/ComicCore/Resources/public-sources.json"
    ios_public = [item for item in json.loads(public_file.read_text(encoding="utf-8-sig")) if item.get("available") is True]
    catalog_file = ios_repo / "ios/ComicCore/Sources/ComicCore/BuiltinSourceCatalog.swift"
    catalog = catalog_file.read_text(encoding="utf-8-sig")
    ios_dedicated = re.findall(r'"([a-z0-9]+)"', catalog.split("dedicatedIDs = [", 1)[1].split("]", 1)[0])
    ios_retired = re.findall(r'"([a-z0-9]+)"', catalog.split("retiredIDs = [", 1)[1].split("]", 1)[0])
    rows = [dict(dedicated_metadata[id], type="dedicated", default_enabled=True) for id in dedicated_ids]
    rows += [
        {"id": item["id"], "name": item["name"], "base_url": item["base"], "type": "public", "default_enabled": item.get("defaultEnabled", True)}
        for item in public
    ]
    checks = {
        "dedicated_count_22": len(dedicated_ids) == len(ios_dedicated) == 22,
        "public_count_29": len(public) == len(ios_public) == 29,
        "dedicated_order": dedicated_ids == ios_dedicated,
        "public_order_names_and_defaults": [(p["id"], p["name"], p.get("defaultEnabled", True)) for p in public]
            == [(p["id"], p["name"], p.get("defaultEnabled", True)) for p in ios_public],
        "unique_active_ids_51": len({r["id"] for r in rows}) == len(rows) == 51,
        "retired_ids": ios_retired == ["baozimh", "mhua5"],
        "default_enabled_50": sum(r["default_enabled"] for r in rows) == 50,
    }
    paths = [catalog_file, public_file, ios_repo / "ios/XXComic/AppEnvironment.swift"]
    return {
        "android_baseline": BASELINE,
        "ios_parent_revision": git(ios_repo, "rev-parse", "HEAD"),
        "evidence_kind": "static catalog metadata; native adapter registration test not executed here; live sites not contacted",
        "checks": checks,
        "current_count": len(rows),
        "default_enabled_count": sum(r["default_enabled"] for r in rows),
        "default_disabled_ids": [r["id"] for r in rows if not r["default_enabled"]],
        "excluded_public_profiles": [p["id"] for p in raw_android_public if p.get("available") is not True],
        "retired_compatibility_only": ios_retired,
        "current_sources": [dict(row, priority=index) for index, row in enumerate(rows, 1)],
        "ios_inputs_sha256": {p.relative_to(ios_repo).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-repo", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    ios_repo = Path(__file__).resolve().parents[1]
    # Managed worktrees share the frozen Git objects with the primary checkout.
    common = Path(git(ios_repo, "rev-parse", "--git-common-dir"))
    if not common.is_absolute():
        common = ios_repo / common
    android_repo = args.android_repo.resolve() if args.android_repo else common.resolve().parent
    result = audit(ios_repo, android_repo)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Catalog: 51 current (22 dedicated + 29 public), 50 enabled by default; " + ("PASS" if all(result["checks"].values()) else "FAIL"))
    raise SystemExit(0 if all(result["checks"].values()) else 1)


if __name__ == "__main__":
    main()

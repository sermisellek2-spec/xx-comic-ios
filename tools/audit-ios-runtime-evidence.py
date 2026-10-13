"""Audit actual full-run methods against the tested Git input; no manual PASS is inferred."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "sermisellek2-spec/xx-comic-ios"
MODULES = {"XXComicTests": "ios/XXComicTests/", "XXComicUITests": "ios/XXComicUITests/"}
CASE = re.compile(r"Test Case '-\[(\w+)\.(\w+) (test\w+)\]' (passed|failed|skipped)(?: \(([\d.]+) seconds\))?")
SWIFT_CASE = re.compile(r"Test Case '(\w+)\.(test\w+)' (passed|failed|skipped)(?: \(([\d.]+) seconds\))?")


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT)


def declared(revision):
    files = git("ls-tree", "-r", "--name-only", revision, "ios/XXComicTests", "ios/XXComicUITests").decode().splitlines()
    result = defaultdict(set)
    for file in files:
        if not file.endswith(".swift"):
            continue
        source = git("show", revision + ":" + file).decode("utf-8")
        module = next(key for key, prefix in MODULES.items() if file.startswith(prefix))
        classes = re.findall(r"\bclass\s+(\w+Tests)\s*:", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if methods and len(classes) != 1:
            raise ValueError("Ambiguous declared test class: " + file)
        for method in methods:
            selector = classes[0] + "/" + method
            if selector in result[module]:
                raise ValueError("Duplicate declared test: " + selector)
            result[module].add(selector)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--run-proof", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--exports", type=Path, required=True)
    parser.add_argument("--requirements", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        raise ValueError("An exact tested Git revision is required")
    if args.output.exists():
        raise ValueError("Use a new output directory; preserve preceding results")
    run = read(args.run_proof)
    if (run.get("head_sha"), run.get("status"), run.get("conclusion")) != (args.revision, "completed", "success"):
        raise ValueError("The actual full validation run did not succeed for this revision")
    if run.get("html_url") != "https://github.com/" + REPOSITORY + "/actions/runs/" + str(run["id"]):
        raise ValueError("Unexpected validation repository")
    log = args.log.read_text(encoding="utf-8", errors="strict").splitlines()
    if not any("==> Native validation scope: full " in line for line in log):
        raise ValueError("The original log does not identify a complete validation scope")
    if any(re.search(r"Executed \d+ tests, with [1-9]\d* failures?", line) for line in log):
        raise ValueError("The original full log reports a test failure")
    if any(re.search(r"Test Case .* (?:failed|skipped)", line) for line in log):
        raise ValueError("The original full log contains a failed or skipped method")
    if not any("Test Suite 'ComicCorePackageTests.xctest' passed" in line for line in log):
        raise ValueError("The actual complete Apple core suite did not pass")
    actual = defaultdict(lambda: defaultdict(dict))
    destination = "apple-core-host"
    destinations = []
    for number, line in enumerate(log, 1):
        match = re.search(r"==> Running tests on destination: .*id=([A-Za-z0-9-]+)", line)
        if match:
            destination = match[1]
            if destination in destinations:
                raise ValueError("Repeated full-run destination")
            destinations.append(destination)
        match = CASE.search(line)
        if match:
            module, cls, method, status, seconds = match.groups()
        else:
            match = SWIFT_CASE.search(line)
            if not match:
                continue
            cls, method, status, seconds = match.groups()
            module = "ComicCoreTests"
        selector = cls + "/" + method
        records = actual[destination][module]
        if selector in records:
            raise ValueError("Repeated method result: " + selector)
        records[selector] = {"status": status, "seconds": float(seconds) if seconds else None, "originalLogLine": number}
    if len(destinations) != 2:
        raise ValueError("Both actual simulator destinations are required")
    expected = declared(args.revision)
    for destination in destinations:
        for module in MODULES:
            observed = set(actual[destination][module])
            if observed != expected[module]:
                raise ValueError(json.dumps({"destination": destination, "module": module,
                    "missing": sorted(expected[module] - observed), "unexpected": sorted(observed - expected[module])}))
    attachments = []
    device_names = {}
    for manifest in sorted(args.exports.glob("*-manifest.json")):
        records = read(manifest)
        if not isinstance(records, list):
            continue
        for record in records:
            if record.get("revision") != args.revision or record.get("status") != "Success":
                raise ValueError("An attachment belongs to a different or unsuccessful test input")
            relative = Path(record["file"]).parts
            if "evidence" not in relative:
                raise ValueError("Unexpected exported attachment path")
            local = args.exports.joinpath(*relative[relative.index("evidence") + 1:])
            if sha(local) != record["sha256"]:
                raise ValueError("Exported attachment changed: " + local.name)
            device = record["destination"]["targetDeviceRecord"]["identifier"]
            if device not in destinations:
                raise ValueError("Attachment destination did not run the full tests")
            device_names[device] = record["device"]
            attachments.append({"file": local.relative_to(args.exports).as_posix(), "sha256": record["sha256"],
                                "test": record["test"], "device": record["device"]})
    if set(device_names) != set(destinations):
        raise ValueError("Both devices must have original kept evidence")
    args.output.mkdir(parents=True, exist_ok=False)
    summary = {"revision": args.revision, "runID": run["id"], "repository": REPOSITORY,
        "recordedAtUTC": datetime.now(timezone.utc).isoformat(), "runtimeInventoryPassed": True,
        "overallGatePassed": False, "boundary": "Actual runtime methods and attachments only; manual component/scope review and packaging remain separate",
        "originalLogSHA256": sha(args.log), "appleCoreMethods": len(actual["apple-core-host"]["ComicCoreTests"]),
        "devices": [{"id": d, "name": device_names[d], "executed": {m: len(actual[d][m]) for m in MODULES},
                     "failures": 0, "skips": 0} for d in destinations], "verifiedAttachments": len(attachments)}
    for name, data in [("summary.json", summary), ("actual-methods.json", dict(actual)), ("verified-attachments.json", attachments)]:
        (args.output / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.requirements:
        requirements = read(args.requirements)
        if requirements.get("revision") != args.revision:
            raise ValueError("The requirement trace does not identify the tested input")
        for requirement in requirements["requirements"]:
            matches = []
            for check in requirement.get("declaredChecks", []):
                path = check["file"]
                module = "ComicCoreTests" if "/ComicCore/" in path else ("XXComicTests" if "/XXComicTests/" in path else "XXComicUITests")
                targets = ["apple-core-host"] if module == "ComicCoreTests" else destinations
                for method in check["declaredMethods"]:
                    selector = Path(path).stem + "/" + method
                    for target in targets:
                        result = actual[target][module].get(selector)
                        if not result:
                            raise ValueError("A declared requirement method did not run: " + selector)
                        matches.append({"destination": target, "selector": selector, **result})
            requirement["actualMethodResults"] = matches
            requirement["runtimeResult"] = "all listed methods passed" if matches else "composite/static/scope review required"
            requirement["manualDecision"] = None
        requirements.update({"isRuntimeResult": True, "runID": run["id"], "note": "实际方法结果已关联；manualDecision未填写，不能据此把需求或总门槛标为通过。"})
        (args.output / "requirement-runtime.json").write_text(json.dumps(requirements, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()

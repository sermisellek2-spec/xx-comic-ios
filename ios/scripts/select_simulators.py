#!/usr/bin/env python3
"""Select the fixed visual devices on the active SDK's matching runtime.

Record the real Apple inventory before selection. Do not silently use an older
runtime with new device profiles or invent simulator identifiers.
"""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess


DEVICES = {"IOS_TEST_DESTINATION": "iPhone 15 Pro", "IOS_IPAD_DESTINATION": "iPad Pro 11-inch (M4)"}


def version_pair(value):
    numbers = [int(v) for v in re.findall(r"\d+", value)]
    if len(numbers) < 2:
        raise ValueError(f"Cannot parse runtime/SDK version: {value}")
    return tuple(numbers[:2])


def select(sdk_version, runtimes, devices):
    matching = [r for r in runtimes["runtimes"] if r.get("isAvailable")
                and ".iOS-" in r["identifier"]
                and version_pair(r["version"]) == version_pair(sdk_version)]
    matching.sort(key=lambda r: r["identifier"])
    for runtime in matching:
        available = devices["devices"].get(runtime["identifier"], [])
        chosen = {}
        for key, name in DEVICES.items():
            matches = [d for d in available if d.get("isAvailable") and d["name"] == name]
            if matches:
                chosen[key] = sorted(matches, key=lambda d: d["udid"])[0]
        if len(chosen) == len(DEVICES):
            return {"sdkVersion": sdk_version, "runtime": runtime, "selected": chosen}
    raise RuntimeError("The fixed iPhone/iPad visual devices are not available together on the active SDK's matching runtime. See the retained inventory; no older runtime was substituted.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    commands = {
        "xcode-version.txt": ["xcodebuild", "-version"],
        "simulator-sdk-version.txt": ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
        "runtimes.json": ["xcrun", "simctl", "list", "runtimes", "-j"],
        "devices.json": ["xcrun", "simctl", "list", "devices", "available", "-j"],
        "device-types.json": ["xcrun", "simctl", "list", "devicetypes", "-j"],
    }
    output = {}
    observations = []
    for name, command in commands.items():
        data = subprocess.check_output(command)
        (args.output / name).write_bytes(data)
        output[name] = data
        observations.append({"file": name, "command": command, "sha256": hashlib.sha256(data).hexdigest()})
    record = {"recordedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "policy": "Fixed devices on matching active SDK major/minor; never substitute an older runtime",
              "inventory": observations}
    try:
        selection = select(output["simulator-sdk-version.txt"].decode().strip(),
                           json.loads(output["runtimes.json"]), json.loads(output["devices.json"]))
        record.update(selection)
    except Exception as error:
        record.update({"status": "failed", "error": str(error)})
        (args.output / "selection.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        raise
    record["status"] = "selected"
    (args.output / "selection.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    for key, device in selection["selected"].items():
        print(f"{key}=platform=iOS Simulator,id={device['udid']}")


if __name__ == "__main__":
    main()

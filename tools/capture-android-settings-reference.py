"""Capture the frozen, offline settings page with actual device metadata.

These are component references, not a claim of same-content cross-platform QA.
Run against a dedicated reference emulator, never the user's daily-use device.
"""
import argparse
import hashlib
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.serial.startswith("emulator-"):
        raise SystemExit("Use a dedicated emulator for reference capture")
    args.output.mkdir(parents=True, exist_ok=True)

    def adb(*values, binary=False):
        output = subprocess.check_output([args.adb, "-s", args.serial, *values], timeout=40,
                                         text=not binary, encoding=None if binary else "utf-8")
        return output if binary else output.strip()

    def hierarchy():
        adb("shell", "uiautomator", "dump", "/sdcard/xxcomic-reference-ui.xml")
        data = adb("exec-out", "cat", "/sdcard/xxcomic-reference-ui.xml", binary=True)
        return data, ET.fromstring(data)

    def settings_page():
        raw, tree = hierarchy()
        if any(n.attrib.get("text") == "主题模式" for n in tree.iter("node")):
            return raw, tree
        candidates = [n for n in tree.iter("node") if n.attrib.get("text") == "设置"]
        if not candidates:
            raise RuntimeError("Settings navigation is unavailable after the configuration change")
        bounds = list(map(int, re.findall(r"\d+", candidates[-1].attrib["bounds"])))
        adb("shell", "input", "tap", str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))
        raw, tree = hierarchy()
        if not any(n.attrib.get("text") == "主题模式" for n in tree.iter("node")):
            raise RuntimeError("Settings page could not be opened")
        return raw, tree

    adb("shell", "cmd", "connectivity", "airplane-mode", "enable")
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
    adb("shell", "am", "start", "-n", "com.xxcomic/.MainActivity")
    settings_page()
    apk_hash = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    records = []
    try:
        for device, size, density in [("phone", "1080x2340", "440"), ("tablet", "1536x2048", "320")]:
            adb("shell", "wm", "size", size)
            adb("shell", "wm", "density", density)
            for rotation, orientation in [("0", "portrait"), ("1", "landscape")]:
                adb("shell", "settings", "put", "system", "user_rotation", rotation)
                for mode, theme in [("no", "light"), ("yes", "dark")]:
                    adb("shell", "cmd", "uimode", "night", mode)
                    time.sleep(1)
                    raw, tree = settings_page()
                    stem = f"android-settings-{device}-{orientation}-{theme}"
                    picture = adb("exec-out", "screencap", "-p", binary=True)
                    (args.output / f"{stem}.png").write_bytes(picture)
                    (args.output / f"{stem}.xml").write_bytes(raw)
                    record = {
                        "file": f"{stem}.png", "sha256": hashlib.sha256(picture).hexdigest(),
                        "baselineCommit": "696e80a44ab36b19de6f630565df32978e55a19e",
                        "apkSHA256": apk_hash, "build": "2.0.40-debug / 340",
                        "device": "dedicated API34 emulator with " + device + " size override",
                        "serial": args.serial, "size": adb("shell", "wm", "size"),
                        "density": adb("shell", "wm", "density"),
                        "fontScale": adb("shell", "settings", "get", "system", "font_scale"),
                        "rotation": tree.attrib.get("rotation"), "orientation": orientation, "theme": theme,
                        "themeMode": "automatic", "fixture": "empty isolated library, 51 current sources, 50 enabled, telemetry disabled",
                        "steps": "launch > settings; override emulator size/density; set rotation and system night mode",
                        "capturedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "sameContentCrossPlatformProof": False,
                        "components": [{"text": n.attrib["text"], "bounds": n.attrib.get("bounds")}
                                       for n in tree.iter("node") if n.attrib.get("text")],
                    }
                    records.append(record)
                    print(stem, "captured", flush=True)
    finally:
        adb("shell", "wm", "size", "reset")
        adb("shell", "wm", "density", "reset")
        adb("shell", "settings", "put", "system", "user_rotation", "0")
        adb("shell", "cmd", "uimode", "night", "no")
        (args.output / "android-settings-manifest.json").write_text(json.dumps({
            "purpose": "Actual frozen Android settings component references; Apple comparisons remain pending",
            "records": records
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

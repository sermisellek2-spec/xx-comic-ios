"""Capture unchanged frozen Android views using the separate test APK provider.

Run only against the task's read-only emulator clone. Every case is pulled and
hashed before the next isolated app-data reset. This is reference evidence,
not a claim that iOS functionality or visual parity has passed.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parent.parent
BASELINE = "696e80a44ab36b19de6f630565df32978e55a19e"
APK_SHA = "a9de8d2c7dde7731846dbae28254722ae4beb656daa55656a0c9281e87b13b71"
SCENES = ["bookshelf_online", "discover", "source_drawer", "search_results",
          "detail", "reader", "reading_settings", "reader_directory"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--adb", required=True, type=Path)
parser.add_argument("--serial", required=True)
parser.add_argument("--avd", required=True)
parser.add_argument("--case", choices=["all"] + [f"{device}_{orientation}_{theme}" for device in ("phone", "tablet") for orientation in ("portrait", "landscape") for theme in ("light", "dark")], default="all")
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
output = (ROOT / args.output).resolve()
evidence_root = (ROOT / "docs/ios-parity-2.0.40/review-evidence").resolve()
if not output.is_relative_to(evidence_root) or output == evidence_root:
    raise ValueError("Capture output must be a specific review-evidence subdirectory")
output.mkdir(parents=True, exist_ok=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adb(*arguments, timeout=30):
    result = subprocess.run([str(args.adb), "-s", args.serial, *arguments],
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"adb {' '.join(arguments[:4])} failed: {result.stdout}\n{result.stderr}")
    return result.stdout


actual_avd = adb("emu", "avd", "name").splitlines()[0].strip()
task_emulators = {("emulator-5566", "xxcomic-ux-api34"), ("emulator-5568", "xxcomic-ux-viewport-api34")}
if actual_avd != args.avd or (args.serial, args.avd) not in task_emulators:
    raise ValueError("The explicit task emulator identity does not match")
if adb("shell", "getprop", "sys.boot_completed").strip() != "1":
    raise RuntimeError("Task emulator has not completed boot")
reference = ROOT / ".reference/android-2.0.40"
manifest = json.loads((ROOT / "docs/ios-parity-2.0.40/baseline/manifest.json").read_text(encoding="utf-8-sig"))
for relative, digest in manifest["files"].items():
    if sha(reference / relative) != digest:
        raise ValueError("Frozen input differs: " + relative)
apk = reference / "app/build/outputs/apk/debug/app-debug.apk"
test_apk = reference / "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
if sha(apk) != APK_SHA:
    raise ValueError("This is not the verified frozen reference APK")
fixture_root = ROOT / "docs/ios-parity-2.0.40/fixtures"
fixture = json.loads((fixture_root / "current-pages.json").read_text(encoding="utf-8"))
fixture_sha, image_sha = sha(fixture_root / "current-pages.json"), sha(fixture_root / "current-page.png")
for install in (apk, test_apk):
    print(adb("install", "-r", str(install), timeout=90).strip(), flush=True)
cases = [args.case] if args.case != "all" else [f"{device}_{orientation}_{theme}" for device in ("phone", "tablet") for orientation in ("portrait", "landscape") for theme in ("light", "dark")]

for case in cases:
    device, orientation, theme = case.split("_")
    stem = "android_" + case
    if (output / (stem + "-manifest.json")).exists() or (output / (stem + ".log")).exists():
        raise FileExistsError("Retain previous evidence; choose a new output directory for a rerun")
    print("Capturing " + stem, flush=True)
    if adb("shell", "pm", "clear", "com.xxcomic").strip() != "Success":
        raise RuntimeError("Could not reset only the isolated task clone's test library")
    adb("shell", "cmd", "connectivity", "airplane-mode", "enable")
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
    adb("shell", "wm", "size", "1179x2556" if device == "phone" else "1668x2420")
    adb("shell", "wm", "density", "480" if device == "phone" else "320")
    adb("shell", "settings", "put", "system", "user_rotation", "0" if orientation == "portrait" else "1")
    adb("shell", "cmd", "uimode", "night", "no" if theme == "light" else "yes")
    # Raw reporting retains the finish code even when Instrumentation emits a
    # stream result; formatted reporting hides that code.
    command = [str(args.adb), "-s", args.serial, "shell", "am", "instrument", "-r", "-w", "-e", "stem", stem,
               "com.xxcomic.test/com.xxcomic.ParityReferenceInstrumentation"]
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
    except subprocess.TimeoutExpired as error:
        raw = error.stdout or b""
        if isinstance(raw, bytes): raw = raw.decode("utf-8", errors="replace")
        (output / (stem + ".log")).write_text(raw + "\nCAPTURE TIMEOUT: 180 seconds\n", encoding="utf-8")
        raise RuntimeError("Reference capture timed out; preserve evidence and repair the test environment") from error
    (output / (stem + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    print(result.stdout, flush=True)
    if result.returncode or "PASS: 8 actual frozen UI reference captures" not in result.stdout or "INSTRUMENTATION_CODE: -1" not in result.stdout:
        raise RuntimeError("Instrumentation shell exit alone is not a successful reference capture")
    remote = "/sdcard/Android/data/com.xxcomic/files/parity-reference/"
    names = [stem + "_" + scene + ".png" for scene in SCENES] + [stem + "-manifest.json"]
    for name in names:
        if (output / name).exists(): raise FileExistsError(name)
        adb("pull", remote + name, str(output / name), timeout=60)
    proof_path = output / (stem + "-manifest.json")
    proof = json.loads(proof_path.read_text(encoding="utf-8"))
    if proof["baseline"] != BASELINE or proof["fixtureID"] != fixture["fixtureID"] or proof["metadataSHA256"] != fixture_sha or proof["imageSHA256"] != image_sha:
        raise ValueError("Reference provider did not consume the shared input")
    if len(proof["captures"]) != 8:
        raise ValueError("Reference capture is incomplete")
    expected_pixels = [1179, 2556] if device == "phone" else [1668, 2420]
    if orientation == "landscape": expected_pixels.reverse()
    for capture in proof["captures"]:
        if sha(output / capture["file"]) != capture["sha256"] or capture["pixels"] != expected_pixels:
            raise ValueError("Screenshot hash or actual orientation mismatch: " + capture["file"])
        bounds = capture.get("decorBoundsOnScreen", [])
        if capture.get("componentCoordinates") != "screen" or len(bounds) != 4:
            raise ValueError("Actual screen component/window coordinates are missing: " + capture["file"])
        if capture.get("activeWindowPackage") != "com.xxcomic" or any("Viewing full screen" in component.get("text", "") or component.get("text") == "GOT IT" for component in capture.get("components", [])):
            raise ValueError("Unexpected system overlay is not a common application state: " + capture["file"])
        if bounds[2] - bounds[0] != expected_pixels[0]:
            raise ValueError("Application content width differs from the common logical window; use the task's matching viewport emulator: " + capture["file"])
        if any(capture["file"].endswith("_" + scene + ".png") for scene in ["reader", "reading_settings", "reader_directory"]):
            state = capture.get("readerState", {})
            if state.get("enhancementMode") != 0 or state.get("enhancementComparison") is not False or state.get("layoutMode") != 0 or state.get("controlsVisible") is not True:
                raise ValueError("Actual common original-reader state differs: " + capture["file"])
    provenance = {"capturedAtUTC": datetime.now(timezone.utc).isoformat(), "serial": args.serial, "avd": actual_avd,
                  "baseline": BASELINE, "apkSHA256": APK_SHA, "testApkSHA256": sha(test_apk),
                  "providerSHA256": sha(fixture_root / "android/ParityReferenceInstrumentation.java"),
                  "fixtureID": fixture["fixtureID"], "logicalWidth": expected_pixels[0] / (3 if device == "phone" else 2),
                  "logicalHeight": expected_pixels[1] / (3 if device == "phone" else 2),
                  "theme": theme, "orientation": orientation, "fontScale": 1.0,
                  "airplaneMode": True, "statisticsDisabledBeforeLaunch": True, "realWebsitesExercised": False,
                  "referenceManifestSHA256": sha(proof_path), "actualScreenshots": 8,
                  "componentCoordinates": "screen", "contentWidthVerified": True,
                  "activeWindowPackage": "com.xxcomic", "unexpectedSystemOverlay": False,
                  "iosVisualAcceptance": "pending same-content, same-width Apple screenshots and component review"}
    (output / (stem + "-provenance.json")).write_text(json.dumps(provenance, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Saved and verified 8 actual screenshots: " + stem, flush=True)

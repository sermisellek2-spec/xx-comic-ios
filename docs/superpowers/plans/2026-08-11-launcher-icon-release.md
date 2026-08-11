# Launcher Icon Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the XX Comic launcher icon with the approved face-focused crop, push `master`, and produce an installable release APK signed with the default debug key.

**Architecture:** Generate density-correct raster resources from the supplied square PNG using the platform `System.Drawing` API. Legacy launchers receive five `mipmap-*` PNGs; Android 8+ receives five 108dp adaptive foreground PNGs whose central safe zone reproduces the approved crop. Keep the existing manifest resource name and add only the release signing line required for an installable artifact.

**Tech Stack:** Android resources, Gradle/AGP 7.4.2, PowerShell `System.Drawing`, Node.js resource verifier, Android `apksigner`.

---

### Task 1: Add a failing launcher resource verifier

**Files:**
- Create: `tools/check-launcher-icon.js`
- Test: `tools/check-launcher-icon.js`

- [ ] **Step 1: Write the failing verifier**

Create a Node script that reads PNG IHDR dimensions without dependencies and asserts:

```javascript
const fs = require("fs");

const expected = {
  "mdpi": [48, 108],
  "hdpi": [72, 162],
  "xhdpi": [96, 216],
  "xxhdpi": [144, 324],
  "xxxhdpi": [192, 432],
};

function dimensions(path) {
  const png = fs.readFileSync(path);
  if (png.toString("hex", 0, 8) !== "89504e470d0a1a0a") throw new Error(`${path}: not PNG`);
  return [png.readUInt32BE(16), png.readUInt32BE(20)];
}

for (const [density, [legacy, adaptive]] of Object.entries(expected)) {
  const launcher = `app/src/main/res/mipmap-${density}/ic_launcher.png`;
  const foreground = `app/src/main/res/drawable-${density}/ic_launcher_foreground.png`;
  if (dimensions(launcher).join("x") !== `${legacy}x${legacy}`) throw new Error(`${launcher}: wrong size`);
  if (dimensions(foreground).join("x") !== `${adaptive}x${adaptive}`) throw new Error(`${foreground}: wrong size`);
}

const adaptive = fs.readFileSync("app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml", "utf8");
if (!adaptive.includes('@drawable/ic_launcher_foreground')) throw new Error("adaptive foreground reference missing");
const gradle = fs.readFileSync("app/build.gradle", "utf8");
if (!/release\s*\{[\s\S]*signingConfig signingConfigs\.debug/.test(gradle)) throw new Error("release debug signing missing");
console.log("launcher icon resources ok");
```

- [ ] **Step 2: Run the verifier and confirm RED**

Run: `node tools/check-launcher-icon.js`

Expected: FAIL with `ENOENT` for `mipmap-mdpi/ic_launcher.png`.

### Task 2: Generate icon resources and configure release signing

**Files:**
- Create: `app/src/main/res/mipmap-mdpi/ic_launcher.png`
- Create: `app/src/main/res/mipmap-hdpi/ic_launcher.png`
- Create: `app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- Create: `app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- Create: `app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- Create: `app/src/main/res/drawable-mdpi/ic_launcher_foreground.png`
- Create: `app/src/main/res/drawable-hdpi/ic_launcher_foreground.png`
- Create: `app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png`
- Create: `app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png`
- Create: `app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png`
- Delete: `app/src/main/res/drawable/ic_launcher_foreground.xml`
- Modify: `app/build.gradle`
- Test: `tools/check-launcher-icon.js`

- [ ] **Step 1: Generate the approved C crop for legacy icons**

Use `System.Drawing` with high-quality bicubic interpolation. Crop the source rectangle `(270, 110, 847, 847)` and resize it to `48`, `72`, `96`, `144`, and `192` pixels for the matching `mipmap-*` directories.

Run this PowerShell from the repository root; the same block also prepares the adaptive source canvas used in Step 2:

```powershell
Add-Type -AssemblyName System.Drawing
$sourcePath = 'C:\Users\15361\Desktop\chatgpt-image-20260811-115409-01.png'
$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$legacyCrop = [System.Drawing.Rectangle]::new(270, 110, 847, 847)
$adaptiveCanvas = [System.Drawing.Bitmap]::new(1270, 1270)
$canvasGraphics = [System.Drawing.Graphics]::FromImage($adaptiveCanvas)
$canvasGraphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#4CAAF1'))
$canvasGraphics.DrawImage($source, [System.Drawing.Rectangle]::new(-58, 102, 1254, 1254))
$canvasGraphics.Dispose()

function Save-Icon([System.Drawing.Image]$image, [System.Drawing.Rectangle]$sourceRect,
                   [int]$size, [string]$path) {
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $output = [System.Drawing.Bitmap]::new($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($output)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($image, [System.Drawing.Rectangle]::new(0, 0, $size, $size),
        $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    $graphics.Dispose()
    $output.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $output.Dispose()
}

$densities = @{
    mdpi = @(48, 108); hdpi = @(72, 162); xhdpi = @(96, 216)
    xxhdpi = @(144, 324); xxxhdpi = @(192, 432)
}
foreach ($entry in $densities.GetEnumerator()) {
    Save-Icon $source $legacyCrop $entry.Value[0] `
        "app/src/main/res/mipmap-$($entry.Key)/ic_launcher.png"
}
```

- [ ] **Step 2: Generate adaptive foreground canvases**

Create a `1270×1270` blue `#4CAAF1` canvas, draw the full source image at `(-58, 102, 1254, 1254)`, then resize to `108`, `162`, `216`, `324`, and `432` pixels for the matching `drawable-*` directories. This places the approved crop inside the adaptive icon central safe zone.

Continue in the same PowerShell process:

```powershell
$adaptiveRect = [System.Drawing.Rectangle]::new(0, 0, 1270, 1270)
foreach ($entry in $densities.GetEnumerator()) {
    Save-Icon $adaptiveCanvas $adaptiveRect $entry.Value[1] `
        "app/src/main/res/drawable-$($entry.Key)/ic_launcher_foreground.png"
}
$adaptiveCanvas.Dispose()
$source.Dispose()
```

- [ ] **Step 3: Remove the old vector foreground**

Delete `app/src/main/res/drawable/ic_launcher_foreground.xml` so density-specific PNG foregrounds are selected.

- [ ] **Step 4: Sign release with the default debug key**

Add the minimum build type configuration to `app/build.gradle`:

```groovy
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
```

Do not modify `defaultConfig`, `versionCode`, or `versionName`.

- [ ] **Step 5: Run the verifier and confirm GREEN**

Run: `node tools/check-launcher-icon.js`

Expected: `launcher icon resources ok`.

### Task 3: Verify, commit, push, and package

**Files:**
- Create: `.worktrees/artifacts/xx-comic-master-release.apk` (ignored artifact)
- Modify: Git history and `origin/master`

- [ ] **Step 1: Inspect the rendered icon**

Create a temporary contact sheet using the generated `xxxhdpi` legacy and adaptive PNGs under circular and rounded-square masks. Verify the face and visible blue hair remain inside every mask and the 56px preview is recognizable.

Use `view_image` on both generated `xxxhdpi` PNGs, then render the same resources in the existing visual companion masks. Do not commit the temporary contact sheet or companion files.

- [ ] **Step 2: Run focused and build verification**

Run:

```powershell
node tools/check-launcher-icon.js
git diff --check
.\gradlew.bat :app:assembleRelease
```

Expected: verifier passes, `git diff --check` exits 0, and Gradle prints `BUILD SUCCESSFUL`.

- [ ] **Step 3: Verify APK signature**

Read `sdk.dir` from `local.properties`, select the newest installed `build-tools/*/apksigner.bat`, then run:

```powershell
& $apksigner verify --verbose --print-certs app/build/outputs/apk/release/app-release.apk
```

Expected: `Verifies` and certificate output identifying the Android debug certificate.

- [ ] **Step 4: Commit only implementation files**

Stage the ten PNGs, deleted vector, `app/build.gradle`, verifier, and this plan. Commit with:

```text
feat: 更换应用启动图标
```

- [ ] **Step 5: Verify the remote has not diverged and push**

Run `git fetch origin master`, confirm `git rev-list --left-right --count origin/master...master` reports `0` remote-only commits, then run `git push origin master`.

Expected: push succeeds and `git rev-parse HEAD` equals `git rev-parse origin/master`.

- [ ] **Step 6: Rebuild from pushed HEAD and copy the artifact**

Run `:app:assembleRelease` again after push, copy `app-release.apk` to `.worktrees/artifacts/xx-comic-master-release.apk`, and calculate SHA-256.

- [ ] **Step 7: Restore tracked Gradle outputs and confirm repository state**

Restore only tracked generated files under `.gradle` and `app/build`. Confirm `git status --short --branch` has no source changes; `.superpowers/` may be removed after stopping its local preview server.

const fs = require("fs");

const source = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const gradle = fs.readFileSync("app/build.gradle", "utf8");
const assets = ["rem_no_image.png", "rem_in_bookshelf.png", "rem_not_in_bookshelf.png"];

function between(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  return from >= 0 && to > from ? source.slice(from, to) : "";
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const detail = between("private void showDetail", "private void refreshCachedComicOnce");
const drawer = between("private void showChapterDrawer", "private void fillChapterRows");
const readButton = between("private View detailReadButton", "private void installDetailHeroStretch");
const heroCover = between("private void addDetailHeroCover", "private String chapterNumber");
const updateDownload = between("private File downloadAndVerifyUpdate", "private void installUpdate");
const readerChrome = between("private void toggleReaderFullscreen", "private int readerChromeBottomOffset");
const latestUpdate = between("private void showUpdateLatest", "private void showUpdateFailure");

check("detail read action follows persisted reading state", detail.includes("detailReadButton(detail)"));
check("first chapter history remains a continue action", source.includes("lastViewedAt.containsKey(detail.summary.comicId)"));
check("detail actions share one centered baseline", detail.includes("actions.setGravity(Gravity.CENTER_VERTICAL)"));
check("detail exposes a pull-to-expand hero", detail.includes("installDetailHeroStretch("));
check("detail uses a flat full-width hero", detail.includes("addDetailHeroCover(") && !detail.includes("addBlurredHeroCover("));
check("detail hero has no lower color veil", !heroCover.includes("View shade") && !heroCover.includes("Color.argb("));
check("detail uses the approved favorite artwork", detail.includes("R.drawable.rem_in_bookshelf") && detail.includes("R.drawable.rem_not_in_bookshelf"));
check("detail fallback artwork exists", assets.every((name) => fs.existsSync("app/src/main/res/drawable-nodpi/" + name)));
check("hero can reveal the full cover", source.includes("DETAIL_HERO_MAX_DP = 390"));
check("hero stretch does not move the cover independently", !source.includes("coverParams.topMargin"));
check("detail viewport keeps one content background", detail.includes("scroll.setBackgroundColor(UIHelpers.CARD)"));
check("detail read copy is centered", readButton.includes("titleView.setGravity(Gravity.CENTER)") && readButton.includes("subtitleView.setGravity(Gravity.CENTER)"));
check("drawer preserves the saved ordering choice", !drawer.includes("chapterDesc = false;"));
check("drawer cancels stale batched rows after reordering", drawer.includes("int[] renderGeneration"));
check("drawer tools keep the sort button in its fixed host", drawer.includes("drawerTools.addView(orderHost") && drawer.includes("titleHost"));
check("drawer sort is lightweight and closable", drawer.includes("order.setBackgroundColor(Color.TRANSPARENT)") && drawer.includes("R.drawable.ic_close"));
check("drawer header and tools use separate aligned rows", drawer.includes("drawerTools") && drawer.includes("panel.addView(drawerTools"));
check("drawer chapter rows use compact alignment", source.includes("setMinimumHeight(UIHelpers.dp(this, 37))") && source.includes("setPadding(UIHelpers.dp(this, 2), 0, UIHelpers.dp(this, 2), 0)"));
check("background detail refresh does not displace an open drawer", source.includes("activePopup == null || !activePopup.isShowing()"));
check("updates try COS before the server fallback", source.includes("apk/xx-comic/xx-comic.bin") && source.includes("UPDATE_APK_URLS") && updateDownload.includes("for (String updateUrl : UPDATE_APK_URLS)"));
check("update fallback preserves cancellation and checksum verification", updateDownload.includes("isExpectedTaskCancellation(error)") && updateDownload.includes("actualHash.equals(release.sha256)"));
check("reader chrome uses directional easing", readerChrome.includes("new AccelerateInterpolator(1.6f)")
  && readerChrome.includes("new DecelerateInterpolator(1.6f)"));
check("reader chrome keeps the responsive animation duration", source.includes("READER_CHROME_ANIM_MS = 260L"));
check("reader chrome animates on a hardware layer", readerChrome.includes("withLayer()"));
check("reader progress fades with the reader chrome", source.includes("chapterProgress.setAlpha(readerFullscreen ? 1f : 0f)")
  && readerChrome.includes(".alpha(readerFullscreen ? 1f : 0f)"));
check("reader chrome travels fully off canvas", readerChrome.includes("translationY(readerFullscreen ? -topHeight : 0f)")
  && readerChrome.includes("translationY(readerFullscreen ? bottomHeight : 0f)"));
check("reader scrolling can enter immersive mode", source.includes("setReaderFullscreen(true, true)"));
check("latest-version scene has no reinstall action", latestUpdate && !latestUpdate.includes("settingsBottomActions")
  && !latestUpdate.includes("startUpdateDownload"));
check("release version is 1.0.55", gradle.includes('versionName "1.0.55"') && gradle.includes("versionCode 55"));

console.log("detail release contracts hold");

const fs = require("fs");

const source = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const gradle = fs.readFileSync("app/build.gradle", "utf8");

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

check("detail read label follows persisted reading state", detail.includes("detailReadLabel(detail)"));
check("first chapter history remains a continue action", source.includes("lastViewedAt.containsKey(detail.summary.comicId)"));
check("detail actions share one centered baseline", detail.includes("actions.setGravity(Gravity.CENTER_VERTICAL)"));
check("detail exposes a pull-to-expand hero", detail.includes("installDetailHeroStretch("));
check("hero cover is top-anchored for predictable reveal", detail.includes("Gravity.TOP | Gravity.CENTER_HORIZONTAL"));
check("hero stretch does not move the cover independently", !source.includes("coverParams.topMargin"));
check("drawer preserves the saved ordering choice", !drawer.includes("chapterDesc = false;"));
check("drawer cancels stale batched rows after reordering", drawer.includes("int[] renderGeneration"));
check("drawer header keeps the sort button in its fixed host", drawer.includes("header.addView(orderHost") && drawer.includes("titleHost"));
check("release version is 1.0.7", gradle.includes('versionName "1.0.7"') && gradle.includes("versionCode 7"));

console.log("detail release contracts hold");

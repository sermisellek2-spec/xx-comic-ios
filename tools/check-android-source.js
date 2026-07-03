const fs = require("fs");
const path = require("path");

const javaDir = "app/src/main/java/com/xxcomic";
let src = "";

function collectSrc(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectSrc(full);
    else if (entry.name.endsWith(".java")) src += fs.readFileSync(full, "utf8") + "\n";
  }
}

collectSrc(javaDir);
const gradle = fs.readFileSync("app/build.gradle", "utf8");

let failed = false;
function check(name, condition) {
  if (condition) console.log("PASS " + name);
  else {
    failed = true;
    console.error("FAIL " + name);
  }
}

function includesAll(items) {
  return items.every((item) => src.includes(item));
}

check("android source loads", src.includes("public class MainActivity extends Activity"));
check("utf8 java compile", gradle.includes('options.encoding = "UTF-8"'));
check("prototype warm ui", includesAll(["UIHelpers.BG", "UIHelpers.ACCENT", "makeBottomNav()", "resultCard(", "UIHelpers.card(this)"]));
check("default category loads paged source", includesAll(["loadDefaultCategory()", "loadSearchPage(\"\", 1, false, true)", "client.category(selectedRegion, selectedState, page)"]));
check("no hardcoded sample search", !src.includes("DEFAULT_QUERY") && !src.includes("柯南"));
check("search ui is readable", includesAll(["搜索漫画名称或作者", "搜索结果"]));
check("baozi real source adapter", includesAll(["sourceClient = new BaoziComicSource", "client.search(", "client.detail(", "client.chapter(", "selectedSource()"]));
check("real image loading", includesAll(["ImageView", "loadImage(", "BitmapFactory.decodeByteArray", "setRequestProperty(\"Referer\"", "https://cn.bzmgcn.com/"]));
check("search request lifecycle", includesAll(["searchGeneration", "runSearch(", "searchResults.addAll(list)", "summaries.put(item.comicId, item)"]));
check("detail cache and chapters", includesAll(["details", "showDetail(", "detail.chapters.size()", "章节目录"]));
check("reader chapter images", includesAll(["chapters", "renderReader(", "page.imageUrls", "switchChapter("]));
check("chapter redirect support", includesAll(["fetch(String url, int redirects)", "setInstanceFollowRedirects(false)", "getHeaderField(\"Location\")"]));
check("favorites persisted", includesAll(["favorites", "toggleFavorite(", "editor.putString(\"favorites\"", "restoreLocalState()"]));
check("source toggle and empty search", includesAll(["sourceEnabled = !sourceEnabled", "当前没有启用站源", "showTab(2)"]));
check("custom source management", includesAll(["showAddSourceDialog()", "customSources.add", "encodeCustomSources()", "restoreCustomSources("]));
check("profile dialogs", includesAll(["renderProfile(", "showInfo(", "healthCheck()"]));
check("cache clear state", includesAll(["private String cacheSize", "cacheSize = \"0 MB\""]));
check("reading history state", includesAll(["progress", "readHistoryText()", "editor.putString(\"progress\""]));
check("no replacement mojibake", !src.includes("\uFFFD"));
check("v1.0.1 android version", gradle.includes('versionName "1.0.1"') && src.includes('"1.0.1"'));
check("manga clean tokens", includesAll([
  "BRAND = Color.rgb(245, 158, 11)",
  "ACCENT = Color.rgb(28, 28, 26)",
  "PLACEHOLDER = Color.rgb(231, 229, 226)",
  "READER_TEXT = Color.rgb(232, 232, 230)"
]));
check("manga clean controls", includesAll([
  "primaryButton",
  "secondaryButton",
  "brandButton",
  "chip.setBackground(round(selected ? ACCENT : SURFACE"
]));
check("reader clean palette", includesAll([
  "DARK = Color.rgb(22, 22, 26)",
  "DARK_BAR = Color.rgb(15, 15, 18)",
  "UIHelpers.READER_TEXT",
  "UIHelpers.BRAND"
]));
check("manga covers have no corner badges", includesAll([
  "coverFrame(",
  "coverView("
]) && !includesAll([
  "statusBadgeText(",
  "addCoverBadge("
]) && !src.includes("連載中") && !src.includes("完結"));
check("detail hero and chapter typography", includesAll([
  "DETAIL_HERO_DP",
  "addBlurredHeroCover(",
  "chapterNumber(",
  "Typeface.MONOSPACE",
  "最新优先",
  "最旧优先"
]));
check("source card information layout", includesAll([
  "sourceLogo(",
  "statusDot(",
  "sourceSwitch(",
  "源信息",
  "点击切换"
]));
check("source switch accessible neutral states", includesAll([
  "track.setFocusable(true);",
  "track.setClickable(true);",
  "track.setOnClickListener(v -> toggle.run());",
  "track.setContentDescription(enabled ? \"站源已启用\" : \"站源已停用\");",
  "UIHelpers.round(enabled ? UIHelpers.ACCENT : UIHelpers.SURFACE",
  "enabled ? Color.TRANSPARENT : UIHelpers.BORDER",
  "enabled ? UIHelpers.GREEN : UIHelpers.TEXT3"
]));
check("source card fixed visual dimensions", includesAll([
  "new LinearLayout.LayoutParams(UIHelpers.dp(this, 48), UIHelpers.dp(this, 48))",
  "new LinearLayout.LayoutParams(UIHelpers.dp(this, 8), UIHelpers.dp(this, 8))",
  "new LinearLayout.LayoutParams(UIHelpers.dp(this, 50), UIHelpers.dp(this, 28))"
]));
check("reader progress and skeleton state", includesAll([
  "readerProgressBar(",
  "readerSkeletonState(",
  "addView(readerProgressBar",
  "30L"
]));
check("full visual redesign detail polish", includesAll([
  "RenderEffect",
  "BlurMaskFilter",
  "detailTagRow(",
  "detailTagPill(",
  "setRenderEffect"
]));
check("full visual redesign chapter drawer", includesAll([
  "chapterDrawerRow(",
  "chapterDrawerHeader(",
  "chapterNumberView(",
  "showReader(detail, chapterIndex)",
  "chapterDesc ? \"最新优先\" : \"最旧优先\""
]));
check("full visual redesign reader loading", includesAll([
  "showReaderLoading(",
  "readerSkeletonState(\"正在解析本章图片\")",
  "applyReaderSystemBars()"
]));
check("global search waits for all sources before rendering results", includesAll([
  "startGlobalSearch(",
  "globalSearchResults.clear();",
  "globalSearchLoading = true;",
  "CountDownLatch latch = new CountDownLatch(clients.size())",
  "latch.await();",
  "globalSearchLoading = false;"
]) && !src.includes("showStandaloneSearch(true);\n                    runGlobalSearch("));

if (failed) process.exit(1);
console.log("\nAndroid source checks passed.");

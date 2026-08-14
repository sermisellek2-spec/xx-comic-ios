const fs = require("fs");

const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const ui = fs.readFileSync("app/src/main/java/com/xxcomic/UIHelpers.java", "utf8");
const gradle = fs.readFileSync("app/build.gradle", "utf8");

let failed = false;
function check(name, condition) {
  if (condition) console.log(`PASS ${name}`);
  else {
    failed = true;
    console.error(`FAIL ${name}`);
  }
}

function block(source, start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  return from >= 0 && to > from ? source.slice(from, to) : "";
}

check("day theme uses approved ice blue background", ui.includes("BG = Color.rgb(241, 249, 254)"));
check("day theme uses approved Rem blue accent", ui.includes("ACCENT = Color.rgb(43, 152, 217)"));
check("compact cards use at most 8dp radius", /surfaceCard[\s\S]*?round\(CARD, dp\(ctx, 8\)/.test(ui));

const nav = block(main, "private LinearLayout makeBottomNav()", "private TextView sectionTitle");
check("bottom navigation has exactly three approved labels",
  nav.includes('String[] labels = {"书架", "发现", "设置"}') &&
  !nav.includes("站源") && !nav.includes("我的"));
check("settings owns source management", /renderSettings[\s\S]*?showSourceManagement/.test(main));

check("discovery has a single-mode state", main.includes("private boolean globalSearchMode"));
const modeButton = block(main, "private TextView searchModeButton", "private ");
check("single/global mode is one borderless text button",
  modeButton.includes('globalSearchMode ? "全站" : "单站"') &&
  modeButton.includes("Color.TRANSPARENT") && !modeButton.includes("round("));
check("keyboard search triggers the active search mode",
  /IME_ACTION_SEARCH[\s\S]*?globalSearchMode[\s\S]*?(startGlobalSearch|runSearch)/.test(main));
check("global empty query shows recent search and results hide it",
  main.includes("renderSearchHistory") && main.includes("globalSearchQuery.isEmpty()"));
check("global source row remains horizontally scrollable", main.includes("globalSearchSourceTabs"));
check("filters render in three columns", /searchTagColumn[\s\S]*?final int columns = 3;/.test(main));

const favorites = block(main, "private View favorite", "private ");
check("bookshelf deletion starts from long press", main.includes("setOnLongClickListener") && main.includes("showFavoriteDeleteOverlay"));
check("bookshelf deletion uses the trash icon", main.includes("R.drawable.ic_trash"));

check("all five Rem state resources are used", [
  "R.drawable.rem_loading",
  "R.drawable.rem_error",
  "R.drawable.rem_empty",
  "R.drawable.rem_reader_boundary",
  "R.drawable.rem_reader_resume",
].every((value) => main.includes(value)));
check("shared Rem state builder exists", main.includes("private View remState("));
check("reader final chapter uses Rem boundary prompt", /switchChapter[\s\S]*?showReaderBoundaryHint/.test(main));
check("reader restore uses Rem resume prompt", /restoreReaderPosition[\s\S]*?showReaderResumeHint/.test(main));

const sources = block(main, "private void renderSources", "private void addSourceCard");
check("source management has no add-source entry", sources && !sources.includes("showAddSourceDialog") && !sources.includes("+ 添加"));
check("source management keeps the four approved functions", [
  "healthCheck", "openImportSourceConfig", "exportSourceConfig", "sourceSwitch",
].every((value) => main.includes(value)));

const detail = block(main, "private void showDetail", "private void refreshCachedComicOnce");
const history = block(main, "private void showHistory", "private View historyRow");
check("detail has no visible back button", detail && !detail.includes("R.drawable.ic_back"));
check("history has no visible back button", history && !history.includes("R.drawable.ic_back"));
check("chapter catalog remains an async right drawer", main.includes("showChapterDrawer") && main.includes("ensureChaptersThen"));

check("release version is 1.0.13", gradle.includes('versionName "1.0.13"'));
check("release code is 13", gradle.includes("versionCode 13"));

if (failed) process.exit(1);
console.log("Rem visual contract holds.");

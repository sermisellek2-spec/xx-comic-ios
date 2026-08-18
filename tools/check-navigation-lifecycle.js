// Async navigation lifecycle contract check.
// Run: node tools/check-navigation-lifecycle.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function method(start, end) {
  return source.slice(source.indexOf(start), source.indexOf(end));
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const navigateBack = method("private boolean navigateBack", "private void applyThemeAndSystemBars");
const onDestroy = method("protected void onDestroy", "protected void onActivityResult");
const enterScreen = method("private void enterScreen", "private Future<?> track");
const filterDrawer = method("private void showFilterDrawer", "private TextView sourceDropdown");
const showTab = method("private void showTab(int tab)", "private void renderSearch");
const showDetail = method("private void showDetail", "private void showReader");
const showReader = method("private void showReader", "private void showReaderLoading");
const renderReader = method("private void renderReader", "private View readerProgressBar");
const standaloneSearch = method("private void showStandaloneSearch", "private void refreshGlobalSearchTabs");
const ensureChapters = method("private void ensureChaptersThen", "private void showChapterDrawer");
const showPageLoading = method("private int showPageLoading", "private boolean isCurrentLoading");
const showHistory = method("private void showHistory", "private View historyRow");
const cacheWriter = method("private void writeComicCacheSnapshots", "private JSONObject summaryToJson");
const postMainIfAlive = method("private void postMainIfAlive", "private void clearErrorLogs");
const writeExportLogs = method("private void writeExportLogs", "private void exportSourceConfig");
const writeExportSourceConfig = method("private void writeExportSourceConfig", "private void openImportSourceConfig");
const importSourceConfig = method("private void importSourceConfig", "private JSONObject sourceConfigJson");
const healthCheck = method("private void healthCheck", "private void rebuildSourceClients");
const miscUiTasks = writeExportLogs + writeExportSourceConfig + importSourceConfig + healthCheck;
const loadSearchPage = method("private void loadSearchPage", "private void loadNextSearchPage");
const runGlobalSearch = method("private void runGlobalSearch", "private void onGlobalSearchSourceDone");

check("loading back action is explicit", /Runnable\s+pageLoadingBackAction/.test(source));
check("detail origin back action is explicit", /private Runnable\s+detailBackAction;/.test(source));
check("legacy loading return tab is removed", !/pageLoadingReturnTab/.test(source));
check("loading API accepts a back action", /showPageLoading\(String title, String desc, Runnable backAction\)/.test(showPageLoading));
check("loading API stores the back action", /pageLoadingBackAction\s*=\s*backAction/.test(showPageLoading));
check(
  "loading back invalidates, cancels, then runs the action",
  /pageLoadingGeneration\+\+[\s\S]*?enterScreen\(\)[\s\S]*?backAction\.run\(\)/.test(navigateBack)
);
check("other screen changes invalidate active loading", /if \(pageLoading\)\s*\{[\s\S]*?pageLoading\s*=\s*false;[\s\S]*?pageLoadingBackAction\s*=\s*null;[\s\S]*?pageLoadingGeneration\+\+;[\s\S]*?\}/.test(enterScreen));
check("detail origin is captured only on first entry", /if \(TextUtils\.isEmpty\(activeDetailId\)\)\s*\{[\s\S]*?detailBackAction\s*=/.test(showDetail));
check("detail origin captures history", /boolean returnToHistory\s*=\s*historyVisible;[\s\S]*?if \(returnToHistory\)[\s\S]*?showHistory\(\)/.test(showDetail));
check("detail loading uses the saved origin action", /showPageLoading\([^;]+detailBackAction\)/s.test(showDetail));
check("history back does not intercept active detail", /if \(historyVisible\s*&&\s*TextUtils\.isEmpty\(activeDetailId\)\)/.test(navigateBack));
check("detail back runs the saved origin action", /Runnable backAction\s*=\s*detailBackAction;[\s\S]*?detailBackAction\s*=\s*null;[\s\S]*?backAction\.run\(\)/.test(navigateBack));
check("top-level tabs clear stale detail origins", /activeDetailId\s*=\s*"";[\s\S]*?detailBackAction\s*=\s*null;/.test(showTab));
const firstShutdown = onDestroy.indexOf("searchIo.shutdownNow()");
check("destroy cancels screen futures before shutdown", /for \(Future<\?> f : currentScreenFutures\)[\s\S]*?f\.cancel\(true\)[\s\S]*?currentScreenFutures\s*=\s*new ArrayList<>\(\)/.test(onDestroy)
  && onDestroy.indexOf("currentScreenFutures") < firstShutdown);
check("destroy cancels image futures before shutdown", /cancelCurrentImageTasks\(\)/.test(onDestroy)
  && onDestroy.indexOf("cancelCurrentImageTasks()") < firstShutdown);
check("destroy marks the activity dead", /activityDestroyed\s*=\s*true;/.test(onDestroy) && onDestroy.indexOf("activityDestroyed = true") < firstShutdown);
check("misc UI helper drops callbacks after destroy", /main\.post\(\(\)\s*->\s*\{[\s\S]*?if \(activityDestroyed\) return;[\s\S]*?action\.run\(\)/.test(postMainIfAlive));
check("all misc business UI callbacks use the alive helper", (miscUiTasks.match(/postMainIfAlive\(/g) || []).length === 7 && !/main\.post\(/.test(miscUiTasks));
check("destroy invalidates async generations", /pageLoadingGeneration\+\+;[\s\S]*?readerGeneration\+\+;[\s\S]*?categoryGeneration\+\+;/.test(onDestroy)
  && onDestroy.indexOf("categoryGeneration++") < firstShutdown);
check("destroy invalidates posted search callbacks", /searchGeneration\+\+;/.test(onDestroy) && onDestroy.indexOf("searchGeneration++") < firstShutdown);
check("destroy invalidates posted global search callbacks", /globalSearchGeneration\+\+;/.test(onDestroy) && onDestroy.indexOf("globalSearchGeneration++") < firstShutdown);
check("posted search success checks the invalidated generation", /main\.post\(\(\)\s*->\s*\{[\s\S]*?if \(generation != searchGeneration\) return;/.test(loadSearchPage));
check("posted global search success checks the invalidated generation", /main\.post\(\(\)\s*->\s*\{[\s\S]*?if \(generation != globalSearchGeneration\) return;/.test(runGlobalSearch));
check("destroy clears visible async state", /pageLoading\s*=\s*false;[\s\S]*?readerVisible\s*=\s*false;/.test(onDestroy));
check("destroy clears navigation actions", /pageLoadingBackAction\s*=\s*null;[\s\S]*?detailBackAction\s*=\s*null;/.test(onDestroy));
check("destroy does not trigger screen rendering", !/(enterScreen|showTab|showDetail|showReader|showHistory)\(/.test(onDestroy));
check("destroy lets queued cache snapshots drain", /miscIo\.shutdown\(\)/.test(onDestroy) && !/miscIo\.shutdownNow\(\)/.test(onDestroy));
check("destroy does not block main waiting for cache persistence", !/awaitTermination/.test(onDestroy));
check("draining cache snapshots only calculate size", /updateCacheSize\(false\)/.test(cacheWriter) && !/updateCacheSizeAsync|imageIo\.|trimImageCache/.test(cacheWriter));
check("chapter loading returns to detail", /showPageLoading\([^;]+\(\)\s*->\s*showDetail\(detail\.summary\.comicId\)/s.test(ensureChapters));
check("loading success clears the action", /pageLoadingBackAction\s*=\s*null[\s\S]*?showDetail\(comicId\)/.test(showDetail));
check("detail loading failure clears the action", /catch \(Exception error\)[\s\S]*?pageLoadingBackAction\s*=\s*null/.test(showDetail));
check("empty chapter response restores detail before dialog", /loadedChapters\.isEmpty\(\)[\s\S]*?showDetail\(detail\.summary\.comicId\)[\s\S]*?showRemDialog\(/.test(ensureChapters));
check("empty chapter response retries the same action", /loadedChapters\.isEmpty\(\)[\s\S]*?\(\)\s*->\s*ensureChaptersThen\(detail, action\)/.test(ensureChapters));
check("chapter exception restores detail before dialog", /catch \(Exception error\)[\s\S]*?showDetail\(detail\.summary\.comicId\)[\s\S]*?showRemDialog\(/.test(ensureChapters));
check("chapter exception retries the same action", /catch \(Exception error\)[\s\S]*?\(\)\s*->\s*ensureChaptersThen\(detail, action\)/.test(ensureChapters));
check("stale chapter callbacks return before UI work", (ensureChapters.match(/if \(!isCurrentLoading\(loadingGeneration\)\) return;/g) || []).length >= 2
  && /if \(expectedCancellation \|\| !isCurrentLoading\(loadingGeneration\)\) return;/.test(ensureChapters));
check("stale chapter success cannot update caches", ensureChapters.indexOf("if (!isCurrentLoading(loadingGeneration)) return;")
  < ensureChapters.indexOf("details.put(detail.summary.comicId, loaded);"));

check("edge gesture routes through navigateBack", /rightFromLeft[\s\S]*?leftFromRight[\s\S]*?navigateBack\(\)/.test(source));
check("detail has no visible back control", !showDetail.includes("R.drawable.ic_back"));
check("reader has no visible back control", !renderReader.includes("R.drawable.ic_back"));
check("history has no visible back control", !showHistory.includes("R.drawable.ic_back"));
const sourcePreselect = filterDrawer.slice(filterDrawer.indexOf("row.setOnClickListener"), filterDrawer.indexOf("content.addView(row)", filterDrawer.indexOf("row.setOnClickListener")));
check("source preselection invalidates search generation", /searchGeneration\+\+/.test(sourcePreselect));
check("source preselection clears search loading", /searchLoading\s*=\s*false;[\s\S]*?searchAppending\s*=\s*false;/.test(sourcePreselect));
check("source preselection removes paging footer", /removeSearchPagingFooter\(\)/.test(sourcePreselect));

console.log("navigation lifecycle ok");

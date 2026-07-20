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
const showDetail = method("private void showDetail", "private void showReader");
const showReader = method("private void showReader", "private void showReaderLoading");
const renderReader = method("private void renderReader", "private View readerProgressBar");
const standaloneSearch = method("private void showStandaloneSearch", "private void refreshGlobalSearchTabs");
const ensureChapters = method("private void ensureChaptersThen", "private void showChapterDrawer");
const showPageLoading = method("private int showPageLoading", "private boolean isCurrentLoading");
const showHistory = method("private void showHistory", "private View historyRow");

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
const firstShutdown = onDestroy.indexOf("searchIo.shutdownNow()");
check("destroy cancels screen futures before shutdown", /for \(Future<\?> f : currentScreenFutures\)[\s\S]*?f\.cancel\(true\)[\s\S]*?currentScreenFutures\s*=\s*new ArrayList<>\(\)/.test(onDestroy)
  && onDestroy.indexOf("currentScreenFutures") < firstShutdown);
check("destroy cancels image futures before shutdown", /cancelCurrentImageTasks\(\)/.test(onDestroy)
  && onDestroy.indexOf("cancelCurrentImageTasks()") < firstShutdown);
check("destroy invalidates async generations", /pageLoadingGeneration\+\+;[\s\S]*?readerGeneration\+\+;[\s\S]*?categoryGeneration\+\+;/.test(onDestroy)
  && onDestroy.indexOf("categoryGeneration++") < firstShutdown);
check("destroy clears visible async state", /pageLoading\s*=\s*false;[\s\S]*?readerVisible\s*=\s*false;/.test(onDestroy));
check("destroy clears navigation actions", /pageLoadingBackAction\s*=\s*null;[\s\S]*?detailBackAction\s*=\s*null;/.test(onDestroy));
check("destroy does not trigger screen rendering", !/(enterScreen|showTab|showDetail|showReader|showHistory)\(/.test(onDestroy));
check("chapter loading returns to detail", /showPageLoading\([^;]+\(\)\s*->\s*showDetail\(detail\.summary\.comicId\)/s.test(ensureChapters));
check("loading success clears the action", /pageLoadingBackAction\s*=\s*null[\s\S]*?showDetail\(comicId\)/.test(showDetail));
check("detail loading failure clears the action", /catch \(Exception error\)[\s\S]*?pageLoadingBackAction\s*=\s*null/.test(showDetail));
check("empty chapter response restores detail before dialog", /loadedChapters\.isEmpty\(\)[\s\S]*?showDetail\(detail\.summary\.comicId\)[\s\S]*?styledDialog\(/.test(ensureChapters));
check("empty chapter response retries the same action", /loadedChapters\.isEmpty\(\)[\s\S]*?\(\)\s*->\s*ensureChaptersThen\(detail, action\)/.test(ensureChapters));
check("chapter exception restores detail before dialog", /catch \(Exception error\)[\s\S]*?showDetail\(detail\.summary\.comicId\)[\s\S]*?styledDialog\(/.test(ensureChapters));
check("chapter exception retries the same action", /catch \(Exception error\)[\s\S]*?\(\)\s*->\s*ensureChaptersThen\(detail, action\)/.test(ensureChapters));
check("stale chapter callbacks return before UI work", (ensureChapters.match(/if \(!isCurrentLoading\(loadingGeneration\)\) return;/g) || []).length >= 2
  && /if \(expectedCancellation \|\| !isCurrentLoading\(loadingGeneration\)\) return;/.test(ensureChapters));
check("stale chapter success cannot update caches", ensureChapters.indexOf("if (!isCurrentLoading(loadingGeneration)) return;")
  < ensureChapters.indexOf("details.put(detail.summary.comicId, loaded);"));

check("full-site search toolbar uses navigateBack", /back\.setOnClickListener\(v -> navigateBack\(\)\)/.test(standaloneSearch));
check("detail toolbar uses navigateBack", /back\.setOnClickListener\(v -> navigateBack\(\)\)/.test(showDetail));
check("reader toolbar uses navigateBack", /back\.setOnClickListener\(v -> navigateBack\(\)\)/.test(renderReader));
check("history toolbar uses navigateBack", /back\.setOnClickListener\(v -> navigateBack\(\)\)/.test(showHistory));

console.log("navigation lifecycle ok");

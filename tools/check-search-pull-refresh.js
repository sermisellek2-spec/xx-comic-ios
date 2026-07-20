const fs = require("fs");

const src = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");

function fail(message) {
  console.error("FAIL " + message);
  process.exit(1);
}

function pass(message) {
  console.log("PASS " + message);
}

function method(start, end) {
  const from = src.indexOf(start);
  const to = src.indexOf(end, from + start.length);
  if (from < 0 || to < 0) fail("method block missing: " + start);
  return src.slice(from, to);
}

if (!src.includes("private static final int SEARCH_PULL_REFRESH_DP = 72;")) fail("pull threshold missing");
if (!src.includes("private boolean searchRefreshing")) fail("refresh state missing");
if (!src.includes("private boolean searchPullTracking")) fail("pull tracking state missing");
if (!src.includes("private float searchPullStartY")) fail("pull start missing");
if (!src.includes("private float searchPullDistance")) fail("pull distance missing");
if (!src.includes("private ProgressBar searchRefreshIndicator")) fail("refresh indicator reference missing");

const render = method("private void renderSearch", "private void appendSearchResults");
if (!render.includes("new ProgressBar(this)")) fail("platform refresh indicator missing");
if (!render.includes("bindSearchPullRefresh(scroll)")) fail("search scroll does not bind pull refresh");
if (!render.includes("searchBody.addView(scroll")) fail("search list is not wrapped with refresh indicator");

const bind = method("private void bindSearchPullRefresh", "private void refreshCurrentSearch");
if (!bind.includes("scroll.getScrollY() == 0")) fail("pull refresh is not top-only");
if (!bind.includes("MotionEvent.ACTION_DOWN")) fail("pull start is not handled");
if (!bind.includes("MotionEvent.ACTION_MOVE")) fail("pull movement is not handled");
if (!bind.includes("MotionEvent.ACTION_UP")) fail("pull release is not handled");
if (!bind.includes("MotionEvent.ACTION_CANCEL")) fail("pull cancellation is not handled");
if (!bind.includes("SEARCH_PULL_REFRESH_DP")) fail("pull trigger does not use threshold");
if (!bind.includes("scroll.setTranslationY(searchPullDistance)")) fail("pull feedback does not move the list");
if (!bind.includes("refreshCurrentSearch()")) fail("pull release does not refresh");
if (!bind.includes("} else if (!searchRefreshing && searchRefreshIndicator != null)")) fail("ordinary touches can hide an active refresh indicator");

const refresh = method("private void refreshCurrentSearch", "private void finishSearchPullRefresh");
if (!refresh.includes("searchLoading || searchAppending || searchRefreshing")) fail("refresh concurrency guard missing");
if (!refresh.includes("String keyword = searchQuery.trim()")) fail("refresh keyword snapshot missing");
if (!refresh.includes("boolean categoryMode = TextUtils.isEmpty(keyword)")) fail("refresh mode snapshot missing");
if (!refresh.includes("loadSearchPage(keyword, 1, false, categoryMode, true)")) fail("refresh does not request page one");

const finish = method("private void finishSearchPullRefresh", "private void loadSearchPage(");
if (!finish.includes("searchRefreshing = false")) fail("refresh completion does not clear state");
if (!finish.includes("searchRefreshIndicator.setVisibility(View.GONE)")) fail("refresh completion does not hide indicator");
if (!finish.includes("searchScroll.setTranslationY(0f)")) fail("refresh completion does not reset list offset");

const load = method("private void loadSearchPage(", "private void loadNextSearchPage");
if (!load.includes("boolean pullRefresh")) fail("search request has no pull-refresh mode");
if (!load.includes("if (pullRefresh)")) fail("pull refresh request branch missing");
if (!load.includes("removeSearchPagingFooter()")) fail("pull refresh does not remove the old paging footer");
if (!load.includes("if (!pullRefresh) showTab(1, false)")) fail("pull refresh still renders a loading page");
if (!load.includes("finishSearchPullRefresh()")) fail("search request does not finish refresh state");
const catchStart = load.indexOf("catch (Exception error)");
const catchBlock = load.slice(catchStart);
if (!catchBlock.includes("if (pullRefresh)")) fail("pull refresh failure branch missing");
if (!catchBlock.includes("appendErrorLog")) fail("pull refresh failure is not logged");
if (!catchBlock.includes("showToast")) fail("pull refresh failure has no feedback");
if (!catchBlock.includes("renderSearchPagingFooter(searchResultsContent)")) fail("pull refresh failure does not restore paging state");
if (catchBlock.indexOf("if (pullRefresh)") > catchBlock.indexOf("showError")) fail("pull refresh failure reaches full-page error");

const next = method("private void loadNextSearchPage", "private void resetSearchPaging");
if (!next.includes("searchRefreshing")) fail("pagination is not blocked during refresh");

const reset = method("private void resetSearchPaging", "private void clearSearchAppendFailure");
if (!reset.includes("finishSearchPullRefresh()")) fail("new searches do not finish an old pull refresh");

const drawer = method("private void showFilterDrawer", "private TextView sourceDropdown");
const sourceChange = drawer.slice(drawer.indexOf("if (!TextUtils.equals(selectedSourceId, sid))"));
if (!sourceChange.includes("finishSearchPullRefresh()")) fail("source changes do not finish an old pull refresh");

const enter = method("private void enterScreen", "private Future<?> track");
if (!enter.includes("finishSearchPullRefresh()")) fail("screen exit does not reset pull refresh");

pass("search pull refresh contracts hold");

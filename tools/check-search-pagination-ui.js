const fs = require("fs");
const src = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
function fail(message) {
  console.error("FAIL " + message);
  process.exit(1);
}
function pass(message) {
  console.log("PASS " + message);
}
const loadStart = src.indexOf("private void loadSearchPage(");
const loadEnd = src.indexOf("private void loadNextSearchPage(");
if (loadStart < 0 || loadEnd < loadStart) fail("loadSearchPage block missing");
const block = src.slice(loadStart, loadEnd);
if (!src.includes("private LinearLayout searchResultsContent;")) fail("search results content reference missing");
if (!src.includes("private View searchPagingFooter;")) fail("search paging footer reference missing");
if (!src.includes("private void appendSearchResults")) fail("append helper missing");
if (block.includes("pendingSearchScrollY = searchScroll.getScrollY()")) fail("append path still saves scroll for full tab rebuild");
if (!block.includes("if (append && searchResultsContent != null)")) fail("append success path missing local-content guard");
if (!block.includes("appendSearchResults(list);")) fail("append success path missing local append call");
if (!src.includes("private boolean searchAppendFailed = false;")) fail("append failure state missing");
if (!block.includes("searchAppendFailed = false")) fail("append success does not clear failure state");
if (!block.includes("searchAppendFailed = true")) fail("append failure does not set failure state");
if (block.indexOf("searchAppendFailed = false") > block.indexOf("if (append)")) fail("request start does not clear failure state");
if (!block.includes("searchHasMore = !list.isEmpty()")) fail("empty page must still stop pagination");
if (!block.includes("if (append)")) fail("append error branch missing");
const appendError = block.slice(block.indexOf("if (append) {", block.indexOf("catch (Exception error)")));
if (appendError.includes("searchHasMore =")) fail("append failure must not change searchHasMore");
if (!src.includes('"加载失败，点击重试"')) fail("retry footer label missing");
if (!src.includes("searchPage + 1")) fail("retry must use next page");
if (!src.includes("|| searchAppendFailed ||")) fail("failed append guard missing");
const footerStart = src.indexOf("private void renderSearchPagingFooter");
const footerEnd = src.indexOf("private void removeSearchPagingFooter", footerStart);
const footer = src.slice(footerStart, footerEnd);
if (footer.indexOf("if (searchAppendFailed)") > footer.indexOf("else if (searchAppending)")) fail("failed footer must replace loading footer");
if (!footer.includes("searchResultsContent == content")) fail("stale footer retry guard missing");
const resetStart = src.indexOf("private void resetSearchPaging()");
const resetEnd = src.indexOf("private void startGlobalSearch", resetStart);
if (resetStart < 0 || !src.slice(resetStart, resetEnd).includes("searchAppendFailed = false;")) fail("reset does not clear failure state");
pass("search pagination appends without rebuilding tab");

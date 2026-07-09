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
pass("search pagination appends without rebuilding tab");
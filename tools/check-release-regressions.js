// Release-blocking UI behavior regressions.
// Run: node tools/check-release-regressions.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const d5d6 = fs.readFileSync(
  "app/src/main/java/com/xxcomic/source/D5d6ComicSource.java",
  "utf8"
);

function method(start, end) {
  return source.slice(source.indexOf(start), source.indexOf(end));
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const loadSearchPage = method("private void loadSearchPage", "private void loadNextSearchPage");
const showDetail = method("private void showDetail", "private void refreshCachedComicOnce");
const showReader = method("private void showReader", "private void showReaderLoading");
const filterDrawer = method("private void showFilterDrawer", "private TextView filterDrawerTab");
const rerender = method("private void rerenderCurrentScreen", "private void enterScreen");
const sourceToggle = method("private void renderSources", "private void addSourceCard");

check("initial search error retries the same request",
  /showError\("加载失败", error, \(\) -> loadSearchPage\(keyword, page, false, categoryMode\)\)/.test(loadSearchPage));
check("detail error retries detail loading",
  /showError\("详情加载失败", error, \(\) -> showDetail\(comicId\)\)/.test(showDetail));
check("reader error retries the current chapter",
  /showReaderError\(detail,[\s\S]*?\(\) -> showReader\(detail, chapterIndex\)\)/.test(showReader));
check("filter confirm preserves the current keyword", !/searchQuery\s*=\s*"";/.test(filterDrawer));
check("filter confirm reruns keyword search", /if \(TextUtils\.isEmpty\(keyword\)\) loadCategory\(\); else runSearch\(keyword\);/.test(filterDrawer));
check("source toggles use one reconciliation path",
  (sourceToggle.match(/finishSourceToggle\(\);/g) || []).length === 15);
check("source reconciliation clears stale single-site results", /private void finishSourceToggle\(\)[\s\S]*?searchResults\.clear\(\)/.test(source));
check("source reconciliation invalidates stale requests", /private void finishSourceToggle\(\)[\s\S]*?searchGeneration\+\+/.test(source));
check("theme rerender preserves source management", /sourceManagementVisible[\s\S]*?showSourceManagement\(\)/.test(rerender));
check("theme rerender preserves history", /historyVisible[\s\S]*?showHistory\(\)/.test(rerender));
check("d5d6 dynamic categories remain a topic group",
  d5d6.includes('SourceFilters.group("category", "题材", categorySlugs)'));
check("d5d6 status remains a separate group",
  d5d6.includes('SourceFilters.group("state", "状态"'));

console.log("release regressions guarded");

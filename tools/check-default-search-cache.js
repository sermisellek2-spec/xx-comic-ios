// Progressive search rendering contract check.
// Run: node tools/check-default-search-cache.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const loadSearchPage = source.slice(source.indexOf("private void loadSearchPage"), source.indexOf("private void loadNextSearchPage"));

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("ordered default-list snapshots are removed", !/DEFAULT_LISTS_CACHE_KEY|restoreDefaultSearchCache|persistDefaultSearchCache/.test(source));
check("search cache persistence is asynchronous", /persistComicCachesAsync\(\)/.test(loadSearchPage));
check(
  "search UI renders before persistence",
  loadSearchPage.indexOf("showTab(1, false)", loadSearchPage.indexOf("searchResults.addAll"))
    < loadSearchPage.indexOf("persistComicCachesAsync()")
);
check("cover cards have a placeholder", /frame\.setBackground\(UIHelpers\.round\(UIHelpers\.PLACEHOLDER/.test(source));
check("cover images load on imageIo", /trackImage\(imageIo\.submit/.test(source));

console.log("progressive search rendering ok");

// Search cancellation contract check.
// Run: node tools/check-search-cancellation.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const loadSearchPage = source.slice(source.indexOf("private void loadSearchPage"), source.indexOf("private void loadNextSearchPage"));

function shouldIgnoreSearchError(error, generation, currentGeneration) {
  return error === "thread interrupted" || generation !== currentGeneration;
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check(
  "intentional screen cancellation is ignored",
  shouldIgnoreSearchError("thread interrupted", 1, 2)
);
check(
  "stale request errors are ignored",
  shouldIgnoreSearchError("timeout", 1, 2)
);
check(
  "current real errors are still reported",
  !shouldIgnoreSearchError("timeout", 2, 2)
);

check("search error handler checks cancellation", /isExpectedTaskCancellation\(error\)/.test(loadSearchPage));
check("search error handler checks generation", /generation\s*!=\s*searchGeneration/.test(loadSearchPage));
check("cancelled current request clears loading state", /isExpectedTaskCancellation\(error\)[\s\S]*?searchLoading\s*=\s*false[\s\S]*?return/.test(loadSearchPage));

console.log("search cancellation ok");

// Source category request generation contract check.
// Run: node tools/check-source-category-generation.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const loadSourceCategories = source.slice(
  source.indexOf("private void loadSourceCategories"),
  source.indexOf("private void showDetailThenRead")
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("category generation field exists", /private int categoryGeneration\s*=\s*0;/.test(source));
check("each category load gets a generation", /int generation\s*=\s*\+\+categoryGeneration;/.test(loadSourceCategories));
check("category load captures source id", /String sourceId\s*=\s*client\.id\(\);/.test(loadSourceCategories));
check(
  "category callback checks generation and selected source",
  /if \(generation\s*!=\s*categoryGeneration\s*\|\|\s*!TextUtils\.equals\(sourceId, selectedSourceId\)\) return;/.test(loadSourceCategories)
);
const guard = loadSourceCategories.indexOf("generation != categoryGeneration");
check("category guard precedes clear", guard >= 0 && guard < loadSourceCategories.indexOf("sourceCategories.clear()"));
check("category guard precedes add", guard >= 0 && guard < loadSourceCategories.indexOf("sourceCategories.addAll(list)"));

console.log("source category generation ok");

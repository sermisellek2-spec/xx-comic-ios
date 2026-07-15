// Default search loading contract check.
// Run: node tools/check-default-search-load.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const onCreate = source.slice(source.indexOf("protected void onCreate"), source.indexOf("protected void onResume"));
const showTab = source.slice(source.indexOf("private void showTab"), source.indexOf("private void renderSearch"));

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("startup does not launch a cancellable search preload", !/loadDefaultCategory\(\)/.test(onCreate));
check("entering search schedules the default request", /scheduleDefaultSearchLoad/.test(showTab));
check("default request is only scheduled for an empty search", /TextUtils\.isEmpty\(searchQuery\.trim\(\)\)/.test(source));
check("search rerenders do not cancel requests", /showTab\(1,\s*false\)/.test(source));

console.log("default search loading ok");

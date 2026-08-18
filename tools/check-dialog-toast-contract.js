const fs = require("fs");

const java = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);

let failed = false;
function fail(message) {
  failed = true;
  console.error(`FAIL ${message}`);
}
function pass(message) {
  console.log(`PASS ${message}`);
}

const removed = [
  "renderProfile",
  "favoriteRow",
  "deleteFavorite",
  "showChoiceDrawer",
  "sourceDropdown",
  "showSourceChooser",
  "showAddSourceDialog",
  "styledDialog",
  "SwipeToDeleteLayout",
];
for (const name of removed) {
  if (java.includes(` ${name}(`) || java.includes(`class ${name}`)) {
    fail(`dead method or class remains: ${name}`);
  }
}

[
  "showSettingsSheet",
  "showFilterDrawer",
  "showChapterDrawer",
  "showRemToast",
  "showReaderHint",
  "showRemDialog",
].forEach((name) => {
  if (!java.includes(` ${name}(`)) fail(`active UI entry missing: ${name}`);
});

if (!java.includes("activeTransientHint")) fail("transient host missing");
if (!java.includes("dismissTransientHint()")) fail("transient cleanup missing");
if (!java.includes("showRemToast(R.drawable.rem_empty")) fail("undo toast missing");
if (!java.includes("showTransientHint(hint")) fail("transient host is not used");
if (!java.includes("errorLogsOverflowButton")
    || !java.includes("导出全部日志")
    || !java.includes("清空错误日志")) fail("error log actions are not grouped in the overflow menu");
if (!java.includes("cacheOverflowButton")
    || !java.includes("清理全部缓存")
    || !java.includes("重新计算大小")) fail("cache actions are not grouped in the overflow menu");

if (failed) process.exit(1);
pass("dialog and toast contracts hold");

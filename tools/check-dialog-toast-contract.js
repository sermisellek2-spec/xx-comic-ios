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

if (failed) process.exit(1);
pass("dialog and toast contracts hold");

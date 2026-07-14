const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check(
  "odd search result keeps one-column width",
  source.includes("row.addView(new View(this), UIHelpers.weight(1));")
);

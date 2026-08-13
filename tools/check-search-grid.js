const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("search results use a fixed three-column grid", source.includes("for (int column = 0; column < 3; column++)"));
check("incomplete rows preserve their column width", source.includes("else row.addView(new View(this), UIHelpers.weight(1));"));

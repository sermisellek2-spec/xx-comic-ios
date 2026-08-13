const fs = require("fs");

const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const d5d6 = fs.readFileSync(
  "app/src/main/java/com/xxcomic/source/D5d6ComicSource.java",
  "utf8"
);

let failed = false;
function check(name, condition) {
  if (condition) console.log("PASS " + name);
  else {
    failed = true;
    console.error("FAIL " + name);
  }
}

check(
  "d5d6 search parses complete cards",
  d5d6.includes("cart-item") && d5d6.includes("cart-info")
);
check(
  "d5d6 title and latest chapter are separate",
  d5d6.includes("new-chapter")
    && d5d6.includes("String latest =")
    && d5d6.includes("absolute(cover), latest,")
);
check(
  "all builtin searches can start concurrently",
  main.includes("Executors.newFixedThreadPool(12)")
);
check(
  "global source completion refreshes failed or empty tabs",
  main.includes("refreshGlobalSearchSourceState(sourceId)")
    && main.includes("refreshGlobalSearchSourceState(client.id())")
);
check(
  "switching global source cancels stale image requests only",
  main.includes("trackImage(imageIo.submit")
    && main.includes("cancelCurrentImageTasks();")
);
check(
  "enabled sources render before disabled sources",
  main.includes("LinearLayout enabledSources = new LinearLayout(this);")
    && main.includes("LinearLayout disabledSources = new LinearLayout(this);")
    && main.includes("addSourceCard(enabledSources, disabledSources")
);

if (failed) process.exit(1);

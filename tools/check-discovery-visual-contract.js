// Finalized discovery-screen visual contract.
// Run: node tools/check-discovery-visual-contract.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
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

function block(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  return from >= 0 && to > from ? source.slice(from, to) : "";
}

const discovery = block("private void renderSearch", "private TextView searchModeButton");
const title = block("private void addDiscoveryTitle", "private TextView searchModeButton");
const history = block("private void renderSearchHistory", "private void renderGlobalSearchResults");
const drawer = block("private void showFilterDrawer", "private TextView filterDrawerTab");
const grid = block("private LinearLayout filterOptionColumn", "private TextView filterGridChip");
const chip = block("private TextView filterGridChip", "private LinearLayout makeBottomNav");

check("discovery uses its finalized title row", discovery.includes("addDiscoveryTitle(page)"));
check("single-site title shows the current source", title.includes("!globalSearchMode") && title.includes("selectedSourceName()"));
check("title source action opens the source drawer", title.includes("showFilterDrawer(0)"));
check("title source action stays borderless", title.includes("Color.TRANSPARENT") && !title.includes("UIHelpers.chip"));
check("lower filter row no longer duplicates source selection", !discovery.includes("filterTextButton(selectedSourceName(), 0)"));
check("lower filter row follows source-defined groups",
  discovery.includes("sourceFilterGroups") && discovery.includes("filterTextButton(group.label, i + 1)"));

check("recent searches wrap by measured natural width", history.includes("availableWidth") && history.includes("chip.measure("));
check("recent searches are not forced into triples", !history.includes("count % 3"));
check("recent searches use a compact dedicated style", history.includes("searchHistoryChip(keyword)"));

check("source drawer identifies enabled sources", drawer.includes('"已启用站源"'));
check("drawer close action is visually light", drawer.includes("close.setBackgroundColor(Color.TRANSPARENT)"));
check("drawer confirm action is compact", drawer.includes("UIHelpers.dp(this, 44)"));
check("filter options remain three columns", grid.includes("final int columns = 3"));
check("filter option cells use compact height and gap", grid.includes("UIHelpers.dp(this, 32)") && grid.includes("UIHelpers.dp(this, 6)"));
check("filter options use the compact corner radius", chip.includes("UIHelpers.dp(this, 6)"));

if (failed) process.exit(1);
console.log("Discovery visual contract holds.");

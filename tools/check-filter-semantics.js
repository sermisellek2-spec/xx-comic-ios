// Discovery filter semantics contract.
// Run: node tools/check-filter-semantics.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const drawer = source.slice(
  source.indexOf("private void showFilterDrawer"),
  source.indexOf("private TextView filterDrawerTab")
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("filter groups come from the active source", /client\.filterGroups\(\)/.test(source));
check("drawer renders source-defined filter groups", /sourceFilterGroups\.get\(filterTab\[0\] - 1\)/.test(drawer));
check("drawer renders source-defined filter options", /group\.options/.test(source));
check("filter values preserve source payloads", /selectedFilters\.put\(group\.key, option\.value\)/.test(source));
check("filter labels remain separate from source values", /selectedFilterLabels\.put\(group\.key, option\.label\)/.test(source));
check("drawer does not send a universal region list", !drawer.includes('Arrays.asList(ALL_TAG, "国漫", "日本", "韩国", "欧美", "内地", "港台", "其它")'));
check("stale selected filters are removed", /selectedFilters\.keySet\(\)\.retainAll\(keys\)/.test(source));
check("missing source filters default to all", /selectedFilters\.put\(group\.key, "all"\)/.test(source));

console.log("discovery filter semantics ok");

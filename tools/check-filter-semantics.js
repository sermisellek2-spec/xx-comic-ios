// Discovery filter semantics contract.
// Run: node tools/check-filter-semantics.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const drawer = source.slice(
  source.indexOf("private void showFilterDrawer"),
  source.indexOf("private TextView sourceDropdown")
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("topic options are source aware", /topicFilterValues\(\)/.test(drawer));
check("region options are source aware", /regionFilterValues\(\)/.test(drawer));
check("state options are source aware", /stateFilterValues\(\)/.test(drawer));
check("drawer does not send a universal region list", !drawer.includes('Arrays.asList(ALL_TAG, "国漫", "日本", "韩国", "欧美", "内地", "港台", "其它")'));
check("topic helper exists", /private List<String> topicFilterValues\(\)/.test(source));
check("region helper exists", /private List<String> regionFilterValues\(\)/.test(source));
check("state helper exists", /private List<String> stateFilterValues\(\)/.test(source));
check("unsupported filter dimensions collapse to all", /return Collections\.singletonList\(ALL_TAG\);/.test(source));

console.log("discovery filter semantics ok");

const fs = require("fs");
const java = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const manifest = fs.readFileSync("app/src/main/AndroidManifest.xml", "utf8");
function fail(message) { console.error("FAIL " + message); process.exit(1); }
function pass(message) { console.log("PASS " + message); }
const navStart = java.indexOf("private LinearLayout makeBottomNav()");
const navEnd = java.indexOf("private TextView sectionTitle", navStart);
if (navStart < 0 || navEnd < navStart) fail("bottom nav block missing");
const nav = java.slice(navStart, navEnd);
const guard = nav.indexOf("if (index == currentTab) return;");
const show = nav.indexOf("showTab(index)");
if (guard < 0 || show < 0 || guard > show) fail("same-tab guard must run before showTab");
const clear = nav.indexOf("clearSearchInputs()");
if (clear >= 0 && guard > clear) fail("same-tab guard must precede clearSearchInputs");
const sourcesStart = java.indexOf("private void renderSources");
const sourcesEnd = java.indexOf("private void addSourceCard", sourcesStart);
const sources = java.slice(sourcesStart, sourcesEnd);
if (sources.includes("for (ComicModels.Source item : customSources)")) fail("source cards expose customSources");
const menuStart = java.indexOf("private void showSourceMenu");
const menuEnd = java.indexOf("private View emptyState", menuStart);
const menu = java.slice(menuStart, menuEnd);
if (menu.includes("showAddSourceDialog")) fail("source menu exposes add source");
if (!menu.includes("exportSourceConfig") || !menu.includes("openImportSourceConfig")) fail("source import/export missing");
if (manifest.includes('android:windowSoftInputMode="adjustNothing"')) fail("manifest still uses adjustNothing");
if (!manifest.includes('android:windowSoftInputMode="adjustResize"')) fail("manifest adjustResize missing");
if (java.includes("SOFT_INPUT_ADJUST_NOTHING")) fail("Java still overrides adjustNothing");
if (!java.includes("showAddSourceDialog") || !java.includes("customSources")) fail("underlying custom source data flow removed");
pass("main interaction contracts hold");

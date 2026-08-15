const fs = require("fs");

const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");

function check(name, condition) {
  if (!condition) {
    console.error(`FAIL ${name}`);
    process.exitCode = 1;
  } else {
    console.log(`PASS ${name}`);
  }
}

function block(start, end) {
  const from = main.indexOf(start);
  const to = main.indexOf(end, from + start.length);
  return from >= 0 && to > from ? main.slice(from, to) : "";
}

const settings = block("private void renderSettings", "private void showSourceManagement");
const sources = block("private void renderSources", "private void addSourceCard");
const theme = block("private void showThemeDrawer", "private void showChoiceDrawer");
const sourceMenu = block("private void showSourceMenu", "private View emptyState");
const cache = block("private void showCacheCleanup", "private void showAboutApp");
const logs = block("private void showErrorLogs", "private String errorLogSummary");
const updates = block("private void checkForUpdate", "private AppRelease fetchAppRelease");
const health = block("private void healthCheck", "private void rebuildSourceClients");

check("settings uses the same clean title as bookshelf and discovery", settings.includes("addTitle(page, \"设置\", null)")
  && !settings.includes("XX Comic · 本地") && !settings.includes("无需登录，数据只保存在本机"));
check("settings rows include approved supporting copy", [
  "跟随系统、浅色或深色",
  "切换阅读页左右触控区",
  "章节与阅读位置",
  "启停、导入导出与检测",
  "保留收藏与阅读历史",
  "只保存在本机",
].every((text) => settings.includes(text)));
check("theme uses three visual choices", theme.includes("themeChoice") && theme.includes("跟随系统")
  && theme.includes("浅色") && theme.includes("深色"));
check("hand preference preview matches the real reader mapping", theme.includes('readerLeftHand ? "下一章" : "上一章"')
  && theme.includes('readerLeftHand ? "上一章" : "下一章"') && theme.includes("显示控制"));
check("source page uses an overflow action sheet", sources.includes("sourceOverflowButton")
  && sourceMenu.includes("导入") && sourceMenu.includes("导出") && sourceMenu.includes("检测可用性"));
check("source rows preserve direct enable switches", main.includes("sourceSwitch")
  && (sources.match(/finishSourceToggle\(\);/g) || []).length === 13);
check("cache page separates cleared and retained data", cache.includes("将被清理")
  && cache.includes("始终保留") && cache.includes("确认清理"));
check("error logs use list and detail scenes", logs.includes("showErrorLogDetail")
  && logs.includes("settingsErrorRow") && logs.includes("copyErrorLog"));
check("update uses dedicated visual states", updates.includes("showUpdateLoading")
  && updates.includes("showUpdateAvailable") && updates.includes("showUpdateLatest"));
check("source health uses loading and result scenes", health.includes("showSourceHealthLoading")
  && health.includes("showSourceHealthResults") && health.includes("sourceHealthGeneration"));
check("source health work is isolated and cancellable when its scene is dismissed", health.includes("sourceHealthFuture = sourceHealthIo.submit")
  && main.includes("private final ExecutorService sourceHealthIo = Executors.newFixedThreadPool(1)")
  && main.includes("sourceHealthIo.shutdownNow()")
  && main.includes("cancelSourceHealthCheck")
  && health.includes("Thread.currentThread().isInterrupted()"));
check("stale update callbacks cannot reopen a dismissed scene", main.includes("generation != updateGeneration"));

if (process.exitCode) process.exit(process.exitCode);
console.log("settings visual contract holds");

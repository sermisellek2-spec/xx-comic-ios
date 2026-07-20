// Comic cache threading and persistence contract check.
// Run: node tools/check-comic-cache-threading.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function method(start, end) {
  return source.slice(source.indexOf(start), source.indexOf(end));
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const persistAsync = method("private void persistComicCachesAsync", "private void writeComicCacheSnapshots");
const writer = method("private void writeComicCacheSnapshots", "private JSONObject summaryToJson");
const showDetail = method("private void showDetail", "private void showReader");
const refresh = method("private void refreshCachedComicOnce", "private ComicModels.ComicDetail withChapters");
const refreshWorker = method("private void refreshCachedComicOnce", "private void finishComicRefresh").slice(refresh.indexOf("detailIo.submit"));
const updateCacheSize = method("private void updateCacheSize()", "private long dirSize");

check("cache maps remain simple main-thread maps", !/ConcurrentHashMap/.test(source));
check("misc cache writer is single-threaded", /miscIo\s*=\s*Executors\.newFixedThreadPool\(1\)/.test(source));
check("there is no synchronous cache persistence entry point", !/persistComicCaches\(\)/.test(source));
check("all cache persistence calls use the async entry point", (source.match(/persistComicCachesAsync\(\)/g) || []).length >= 5);
check("main thread creates all three snapshots", /new ArrayList<>\(summaries\.values\(\)\)[\s\S]*?new ArrayList<>\(details\.values\(\)\)[\s\S]*?new ArrayList<>\(chapters\.values\(\)/.test(persistAsync));
check("snapshots are queued once on miscIo", /miscIo\.execute\(\(\)\s*->\s*writeComicCacheSnapshots\(summarySnapshot, detailSnapshot, chapterSnapshot\)\)/.test(persistAsync));
check("writer only consumes snapshots", !/summaries\.|details\.|chapters\./.test(writer));
check("writer serializes JSON and writes SharedPreferences", /JSONArray[\s\S]*?getSharedPreferences[\s\S]*?\.edit\(\)[\s\S]*?\.apply\(\)/.test(writer));
check("network detail result is handed to main before map writes", showDetail.indexOf("main.post") < showDetail.indexOf("details.put(comicId, loaded)"));
check("automatic refresh result is handed to main before map writes", refresh.indexOf("main.post") < refresh.indexOf("details.put(comicId, loaded)"));
check("worker blocks do not directly write cache maps", !/client\.detail\(comicId\);\s*(?:details|summaries|chapters)\.put/.test(source));
check("snapshot writer only calculates cache size on its FIFO worker", /updateCacheSize\(false\)/.test(writer));
check("cache size is assigned on main after background calculation", /String updatedCacheSize\s*=\s*formatBytes\(bytes\)[\s\S]*?main\.post\(\(\)\s*->\s*\{[\s\S]*?if \(activityDestroyed\) return;[\s\S]*?cacheSize\s*=\s*updatedCacheSize/.test(updateCacheSize));
check("cache size completion does not rerender destroyed UI", !/rerender|showTab|showDetail/.test(updateCacheSize));
check("automatic refresh captures its source before worker submission", /ComicSource client\s*=\s*sourceForDetail\(detail\)/.test(refresh) && refresh.indexOf("sourceForDetail(detail)") < refresh.indexOf("detailIo.submit"));
check("automatic refresh worker does not read cache maps", !/sourceForComicId|sourceForDetail|summaries\.|details\.|chapters\./.test(refreshWorker));

console.log("comic cache threading ok");

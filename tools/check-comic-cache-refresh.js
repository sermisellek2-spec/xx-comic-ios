// Cached detail refresh contract check.
// Run: node tools/check-comic-cache-refresh.js
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

const showDetail = method("private void showDetail", "private void showReader");
const refresh = method("private void refreshCachedComicOnce", "private ComicModels.ComicDetail withChapters");
const initialLoad = showDetail.slice(showDetail.indexOf("if (detail == null)"), showDetail.indexOf("root.removeAllViews()"));

check("per-process refreshed ids exist", /Set<String>\s+refreshedComicIds\s*=\s*new HashSet/.test(source));
check("in-flight refresh ids exist", /Set<String>\s+refreshingComicIds\s*=\s*new HashSet/.test(source));
check("activity destruction state exists", /boolean\s+activityDestroyed/.test(source));
check("cached detail renders before refresh starts", showDetail.indexOf("root.removeAllViews()") < showDetail.indexOf("refreshCachedComicOnce(comicId)"));
check("uncached detail does not wait for the chapter directory", /client\.detail\(comicId\)/.test(initialLoad) && !/client\.chapters\(comicId\)/.test(initialLoad));
check("refresh is skipped after one process attempt", /refreshedComicIds\.contains\(comicId\)/.test(refresh));
check("same comic refresh is deduplicated", /refreshingComicIds\.contains\(comicId\)/.test(refresh));
check("refresh marks in-flight before worker submit", refresh.indexOf("refreshingComicIds.add(comicId)") < refresh.indexOf("detailIo.submit"));
check("refresh fetches detail", /client\.detail\(comicId\)/.test(refresh));
check("refresh fetches chapters through ComicSource", /client\.chapters\(comicId\)/.test(refresh));
check("refresh completion updates ids on main", /main\.post\(\(\)\s*->\s*\{[\s\S]*?refreshingComicIds\.remove\(comicId\)[\s\S]*?refreshedComicIds\.add\(comicId\)/.test(refresh));
check("destroyed activity ignores refresh callbacks", (refresh.match(/if \(activityDestroyed\) return;/g) || []).length === 2);
check("failed automatic refresh still completes the process attempt", /catch \(Exception error\)[\s\S]*?main\.post\(\(\)\s*->\s*\{[\s\S]*?refreshingComicIds\.remove\(comicId\)[\s\S]*?refreshedComicIds\.add\(comicId\)/.test(refresh));
check("successful refresh rerenders only the active detail", /TextUtils\.equals\(activeDetailId, comicId\)[\s\S]*?!readerVisible[\s\S]*?showDetail\(comicId\)/.test(refresh));
check("explicit chapter retry still performs a request", /styledDialog\([\s\S]*?ensureChaptersThen\(detail, action\)/.test(source));

console.log("comic cache refresh ok");

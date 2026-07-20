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
const finishRefresh = method("private void finishComicRefresh", "private void waitForComicRefresh");
const waitForRefresh = method("private void waitForComicRefresh", "private ComicModels.ComicDetail withChapters");
const withChapters = method("private ComicModels.ComicDetail withChapters", "private void showReader");
const ensureChapters = method("private void ensureChaptersThen", "private void showChapterDrawer");
const initialLoad = showDetail.slice(showDetail.indexOf("if (detail == null)"), showDetail.indexOf("root.removeAllViews()"));

check("per-process refreshed ids exist", /Set<String>\s+refreshedComicIds\s*=\s*new HashSet/.test(source));
check("in-flight refresh ids exist", /Set<String>\s+refreshingComicIds\s*=\s*new HashSet/.test(source));
check("one pending user action can wait for each refresh", /Map<String, DetailAction>\s+pendingRefreshActions\s*=\s*new HashMap/.test(source));
check("activity destruction state exists", /boolean\s+activityDestroyed/.test(source));
check("cached detail renders before refresh starts", showDetail.indexOf("root.removeAllViews()") < showDetail.indexOf("refreshCachedComicOnce(detail)"));
check("uncached detail does not wait for the chapter directory", /client\.detail\(comicId\)/.test(initialLoad) && !/client\.chapters\(comicId\)/.test(initialLoad));
check("refresh is skipped after one process attempt", /refreshedComicIds\.contains\(comicId\)/.test(refresh));
check("same comic refresh is deduplicated", /refreshingComicIds\.contains\(comicId\)/.test(refresh));
check("refresh marks in-flight before worker submit", refresh.indexOf("refreshingComicIds.add(comicId)") < refresh.indexOf("detailIo.submit"));
check("refresh fetches detail", /client\.detail\(comicId\)/.test(refresh));
check("refresh fetches chapters through ComicSource", /client\.chapters\(comicId\)/.test(refresh));
check("empty automatic chapter refresh does not create a detail replacement", /loadedChapters\.isEmpty\(\)[\s\S]*?finishComicRefresh\(comicId, null\)[\s\S]*?return;/.test(refresh));
check("fresh detail chapters are never an empty-directory fallback", !/detail\.chapters/.test(withChapters));
check("refresh completion updates ids on main", /main\.post\(\(\)\s*->[\s\S]*?finishComicRefresh\(comicId, loaded\)/.test(refresh) && /refreshingComicIds\.remove\(comicId\)[\s\S]*?refreshedComicIds\.add\(comicId\)/.test(finishRefresh));
check("destroyed activity ignores refresh callbacks", (refresh.match(/if \(activityDestroyed\) return;/g) || []).length >= 2);
check("failed automatic refresh still completes the process attempt", /catch \(Exception error\)[\s\S]*?finishComicRefresh\(comicId, null\)/.test(refresh));
check("successful refresh rerenders only the active detail", /TextUtils\.equals\(activeDetailId, comicId\)[\s\S]*?!readerVisible[\s\S]*?showDetail\(comicId\)/.test(finishRefresh));
check("user chapter action waits for an in-flight comic refresh", /refreshingComicIds\.contains\(detail\.summary\.comicId\)[\s\S]*?waitForComicRefresh\(detail, action\)[\s\S]*?return;/.test(ensureChapters));
check("in-flight refresh is checked before cached chapters", ensureChapters.indexOf("refreshingComicIds.contains") < ensureChapters.indexOf("if (!detail.chapters.isEmpty())"));
check("waiting action is registered without another worker request", /pendingRefreshActions\.put\(comicId,/.test(waitForRefresh) && !/detailIo\.submit/.test(waitForRefresh));
check("failed or empty automatic refresh falls through to explicit chapter loading", /ensureChaptersThen\(detail, action\)/.test(waitForRefresh));
check("refresh clears in-flight state before resuming the user action", finishRefresh.indexOf("refreshingComicIds.remove(comicId)") < finishRefresh.indexOf("pendingAction.run"));
check("pending user action suppresses automatic detail redraw", /if \(pendingAction != null\)\s*\{[\s\S]*?pendingAction\.run[\s\S]*?return;[\s\S]*?\}[\s\S]*?showDetail\(comicId\)/.test(finishRefresh));
check("explicit chapter retry still performs a request", /styledDialog\([\s\S]*?ensureChaptersThen\(detail, action\)/.test(source));

console.log("comic cache refresh ok");

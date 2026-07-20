// Reading history commit and favorite-removal contract check.
// Run: node tools/check-reading-history-semantics.js
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

const showReader = method("private void showReader", "private boolean isCurrentReaderRequest");
const commit = method("private void commitReaderPage", "private boolean isCurrentReaderRequest");
const toggleFavorite = method("private void toggleFavorite", "private void deleteFavorite");
const deleteFavorite = method("private void deleteFavorite", "private void removeDuplicateFavorites");
const removeDuplicates = method("private void removeDuplicateFavorites", "private String normalizedComicTitle");

check("reader entry no longer records history before page load", !/progress\.put|lastViewedAt\.put|saveLocalState\(\)/.test(showReader.slice(0, showReader.indexOf("ComicModels.Chapter chapter"))));
check("valid-page commit rejects empty pages", /if \(isEmptyChapterPage\(page\)\)\s*\{[\s\S]*?return;[\s\S]*?\}/.test(commit));
check("valid-page commit rechecks the reader guard", /if \(!isCurrentReaderRequest\(generation, comicId, chapterUrl, detail\)\) return;/.test(commit));
check("history is written only after validity and guard checks", commit.indexOf("isEmptyChapterPage(page)") < commit.indexOf("progress.put") && commit.indexOf("isCurrentReaderRequest") < commit.indexOf("progress.put"));
check("history commit writes progress and timestamp", /progress\.put\(comicId, readerChapterIndex\)[\s\S]*?lastViewedAt\.put\(comicId, System\.currentTimeMillis\(\)\)[\s\S]*?saveLocalState\(\)/.test(commit));
check("network success uses the shared commit point", /commitReaderPage\(generation, comicId, chapterUrl, detail, page\)/.test(showReader));
check("cache hit uses the shared commit point", /commitReaderPage\(generation, comicId, chapterUrl, detail, cached\)/.test(showReader));
check("cancel favorite preserves reading history", !/progress\.remove|removeReaderPositions|lastViewedAt\.remove/.test(toggleFavorite));
check("delete favorite preserves reading history", !/progress\.remove|removeReaderPositions|lastViewedAt\.remove/.test(deleteFavorite));
check("duplicate favorite removal preserves reading history", !/progress\.remove|removeReaderPositions|lastViewedAt\.remove/.test(removeDuplicates));
check("favorite removal still clears favorite timestamp", /favoriteAt\.remove\(id\)/.test(toggleFavorite) && /favoriteAt\.remove\(id\)/.test(deleteFavorite) && /favoriteAt\.remove\(oldId\)/.test(removeDuplicates));

console.log("reading history semantics ok");

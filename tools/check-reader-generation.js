// Reader request generation contract check.
// Run: node tools/check-reader-generation.js
const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);
const enterScreen = source.slice(source.indexOf("private void enterScreen"), source.indexOf("private Future<?> track"));
const showReader = source.slice(source.indexOf("private void showReader"), source.indexOf("private void showReaderLoading"));
const readerGuard = source.slice(source.indexOf("private boolean isCurrentReaderRequest"), source.indexOf("private void showReaderLoading"));

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("reader generation field exists", /private int readerGeneration\s*=\s*0;/.test(source));
check("entering every screen invalidates reader requests", /readerGeneration\+\+;/.test(enterScreen));
check("chapter request captures reader generation", /int generation\s*=\s*readerGeneration;/.test(showReader));
check("chapter request captures comic id", /String comicId\s*=\s*detail\.summary\.comicId;/.test(showReader));
check("chapter request captures chapter url", /String chapterUrl\s*=\s*chapter\.url;/.test(showReader));
check("reader guard checks generation", /generation\s*!=\s*readerGeneration/.test(readerGuard));
check("reader guard checks visibility", /!readerVisible/.test(readerGuard));
check("reader guard checks active comic", /activeDetailId[\s\S]*?comicId/.test(readerGuard));
check("reader guard checks current chapter index", /readerChapterIndex\s*<\s*0[\s\S]*?readerChapterIndex\s*>=\s*detail\.chapters\.size\(\)/.test(readerGuard));
check("reader guard checks current chapter url", /detail\.chapters\.get\(readerChapterIndex\)\.url[\s\S]*?chapterUrl/.test(readerGuard));
check("success callback uses the complete guard", /main\.post\(\(\)\s*->\s*\{[\s\S]*?if \(!isCurrentReaderRequest\(generation, comicId, chapterUrl, detail\)\) return;[\s\S]*?renderReader/.test(showReader));
check("failure callback uses the complete guard", /catch \(Exception error\)[\s\S]*?main\.post\(\(\)\s*->\s*\{[\s\S]*?if \([^\n]*!isCurrentReaderRequest\(generation, comicId, chapterUrl, detail\)[^\n]*\) return;[\s\S]*?showError/.test(showReader));
check("expected cancellation is computed on worker", /catch \(Exception error\)\s*\{\s*boolean expectedCancellation\s*=\s*isExpectedTaskCancellation\(error\);/.test(showReader));
check("cancelled reader errors are silent", /if \(expectedCancellation\s*\|\|\s*!isCurrentReaderRequest/.test(showReader));
check("reader errors return to the current detail", /showError\("章节加载失败", error, \(\) -> showDetail\(comicId\)\);/.test(showReader));

console.log("reader generation ok");

const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);

function check(condition, message) {
  if (!condition) throw new Error(message);
}

function method(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  check(from >= 0 && to > from, `method block missing: ${start}`);
  return source.slice(from, to);
}

check(
  /private boolean isRetiredSource\(String sourceId\)/.test(source),
  "retired source helper missing",
);
check(
  /coverFrame\(String url, int widthDp, int heightDp, boolean cacheOnly\)/.test(source),
  "cache-only cover overload missing",
);
check(
  /loadImage\(ImageView target, String imageUrl, String pageReferer, boolean cacheOnly\)/.test(source),
  "cache-only image loader missing",
);

const coverLoader = method(
  "private void loadImage(ImageView target, String imageUrl, String pageReferer, boolean cacheOnly)",
  "private void loadImageToCache",
);
check(coverLoader.includes("if (cacheOnly)"), "cover cache miss still reaches network");
check(
  coverLoader.indexOf("if (cacheOnly)") < coverLoader.indexOf("new URL(imageUrl)"),
  "cover cache-only guard runs after network setup",
);

const readerCache = method(
  "private boolean ensureReaderImageCached(String imageUrl, String chapterUrl, boolean cacheOnly)",
  "private Future<?> loadReaderImage",
);
check(readerCache.includes("if (cacheOnly) return false;"), "reader cache miss still reaches network");
check(
  readerCache.indexOf("if (cacheOnly) return false;") < readerCache.indexOf("new URL(imageUrl)"),
  "reader cache-only guard runs after network setup",
);

check(
  /prefetchReaderImages\([\s\S]*?boolean cacheOnly\)/.test(source),
  "reader prefetch does not receive cache-only state",
);
check(
  /loadReaderImage\([\s\S]*?boolean cacheOnly\)/.test(source),
  "reader rows do not receive cache-only state",
);
check(
  source.includes("coverFrame(cover, 86, 116, isRetiredComic(id))"),
  "favorite cover can still use network",
);
check(
  source.includes(
    "if (!isRetiredComic(detail.summary.comicId)) loadImageToCache(detail.summary.coverUrl);",
  ),
  "favorite action can still pre-download retired cover",
);

const sourceForComicId = method(
  "private ComicSource sourceForComicId",
  "private ComicSource sourceForDetail",
);
check(
  sourceForComicId.indexOf('comicId.startsWith(mhua5Client.id() + ":")') <
    sourceForComicId.indexOf("if (summary != null)"),
  "legacy mhua5 id can be routed by an empty source id",
);

const sourceForDetail = method(
  "private ComicSource sourceForDetail",
  "private ComicSource sourceForId",
);
check(
  sourceForDetail.includes("isRetiredComic(detail.summary.comicId)"),
  "legacy mhua5 detail can fall back to the default source",
);

const retiredComic = method(
  "private boolean isRetiredComic",
  "private void loadDefaultCategory",
);
check(
  retiredComic.includes('comicId.startsWith(mhua5Client.id() + ":")') &&
    !retiredComic.includes("TextUtils.isEmpty(sourceId) && comicId"),
  "mhua5 id prefix is not an authoritative retired marker",
);

check(
  (source.match(/boolean cacheOnly = isRetiredComic\(detail\.summary\.comicId\);/g) || []).length >= 2,
  "detail or reader can bypass cache-only mode when source id is empty",
);
check(
  /coverFrame\(summary\.coverUrl,\s*\d+,\s*\d+,\s*isRetiredComic\(comicId\)\)/.test(source),
  "history cover can bypass cache-only mode when source id is empty",
);

const summaryFromJson = method(
  "private ComicModels.ComicSummary summaryFromJson",
  "private JSONObject detailToJson",
);
check(
  summaryFromJson.includes("TextUtils.isEmpty(sourceId) && isRetiredComic(comicId)"),
  "legacy mhua5 cache source id is not normalized",
);

console.log("retired mhua5 cache-only checks ok");

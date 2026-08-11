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
  source.includes("boolean cacheOnly = isRetiredSource(detail.summary.sourceId);"),
  "detail/reader does not derive retired state",
);
check(
  source.includes("coverFrame(cover, 86, 116, isRetiredComic(id))"),
  "favorite cover can still use network",
);
check(
  source.includes("coverFrame(summary.coverUrl, 80, 107, isRetiredSource(summary.sourceId))"),
  "history cover can still use network",
);
check(
  source.includes(
    "if (!isRetiredSource(detail.summary.sourceId)) loadImageToCache(detail.summary.coverUrl);",
  ),
  "favorite action can still pre-download retired cover",
);

console.log("retired mhua5 cache-only checks ok");

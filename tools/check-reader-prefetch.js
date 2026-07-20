const fs = require("fs");

const src = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");

function fail(message) {
  console.error("FAIL " + message);
  process.exit(1);
}

function pass(message) {
  console.log("PASS " + message);
}

function method(start, end) {
  const from = src.indexOf(start);
  const to = src.indexOf(end, from + start.length);
  if (from < 0 || to < 0) fail("method block missing: " + start);
  return src.slice(from, to);
}

if (!src.includes("private static final int READER_PREFETCH_COUNT = 4;")) fail("reader prefetch window missing");
if (!src.includes("private final Set<String> readerPrefetching")) fail("reader prefetch dedupe set missing");
if (!src.includes("readerPrefetchIo = Executors.newFixedThreadPool(2)")) fail("reader prefetch has no dedicated executor");

const render = method("private void renderReader", "private final class PullRefreshScrollView");
if (!render.includes("list.getLastVisiblePosition() + 1")) fail("reader does not prefetch after the initial visible window");
if (!render.includes("prefetchReaderImages(imageUrls, firstVisibleItem + visibleItemCount")) fail("reader does not prefetch on scroll");
if (!render.includes("visibleItemCount > 0")) fail("reader can prefetch visible rows before layout");

const prefetch = method("private void prefetchReaderImages", "private void ensureReaderImageCached");
if (!prefetch.includes("READER_PREFETCH_COUNT")) fail("prefetch window is not bounded");
if (!prefetch.includes("readerPrefetching.add")) fail("prefetch requests are not deduplicated");
if (!prefetch.includes("submitReaderImage(readerPrefetchIo")) fail("prefetch can block visible image loads");
if (!prefetch.includes("ensureReaderImageCached")) fail("prefetch does not use the disk cache path");
if (/decodeReaderImage/.test(prefetch)) fail("prefetch decodes bitmaps instead of warming disk cache");

const ensure = method("private void ensureReaderImageCached", "private Future<?> loadReaderImage");
if (!ensure.includes("writeReaderImageCache(cached, stream)")) fail("shared reader cache writer is missing");
if (!ensure.includes("imageCacheFile(imageUrl)")) fail("reader cache path is not reused");

const loader = method("private Future<?> loadReaderImage", "private boolean isCurrentReaderImageRequest");
if (!loader.includes("ensureReaderImageCached(imageUrl, chapterUrl)")) fail("visible loader does not reuse prefetch cache");

const enter = method("private void enterScreen", "private Future<?> track");
if (!enter.includes("readerPrefetching.clear()")) fail("prefetch dedupe state is not cleared on screen exit");

pass("reader prefetch contracts hold");

// Reader virtualization and sampled image-loading contract check.
// Run: node tools/check-reader-memory.js
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

const renderReader = method("private void renderReader", "private boolean handleReaderTap");
const readerLoader = method("private Future<?> loadReaderImage", "private void loadImage(");
const readerDecode = method("private Bitmap decodeReaderImage", "private void loadImage(");
const readerGuard = method("private boolean isCurrentReaderImageRequest", "private Bitmap decodeReaderImage");

check("reader uses ListView", /ListView\s+list\s*=\s*new ListView\(this\)/.test(renderReader));
check("reader uses BaseAdapter", /setAdapter\(new BaseAdapter\(\)/.test(renderReader));
check("reader no longer wraps pages in ScrollView", !/new ScrollView\(this\)/.test(renderReader));
check("reader no longer creates the full chapter in a loop", !/for\s*\(String url\s*:\s*page\.imageUrls\)/.test(renderReader));
check("adapter reuses ImageView rows", /convertView instanceof ImageView[\s\S]*?\(ImageView\) convertView[\s\S]*?new ImageView/.test(renderReader));
check("reader tracks each row future", /Map<ImageView, Future<\?>>\s+readerImageFutures/.test(renderReader));
check("row rebinding removes its previous future", /readerImageFutures\.remove\(image\)/.test(renderReader));
check("row rebinding cancels before the new load", /readerImageFutures\.remove\(image\)[\s\S]*?cancel\(true\)[\s\S]*?loadReaderImage\(image/.test(renderReader));
check("new reader future is associated with its row", /readerImageFutures\.put\(image,\s*future\)/.test(renderReader));
check("row binding clears stale drawable", /setImageDrawable\(null\)/.test(renderReader));
check("row binding tags the current url", /setTag\(imageUrl\)/.test(renderReader));
check("row binding has a non-zero placeholder", /placeholderHeight\s*=\s*Math\.max\(1,[^;]+\)/.test(renderReader));
check("reader rows use the placeholder height", /AbsListView\.LayoutParams\(-1, placeholderHeight\)/.test(renderReader));
check("reader image loads use dedicated path", /loadReaderImage\(image, imageUrl, chapterUrl, generation, comicId,/.test(renderReader));

check("reader loader is tracked for screen cancellation", /trackImage\(imageIo\.submit/.test(readerLoader));
check("reader loader returns its future", /private Future<\?> loadReaderImage[\s\S]*?return trackImage\(imageIo\.submit/.test(readerLoader));
check("reader loader never reads or writes cover memory cache", !/imageMemoryCache/.test(readerLoader));
check("reader network is streamed to disk", /writeReaderImageCache\(cached, stream\)/.test(readerLoader) && !/readAllBytes|decodeByteArray/.test(readerLoader));
check("reader decode reads bounds first", /inJustDecodeBounds\s*=\s*true[\s\S]*?BitmapFactory\.decodeFile/.test(readerDecode));
check("reader decode uses sampled decode", /inSampleSize\s*=\s*sampleSize[\s\S]*?BitmapFactory\.decodeFile/.test(readerDecode));
check("reader sample size stays power-of-two", /sampleSize\s*\*=\s*2/.test(readerDecode));

check("reader callback checks url tag", /TextUtils\.equals\(imageUrl, \(String\) target\.getTag\(\)\)/.test(readerLoader));
check("reader callback checks request guard", /isCurrentReaderImageRequest\(generation, comicId, chapterUrl\)/.test(readerLoader));
check("reader guard checks generation", /generation\s*!=\s*readerGeneration/.test(readerGuard));
check("reader guard checks visibility", /!readerVisible/.test(readerGuard));
check("reader guard checks comic id", /activeDetailId[\s\S]*?comicId/.test(readerGuard));
check("reader guard checks current chapter", /readerChapterIndex[\s\S]*?chapterUrl/.test(readerGuard));
check("reader success updates real row height", /params\.height/.test(readerLoader)
  && /(?:bitmap|loaded)\.getHeight\(\)/.test(readerLoader)
  && /(?:bitmap|loaded)\.getWidth\(\)/.test(readerLoader));

console.log("reader memory ok");

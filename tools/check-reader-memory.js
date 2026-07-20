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
const readerCacheLoader = method("private void ensureReaderImageCached", "private Future<?> loadReaderImage");
const readerSubmit = method("private Future<?> submitReaderImage", "private Future<?> loadReaderImage");
const readerDecode = method("private Bitmap decodeReaderImage", "private void loadImage(");
const readerGuard = method("private boolean isCurrentReaderImageRequest", "private Bitmap decodeReaderImage");
const readerCacheWriter = method("private void writeReaderImageCache", "private void trimImageCache");
const readerCacheRestore = method("private boolean restoreReaderImageBackup", "private void trimImageCache");
const legacyLoader = method("private void loadImage(ImageView target, String imageUrl, String pageReferer)", "private void loadImageToCache");
const cacheIdentity = method("private long[] captureImageCacheIdentity", "private void deleteImageCacheIfUnchanged");
const cacheDelete = method("private void deleteImageCacheIfUnchanged", "private Future<?> loadReaderImage");

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

check("reader loader is tracked for screen cancellation", /submitReaderImage\(/.test(readerLoader));
check("reader loader returns its future", /private Future<\?> loadReaderImage[\s\S]*?return submitReaderImage\(/.test(readerLoader));
check("reader loader uses a self-cleaning FutureTask", /submitReaderImage\(/.test(readerLoader) && /FutureTask/.test(readerSubmit));
check("reader Future cleanup runs after completion", /protected void done\(\)[\s\S]*?main\.post[\s\S]*?currentImageFutures\.remove\(this\)/.test(readerSubmit));
check("reader loader never reads or writes cover memory cache", !/imageMemoryCache/.test(readerLoader));
check("reader network is streamed to disk", /writeReaderImageCache\(cached, stream\)/.test(readerCacheLoader)
  && !/readAllBytes|decodeByteArray/.test(readerCacheLoader));
check("reader decode reads bounds first", /inJustDecodeBounds\s*=\s*true[\s\S]*?BitmapFactory\.decodeFile/.test(readerDecode));
check("reader decode uses sampled decode", /inSampleSize\s*=\s*\(int\) sampleSize[\s\S]*?BitmapFactory\.decodeFile/.test(readerDecode));
check("reader sample size stays power-of-two", /sampleSize\s*\*=\s*2L/.test(readerDecode));
check("reader decode caps pixels and bytes", /READER_MAX_DECODE_PIXELS/.test(source) && /READER_MAX_DECODE_BYTES/.test(source)
  && /sampledPixels/.test(readerDecode) && /maxBytes/.test(readerDecode));
check("reader decode uses long arithmetic for bounds", /long sampledWidth/.test(readerDecode) && /long sampledHeight/.test(readerDecode)
  && /long sampledPixels/.test(readerDecode));

check("reader callback checks url tag", /TextUtils\.equals\(imageUrl, \(String\) target\.getTag\(\)\)/.test(readerLoader));
check("reader callback checks request guard", /isCurrentReaderImageRequest\(generation, comicId, chapterUrl\)/.test(readerLoader));
check("reader guard checks generation", /generation\s*!=\s*readerGeneration/.test(readerGuard));
check("reader guard checks visibility", /!readerVisible/.test(readerGuard));
check("reader guard checks comic id", /activeDetailId[\s\S]*?comicId/.test(readerGuard));
check("reader guard checks current chapter", /readerChapterIndex[\s\S]*?chapterUrl/.test(readerGuard));
check("reader success updates real row height", /params\.height/.test(readerLoader)
  && /(?:bitmap|loaded)\.getHeight\(\)/.test(readerLoader)
  && /(?:bitmap|loaded)\.getWidth\(\)/.test(readerLoader));

check("reader cache temp is created beside destination", /File\.createTempFile\("reader-", "\.tmp", parent\)/.test(readerCacheWriter));
check("reader cache replacement backs up old file", /file\.renameTo\(backup\)/.test(readerCacheWriter));
check("reader cache replacement renames temp atomically", /temp\.renameTo\(file\)/.test(readerCacheWriter));
check("reader cache replacement restores backup on failure", /restoreReaderImageBackup\(backup, file\)/.test(readerCacheWriter));
check("reader cache replacement never deletes valid target first", !/file\.delete\(\)/.test(readerCacheWriter));
check("reader cache writer uses reliable backup helper", /restoreReaderImageBackup\(backup, file\)/.test(readerCacheWriter));
check("backup helper tries rename before copy", /backup\.renameTo\(target\)[\s\S]*?FileInputStream/.test(readerCacheRestore));
check("backup copy is flushed to storage", /FileOutputStream[\s\S]*?getFD\(\)\.sync\(\)/.test(readerCacheRestore));
check("backup copy closes before restore rename", /try \(InputStream input[\s\S]*?\}[\s\S]*?restore\.renameTo\(target\)/.test(readerCacheRestore));
check("failed backup restore is retained and reported", /return false/.test(readerCacheRestore)
  && /appendErrorLog\("阅读图片缓存恢复失败"/.test(readerCacheWriter));
check("writer no longer ignores backup rename in finally", !/finally\s*\{[\s\S]*?backup\.renameTo\(file\)/.test(readerCacheWriter));
check("reader target swap is protected by cache lock", /synchronized \(imageCacheLock\)\s*\{[\s\S]*?file\.renameTo\(backup\)[\s\S]*?temp\.renameTo\(file\)/.test(readerCacheWriter));
check("backup restore is fully protected by cache lock", /synchronized \(imageCacheLock\)\s*\{[\s\S]*?backup\.exists\(\)[\s\S]*?backup\.renameTo\(target\)[\s\S]*?FileInputStream[\s\S]*?restore\.renameTo\(target\)/.test(readerCacheRestore));
check("cache restore lock contains no UI work", !/main\.post/.test(readerCacheRestore));
check("cache identity captures length and timestamp under lock", /synchronized \(imageCacheLock\)[\s\S]*?file\.exists\(\)[\s\S]*?file\.length\(\)[\s\S]*?file\.lastModified\(\)/.test(cacheIdentity));
check("conditional cache delete rechecks identity under lock", /synchronized \(imageCacheLock\)[\s\S]*?file\.length\(\)\s*==\s*identity\[0\][\s\S]*?file\.lastModified\(\)\s*==\s*identity\[1\][\s\S]*?file\.delete\(\)/.test(cacheDelete));
check("reader disk decode uses identity-checked delete", /captureImageCacheIdentity\(cached\)[\s\S]*?decodeReaderImage\(cached[\s\S]*?deleteImageCacheIfUnchanged\(cached, cachedIdentity\)/.test(readerLoader));
check("legacy disk decode uses identity-checked delete", /captureImageCacheIdentity\(cached\)[\s\S]*?BitmapFactory\.decodeFile\(cached\.getAbsolutePath\(\)\)[\s\S]*?deleteImageCacheIfUnchanged\(cached, cachedIdentity\)/.test(legacyLoader));
check("image loaders never directly delete shared cache target", !/cached\.delete\(\)/.test(readerLoader) && !/cached\.delete\(\)/.test(legacyLoader));
check("cache decode remains outside cache lock", !/synchronized \(imageCacheLock\)[\s\S]*?(?:decodeReaderImage|BitmapFactory\.decodeFile)/.test(cacheIdentity + cacheDelete));

console.log("reader memory ok");

// ============================================================
// BaoziComicSource JS client
// Ported from app/src/.../source/BaoziComicSource.java
// Talks to a CORS proxy (tools/proxy-server.js) on localhost:4174
// ============================================================

const PROXY = "http://localhost:4174";

let sourceAvailable = false;
(function probeSource() {
  if (typeof fetch === "undefined") return;
  fetch(PROXY + "/api/health")
    .then(r => r.json())
    .then(j => { sourceAvailable = j.ok === true; })
    .catch(() => {});
})();

function decodeHtml(raw) {
  var e = document.createElement("div");
  e.innerHTML = raw;
  return e.textContent.replace(/\s+/g, " ").trim();
}

function comicIdFromHref(href) {
  var idx = href.lastIndexOf("/comic/");
  return idx >= 0 ? href.substring(idx + 7) : href.replace("/comic/", "");
}

async function fetchHtml(path) {
  if (typeof fetch === "undefined") throw new Error("fetch not available");
  var resp = await fetch(PROXY + path);
  if (!resp.ok) throw new Error("fetch failed: " + resp.status);
  return await resp.text();
}

async function sourceSearch(keyword) {
  if (!sourceAvailable) throw new Error("source not available");
  var q = encodeURIComponent(keyword || "");
  var html = await fetchHtml("/api/search?q=" + q);
  var cardRe = /<div class="comics-card"[\s\S]*?<a href="([^"]+)" title="([^"]+)"[\s\S]*?src="([^"]+)"[\s\S]*?<small class="tags text-truncate">([\s\S]*?)<\/small>/gi;
  var results = [];
  var m;
  while ((m = cardRe.exec(html)) !== null) {
    var href = m[1].replace(/&amp;/g, "&");
    var title = decodeHtml(m[2]);
    var cover = m[3].replace(/&amp;/g, "&");
    var subtitle = decodeHtml(m[4]);
    var cid = comicIdFromHref(href);
    results.push({ id: cid, title: title, cover: cover, subtitle: subtitle, source: "baozimh" });
  }
  return results;
}

async function sourceDetail(comicId) {
  var html = await fetchHtml("/api/comic/" + comicId);
  var metaRe = /<meta[^>]+(?:name|property|data-hid)="([^"]+)"[^>]+content="([^"]*)"/gi;
  var metas = {};
  var m;
  while ((m = metaRe.exec(html)) !== null) { metas[m[1]] = decodeHtml(m[2] || ""); }
  var chRe = /<a href="([^"]*page_direct[^"]*)"[^>]*class="comics-chapters__item"[\s\S]*?<span[^>]*>([\s\S]*?)<\/span>/gi;
  var chapters = [];
  while ((m = chRe.exec(html)) !== null) {
    var url = m[1].replace(/&amp;/g, "&");
    if (!url.startsWith("https://")) url = "https://cn.bzmgcn.com" + (url.startsWith("/") ? "" : "/") + url;
    chapters.push({ url: url, title: decodeHtml(m[2]) });
  }
  var tags = (metas["og:novel:category"] || "").split(",").map(s => decodeHtml(s)).filter(t => t && !t.startsWith("types."));
  return {
    id: comicId,
    title: metas["og:novel:book_name"] || "",
    author: metas["og:novel:author"] || "",
    status: metas["og:novel:status"] || "",
    desc: metas["og:description"] || "",
    latest: metas["og:novel:latest_chapter_name"] || "",
    cover: metas["og:image"] || "",
    tags: tags,
    source: "baozimh",
    chapters: chapters
  };
}

async function sourceChapter(chapterUrl) {
  var html = await fetchHtml("/api/chapter?url=" + encodeURIComponent(chapterUrl));
  var imgRe = /<amp-img[^>]+(?:data-src|src)="(https:\/\/[^"]+?\.(?:jpg|jpeg|png|webp)[^"]*)"/gi;
  var images = [];
  var m;
  while ((m = imgRe.exec(html)) !== null) {
    var url = m[1].replace(/&amp;/g, "&");
    if (url.includes("/scomic/") && images.indexOf(url) < 0) images.push(url);
  }
  var nextRe = /<div class="next_chapter">[\s\S]*?<a href="([^"]+)"/i;
  var nextM = nextRe.exec(html);
  var nextPage = "";
  if (nextM) {
    nextPage = nextM[1].replace(/&amp;/g, "&");
    if (!nextPage.startsWith("https://")) nextPage = "https://cn.bzmgcn.com" + (nextPage.startsWith("/")?"":"/") + nextPage;
  }
  return { images: images, nextPage: nextPage };
}

// Export for Node usage (CommonJS)
if (typeof module !== "undefined" && module.exports) {
  module.exports = { sourceSearch, sourceDetail, sourceChapter, sourceAvailable, PROXY };
}

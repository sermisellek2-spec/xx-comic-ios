const https = require("https");

const base = "https://hanman18.com";
const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { "User-Agent": ua, "Referer": base + "/" } }, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", chunk => body += chunk);
      res.on("end", () => resolve({ status: res.statusCode, body }));
    }).on("error", reject);
  });
}

function absolute(url) {
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  if (url.startsWith("//")) return "https:" + url;
  return base + (url.startsWith("/") ? url : "/" + url);
}

function attr(tag, name) {
  const match = tag.match(new RegExp(`\\b${name}=["']([^"']*)["']`, "i"));
  return match ? match[1].replace(/&amp;/g, "&").trim() : "";
}

function imageFromTag(tag) {
  return absolute(attr(tag, "data-src") || attr(tag, "data-original") || attr(tag, "data-lazy-src") || attr(tag, "src"));
}

function clean(value) {
  return (value || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

(async () => {
  const search = await fetchText(base + "/search?search=" + encodeURIComponent("新世界"));
  const searchJson = JSON.parse(search.body);
  console.log("search", search.status, searchJson.data.length, searchJson.data.slice(0, 2).map(x => x.name + ":" + x.slug));

  const detail = await fetchText(base + "/manhwa/meilixinshijie");
  const chapterBox = detail.body.match(/<div[^>]+class=["']chapter_box["'][\s\S]*?<\/div>\s*<\/div>/i)?.[0] || detail.body;
  const chapters = [...chapterBox.matchAll(/<a[^>]+href=["']([^"']*\/manhwa\/[^"']+)["'][^>]*class=["']chapter_num["'][^>]*>([\s\S]*?)<\/a>/gi)]
    .map(m => ({ url: absolute(m[1]), title: clean(m[2]) }));
  console.log("detail", detail.status, "chapters", chapters.length, chapters.slice(0, 3));

  const chapterUrl = chapters[0]?.url || base + "/manhwa/meilixinshijie/262";
  const reader = await fetchText(chapterUrl);
  const images = [...reader.body.matchAll(/<img\b[^>]*>/gi)]
    .map(m => imageFromTag(m[0]))
    .filter(v => /\.(jpe?g|png|webp)(?:[?#].*)?$/i.test(v));
  console.log("reader", reader.status, chapterUrl, "images", images.length, images.slice(0, 3));

  if (!searchJson.data.length) throw new Error("search returned no results");
  if (!chapters.length) throw new Error("detail returned no chapters");
  if (!images.length) throw new Error("reader returned no images");
})();

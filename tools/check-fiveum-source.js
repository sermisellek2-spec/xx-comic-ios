// Offline contract checks for FiveUmComicSource and its MainActivity registration.
// Run: node tools/check-fiveum-source.js
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const FIXTURES = path.join(__dirname, "fixtures");

function assert(condition, message) {
  if (!condition) throw new Error("FAIL: " + message);
}

function fixture(name) {
  return fs.readFileSync(path.join(FIXTURES, name), "utf8");
}

function clean(value) {
  return String(value || "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&#40;/gi, "(")
    .replace(/&#41;/gi, ")")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/\s+/g, " ")
    .trim();
}

function attr(tag, name) {
  const match = String(tag || "").match(new RegExp("\\b" + name + "=[\\\"']([^\\\"']*)[\\\"']", "i"));
  return match ? clean(match[1]) : "";
}

function absolute(baseUrl, value) {
  if (!value) return "";
  if (/^https?:\/\//i.test(value)) return value;
  if (value.startsWith("//")) return "https:" + value;
  return baseUrl + (value.startsWith("/") ? value : "/" + value);
}

function rawComicId(value) {
  const match = String(value || "").match(/(?:^|\/)comic_([^/\"'?]+)\.html/i);
  return match ? match[1] : "";
}

function imageFromTag(tag) {
  return attr(tag, "data-src") || attr(tag, "data-original") || attr(tag, "src");
}

function parseCards(html, sourceId, baseUrl) {
  const result = [];
  const seen = new Set();
  const cards = String(html || "").match(/<div[^>]*class=["'][^"']*\bcomic-item\b[^"']*["'][^>]*>[\s\S]*?<\/div>/gi) || [];
  for (const card of cards) {
    const hrefMatch = card.match(/<a[^>]+href=["']([^"']*\/comic_[^"']+\.html)["'][^>]*>/i);
    const href = hrefMatch ? clean(hrefMatch[1]) : "";
    const comicId = rawComicId(href);
    if (!comicId || seen.has(href)) continue;
    seen.add(href);
    const imageTag = (card.match(/<img[^>]*>/i) || [""])[0];
    const title = attr(imageTag, "alt") || attr(card, "title");
    if (!title) continue;
    const authorMatch = card.match(/<p[^>]*class=["'][^"']*\bcomic-author\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
    result.push({
      sourceId,
      comicId: sourceId + ":" + comicId,
      title,
      coverUrl: absolute(baseUrl, imageFromTag(imageTag)),
      subtitle: authorMatch ? clean(authorMatch[1]) : "",
    });
  }
  return result;
}

function parseCategoryMap(html) {
  const sections = String(html || "").split(/(?=<div[^>]*class=["'][^"']*\bfilter-section\b)/i);
  const section = sections.find(value => /漫画类型/.test(clean(value))) || "";
  const result = new Map();
  const links = section.matchAll(/<a[^>]+href=["']([^"']*\/category\/tags\/\d+\/?)["'][^>]*>([\s\S]*?)<\/a>/gi);
  for (const match of links) {
    const name = clean(match[2]);
    if (name && !result.has(name)) result.set(name, clean(match[1]).replace(/\/$/, ""));
  }
  return result;
}

function categoryUrl(baseUrl, tagPath, page) {
  const root = tagPath || "/category";
  return baseUrl + root + (page > 1 ? "/page/" + page : "");
}

function parseDetail(html) {
  const titleMatch = String(html || "").match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const coverBlock = String(html || "").match(/<div[^>]*class=["'][^"']*\bcomic-cover-large\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i);
  const coverTag = ((coverBlock ? coverBlock[1] : "").match(/<img[^>]*>/i) || [""])[0];
  const authorMatch = String(html || "").match(/作者[：:]\s*([\s\S]*?)<\/span>/i);
  const descriptionMatch = String(html || "").match(/<div[^>]*class=["'][^"']*\bcomic-description\b[^"']*["'][^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i);
  return {
    title: clean(titleMatch ? titleMatch[1] : "").replace(/^《|》$/g, ""),
    coverUrl: imageFromTag(coverTag),
    author: clean(authorMatch ? authorMatch[1] : ""),
    description: clean(descriptionMatch ? descriptionMatch[1] : ""),
  };
}

function parseChapters(html, baseUrl) {
  const result = [];
  const seen = new Set();
  const links = String(html || "").matchAll(/<a[^>]+href=["']([^"']*\/chapter_(\d+)_(\d+)\.html)["'][^>]*>([\s\S]*?)<\/a>/gi);
  for (const match of links) {
    const url = absolute(baseUrl, clean(match[1]));
    if (seen.has(url)) continue;
    seen.add(url);
    result.push({ chapterId: match[3], title: clean(match[4]), url });
  }
  return result;
}

function parseImages(html, baseUrl) {
  const contentMatch = String(html || "").match(/<div[^>]*class=["'][^"']*\bcomic-content\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i);
  const result = [];
  const seen = new Set();
  const tags = (contentMatch ? contentMatch[1] : "").match(/<img[^>]*>/gi) || [];
  for (const tag of tags) {
    if (!/class=["'][^"']*\bcomic-image\b/i.test(tag)) continue;
    const url = absolute(baseUrl, imageFromTag(tag));
    if (url && !seen.has(url)) {
      seen.add(url);
      result.push(url);
    }
  }
  return result;
}

const search = fixture("fiveum-search.html");
const category = fixture("fiveum-category.html");
const detail = fixture("fiveum-detail.html");
const chapter = fixture("fiveum-chapter.html");
const manhuazhanCards = parseCards(search, "manhuazhan", "https://www.60ti.com");
const bbyinCards = parseCards(search, "bbyin", "https://bbyin.com");
const categories = parseCategoryMap(category);

assert(manhuazhanCards.length === 2, "search cards deduplicate by detail URL");
assert(manhuazhanCards[0].comicId === "manhuazhan:doupocangkong40jiu41", "manhuazhan comic ID");
assert(bbyinCards[0].comicId === "bbyin:doupocangkong40jiu41", "bbyin comic ID isolation");
assert(manhuazhanCards[0].title === "斗破苍穹(旧)", "HTML entity title decoding");
assert(manhuazhanCards[0].coverUrl.endsWith("70775s.jpg"), "data-src cover priority");
assert([...categories.keys()].join(",") === "热血,奇幻,治愈", "dynamic category order");
assert(categories.get("奇幻") === "/category/tags/61", "dynamic category path");
assert(categoryUrl("https://www.60ti.com", "", 2) === "https://www.60ti.com/category/page/2", "default category pagination");
assert(categoryUrl("https://bbyin.com", categories.get("奇幻"), 3) === "https://bbyin.com/category/tags/61/page/3", "tag pagination");
assert(parseDetail(detail).title === "刃牙II", "detail title");
assert(parseDetail(detail).coverUrl.endsWith("11262s.jpg"), "detail cover outside main info");
assert(parseDetail(detail).author === "板垣惠介,秋田书店", "detail author");
assert(parseDetail(detail).description.includes("死刑犯"), "detail description");
assert(parseChapters(detail, "https://www.60ti.com").length === 2, "chapter URL deduplication");
const images = parseImages(chapter, "https://www.60ti.com");
assert(images.length === 3, "reader images scoped and deduplicated");
assert(images[0].endsWith("001.webp") && images[1].endsWith("002.webp") && images[2].endsWith("003.webp"), "reader image order and attribute priority");

const sourcePath = path.join(ROOT, "app", "src", "main", "java", "com", "xxcomic", "source", "FiveUmComicSource.java");
assert(fs.existsSync(sourcePath), "FiveUmComicSource.java exists");
const source = fs.readFileSync(sourcePath, "utf8");
const config = fs.readFileSync(path.join(ROOT, "app", "src", "main", "java", "com", "xxcomic", "source", "SourceConfig.java"), "utf8");
const main = fs.readFileSync(path.join(ROOT, "app", "src", "main", "java", "com", "xxcomic", "MainActivity.java"), "utf8");

assert(/class\s+FiveUmComicSource\s+implements\s+ComicSource/.test(source), "shared parser class");
assert(/volatile\s+Map<String,\s*String>\s+categoryPaths/.test(source), "immutable category snapshot field");
assert(/Collections\.unmodifiableMap/.test(source), "immutable category snapshot assignment");
assert(/comic-cover-large/.test(source), "detail parser scopes cover to the real cover block");
assert(!source.includes("String descriptionBlock"), "detail description survives nested section header");
assert(/if\s*\(page\s*>\s*1\)\s*return\s+new\s+ArrayList/.test(source), "search does not paginate");
assert(/SourceConfig\s+manhuazhan\(boolean enabled\)/.test(config), "manhuazhan config");
assert(/SourceConfig\s+bbyin\(boolean enabled\)/.test(config), "bbyin config");
assert(/newFixedThreadPool\(11\)/.test(main), "search pool matches eleven active sources");
assert(/SourceConfig\.manhuazhan/.test(main) && /SourceConfig\.bbyin/.test(main), "both source configs registered");
assert(/ComicSource\s+manhuazhanClient/.test(main) && /ComicSource\s+bbyinClient/.test(main), "both source clients declared");
assert(/boolean\s+manhuazhanEnabled\s*=\s*true/.test(main) && /boolean\s+bbyinEnabled\s*=\s*true/.test(main), "both sources default enabled");
assert(/sources\.add\(manhuazhanClient\)/.test(main) && /sources\.add\(bbyinClient\)/.test(main), "both sources join global search");
assert(/new\s+FiveUmComicSource\(manhuazhanConfig/.test(main) && /new\s+FiveUmComicSource\(bbyinConfig/.test(main), "both source clients rebuilt");
assert(/source\.manhuazhan\.enabled/.test(main) && /source\.bbyin\.enabled/.test(main), "both enabled states persisted");
assert(/array\.put\(manhuazhanConfig\.withEnabled/.test(main) && /array\.put\(bbyinConfig\.withEnabled/.test(main), "both configs encoded");
assert(/manhuazhanClient\.id\(\)\.equals\(selectedSourceId\)[\s\S]{0,100}bbyinClient\.id\(\)\.equals\(selectedSourceId\)/.test(main), "dynamic category UI registered");
assert(/isFiveUmImage/.test(main) && /requireImageContentType/.test(main), "5um content type protection");
assert(/\.5um\.net/.test(main) || /5um\.net/.test(main), "5um referer routing");
assert((main.match(/requireImageContentType\(/g) || []).length >= 4, "all three image cache writes validate 5um content type");

console.log("fiveum source ok", "cards=" + manhuazhanCards.length, "categories=" + categories.size, "chapters=2", "images=" + images.length);

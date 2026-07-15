// Manben source parsing checks - mirrors ManbenComicSource.java logic against fixtures.
// Run: node tools/check-manben-source.js
const fs = require("fs");
const path = require("path");

const FIXTURES = path.join(__dirname, "fixtures");
const SOURCE = fs.readFileSync(path.join(__dirname, "..", "app", "src", "main", "java", "com", "xxcomic", "source", "ManbenComicSource.java"), "utf8");

function readFixture(name) {
  return fs.readFileSync(path.join(FIXTURES, name), "utf8");
}

function clean(value) {
  return (value == null ? "" : String(value))
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function first(source, pattern) {
  const m = (source || "").match(pattern);
  return m ? m[1] : "";
}
function firstRaw(source, pattern) {
  const m = (source || "").match(pattern);
  return m ? m[0] : "";
}
function attr(source, name) {
  return first(source, new RegExp("\\b" + name + "=[\"']([^\"']*)[\"']", "i"));
}
function imageUrlFromTag(tag) {
  return attr(tag, "data-src") || attr(tag, "data-original") || attr(tag, "src");
}

const BASE = "https://www.manben.com";
function absolute(url) {
  if (!url) return "";
  if (/^https?:\/\//.test(url)) return url;
  if (url.startsWith("//")) return "https:" + url;
  if (url.startsWith("/")) return BASE + url;
  return BASE + "/" + url;
}

function rawComicId(value) {
  if (!value) return "";
  const m = /\/mh-([^/"'?]+)\//.exec(value);
  if (m) return m[1];
  return value.replace(/\/+$/, "").trim();
}

// ---- category JSON ----
function parseCategoryJson(json) {
  const result = [];
  let array;
  try { array = JSON.parse(json); }
  catch (e) { throw new Error("manben category JSON not an array: " + json.slice(0, 200)); }
  if (!Array.isArray(array)) throw new Error("manben category JSON not an array");
  const seen = new Set();
  for (const item of array) {
    const rawId = rawComicId(item.Url || "");
    if (!rawId || seen.has(rawId)) continue;
    seen.add(rawId);
    const title = clean(item.Title || "");
    if (!title) continue;
    const cover = absolute(item.BigPic || "");
    const author = (item.Author && item.Author.length) ? clean(item.Author[0]) : "";
    const latest = clean(item.LastPartShowName || "");
    const subtitle = author || latest;
    const tags = [];
    const tagSeen = new Set();
    (item.TagList || []).forEach(t => { t = clean(t); if (t && !tagSeen.has(t)) { tagSeen.add(t); tags.push(t); } });
    result.push({ sourceId: "manben", comicId: "manben:" + rawId, title, cover, subtitle, tags });
  }
  return result;
}

// ---- search cards ----
function parseSearchCards(html) {
  const result = [];
  if (!html) return result;
  const seen = new Set();
  const re = /class=["'][^"']*\bitem\b[^"']*["'][^>]*>([\s\S]*?)(?=class=["'][^"']*\b(?:item|pager)\b[^"']*["']|$)/gi;
  let m;
  while ((m = re.exec(html))) {
    const block = m[1];
    const slug = first(block, /\/mh-([^/"'?]+)\//);
    if (!slug || seen.has(slug)) continue;
    seen.add(slug);
    let title = clean(first(block, /class=["']title["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i));
    if (!title) title = clean(first(block, /class=["']title["'][^>]*>([\s\S]*?)<\/div>/i));
    if (!title) continue;
    let imgTag = firstRaw(block, /<img[^>]*\bclass=["'][^"']*cover[^"']*["'][^>]*>/i);
    if (!imgTag) imgTag = firstRaw(block, /<img[^>]+>/i);
    const cover = absolute(cleanUrl(imageUrlFromTag(imgTag)));
    const tip = clean(first(block, /class=["']tip["'][^>]*>([\s\S]*?)<\/(?:div|p)>/i));
    result.push({ sourceId: "manben", comicId: "manben:" + slug, title, cover, subtitle: tip });
  }
  return result;
}
function cleanUrl(value) {
  let url = (value || "").replace(/&amp;/g, "&").replace(/\\\//g, "/").trim();
  const q = url.indexOf('"');
  if (q >= 0) url = url.slice(0, q);
  const s = url.indexOf(' ');
  if (s > 0) url = url.slice(0, s);
  return url;
}

// ---- detail ----
function parseDetail(html) {
  const info = elementContentByClass(html, "comicInfo") || html;
  // <p class="title"><span class="grading">9.2分…</span> 妖神记</p> - grading span nests, take text after last </span>
  let titleContent = first(info, /<p[^>]*class=["']title["'][^>]*>([\s\S]*?)<\/p>/i);
  let title = "";
  if (titleContent) {
    const lastSpan = titleContent.lastIndexOf("</span>");
    title = clean(lastSpan >= 0 ? titleContent.slice(lastSpan + "</span>".length) : titleContent);
  }
  if (!title) title = clean(first(info, /<h1[^>]*>([\s\S]*?)<\/h1>/i));
  if (!title) { title = clean(first(info, /<title>([\s\S]*?)<\/title>/i)); if (title.indexOf(" - ") >= 0) title = title.slice(0, title.indexOf(" - ")).trim(); }
  let coverTag = firstRaw(info, /<div[^>]*class=["'][^"']*\bcover\b[^"']*["'][^>]*>[\s\S]*?<img[^>]+>/i);
  let cover = absolute(cleanUrl(imageUrlFromTag(coverTag)));
  if (!cover) cover = absolute(first(info, /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']*)["']/i));
  const avatar = info.match(/<a\b(?:(?:"[^"]*")|(?:'[^']*')|[^>])*\bclass\s*=\s*["'][^"']*\bavatar\b[^"']*["'](?:(?:"[^"]*")|(?:'[^']*')|[^>])*>/i);
  let author = "";
  if (avatar) {
    const start = avatar.index + avatar[0].length;
    const end = info.indexOf("</a>", start);
    if (end >= start) author = clean(info.slice(start, end));
  }
  if (!author) author = clean(first(info, /作\s*者[：:]?\s*<a[^>]*>([\s\S]*?)<\/a>/i));
  let status = clean(first(info, /状\s*态[：:]?\s*([^<]+)/i));
  let description = clean(first(info, /<p[^>]*class=["']content["'][^>]*>([\s\S]*?)<\/p>/i));
  if (!description) description = clean(first(info, /<meta[^>]+name=["']Description["'][^>]+content=["']([^"']*)["']/i));
  let latest = clean(first(info, /<a[^>]*href=["'][^"']*\/m\d+\/["'][^>]*class=["'][^"']*\bop\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i));
  let tagText = clean(first(info, /类\s*别[：:]?\s*([^<]+)/i));
  let tags = [];
  if (tagText) tagText.split(/[/／]/).forEach(t => { t = clean(t); if (t) tags.push(t); });
  return { title, cover, author, status, description, latest, tags };
}

function elementContentByClass(html, className) {
  const re = new RegExp("<div[^>]*class=[\\\"'][^\\\"']*\\b" + className + "\\b[^\\\"']*[\\\"'][^>]*>", "i");
  const m = re.exec(html || "");
  if (!m) return "";
  return elementContentAt(html, m.index, m[0].length);
}

function elementContentAt(html, start, tagLength) {
  const tagClose = html.indexOf(">", start + tagLength - 1);
  if (tagClose < 0) return "";
  let depth = 1, pos = tagClose + 1;
  while (pos < html.length && depth > 0) {
    const open = html.indexOf("<div", pos);
    const close = html.indexOf("</div", pos);
    if (close < 0) return html.slice(tagClose + 1);
    if (open >= 0 && open < close) { depth++; pos = open + 4; }
    else { depth--; if (depth === 0) return html.slice(tagClose + 1, close); pos = close + 5; }
  }
  return html.slice(tagClose + 1);
}

// ---- chapters ----
function elementContentById(html, idValue) {
  if (!html || !idValue) return "";
  const idx = html.indexOf(idValue);
  if (idx < 0) return "";
  const tagClose = html.indexOf(">", idx);
  if (tagClose < 0) return "";
  let depth = 1, pos = tagClose + 1;
  while (pos < html.length && depth > 0) {
    const open = html.indexOf("<div", pos);
    const close = html.indexOf("</div", pos);
    if (close < 0) return html.slice(tagClose + 1);
    if (open >= 0 && open < close) { depth++; pos = open + 4; }
    else { depth--; if (depth === 0) return html.slice(tagClose + 1, close); pos = close + 5; }
  }
  return html.slice(tagClose + 1);
}
function splitListGroups(block) {
  const groups = [];
  if (!block) return groups;
  const re = /<div[^>]*\bclass=["'][^"']*\blist\b[^"']*["']/gi;
  const starts = [];
  let m;
  while ((m = re.exec(block))) starts.push(m.index);
  for (let i = 0; i < starts.length; i++) {
    const s = starts[i];
    const e = (i + 1 < starts.length) ? starts[i + 1] : block.length;
    groups.push(block.slice(s, e));
  }
  if (!groups.length && block.includes("/m")) groups.push(block);
  return groups;
}
function parseChapters(html) {
  const block = elementContentById(html, "chapterlistload");
  const groups = splitListGroups(block);
  const collected = [];
  const seen = new Set();
  const re = /<a[^>]*href=["'][^"']*\/m(\d+)\/?[^"']*["'][^>]*>([\s\S]*?)<\/a>/gi;
  for (let g = 0; g < groups.length; g++) {
    let m;
    re.lastIndex = 0;
    while ((m = re.exec(groups[g]))) {
      const chapterId = m[1];
      if (!chapterId || seen.has(chapterId)) continue;
      seen.add(chapterId);
      let title = clean(m[2]);
      if (!title) title = "第" + chapterId + "话";
      collected.push({ chapterId: Number(chapterId), title, url: absolute("/m" + chapterId + "/"), sectionSlot: g });
    }
  }
  collected.sort((a, b) => a.sectionSlot - b.sectionSlot || a.chapterId - b.chapterId);
  return collected.map((c, i) => ({ ...c, chapterSlot: i }));
}

// ---- chapter images ----
function isBlockedChapter(html) {
  if (!html) return false;
  const blocked = html.includes("屏蔽") || html.includes("章节数据缺少");
  const hasReaderMarkup = html.includes('class="myview"') || html.includes('class="pageItem"') || html.includes("imageshow.ashx");
  return blocked && !hasReaderMarkup;
}
function parseChapterImageData(script) {
  if (!script || script.indexOf("chapterimage") < 0) throw new Error("no chapterimage");
  const start = script.indexOf("{");
  const end = script.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no json object");
  let root;
  try { root = JSON.parse(script.slice(start, end + 1)); }
  catch (e) { throw new Error("bad json"); }
  const imagePix = root.ImagePix || "";
  const images = root.Images || [];
  if (!imagePix || !images.length) throw new Error("missing ImagePix/Images");
  const result = [];
  const seen = new Set();
  for (const p of images) {
    if (!p) continue;
    const url = /^https?:\/\//.test(p) ? p : imagePix + p;
    if (!/^https?:\/\//.test(url)) continue;
    if (!url.startsWith(imagePix)) continue;
    if (seen.has(url)) continue;
    seen.add(url);
    result.push(url);
  }
  return { images: result, isEnd: !!root.IsEnd };
}

// ===== assertions =====
function assert(cond, msg) { if (!cond) throw new Error("FAIL: " + msg); }

// 1. category JSON
const categoryJson = readFixture("manben-category.json");
const categories = parseCategoryJson(categoryJson);
assert(categories.length === 2, "category count " + categories.length);
assert(categories[0].comicId === "manben:yaoshenji", "category comicId " + categories[0].comicId);
assert(categories[0].title === "妖神记", "category title " + categories[0].title);
assert(categories[0].cover.startsWith("https://mhfm8tel.cdndm5.com/"), "category cover " + categories[0].cover);
assert(categories[0].subtitle === "踏雪动漫", "category subtitle " + categories[0].subtitle);
assert(categories[0].tags.length === 2 && categories[0].tags[0] === "热血", "category tags " + JSON.stringify(categories[0].tags));
// dedup: second item TagList has duplicate 热血 -> should be removed
assert(categories[1].tags.length === 2, "category tag dedup " + JSON.stringify(categories[1].tags));

// 2. search parses 妖神记 + empty page returns empty (no repeat)
const searchHtml = readFixture("manben-search.html");
const searchCards = parseSearchCards(searchHtml);
assert(searchCards.length === 2, "search count " + searchCards.length);
assert(searchCards.some(c => c.title === "妖神记"), "search 妖神记 missing");
assert(searchCards[0].comicId === "manben:yaoshenji", "search comicId " + searchCards[0].comicId);
assert(searchCards[0].cover.startsWith("https://"), "search cover " + searchCards[0].cover);
assert(searchCards[0].subtitle === "妖神一出，谁与争锋。", "search tip " + searchCards[0].subtitle);
const emptyPage = "<html><body><div class='mainSearch'></div></body></html>";
assert(parseSearchCards(emptyPage).length === 0, "empty page should not repeat page 1");

// 3. detail metadata (real comicInfo structure)
const detailHtml = readFixture("manben-detail.html");
const detail = parseDetail(detailHtml);
assert(detail.title === "妖神记", "detail title " + detail.title);
assert(detail.cover === "https://mhfm8tel.cdndm5.com/34/33771/20251023133237_180x240_27.jpg", "detail cover " + detail.cover);
assert(detail.author === "踏雪动漫", "detail author " + detail.author);
assert(detail.status === "连载中", "detail status " + detail.status);
assert(detail.description.includes("妖神一出"), "detail description " + detail.description);
assert(detail.latest === "第522回", "detail latest " + detail.latest);
assert(detail.tags.length === 2 && detail.tags[0] === "热血" && detail.tags[1] === "奇幻", "detail tags " + JSON.stringify(detail.tags));
assert(!detail.title.includes("错误") && detail.cover.indexOf("wrong-cover") < 0 && detail.author !== "错误作者", "detail leaked sidebar metadata " + JSON.stringify(detail));

// 4 & 5 & 6. chapters: only #chapterlistload, hidden included, recommend/comment excluded, oldest-first, bonus present
const chapters = parseChapters(detailHtml);
const ids = chapters.map(c => c.chapterId);
assert(ids.includes(615293) && ids.includes(615292) && ids.includes(615290), "formal chapters present " + JSON.stringify(ids));
assert(ids.includes(615200), "bonus chapter present " + JSON.stringify(ids));
assert(!ids.includes(1801111) && !ids.includes(426476) && !ids.includes(999999) && !ids.includes(888888), "non-chapterlistload links leaked into chapters " + JSON.stringify(ids));
// hidden chapter 第173回 (615290, display:none) must be included
assert(ids.includes(615290), "hidden chapter 615290 missing");
// formal oldest-first: by chapterId ascending the three formal chapters should be 615290 < 615292 < 615293
const formalIds = ids.filter(id => id !== 615200);
assert(formalIds[0] < formalIds[1] && formalIds[1] < formalIds[2], "formal not oldest-first " + JSON.stringify(formalIds));
assert(ids.indexOf(615200) > ids.indexOf(615293) || ids.indexOf(615200) === -1, "bonus must follow formal chapters " + JSON.stringify(ids));
// bonus present (stable - single item)
const bonus = chapters.filter(c => c.chapterId === 615200);
assert(bonus.length === 1 && bonus[0].title.includes("番外"), "bonus chapter " + JSON.stringify(bonus));

// 7 & 8. image data safe parse, ImagePix+Images order, no dup, no JS exec
const imageScript = readFixture("manben-imageshow.txt");
const imageData = parseChapterImageData(imageScript);
assert(imageData.images.length === 2, "image count " + imageData.images.length);
assert(imageData.images[0].startsWith("https://manhua1032-223-111-182-10.cdndm5.com/34/33771/615292/1_6422.jpg"), "image[0] " + imageData.images[0]);
assert(imageData.images[1].endsWith("/2_1934.jpg?cid=615293&key=bbb"), "image[1] " + imageData.images[1]);
assert(imageData.isEnd === false, "isEnd " + imageData.isEnd);
// PreloadImages must NOT be included
assert(imageData.images.length === 2, "preload images leaked " + JSON.stringify(imageData.images));

// 9. blocked chapter detection
const blockedHtml = readFixture("manben-chapter-blocked.html");
assert(isBlockedChapter(blockedHtml), "blocked chapter not detected");
const normalChapter = readFixture("manben-chapter.html");
assert(!isBlockedChapter(normalChapter), "normal chapter flagged as blocked");

// The production loop must fail instead of returning truncated images when IsEnd never arrives.
assert(/boolean\s+reachedEnd\s*=\s*false/.test(SOURCE), "chapter image loop has no reachedEnd guard");
assert(/if\s*\(!reachedEnd\)/.test(SOURCE), "chapter image loop does not fail without IsEnd");

// 10. empty/corrupt/consecutive-empty fail
let threw = false;
try { parseChapterImageData("not a script"); } catch (e) { threw = true; }
assert(threw, "corrupt image script should fail");
threw = false;
try { parseChapterImageData("var chapterimage={};"); } catch (e) { threw = true; }
assert(threw, "empty ImagePix/Images should fail");
// corrupt category JSON
threw = false;
try { parseCategoryJson("{not array}"); } catch (e) { threw = true; }
assert(threw, "corrupt category JSON should fail");

// mojibake guard on the Java source
if (/[鈧濠担婊娴]/.test(SOURCE)) throw new Error("ManbenComicSource.java contains mojibake regex literals");
assert(/elementContentByClass/.test(SOURCE), "detail parser does not scope metadata to comicInfo");
assert(/Matcher avatar/.test(SOURCE), "detail parser does not handle template markup in author href");
const mainActivity = fs.readFileSync(path.join(__dirname, "..", "app", "src", "main", "java", "com", "xxcomic", "MainActivity.java"), "utf8");
assert(/cachedAuthor/.test(mainActivity), "cached author migration missing");

console.log("manben parser ok:", "categories=" + categories.length, "search=" + searchCards.length, "chapters=" + chapters.length, "images=" + imageData.images.length);

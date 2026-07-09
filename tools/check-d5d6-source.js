const fs = require("fs");

const html = fs.readFileSync(process.argv[2], "utf8");

function clean(value) {
  return (value || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

function parseCategories(source) {
  const result = [];
  const re = /<a[^>]+href=["'](?:https?:\/\/www\.d5d6\.com)?\/jiujiucate_(jiujiu[^_\/]+)_allvisit_\d+_\d+\/?["'][^>]*>([\s\S]*?)<\/a>/gi;
  let m;
  const seen = new Set();
  while ((m = re.exec(source || ""))) {
    const slug = m[1];
    const title = clean(m[2]);
    if (!slug || !title || seen.has(slug)) continue;
    seen.add(slug);
    result.push({ slug, title });
  }
  return result;
}

function categoryUrl(slug, state, page) {
  return `https://www.d5d6.com/jiujiucate_${slug || "jiujiuquanbu"}_allvisit_${state || "0"}_${page || 1}/`;
}


function first(source, pattern) {
  const match = (source || "").match(pattern);
  return match ? match[1] : "";
}
function attr(source, name) {
  const match = (source || "").match(new RegExp("\\b" + name + "=[\\\"']([^\\\"']*)[\\\"']", "i"));
  return match ? match[1].replace(/&amp;/g, "&") : "";
}
function imageUrlFromTag(tag) {
  return attr(tag, "data-original") || attr(tag, "data-src") || attr(tag, "src");
}
function parseDetail(source) {
  const title = clean(first(source, /<h1[^>]*class=["'][^"']*title[^"']*["'][^>]*>([\s\S]*?)<\/h1>/i)) || clean(first(source, /<h1[^>]*>([\s\S]*?)<\/h1>/i));
  const info = (source || "").match(/<div[^>]+class=["'][^"']*article-info-item[^"']*["'][^>]*>[\s\S]*?<\/div>\s*<\/div>/i)?.[0] || source || "";
  const coverBlock = (source || "").match(/<div[^>]+class=["'][^"']*cover-box[^"']*["'][^>]*>[\s\S]*?<img[^>]+>/i)?.[0] || "";
  const cover = imageUrlFromTag(coverBlock) || imageUrlFromTag(first(source, /(<img[^>]+alt=["'][^"']*["'][^>]*>)/i));
  const author = clean(first(info, /<span[^>]*class=["']tag["'][^>]*>\s*作者：\s*<\/span>\s*([^<]+)/i));
  const description = clean(first(info, /<span[^>]*class=["']tag["'][^>]*>\s*简介：\s*<\/span>\s*([\s\S]*?)<\/p>/i));
  const latest = clean(first(info, /<span[^>]*class=["']tag["'][^>]*>\s*最新章节：\s*<\/span>\s*<a[^>]*>([\s\S]*?)<\/a>/i));
  return { title, cover, author, description, latest };
}
function parseChapters(source) {
  const result = [];
  const re = /<li>\s*<a[^>]+href=["']([^"']+\.html)["'][^>]*>([\s\S]*?)<\/a>\s*<\/li>/gi;
  let m;
  while ((m = re.exec(source || ""))) result.push({ href: m[1], title: clean(m[2]) });
  return result;
}

function parseReaderImages(source) {
  const block = (source || "").match(/<div[^>]+class=["'][^"']*(?:comicpage|comic-page|read-content|reading|chapter-content|article-content|comic-content|read-img|manga-content)[^"']*["'][^>]*>[\s\S]*?<\/div>/i)?.[0] || source || "";
  const result = [];
  const seen = new Set();
  const re = /<img[^>]+(?:data-original|data-src|src)=["']([^"']+)["'][^>]*>/gi;
  let m;
  while ((m = re.exec(block))) {
    const url = m[1];
    if (!/\.(jpe?g|png|webp)(\?.*)?$/i.test(url) || seen.has(url)) continue;
    seen.add(url);
    result.push(url);
  }
  return result;
}
function isEmptySearchPage(source) {
  return /\u641c\u7d22\u300a[^\u300b]+\u300b\u7ed3\u679c\u4e3a\u7a7a\uff0c\u4ee5\u4e0b\u662f\u4e3a\u60a8\u63a8\u8350\u7684\u70ed\u95e8\u4f5c\u54c1/.test(clean(source));
}

const categories = parseCategories(html);
const expectedAllCategories = 20;
if (categories.length < expectedAllCategories) throw new Error(`missing d5d6 full categories: ${categories.length}`);if (!categories.some(item => item.slug === "jiujiudalu")) throw new Error("missing d5d6 dalu category");
if (categoryUrl("jiujiuquanbu", "1", 2) !== "https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_1_2/") {
  throw new Error("d5d6 category url format changed");
}

const chapterSample = `
<ul class="chapter-list mt20 clearfix">
  <li><a href="225740.html">chapter one</a></li>
  <li><a href="225739.html">chapter two</a></li>
</ul>`;
const chapters = parseChapters(chapterSample);
if (chapters.length !== 2 || chapters[0].href !== "225740.html" || chapters[1].title !== "chapter two") {
  throw new Error("d5d6 chapter parser failed");
}

const emptySearch = `<h2>\u641c\u7d22\u300a\u793e\u56e2\u5b66\u59d0\u300b\u7ed3\u679c\u4e3a\u7a7a\uff0c\u4ee5\u4e0b\u662f\u4e3a\u60a8\u63a8\u8350\u7684\u70ed\u95e8\u4f5c\u54c1</h2>
<a href="https://www.d5d6.com/jiujiucomic_218941/" title="\u70ed\u95e8\u6f2b\u753b">\u70ed\u95e8\u6f2b\u753b</a>`;
if (!isEmptySearchPage(emptySearch)) throw new Error("d5d6 empty search marker failed");


const detailSample = `
<div class="article-info-box clearfix">
  <div class="article-info-content container">
    <div class="cover-box"><img src="https://img.testrainshine.top/prod/0/71/71s.jpg" alt="妖神记"></div>
    <div class="article-info-item">
      <h1 class="title">妖神记</h1>
      <p class="mt10"><span class="tag">作者：</span>踏雪动漫</p>
      <p><span class="tag">最新章节：</span><a href="https://www.d5d6.com/jiujiucomic_218941/2840364.html">第513话2 一线生机</a></p>
      <p class="line-clamp-4"><span class="tag">简介：</span>妖神一出，谁与争锋？</p>
    </div>
  </div>
</div>`;
const detail = parseDetail(detailSample);
if (detail.title !== "妖神记" || detail.author !== "踏雪动漫" || detail.latest !== "第513话2 一线生机" || !detail.cover.includes("71s.jpg") || !detail.description.includes("妖神一出")) {
  throw new Error(`d5d6 detail parser failed: ${JSON.stringify(detail)}`);
}
const javaSource = fs.readFileSync("app/src/main/java/com/xxcomic/source/D5d6ComicSource.java", "utf8");
if (/[鈧濠担婊娴]/.test(javaSource)) {
  throw new Error("d5d6 detail parser still contains mojibake regex literals");
}
const readerSample = `
<img src="https://www.d5d6.com/static/top-ad.webp">
<div class="comicpage">
  <img data-original="https://img.d5d6.com/comic/218941/225740/001.webp">
  <img data-original="https://img.d5d6.com/comic/218941/225740/002.webp">
</div>
<img src="https://www.d5d6.com/static/bottom-ad.jpg">`;
const readerImages = parseReaderImages(readerSample);
if (readerImages.length !== 2 || readerImages[0].includes("ad") || readerImages[1].includes("ad")) {
  throw new Error(`d5d6 reader image parser included ads: ${readerImages.join(",")}`);
}
console.log("d5d6 parser ok", categories.length, categoryUrl("jiujiudalu", "2", 1));





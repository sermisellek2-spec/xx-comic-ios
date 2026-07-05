const https = require("https");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

function get(target, hdrs, rd) {
  rd = rd || 0;
  hdrs = hdrs || {};
  return new Promise((res, rej) => {
    const p = new URL(target);
    const o = {
      hostname: p.hostname, port: p.port || 443, path: p.pathname + p.search, method: "GET",
      headers: Object.assign({
        "User-Agent": UA, "Accept": "text/html,application/xhtml+xml,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
      }, hdrs),
    };
    const q = https.request(o, (r) => {
      if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location && rd < 5) {
        r.resume();
        res(get(new URL(r.headers.location, target).href, hdrs, rd + 1));
        return;
      }
      const chunks = [];
      r.on("data", (c) => chunks.push(c));
      r.on("end", () => res({ code: r.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    q.on("error", rej);
    q.setTimeout(12000, () => { q.destroy(); rej(new Error("timeout")); });
    q.end();
  });
}

function findAll(re, str) { const r = []; let m; while ((m = re.exec(str)) !== null) r.push(m); return r; }

(async () => {
  const HOST = "www.1kkk.com";
  const BASE = "https://" + HOST;

  // 1. 搜索
  var searchUrl = BASE + "/search?title=" + encodeURIComponent("柯南");
  var search = await get(searchUrl);
  console.log("===== 搜索 =====");
  console.log("状态: " + search.code + ", 长度: " + search.body.length);
  console.log("标题: " + (search.body.match(/<title>([^<]*)<\/title>/) || [])[1]);

  // 找卡片链接
  var links = findAll(/href="([^"]*\d{4,}[^"]*)"/g, search.body);
  console.log("数字链接: " + links.length);
  links.slice(0, 15).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 找图片
  var imgs = findAll(/(?:src|data-src|data-original)="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g, search.body);
  console.log("\n图片: " + imgs.length);
  imgs.slice(0, 5).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 找标题
  var titles = findAll(/title="([^"]{2,40})"/g, search.body);
  console.log("\ntitle属性: " + titles.length);
  titles.slice(0, 5).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 打印包含结果的 HTML
  var idx = search.body.indexOf("search-result");
  if (idx < 0) idx = search.body.indexOf("comic-list");
  if (idx < 0) idx = search.body.indexOf("柯南");
  if (idx > 0) console.log("\n结果HTML:\n" + search.body.substring(Math.max(0, idx - 300), idx + 800));

  // 2. 详情 - 从搜索结果找一个链接
  var detailHref = links.filter((m) => !m[1].match(/\.(css|js|png|jpg|ico)/)).map((m) => m[1])[0];
  if (!detailHref) { console.log("无详情链接，结束"); return; }
  var detailUrl = detailHref.startsWith("http") ? detailHref : (BASE + (detailHref.startsWith("/") ? "" : "/") + detailHref);
  console.log("\n===== 详情 =====");
  console.log("URL: " + detailUrl);
  var detail = await get(detailUrl, { Referer: searchUrl });
  console.log("状态: " + detail.code + ", 长度: " + detail.body.length);

  // meta
  var metas = findAll(/<meta[^>]+(?:property|name)="([^"]+)"[^>]+content="([^"]*)"/g, detail.body);
  console.log("\nmeta:");
  metas.forEach((m) => console.log("  " + m[1] + " = " + m[2].substring(0, 100)));

  // 章节链接
  var chLinks = findAll(/href="([^"]*(?:chapter|chaptercontent|\/\d+\/\d+)[^"]*)"/g, detail.body);
  console.log("\n章节链接: " + chLinks.length);
  chLinks.slice(0, 10).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 3. 章节页
  if (chLinks.length === 0) { console.log("无章节，结束"); return; }
  var chapterUrl = chLinks[0][1].startsWith("http") ? chLinks[0][1] : (BASE + chLinks[0][1]);
  console.log("\n===== 章节 =====");
  console.log("URL: " + chapterUrl);
  var chapter = await get(chapterUrl, { Referer: detailUrl });
  console.log("状态: " + chapter.code + ", 长度: " + chapter.body.length);

  // 图片
  var chapterImgs = findAll(/(?:src|data-src)="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g, chapter.body);
  console.log("\n图片: " + chapterImgs.length);
  chapterImgs.slice(0, 5).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // JS 变量
  var jsVars = findAll(/var\s+(\w+)\s*=\s*["']{0,1}([^"';\n]{3,200})["']{0,1}/g, chapter.body);
  console.log("\nJS变量:");
  jsVars.slice(0, 15).forEach((m) => console.log("  " + m[1] + " = " + m[2]));

  // 章节页片段
  console.log("\n章节页HTML:\n" + chapter.body.substring(0, 2000));

  console.log("\n===== 完成 =====");
})().catch((e) => { console.error("致命:", e); process.exit(1); });

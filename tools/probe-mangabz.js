const https = require("https");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const HOST = "mangabz.com";

function dohResolve(host) {
  return new Promise((resolve, reject) => {
    https.get("https://doh.pub/dns-query?name=" + host + "&type=A", {
      headers: { "User-Agent": UA, "Accept": "application/dns-json" },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          const json = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          resolve((json.Answer || []).filter((a) => a.type === 1).map((a) => a.data)[0]);
        } catch (e) { reject(e); }
      });
    }).on("error", reject);
  });
}

function get(target, ip, headers, redirects) {
  redirects = redirects || 0;
  headers = headers || {};
  return new Promise((resolve, reject) => {
    const parsed = new URL(target);
    const options = {
      hostname: ip,
      port: 443,
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: Object.assign({
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Host": parsed.hostname,
        "Referer": "https://" + parsed.hostname + "/",
      }, headers),
      servername: parsed.hostname,
    };
    const req = https.request(options, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        resolve(get(new URL(res.headers.location, target).href, ip, headers, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ code: res.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    req.setTimeout(15000, () => { req.destroy(); reject(new Error("timeout")); });
    req.end();
  });
}

function findAll(re, str) { const r = []; let m; while ((m = re.exec(str)) !== null) r.push(m); return r; }

(async () => {
  const ip = await dohResolve(HOST);
  if (!ip) { console.log("DoH解析失败"); process.exit(1); }
  console.log("mangabz IP: " + ip);

  // 1. 搜索页
  var searchUrl = "https://" + HOST + "/search?title=" + encodeURIComponent("柯南");
  var search = await get(searchUrl, ip);
  console.log("\n===== 搜索页 =====");
  console.log("状态: " + search.code + ", 长度: " + search.body.length);

  // 打印所有 href
  var hrefs = findAll(/href="([^"]{2,100})"/g, search.body);
  console.log("\n所有href (" + hrefs.length + " 个):");
  hrefs.slice(0, 30).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 打印封面图附近的 HTML
  var coverIdx = search.body.indexOf("cover.mangabz");
  if (coverIdx > 0) {
    console.log("\n封面图附近HTML:\n" + search.body.substring(Math.max(0, coverIdx - 800), coverIdx + 400));
  }

  // 2. 从 href 里找详情页（排除 css/js 等资源链接）
  var detailHref = hrefs
    .map((m) => m[1])
    .filter((h) => h.match(/^\/\d+\/bz/) || h.match(/^\/bz\d/) || (h.match(/mangabz\.com\/\d+/) && !h.match(/\.(css|js|png|jpg)/)));
  console.log("\n候选详情href: " + detailHref.length);
  if (detailHref.length === 0) {
    // 试试从 title 属性找
    var titleMatch = search.body.match(/<a[^>]*href="([^"]*)"[^>]*title="名偵探柯南"/);
    if (titleMatch) detailHref = [titleMatch[1]];
  }
  if (detailHref.length === 0) { console.log("找不到详情链接，结束"); return; }

  var firstHref = detailHref[0];
  var detailUrl = firstHref.startsWith("http") ? firstHref : ("https://" + HOST + firstHref);
  console.log("详情URL: " + detailUrl);

  var detail = await get(detailUrl, ip, { Referer: searchUrl });
  console.log("\n===== 详情页 =====");
  console.log("状态: " + detail.code + ", 长度: " + detail.body.length);

  // meta 标签
  var metas = findAll(/<meta[^>]+(?:property|name)="([^"]+)"[^>]+content="([^"]*)"/g, detail.body);
  console.log("\nmeta标签:");
  metas.forEach((m) => console.log("  " + m[1] + " = " + m[2].substring(0, 120)));

  // 章节链接
  var chLinks = findAll(/href="([^"]{3,100})"[^>]*>[^<]*話/g, detail.body);
  console.log("\n章节链接（含'話'）: " + chLinks.length);
  if (chLinks.length === 0) chLinks = findAll(/href="([^"]{3,100})"[^>]*>[^<]*章/g, detail.body);
  console.log("章节链接（含'章'）: " + chLinks.length);
  chLinks.slice(0, 10).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 所有 href
  var detailHrefs = findAll(/href="([^"]{3,100})"/g, detail.body);
  console.log("\n详情页所有href (" + detailHrefs.length + " 个):");
  detailHrefs.slice(0, 25).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 3. 章节页
  if (chLinks.length === 0) { console.log("无章节链接，结束"); return; }
  var chapterUrl = chLinks[0][1].startsWith("http") ? chLinks[0][1] : ("https://" + HOST + chLinks[0][1]);
  console.log("\n===== 章节页 =====");
  console.log("URL: " + chapterUrl);
  var chapter = await get(chapterUrl, ip, { Referer: detailUrl });
  console.log("状态: " + chapter.code + ", 长度: " + chapter.body.length);

  // 图片
  var imgs = findAll(/src="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g, chapter.body);
  console.log("\n图片数: " + imgs.length);
  imgs.slice(0, 5).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // JS 变量
  var jsVars = findAll(/var\s+(\w+)\s*=\s*["']{0,1}([^"';\n]{3,200})["']{0,1}/g, chapter.body);
  console.log("\nJS变量:");
  jsVars.forEach((m) => console.log("  " + m[1] + " = " + m[2]));

  // 章节页片段
  console.log("\n章节页HTML片段:\n" + chapter.body.substring(0, 2000));

  console.log("\n===== 完成 =====");
})().catch((e) => { console.error("致命:", e); process.exit(1); });

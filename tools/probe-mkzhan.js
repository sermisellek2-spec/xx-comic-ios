const https = require("https");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

function doh(h) {
  return new Promise((resolve) => {
    https.get("https://doh.pub/dns-query?name=" + h + "&type=A", {
      headers: { "User-Agent": UA, "Accept": "application/dns-json" },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          const json = JSON.parse(Buffer.concat(chunks).toString());
          resolve((json.Answer || []).filter((a) => a.type === 1).map((a) => a.data));
        } catch { resolve([]); }
      });
    }).on("error", () => resolve([]));
  });
}

function get(target, ip, hdrs, rd) {
  rd = rd || 0;
  hdrs = hdrs || {};
  return new Promise((res, rej) => {
    const p = new URL(target);
    const useIp = ip || p.hostname;
    const o = {
      hostname: useIp, port: p.port || 443, path: p.pathname + p.search, method: "GET",
      headers: Object.assign({
        "User-Agent": UA, "Host": p.hostname, "Accept": "text/html,application/xhtml+xml,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9", "Referer": "https://" + p.hostname + "/",
      }, hdrs),
      servername: p.hostname,
    };
    const q = https.request(o, (r) => {
      if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location && rd < 5) {
        r.resume();
        res(get(new URL(r.headers.location, target).href, ip, hdrs, rd + 1));
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
  const HOST = "www.mkzhan.com";
  const BASE = "https://" + HOST;
  const ips = await doh(HOST);
  console.log("漫客栈 IP: " + (ips[0] || "N/A"));
  if (!ips[0]) { console.log("DoH失败"); return; }

  // 1. 搜索
  var searchUrl = BASE + "/search/?keyword=" + encodeURIComponent("柯南");
  var search = await get(searchUrl, ips[0]);
  console.log("\n===== 搜索 =====");
  console.log("状态: " + search.code + ", 长度: " + search.body.length);
  console.log("标题: " + (search.body.match(/<title>([^<]*)<\/title>/) || [])[1]);

  // 找卡片链接
  var links = findAll(/href="([^"]*\/comic\/[^"]*)"/g, search.body);
  console.log("comic链接: " + links.length);
  links.slice(0, 10).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 找图片
  var imgs = findAll(/src="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g, search.body);
  console.log("图片: " + imgs.length);
  imgs.slice(0, 5).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 找标题
  var titles = findAll(/title="([^"]{2,40})"/g, search.body);
  console.log("title属性: " + titles.length);
  titles.slice(0, 5).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 打印卡片附近 HTML
  var idx = search.body.indexOf("comic/");
  if (idx > 0) console.log("\n卡片HTML:\n" + search.body.substring(Math.max(0, idx - 500), idx + 500));

  // 2. 详情
  if (links.length === 0) { console.log("无链接，结束"); return; }
  var detailUrl = links[0][1].startsWith("http") ? links[0][1] : (BASE + links[0][1]);
  console.log("\n===== 详情 =====");
  console.log("URL: " + detailUrl);
  var detail = await get(detailUrl, ips[0], { Referer: searchUrl });
  console.log("状态: " + detail.code + ", 长度: " + detail.body.length);

  // meta
  var metas = findAll(/<meta[^>]+(?:property|name)="([^"]+)"[^>]+content="([^"]*)"/g, detail.body);
  console.log("\nmeta:");
  metas.forEach((m) => console.log("  " + m[1] + " = " + m[2].substring(0, 100)));

  // 章节链接
  var chLinks = findAll(/href="([^"]*\/chapter[^"]*)"/g, detail.body);
  console.log("\n章节链接: " + chLinks.length);
  if (chLinks.length === 0) {
    // 尝试其他模式
    chLinks = findAll(/href="([^"]*chaptercontent[^"]*)"/g, detail.body);
    if (chLinks.length === 0) {
      var allLinks = findAll(/href="([^"]{3,80})"/g, detail.body);
      console.log("所有href (前20):");
      allLinks.slice(0, 20).forEach((m, i) => console.log("  [" + i + "] " + m[1]));
    }
  }
  chLinks.slice(0, 10).forEach((m, i) => console.log("  [" + i + "] " + m[1]));

  // 3. 章节页
  if (chLinks.length === 0) { console.log("无章节，结束"); return; }
  var chapterUrl = chLinks[0][1].startsWith("http") ? chLinks[0][1] : (BASE + chLinks[0][1]);
  console.log("\n===== 章节 =====");
  console.log("URL: " + chapterUrl);
  var chapter = await get(chapterUrl, ips[0], { Referer: detailUrl });
  console.log("状态: " + chapter.code + ", 长度: " + chapter.body.length);

  // 图片
  var chapterImgs = findAll(/src="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g, chapter.body);
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

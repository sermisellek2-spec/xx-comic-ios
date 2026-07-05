const https = require("https");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";

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

function getIP(url, ip, hdrs, rd) {
  rd = rd || 0;
  return new Promise((res, rej) => {
    const p = new URL(url);
    const o = {
      hostname: ip, port: 443, path: p.pathname + p.search, method: "GET",
      headers: Object.assign({
        "User-Agent": UA, "Host": p.hostname, "Accept": "*/*",
        "Referer": "https://mangabz.com/m500676/",
      }, hdrs || {}),
      servername: p.hostname,
    };
    const q = https.request(o, (r) => {
      if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location && rd < 3) {
        r.resume();
        res(getIP(new URL(r.headers.location, url).href, ip, hdrs, rd + 1));
        return;
      }
      const chunks = [];
      r.on("data", (c) => chunks.push(c));
      r.on("end", () => res({ code: r.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    q.on("error", rej);
    q.setTimeout(10000, () => { q.destroy(); rej(new Error("timeout")); });
    q.end();
  });
}

function findAll(re, str) { const r = []; let m; while ((m = re.exec(str)) !== null) r.push(m); return r; }

(async () => {
  const ips = await doh("mangabz.com");
  console.log("mangabz IP: " + ips[0]);

  // 获取章节页完整 HTML
  const r = await getIP("https://mangabz.com/m500676/", ips[0]);
  const b = r.body;
  console.log("状态: " + r.code + ", 长度: " + b.length);

  // 所有图片 URL
  var imgs = findAll(/https?:\/\/[^"' ]+\.(?:jpg|jpeg|png|webp|gif)[^"' ]*/g, b);
  console.log("\n所有图片URL: " + imgs.length);
  imgs.forEach((m, i) => console.log("  [" + i + "] " + m[0]));

  // data-src / data-original
  var ds = findAll(/data-(src|original|lazy)=([^"' ]+)/g, b);
  console.log("\ndata属性: " + ds.length);
  ds.forEach((m) => console.log("  " + m[1] + " = " + m[2]));

  // 搜索所有 img 标签
  var imgTags = findAll(/<img[^>]+>/g, b);
  console.log("\nimg标签: " + imgTags.length);
  imgTags.forEach((m, i) => console.log("  [" + i + "] " + m[0].substring(0, 200)));

  // 搜索 MANGABZ_IMAGE_COUNT
  var ic = b.match(/MANGABZ_IMAGE_COUNT\s*=\s*(\d+)/);
  if (ic) console.log("\nMANGABZ_IMAGE_COUNT: " + ic[1]);

  // 打印页面尾部 3000 字符
  console.log("\n页面尾部:\n" + b.substring(b.length - 3000));

  // 尝试 chapter.js 中的 getImageUrl
  const cssIps = await doh("css.mangabz.com");
  if (cssIps.length > 0) {
    console.log("\ncss.mangabz.com IP: " + cssIps[0]);
    try {
      var js = await getIP("https://css.mangabz.com/v202606241611/mangabz/js/chapter.js", cssIps[0]);
      console.log("chapter.js: " + js.code + ", 长度: " + js.body.length);
      // 找图片相关逻辑
      var idx = js.body.indexOf("imageUrl");
      if (idx > 0) console.log("\nimageUrl片段:\n" + js.body.substring(Math.max(0, idx - 200), idx + 600));
      idx = js.body.indexOf("getImag");
      if (idx > 0) console.log("\ngetImag片段:\n" + js.body.substring(Math.max(0, idx - 100), idx + 500));
      idx = js.body.indexOf("chapterImage");
      if (idx > 0) console.log("\nchapterImage片段:\n" + js.body.substring(Math.max(0, idx - 100), idx + 500));
      // 搜索所有 ajax 请求
      var ajaxs = findAll(/(?:url|src)\s*[:=]\s*["']([^"']+chapter[^"']+)["']/g, js.body);
      console.log("\nchapter相关URL: " + ajaxs.length);
      ajaxs.forEach((m) => console.log("  " + m[1]));
    } catch (e) {
      console.log("chapter.js失败: " + e.message);
    }
  }

  console.log("\n===== 完成 =====");
})().catch((e) => { console.error("致命:", e); process.exit(1); });

const https = require("https");
const http = require("http");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const KEYWORD = "柯南";

function get(target, headers = {}, redirects = 0) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(target);
    const isHttps = parsed.protocol === "https:";
    const lib = isHttps ? https : http;
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        ...headers,
      },
    };
    const req = lib.request(options, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        resolve(get(new URL(res.headers.location, target).href, headers, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        resolve({ code: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString("utf8") });
      });
    });
    req.on("error", reject);
    req.setTimeout(15000, () => { req.destroy(); reject(new Error("timeout: " + target)); });
    req.end();
  });
}

function banner(name) { console.log("\n========== " + name + " =========="); }
function snip(s, max) { return s.substring(0, max || 600); }

// ── 拷贝漫画 CopyManga ──
async function probeCopyManga() {
  banner("拷贝漫画 CopyManga");
  const api = "https://api.copymanga.site";
  try {
    const res = await get(api + "/api/v3/search/comic?offset=0&platform=1&q=" + encodeURIComponent(KEYWORD) + "&limit=5");
    console.log("搜索: " + res.code + ", 长度: " + res.body.length);
    if (res.code !== 200) { console.log(snip(res.body)); return; }
    try {
      const json = JSON.parse(res.body);
      console.log("顶层keys: " + Object.keys(json).join(", "));
      const list = (json.results && json.results.list) || json.results || [];
      console.log("结果数: " + (Array.isArray(list) ? list.length : "N/A"));
      if (Array.isArray(list) && list.length > 0) {
        console.log("首条: " + JSON.stringify(list[0]).substring(0, 500));
        const pathWord = list[0].path_word;
        if (pathWord) {
          const detail = await get(api + "/api/v3/comic2/" + pathWord + "?platform=1");
          console.log("详情: " + detail.code + ", 长度: " + detail.body.length);
          try {
            const dj = JSON.parse(detail.body);
            console.log("详情keys: " + Object.keys(dj).join(", "));
            if (dj.results) console.log("详情results: " + JSON.stringify(dj.results).substring(0, 600));
          } catch (e) { console.log("详情非JSON: " + snip(detail.body)); }
        }
      }
    } catch (e) { console.log("非JSON: " + e.message); console.log(snip(res.body)); }
  } catch (e) { console.log("失败: " + e.message); }
}

// ── 动漫之家 DMZJ ──
async function probeDmzj() {
  banner("动漫之家 DMZJ");
  const api = "https://v3api.dmzj.com";
  try {
    let res = await get(api + "/v3/search/search?key=" + encodeURIComponent(KEYWORD) + "&offset=0&limit=5");
    console.log("搜索v3: " + res.code + ", 长度: " + res.body.length);
    if (res.code === 200) {
      try {
        const json = JSON.parse(res.body);
        if (Array.isArray(json)) console.log("是数组, 长度: " + json.length);
        else console.log("顶层keys: " + Object.keys(json).join(", "));
        const list = Array.isArray(json) ? json : (json.data || json.list || json.results || []);
        if (Array.isArray(list) && list.length > 0) console.log("首条: " + JSON.stringify(list[0]).substring(0, 500));
      } catch (e) { console.log("非JSON: " + e.message); console.log(snip(res.body)); }
    } else {
      console.log("v3失败, 尝试旧API...");
      const res2 = await get("https://m.dmzj.com/search.do?keyword=" + encodeURIComponent(KEYWORD));
      console.log("搜索m: " + res2.code + ", 长度: " + res2.body.length);
      console.log(snip(res2.body));
    }
  } catch (e) { console.log("失败: " + e.message); }
}

// ── 漫画柜 ManHuaGui ──
async function probeManhuagui() {
  banner("漫画柜 ManHuaGui");
  const base = "https://www.manhuagui.com";
  try {
    const res = await get(base + "/s/" + encodeURIComponent(KEYWORD) + ".html", { Referer: base + "/" });
    console.log("搜索: " + res.code + ", 长度: " + res.body.length);
    const cards = res.body.match(/href="\/comic\/(\d+)\/"[^>]*title="([^"]*)"/g);
    console.log("卡片数: " + (cards ? cards.length : 0));
    if (cards) console.log("前3条:\n  " + cards.slice(0, 3).join("\n  "));
    const imgs = res.body.match(/src="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g);
    console.log("图片数: " + (imgs ? imgs.length : 0));
    if (imgs) console.log("前2图:\n  " + imgs.slice(0, 2).join("\n  "));
    console.log("HTML片段:\n  " + snip(res.body, 800).replace(/\n/g, "\n  "));
  } catch (e) { console.log("失败: " + e.message); }
}

// ── mangabz ──
async function probeMangabz() {
  banner("mangabz");
  const base = "https://mangabz.com";
  try {
    const res = await get(base + "/search?title=" + encodeURIComponent(KEYWORD));
    console.log("搜索: " + res.code + ", 长度: " + res.body.length);
    const cards = res.body.match(/href="(\/\d+\/)"[^>]*title="([^"]*)"/g);
    console.log("卡片数: " + (cards ? cards.length : 0));
    if (cards) console.log("前3条:\n  " + cards.slice(0, 3).join("\n  "));
    const imgs = res.body.match(/src="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g);
    console.log("图片数: " + (imgs ? imgs.length : 0));
    if (imgs) console.log("前2图:\n  " + imgs.slice(0, 2).join("\n  "));
    console.log("HTML片段:\n  " + snip(res.body, 800).replace(/\n/g, "\n  "));
  } catch (e) { console.log("失败: " + e.message); }
}

// ── 动漫狂 CartoonMad ──
async function probeCartoonMad() {
  banner("动漫狂 CartoonMad");
  const base = "https://www.cartoonmad.com";
  try {
    const res = await get(base + "/search.html?keyword=" + encodeURIComponent(KEYWORD));
    console.log("搜索: " + res.code + ", 长度: " + res.body.length);
    const links = res.body.match(/href="\/comic\/(\d+)\.html"[^>]*>([^<]*)/g);
    console.log("卡片数: " + (links ? links.length : 0));
    if (links) console.log("前3条:\n  " + links.slice(0, 3).join("\n  "));
    const imgs = res.body.match(/src="([^"]*\.(?:jpg|jpeg|png|gif)[^"]*)"/g);
    console.log("图片数: " + (imgs ? imgs.length : 0));
    if (imgs) console.log("前2图:\n  " + imgs.slice(0, 2).join("\n  "));
    console.log("HTML片段:\n  " + snip(res.body, 800).replace(/\n/g, "\n  "));
  } catch (e) { console.log("失败: " + e.message); }
}

(async () => {
  await probeCopyManga();
  await probeDmzj();
  await probeManhuagui();
  await probeMangabz();
  await probeCartoonMad();
  console.log("\n========== 探测完成 ==========");
})().catch((e) => {
  console.error("致命错误:", e);
  process.exit(1);
});

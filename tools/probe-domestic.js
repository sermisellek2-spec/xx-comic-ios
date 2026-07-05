const https = require("https");
const dns = require("dns");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const KEYWORD = "柯南";

// 候选国内站源
const SOURCES = [
  { name: "漫客栈", host: "www.mkzhan.com", path: "/search/?keyword=" },
  { name: "古风漫画", host: "www.gufengmh9.com", path: "/search/?keywords=" },
  { name: "36漫画", host: "www.36mh.com", path: "/search/?searchkey=" },
  { name: "77漫画", host: "www.77mh.nl", path: "/search/?searchkey=" },
  { name: "733动漫", host: "www.733dm.com", path: "/search/?keyword=" },
  { name: "动漫之家移动", host: "m.idmzj.com", path: "/search.do?keyword=" },
  { name: "漫小肆", host: "www.manxiaosi.cn", path: "/search.html?searchkey=" },
  { name: "极速漫画", host: "www.1kkk.com", path: "/search?title=" },
  { name: "汗汗漫画", host: "www.hhmmoo.com", path: "/search/index.aspx?searchkeyword=" },
  { name: "拷贝漫画网页", host: "www.mangacopy.com", path: "/api/v3/search/comic?offset=0&platform=1&q=" },
];

function get(target, headers = {}, redirects = 0) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(target);
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || 443,
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        ...headers,
      },
    };
    const req = https.request(options, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        resolve(get(new URL(res.headers.location, target).href, headers, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        resolve({ code: res.statusCode, body: Buffer.concat(chunks).toString("utf8") });
      });
    });
    req.on("error", reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error("timeout")); });
    req.end();
  });
}

function dohResolve(host) {
  return new Promise((resolve) => {
    https.get("https://doh.pub/dns-query?name=" + host + "&type=A", {
      headers: { "User-Agent": UA, "Accept": "application/dns-json" },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          const json = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          resolve((json.Answer || []).filter((a) => a.type === 1).map((a) => a.data));
        } catch { resolve([]); }
      });
    }).on("error", () => resolve([]));
  });
}

function getWithIP(target, ip, headers = {}, redirects = 0) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(target);
    const options = {
      hostname: ip,
      port: 443,
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Host": parsed.hostname,
        ...headers,
      },
      servername: parsed.hostname,
    };
    const req = https.request(options, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        resolve(getWithIP(new URL(res.headers.location, target).href, ip, headers, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        resolve({ code: res.statusCode, body: Buffer.concat(chunks).toString("utf8") });
      });
    });
    req.on("error", reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error("timeout")); });
    req.end();
  });
}

async function probeSource(src) {
  console.log("\n--- " + src.name + " (" + src.host + ") ---");
  const url = "https://" + src.host + src.path + encodeURIComponent(KEYWORD);

  // 先用系统 DNS 直连
  try {
    const res = await get(url, { Referer: "https://" + src.host + "/" });
    console.log("直连: " + res.code + ", 长度 " + res.body.length);
    if (res.code === 200 && res.body.length > 500) {
      console.log("标题: " + (res.body.match(/<title>([^<]*)<\/title>/) || [])[1]);
      const imgs = res.body.match(/src="(https?:\/\/[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g);
      console.log("图片数: " + (imgs ? imgs.length : 0));
      console.log("片段: " + res.body.substring(0, 400).replace(/\n/g, " ").replace(/\s+/g, " "));
      return true;
    }
    console.log("片段: " + res.body.substring(0, 200).replace(/\n/g, " "));
  } catch (e) {
    console.log("直连失败: " + e.message);
  }

  // 尝试 DoH
  const ips = await dohResolve(src.host);
  if (ips.length > 0) {
    console.log("DoH IP: " + ips[0]);
    try {
      const res = await getWithIP(url, ips[0], { Referer: "https://" + src.host + "/" });
      console.log("DoH直连: " + res.code + ", 长度 " + res.body.length);
      if (res.code === 200 && res.body.length > 500) {
        console.log("标题: " + (res.body.match(/<title>([^<]*)<\/title>/) || [])[1]);
        console.log("片段: " + res.body.substring(0, 400).replace(/\n/g, " ").replace(/\s+/g, " "));
        return true;
      }
      console.log("片段: " + res.body.substring(0, 200).replace(/\n/g, " "));
    } catch (e) {
      console.log("DoH直连失败: " + e.message);
    }
  } else {
    console.log("DoH: 无A记录");
  }
  return false;
}

(async () => {
  for (const src of SOURCES) {
    await probeSource(src);
  }
  console.log("\n========== 国内站源探测完成 ==========");
})().catch((e) => { console.error("致命:", e); process.exit(1); });

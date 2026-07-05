const https = require("https");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const KEYWORD = "柯南";
const HOSTS = [
  "api.copymanga.site",
  "v3api.dmzj.com",
  "www.manhuagui.com",
  "mangabz.com",
  "www.cartoonmad.com",
];

// 用腾讯 DoH 解析真实 IP
function dohResolve(host) {
  return new Promise((resolve, reject) => {
    const url = "https://doh.pub/dns-query?name=" + host + "&type=A";
    https.get(url, {
      headers: {
        "User-Agent": UA,
        "Accept": "application/dns-json",
      },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          const json = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          const answers = (json.Answer || []).filter((a) => a.type === 1).map((a) => a.data);
          resolve(answers);
        } catch (e) {
 reject(new Error("DoH parse: " + e.message));
        }
      });
    }).on("error", reject);
  });
}

// 用阿里 DoH 作为备用
function dohResolveAli(host) {
  return new Promise((resolve, reject) => {
    const url = "https://dns.alidns.com/resolve?name=" + host + "&type=A";
    https.get(url, {
      headers: { "User-Agent": UA },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          const json = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          const answers = (json.Answer || []).filter((a) => a.type === 1).map((a) => a.data);
          resolve(answers);
        } catch (e) {
          reject(new Error("DoH parse: " + e.message));
        }
      });
    }).on("error", reject);
  });
}

// 用真实 IP 直连（带 Host 头）
function getWithIP(target, realIP, headers = {}, redirects = 0) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(target);
    const options = {
      hostname: realIP,
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
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 3) {
        res.resume();
        const nextUrl = new URL(res.headers.location, target).href;
        resolve(getWithIP(nextUrl, realIP, headers, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        resolve({ code: res.statusCode, body: Buffer.concat(chunks).toString("utf8") });
      });
    });
    req.on("error", reject);
    req.setTimeout(12000, () => { req.destroy(); reject(new Error("timeout")); });
    req.end();
  });
}

(async () => {
  for (const host of HOSTS) {
    console.log("\n--- " + host + " ---");
    let ips = [];
    try {
      ips = await dohResolve(host);
      console.log("腾讯DoH: " + (ips.length ? ips.join(", ") : "无A记录"));
    } catch (e) {
      console.log("腾讯DoH失败: " + e.message);
    }
    if (ips.length === 0) {
      try {
        ips = await dohResolveAli(host);
        console.log("阿里DoH: " + (ips.length ? ips.join(", ") : "无A记录"));
      } catch (e) {
        console.log("阿里DoH失败: " + e.message);
      }
    }
    if (ips.length === 0) { console.log("无可用IP，跳过"); continue; }

    const ip = ips[0];
    let url;
    if (host === "api.copymanga.site") {
      url = "https://" + host + "/api/v3/search/comic?offset=0&platform=1&q=" + encodeURIComponent(KEYWORD) + "&limit=3";
    } else if (host === "v3api.dmzj.com") {
      url = "https://" + host + "/v3/search/search?key=" + encodeURIComponent(KEYWORD) + "&offset=0&limit=3";
    } else if (host === "www.manhuagui.com") {
      url = "https://" + host + "/s/" + encodeURIComponent(KEYWORD) + ".html";
    } else if (host === "mangabz.com") {
      url = "https://" + host + "/search?title=" + encodeURIComponent(KEYWORD);
    } else {
      url = "https://" + host + "/search.html?keyword=" + encodeURIComponent(KEYWORD);
    }

    try {
      const res = await getWithIP(url, ip, { Referer: "https://" + host + "/" });
      console.log("直连 " + ip + ": " + res.code + ", 长度 " + res.body.length);
      console.log("片段: " + res.body.substring(0, 400).replace(/\n/g, " "));
    } catch (e) {
      console.log("直连失败: " + e.message);
    }
  }
  console.log("\n========== DoH 探测完成 ==========");
})().catch((e) => { console.error("致命:", e); process.exit(1); });

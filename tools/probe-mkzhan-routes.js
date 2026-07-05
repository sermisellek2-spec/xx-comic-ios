const https = require("https");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const HOST = "www.mkzhan.com";

function doh(host) {
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
        } catch {
          resolve([]);
        }
      });
    }).on("error", () => resolve([]));
  });
}

function get(path, ip, snippet) {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: ip,
      port: 443,
      path,
      method: "GET",
      servername: HOST,
      headers: {
        "Host": HOST,
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,*/*",
        "Referer": "https://" + HOST + "/",
      },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        const cards = (body.match(/common-comic-item/g) || []).length;
        const listStart = body.indexOf('cate-comic-list clearfix');
        const pagination = body.indexOf('<div id="Pagination"', listStart);
        const parseBody = listStart >= 0 && pagination > listStart ? body.slice(listStart, pagination) : body;
        const idx = parseBody.indexOf("common-comic-item");
        const parsed = [];
        const re = /<div class="common-comic-item"[^>]*>[\s\S]*?(?=<div class="common-comic-item"|<div id="Pagination"|$)/gi;
        let m;
        while ((m = re.exec(parseBody)) && parsed.length < 3) {
          const block = m[0];
          const dataCid = (block.match(/data-cid="(\d+)"/) || [])[1] || "";
          const href = (block.match(/<a[^>]+class="[^"]*cover[^"]*"[^>]+href="([^"]+)"/) || [])[1] || "";
          const id = dataCid || ((href.match(/\/(\d+)\//) || [])[1] || "");
          const title = (block.match(/<p class="comic__title">[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/) || [])[1] || "";
          parsed.push({ id, title: title.replace(/<[^>]+>/g, "").trim() });
        }
        resolve({
          code: res.statusCode,
          len: body.length,
          cards,
          parsed,
          title: (body.match(/<title>([^<]*)/) || [])[1] || "",
          snippet: snippet && idx >= 0 ? body.slice(Math.max(0, idx - 300), idx + 1400) : "",
        });
      });
    });
    req.on("error", (e) => resolve({ error: e.message }));
    req.setTimeout(12000, () => req.destroy(new Error("timeout")));
    req.end();
  });
}

(async () => {
  const ip = (await doh(HOST))[0];
  console.log("ip", ip);
  for (const path of ["/", "/manga", "/category", "/category/", "/category/?finish=1", "/category/?finish=2", "/category/?is_free=1", "/category/?is_fee=1", "/category/?is_vip=1", "/category/page/2/?finish=1", "/category/?finish=1&page=2", "/comic/", "/search/?keyword=%E7%BE%9E%E8%80%BB%E4%BE%A0"]) {
    const result = await get(path, ip, path === "/category/?finish=1" || path.startsWith("/search/"));
    console.log(path, result);
  }
})();

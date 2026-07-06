const https = require("https");
const zlib = require("zlib");

const target = process.argv[2] || "https://www.manhuagui.com/list";
const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";

function fetch(url) {
  return new Promise((resolve, reject) => {
    https.get(url, {
      headers: {
        "User-Agent": ua,
        "Referer": "https://www.manhuagui.com/",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Accept-Encoding": "gzip",
        "Upgrade-Insecure-Requests": "1"
      }
    }, (res) => {
      const chunks = [];
      res.on("data", chunk => chunks.push(chunk));
      res.on("end", () => {
        const buffer = Buffer.concat(chunks);
        const body = res.headers["content-encoding"] === "gzip" ? zlib.gunzipSync(buffer).toString("utf8") : buffer.toString("utf8");
        resolve({ status: res.statusCode, body });
      });
    }).on("error", reject);
  });
}

function count(regex, text) {
  return [...text.matchAll(regex)].length;
}

(async () => {
  const { status, body } = await fetch(target);
  const oldPattern = /<a[^>]+class=["']bcover["'][^>]*href=["']([^"']+)["'][^>]*title=["']([^"']*)["'][\s\S]*?<img[^>]+src=["']([^"']+)["']/gi;
  const anyBcover = /<a\b[^>]*\bclass=["'][^"']*\bbcover\b[^"']*["'][^>]*>[\s\S]*?<\/a>/gi;
  const bcoverBlocks = [...body.matchAll(anyBcover)].map(m => m[0]);
  console.log("status", status, "length", body.length);
  console.log("contains bcover", body.includes("bcover"));
  console.log("oldPattern", count(oldPattern, body));
  console.log("bcoverBlocks", bcoverBlocks.length);
  console.log("firstBlock", (bcoverBlocks[0] || body.slice(0, 800)).slice(0, 1200));
  if (status !== 200) throw new Error("HTTP " + status);
  if (!bcoverBlocks.length) throw new Error("no bcover blocks found");
})();

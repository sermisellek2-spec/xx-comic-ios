const https = require("https");
const zlib = require("zlib");

const target = process.argv[2] || "https://www.manhuagui.com/comic/67890/111.html";
const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";

function fetch(url, redirects = 0) {
  return new Promise((resolve, reject) => {
    https.get(url, {
      headers: {
        "User-Agent": ua,
        "Referer": "https://www.manhuagui.com/",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Accept-Encoding": "gzip",
        "Upgrade-Insecure-Requests": "1",
      }
    }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        const next = new URL(res.headers.location.replace(/^http:\/\/www\.manhuagui\.com/, "https://www.manhuagui.com"), url).href;
        resolve(fetch(next, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", chunk => chunks.push(chunk));
      res.on("end", () => {
        const buffer = Buffer.concat(chunks);
        const body = res.headers["content-encoding"] === "gzip" ? zlib.gunzipSync(buffer).toString("utf8") : buffer.toString("utf8");
        resolve({ status: res.statusCode, url, body });
      });
    }).on("error", reject);
  });
}

function unescapeJs(s) {
  return (s || "").replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/\\\\/g, "\\").replace(/\\\//g, "/");
}

function base62(c, a) {
  if (c < a) return c > 35 ? String.fromCharCode(c + 29) : c.toString(36);
  return base62(Math.floor(c / a), a) + base62(c % a, a);
}

function unpack(html) {
  const re = /\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\s*(?:\.\s*split|\[[^\]]*\])\s*\(\s*'([^']*)'\s*\)/;
  const m = html.match(re);
  if (!m) return "";
  let result = unescapeJs(m[1]);
  const radix = Number(m[2]);
  const count = Number(m[3]);
  const dict = unescapeJs(m[4]).split(unescapeJs(m[5]));
  for (let i = count - 1; i >= 0; i--) {
    if (dict[i]) {
      const token = base62(i, radix).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      result = result.replace(new RegExp(`\\b${token}\\b`, "g"), dict[i]);
    }
  }
  return result;
}

function imgDataFromScript(script) {
  const marker = script.indexOf("SMH.imgData");
  const start = marker >= 0 ? script.indexOf("{", marker) : script.indexOf("{");
  const callEnd = script.indexOf(").preInit", start);
  const end = callEnd >= 0 ? script.lastIndexOf("}", callEnd) : script.lastIndexOf("}");
  return start >= 0 && end > start ? script.slice(start, end + 1) : "";
}

(async () => {
  const { status, url, body } = await fetch(target);
  console.log("status", status, "url", url, "length", body.length);
  console.log("has SMH", body.includes("SMH.imgData"), "has eval", body.includes("eval(function"));
  const script = unpack(body);
  console.log("unpacked length", script.length);
  console.log("unpacked snippet", script.slice(0, 800));
  const config = imgDataFromScript(script || body);
  console.log("config length", config.length);
  console.log("config snippet", config.slice(0, 1200));
  if (config) {
    const parsed = JSON.parse(config);
    console.log("keys", Object.keys(parsed));
    console.log("files", parsed.files && parsed.files.length, "path", parsed.path, "sl", parsed.sl);
  }
})();

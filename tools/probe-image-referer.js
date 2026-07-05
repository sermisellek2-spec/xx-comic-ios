// Test whether Aikan/Mhua5 image CDNs enforce Referer hotlink protection.
// Tries each image with: no Referer, source's own Referer, and Baozi Referer (the current default).
const https = require("https");
const http = require("http");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

function head(target, headers = {}, redirects = 0) {
  return new Promise((resolve) => {
    const parsed = new URL(target);
    const isHttps = parsed.protocol === "https:";
    const lib = isHttps ? https : http;
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: "GET", // some CDNs ignore HEAD; use GET but only read headers
      headers: { "User-Agent": UA, "Range": "bytes=0-0", ...headers },
    };
    const req = lib.request(options, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        resolve(head(new URL(res.headers.location, target).href, headers, redirects + 1));
        return;
      }
      const len = res.headers["content-length"] || "?";
      const type = res.headers["content-type"] || "?";
      res.resume();
      resolve({ code: res.statusCode, len, type, final: res.req && res.req.path });
    });
    req.on("error", (e) => resolve({ code: "ERR", err: e.message }));
    req.setTimeout(12000, () => { req.destroy(); resolve({ code: "TIMEOUT" }); });
    req.end();
  });
}

async function tryAll(label, url, referers) {
  console.log(`\n=== ${label} ===`);
  console.log(`url: ${url}`);
  for (const [name, ref] of referers) {
    const headers = ref == null ? {} : { Referer: ref };
    const r = await head(url, headers);
    console.log(`  [${name.padEnd(14)}] code=${r.code} type=${r.type} len=${r.len}${r.err ? " err=" + r.err : ""}`);
  }
}

(async () => {
  const aikanImage = "http://f2-img.534zm.com/colatj/mingzhentankenan/2/d8dd1b1cbdfab0f00c7bc4fa72d5329d.webp";
  const mhua5Image = "https://s1.baozimh.com/scomic/mingzhentankenanlingderichang-xinjinglongyan/0/1-609u/1.jpg";

  const aikanReferers = [
    ["no-referer", null],
    ["aikan", "https://www.0592cr.com/"],
    ["baozi(default)", "https://cn.bzmgcn.com/"],
  ];
  const mhua5Referers = [
    ["no-referer", null],
    ["mhua5", "https://www.mhua5.com/"],
    ["baozi(default)", "https://cn.bzmgcn.com/"],
  ];

  await tryAll("Aikan image (f2-img.534zm.com)", aikanImage, aikanReferers);
  await tryAll("Mhua5 image (s1.baozimh.com)", mhua5Image, mhua5Referers);
})();

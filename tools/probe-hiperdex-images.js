const https = require("https");

const url = process.argv[2] || "https://hiperdex.com/manga/drama-queens-official/chapter-215/";
const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

function fetch(target) {
  return new Promise((resolve, reject) => {
    https.get(target, { headers: { "User-Agent": ua, "Referer": "https://hiperdex.com/" } }, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", chunk => body += chunk);
      res.on("end", () => resolve({ status: res.statusCode, body }));
    }).on("error", reject);
  });
}

function fetchBuffer(target, referer) {
  return new Promise((resolve, reject) => {
    https.get(target, { headers: { "User-Agent": ua, "Referer": referer } }, (res) => {
      const chunks = [];
      res.on("data", chunk => chunks.push(chunk));
      res.on("end", () => resolve({
        status: res.statusCode,
        type: res.headers["content-type"] || "",
        length: chunks.reduce((sum, chunk) => sum + chunk.length, 0),
        head: Buffer.concat(chunks).subarray(0, 12).toString("hex")
      }));
    }).on("error", reject);
  });
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function attr(tag, name) {
  const match = tag.match(new RegExp(`\\b${name}="([^"]*)"`, "i"));
  return match ? match[1] : "";
}

function imageFromTag(tag) {
  return (attr(tag, "data-src") || attr(tag, "data-lazy-src") || attr(tag, "src")).trim();
}

(async () => {
  const { status, body } = await fetch(url);
  console.log("status", status, "length", body.length);
  const readingMatch = body.match(/<div[^>]+class="[^"]*reading-content[^"]*"[\s\S]*?<div[^>]+class="[^"]*comments-area/s);
  const block = readingMatch ? readingMatch[0] : body;
  const javaMatch = body.match(/<div[^>]+class="[^"]*reading-content[^"]*"[\s\S]*?<\/div>\s*<\/div>/i);
  const javaBlock = javaMatch ? javaMatch[0] : body;
  const fixedMatch = body.match(/<div[^>]+class="[^"]*reading-content[^"]*"[\s\S]*?(?=<div[^>]+class="[^"]*comments-area|<\/body>|$)/i);
  const fixedBlock = fixedMatch ? fixedMatch[0] : body;
  const currentRegex = /<img[^>]+(?:data-src|data-lazy-src|src)="([^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"/gi;
  const attrsRegex = /<img\b[^>]*>/gi;
  const attrRegex = /\b(?:data-src|data-lazy-src|src)="([^"]+)"/gi;
  const current = unique([...block.matchAll(currentRegex)].map(m => m[1]));
  const javaCurrent = unique([...javaBlock.matchAll(currentRegex)].map(m => m[1]));
  const fixedCurrent = unique([...fixedBlock.matchAll(attrsRegex)].map(m => imageFromTag(m[0]))).filter(v => /\.(jpe?g|png|webp)(?:[?#].*)?$/i.test(v));
  const attrs = [];
  for (const tag of block.matchAll(attrsRegex)) {
    for (const attr of tag[0].matchAll(attrRegex)) attrs.push(attr[1]);
  }
  const allAttrs = unique(attrs).filter(v => /\.(jpe?g|png|webp)(?:[?#].*)?$/i.test(v));
  console.log("currentRegex", current.length, current.slice(0, 3));
  console.log("javaBlockRegex", javaCurrent.length, javaCurrent.slice(0, 3));
  console.log("fixedParser", fixedCurrent.length, fixedCurrent.slice(0, 3));
  console.log("attrRegex", allAttrs.length, allAttrs.slice(0, 3));
  const firstImg = block.match(/<img\b[^>]*>/i);
  console.log("firstImg", firstImg ? firstImg[0].slice(0, 500) : "none");
  if (allAttrs[0]) {
    const image = allAttrs[0].trim();
    console.log("imageWithHiperdexReferer", await fetchBuffer(image, "https://hiperdex.com/"));
    console.log("imageWithBaoziReferer", await fetchBuffer(image, "https://cn.bzmgcn.com/"));
  }
  if (fixedCurrent.length === 0) throw new Error("fixed parser found no reader images");
})();

// Probe + simulate chapter-image extraction for Aikan and Mhua5 against real HTML.
// Mirrors the logic in AikanComicSource.chapter() and Mhua5ComicSource.chapter().
const https = require("https");
const http = require("http");
const fs = require("fs");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

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

function save(name, body) {
  fs.writeFileSync("F:/softForCode/codex-project/xx-comic/tools/" + name, body, "utf8");
}

function count(html, label, re) {
  const matches = [];
  let m;
  const r = new RegExp(re, "gi");
  while ((m = r.exec(html)) !== null) matches.push(m[1] || m[0]);
  console.log(`  ${label}: ${matches.length}`);
  matches.slice(0, 3).forEach((s, i) => console.log(`    [${i}] ${String(s).substring(0, 160)}`));
  return matches;
}

// ---- Aikan chapter-image simulation (mirrors AikanComicSource.chapter) ----
function simAikanImages(html) {
  console.log("\n=== Aikan chapter image sim ===");
  console.log("html length:", html.length);

  // title
  const titleM = /<title>([\s\S]*?)<\/title>/i.exec(html);
  console.log("title:", titleM ? titleM[1].replace(/\s+/g, " ").trim() : "(none)");

  // direct data-original
  const direct = count(html, "data-original matches", 'data-original="(https?://[^"]+)"');
  // json "img":"..."
  const jsonImg = count(html, '"img":"..." matches', '"img"\\s*:\\s*"(https?://[^"]+)"');

  // isReaderImage filter: /colafm/ /colatj/ /scomic/
  const all = [...direct, ...jsonImg];
  const kept = all.filter((u) => /\/colafm\/|\/colatj\/|\/scomic\//.test(u));
  console.log(`  after isReaderImage filter: ${kept.length}`);
  kept.slice(0, 3).forEach((s, i) => console.log(`    [${i}] ${s}`));

  // next chapter
  const nextM = /next_chapter'\)\.html\('<a href="([^"]+)"/i.exec(html);
  console.log("next:", nextM ? nextM[1] : "(none)");

  // script-encrypted fallback marker
  const scriptEnc = /data-original="\s*"\s*\+\s*picx\[i\]\.img\s*\+\s*"/i.test(html);
  console.log("script-encrypted marker (SCRIPT_IMAGE_PATTERN):", scriptEnc);

  // diagnostic: what does data-original actually look like in this page?
  const sampleDo = /data-original="[^"]{0,80}"/i.exec(html);
  console.log("sample data-original attr:", sampleDo ? sampleDo[0] : "(none found)");
  // diagnostic: any picx/img JS var?
  const picxM = /picx\[[^\]]*\]\.img\s*=\s*"([^"]{0,80})"/i.exec(html)
    || /var\s+picx[\s\S]{0,200}?\.img\s*=\s*"([^"]{0,80})"/i.exec(html)
    || /picx[\s\S]{0,80}/i.exec(html);
  console.log("picx hint:", picxM ? picxM[0].substring(0, 120).replace(/\s+/g, " ") : "(none)");
}

// ---- Mhua5 chapter-image simulation (mirrors Mhua5ComicSource.chapter) ----
function simMhua5Images(html) {
  console.log("\n=== Mhua5 chapter image sim ===");
  console.log("html length:", html.length);

  // title
  const titleM1 = /<h1 class="comic-title">[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i.exec(html);
  const titleM2 = /<h1 class="comic-name">([\s\S]*?)<\/h1>/i.exec(html);
  console.log("title:", (titleM1 && titleM1[1] || titleM2 && titleM2[1] || "(none)").replace(/\s+/g, " ").trim());

  // IMAGE_PATTERN: <img class="lazy-read"...data-original="..."
  const lazy = count(html, "lazy-read matches", '<img class="lazy-read"[^>]+data-original="(https?://[^"]+)"');

  // isReaderImage filter: /scomic/
  const kept = lazy.filter((u) => /\/scomic\//.test(u));
  console.log(`  after isReaderImage filter: ${kept.length}`);
  kept.slice(0, 3).forEach((s, i) => console.log(`    [${i}] ${s}`));

  // fallback: READER_IMAGE_PATTERN inside <ul class="comic-list">...</ul>
  let imageBlock = "";
  const blockM = /<ul class="comic-list"[\s\S]*?<\/ul>/i.exec(html);
  if (blockM) imageBlock = blockM[0];
  console.log("comic-list block:", imageBlock ? `${imageBlock.length} bytes` : "(none)");
  if (imageBlock) {
    const fb = count(imageBlock, "fallback <img data-original|data-src|src>", '<img[^>]+(?:data-original|data-src|src)="([^"]+)"[^>]*>');
  }

  // next
  const nextM = /<a class="rd-aside__item j-rd-next" _href="([^"]+)"/i.exec(html)
    || /<[^>]+class="[^"]*next[^"]*"[^>]+_href="([^"]*)"/i.exec(html);
  console.log("next:", nextM ? nextM[1] : "(none)");

  // diagnostic: what <img> classes appear?
  const imgClasses = new Set();
  const imgRe = /<img[^>]*class="([^"]+)"/gi;
  let m;
  while ((m = imgRe.exec(html)) !== null) imgClasses.add(m[1]);
  console.log("img classes on page:", [...imgClasses].slice(0, 12).join(" | ") || "(none)");
}

(async () => {
  // Aikan: chapter 001 of 柯南
  const aikanChapter = "https://www.0592cr.com/chook/116040";
  console.log("\n--- fetching aikan chapter:", aikanChapter);
  try {
    const r = await get(aikanChapter, { Referer: "https://www.0592cr.com/" });
    console.log("status:", r.code, "bytes:", r.body.length);
    save("probe-aikan-chapter.html", r.body);
    simAikanImages(r.body);
  } catch (e) { console.error("aikan chapter error:", e.message); }

  // Mhua5: 第02回 of 柯南
  const mhua5Chapter = "https://www.mhua5.com/index.php/chapter/818328";
  console.log("\n--- fetching mhua5 chapter:", mhua5Chapter);
  try {
    const r = await get(mhua5Chapter, { Referer: "https://www.mhua5.com/" });
    console.log("status:", r.code, "bytes:", r.body.length);
    save("probe-mhua5-chapter.html", r.body);
    simMhua5Images(r.body);
  } catch (e) { console.error("mhua5 chapter error:", e.message); }
})();

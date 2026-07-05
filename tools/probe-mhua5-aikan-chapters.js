const https = require("https");
const http = require("http");

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
  require("fs").writeFileSync("F:/softForCode/codex-project/xx-comic/tools/" + name, body, "utf8");
  console.log("saved " + name + " (" + body.length + " bytes)");
}

(async () => {
  // Mhua5: search for a known comic
  console.log("\n=== mhua5 search ===");
  try {
    const r = await get("https://www.mhua5.com/index.php/search?key=" + encodeURIComponent("柯南"));
    save("probe-mhua5-search.html", r.body);
    const matches = r.body.match(/href="\/index\.php\/comic\/[^"]+"/g) || [];
    console.log("comic links:", matches.slice(0, 5));
    // get first comic detail
    if (matches.length > 0) {
      const href = matches[0].match(/href="([^"]+)"/)[1];
      const url = "https://www.mhua5.com" + href;
      console.log("fetching detail:", url);
      const d = await get(url);
      save("probe-mhua5-detail.html", d.body);
      // count chapter patterns
      const desktopChapters = d.body.match(/<li class="j-chapter-item[\s\S]*?<\/li>/g) || [];
      const mobileChapters = d.body.match(/<li class="chapter-item[^"]*"[\s\S]*?<\/li>/g) || [];
      console.log("desktop chapter count:", desktopChapters.length);
      console.log("mobile chapter count:", mobileChapters.length);
      if (desktopChapters.length > 0) {
        console.log("first 3 desktop:");
        desktopChapters.slice(0, 3).forEach((c, i) => console.log("  [" + i + "]", c.substring(0, 200).replace(/\s+/g, " ")));
        console.log("last 3 desktop:");
        desktopChapters.slice(-3).forEach((c, i) => console.log("  [-" + (3-i) + "]", c.substring(0, 200).replace(/\s+/g, " ")));
      }
      if (mobileChapters.length > 0) {
        console.log("first 3 mobile:");
        mobileChapters.slice(0, 3).forEach((c, i) => console.log("  [" + i + "]", c.substring(0, 200).replace(/\s+/g, " ")));
        console.log("last 3 mobile:");
        mobileChapters.slice(-3).forEach((c, i) => console.log("  [-" + (3-i) + "]", c.substring(0, 200).replace(/\s+/g, " ")));
      }
    }
  } catch (e) { console.error("mhua5 error:", e.message); }

  // Aikan: search for a known comic
  console.log("\n=== aikan search ===");
  try {
    const r = await get("https://www.0592cr.com/index.php/search?key=" + encodeURIComponent("柯南"));
    save("probe-aikan-search.html", r.body);
    const matches = r.body.match(/href="[^"]*\/youbooks\/\d+\.html"/g) || [];
    console.log("comic links:", matches.slice(0, 5));
    if (matches.length > 0) {
      const href = matches[0].match(/href="([^"]+)"/)[1];
      const url = "https://www.0592cr.com" + (href.startsWith("/") ? href : "/" + href);
      console.log("fetching detail:", url);
      const d = await get(url);
      save("probe-aikan-detail.html", d.body);
      // count chapter patterns
      const chapters = d.body.match(/<a [^>]*href="[^"]*\/chook\/\d+"[^>]*class="comics-chapters__item[^"]*"[^>]*>[\s\S]*?<\/a>/g) || [];
      console.log("chapter count:", chapters.length);
      if (chapters.length > 0) {
        console.log("first 3:");
        chapters.slice(0, 3).forEach((c, i) => console.log("  [" + i + "]", c.substring(0, 250).replace(/\s+/g, " ")));
        console.log("last 3:");
        chapters.slice(-3).forEach((c, i) => console.log("  [-" + (3-i) + "]", c.substring(0, 250).replace(/\s+/g, " ")));
      }
      // search for "章节目录" section
      const idx = d.body.indexOf("章节目录");
      console.log("章节目录 index:", idx);
      if (idx > 0) {
        console.log("section after 章节目录 (1000 chars):");
        console.log(d.body.substring(idx, idx + 1000).replace(/\s+/g, " "));
      }
    }
  } catch (e) { console.error("aikan error:", e.message); }
})();

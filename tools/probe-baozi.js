const https = require("https");

const headers = {
  "User-Agent": "Mozilla/5.0 (Android) XXComic/1.0",
  Referer: "https://cn.bzmgcn.com/",
  "Accept-Language": "zh-CN,zh;q=0.9",
};

function get(target, redirects = 0) {
  return new Promise((resolve, reject) => {
    https
      .get(target, { headers }, (res) => {
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
          res.resume();
          resolve(get(new URL(res.headers.location, target).href, redirects + 1));
          return;
        }
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          resolve({
            code: res.statusCode,
            body: Buffer.concat(chunks).toString("utf8"),
          });
        });
      })
      .on("error", reject);
  });
}

function absolutize(path) {
  if (!path) return "";
  const clean = path.replace(/&amp;/g, "&");
  if (clean.startsWith("https://")) return clean;
  return "https://cn.bzmgcn.com" + (clean.startsWith("/") ? "" : "/") + clean;
}

(async () => {
  const search = await get("https://cn.bzmgcn.com/search?q=%E6%9F%AF%E5%8D%97");
  console.log("search", search.code, search.body.length, "cards", (search.body.match(/comics-card/g) || []).length);
  const first = search.body.match(/href="([^"]*\/comic\/[^"]+)"[^>]*title="([^"]+)/);
  console.log("first", first && first[1], first && first[2]);
  if (!first) return;

  const comicUrl = absolutize(first[1]);
  const detail = await get(comicUrl);
  console.log("detail", detail.code, detail.body.length, "chapters", (detail.body.match(/page_direct/g) || []).length);
  console.log("title meta", (detail.body.match(/og:novel:book_name"[^>]+content="([^"]*)"/) || [])[1]);
  const chapter = detail.body.match(/href="([^"]*page_direct[^"]*)"/);
  console.log("chapter", chapter && chapter[1]);
  if (!chapter) return;

  const page = await get(absolutize(chapter[1]));
  console.log("page", page.code, page.body.length, "amp", (page.body.match(/amp-img/g) || []).length, "scomic", (page.body.match(/scomic/g) || []).length);
  const img = page.body.match(/<amp-img[^>]+(?:data-src|src)="([^"]+)"/);
  console.log("image", img && img[1]);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});

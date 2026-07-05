const https = require("https");

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const HOST = "www.mkzhan.com";
const BASE = "https://" + HOST;

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

function get(url, ip, referer, redirects = 0) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = https.request({
      hostname: ip || parsed.hostname,
      port: parsed.port || 443,
      path: parsed.pathname + parsed.search,
      method: "GET",
      servername: parsed.hostname,
      headers: {
        "Host": parsed.hostname,
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Referer": referer || (BASE + "/"),
      },
    }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 5) {
        res.resume();
        resolve(get(new URL(res.headers.location, url).href, ip, referer, redirects + 1));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    req.setTimeout(15000, () => {
      req.destroy(new Error("timeout"));
    });
    req.end();
  });
}

async function getByDoh(url, referer) {
  const parsed = new URL(url);
  const ips = await doh(parsed.hostname);
  if (!ips[0]) throw new Error("no ip for " + parsed.hostname);
  return get(url, ips[0], referer);
}

function attr(tag, name) {
  const m = new RegExp(name + '="([^"]*)"', "i").exec(tag || "");
  return m ? m[1].replace(/&amp;/g, "&") : "";
}

function clean(html) {
  return (html || "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function first(re, html) {
  const m = re.exec(html);
  return m ? m[1] : "";
}

function firstMatch(re, html) {
  const m = re.exec(html);
  return m ? m[0] : "";
}

(async () => {
  const ips = await doh(HOST);
  const ip = ips[0];
  console.log("ip =", ip || "N/A");
  if (!ip) return;

  const searchUrl = BASE + "/search/?keyword=" + encodeURIComponent("羞耻侠");
  const search = await get(searchUrl, ip);
  console.log("search", search.status, search.body.length);

  const card = /<div class="common-comic-item"[^>]*data-cid="(\d+)"[\s\S]*?(?=<div class="common-comic-item"|$)/i.exec(search.body);
  if (!card) {
    console.log("no card");
    return;
  }
  const cardHtml = card[0];
  const cid = card[1];
  const coverTag = firstMatch(/<img[^>]+>/i, cardHtml);
  const title = clean(first(/<p class="comic__title">([\s\S]*?)<\/p>/i, cardHtml)) || attr(coverTag, "alt");
  const detailUrl = BASE + "/" + cid + "/";
  console.log("card", { cid, title, cover: attr(coverTag, "data-src") || attr(coverTag, "src"), detailUrl });

  const detail = await get(detailUrl, ip, searchUrl);
  console.log("detail", detail.status, detail.body.length, clean(first(/<title>([\s\S]*?)<\/title>/i, detail.body)));
  const chapterLinks = [];
  const chapterRe = /<a[^>]+(?:href|data-hreflink)="(\/\d+\/\d+(?:\.html|\/)?)"[^>]*>([\s\S]*?)<\/a>/g;
  let m;
  while ((m = chapterRe.exec(detail.body))) chapterLinks.push({ href: m[1], title: clean(m[2]) });
  console.log("chapters", chapterLinks.length, chapterLinks.slice(0, 5));
  if (!chapterLinks.length) {
    const idx = detail.body.indexOf("chapter");
    console.log(detail.body.slice(Math.max(0, idx - 500), idx + 1200));
    return;
  }

  const chapterUrl = BASE + chapterLinks[0].href;
  const chapter = await get(chapterUrl, ip, detailUrl);
  console.log("chapter", chapter.status, chapter.body.length, clean(first(/<title>([\s\S]*?)<\/title>/i, chapter.body)));
  const imgs = [];
  const imgRe = /<img[^>]+(?:data-src|data-original|src)="([^"]+)"[^>]*>/g;
  while ((m = imgRe.exec(chapter.body))) imgs.push(m[1].replace(/&amp;/g, "&"));
  console.log("imgs", imgs.length, imgs.slice(0, 10));
  const jsHints = chapter.body.match(/(?:chapter|image|page|mkz)[^<]{0,120}/gi) || [];
  console.log("js hints", jsHints.slice(0, 20));
  const scriptSrcs = [];
  const scriptRe = /<script[^>]+src="([^"]+)"/g;
  while ((m = scriptRe.exec(chapter.body))) scriptSrcs.push(new URL(m[1], chapterUrl).href);
  console.log("scripts", scriptSrcs);
  const vars = chapter.body.match(/(?:comic|chapter|cid|mid|page|data)[A-Za-z0-9_$.\s='":,{}[\]-]{0,160}/gi) || [];
  console.log("vars", vars.slice(0, 40));
  const readIdx = chapter.body.search(/readData|chapterData|comicData|pageData|vm\.|axios|ajax|api/i);
  console.log("near api", readIdx, chapter.body.slice(Math.max(0, readIdx - 800), readIdx + 1600));
  const contentJs = scriptSrcs.find((src) => src.includes("/modules/read/content.js"));
  if (contentJs) {
    const js = await getByDoh(contentJs, chapterUrl);
    console.log("content.js", js.status, js.body.length);
    const apiHints = js.body.match(/(?:api|chapter|image|comic|pic|page|ajax|request)[^'"\n]{0,180}/gi) || [];
    console.log("content api hints", apiHints.slice(0, 60));
    console.log(js.body.slice(0, 12000));
  }
  const httpApiJs = scriptSrcs.find((src) => src.includes("/modules/httpApi/httpApi.js"));
  if (httpApiJs) {
    const js = await getByDoh(httpApiJs, chapterUrl);
    console.log("httpApi.js", js.status, js.body.length);
    const idx = js.body.indexOf("chapterContentV1");
    console.log("chapterContentV1 idx", idx);
    console.log(js.body.slice(Math.max(0, idx - 1800), idx + 1800));
  }
  const comicApiJs = "https://static.mkzcdn.com/home/assets/script/modules/httpApi/apis/comic.js";
  const apiJs = await getByDoh(comicApiJs, chapterUrl);
  console.log("apis/comic.js", apiJs.status, apiJs.body.length);
  const domainHint = apiJs.body.match(/comicDomain\s*=\s*"([^"]+)"/) || apiJs.body.match(/comicDomain\s*=\s*'([^']+)'/);
  console.log("comicDomain", domainHint ? domainHint[1] : "N/A");
  const apiIdx = apiJs.body.indexOf("chapterContentV1");
  console.log("api chapterContentV1 idx", apiIdx);
  console.log(apiJs.body.slice(Math.max(0, apiIdx - 2200), apiIdx + 2200));
  if (domainHint) {
    const apiUrl = domainHint[1] + "chapter/content/v1/?chapter_id=1067286&comic_id=217053&quality=1&type=1&format=0&uid=&sign=";
    const apiRes = await getByDoh(apiUrl, chapterUrl);
    console.log("chapter api", apiRes.status, apiRes.body.length, apiRes.body.slice(0, 1000));
  }
})();

const https = require("https");
const UA = "Mozilla/5.0";

function doh(h) {
  return new Promise((resolve) => {
    https.get("https://doh.pub/dns-query?name=" + h + "&type=A", {
      headers: { "User-Agent": UA, "Accept": "application/dns-json" },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          const json = JSON.parse(Buffer.concat(chunks).toString());
          resolve((json.Answer || []).filter((a) => a.type === 1).map((a) => a.data));
        } catch { resolve([]); }
      });
    }).on("error", () => resolve([]));
  });
}

function getIP(url, ip) {
  return new Promise((res, rej) => {
    const p = new URL(url);
    const q = https.request({
      hostname: ip, port: 443, path: p.pathname + p.search, method: "GET",
      headers: { "User-Agent": UA, "Host": p.hostname, "Accept": "*/*", "Referer": "https://mangabz.com/m500676/" },
      servername: p.hostname,
    }, (r) => {
      const chunks = [];
      r.on("data", (c) => chunks.push(c));
      r.on("end", () => res({ code: r.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    q.on("error", rej);
    q.setTimeout(10000, () => { q.destroy(); rej(new Error("timeout")); });
    q.end();
  });
}

(async () => {
  const ips = await doh("mangabz.com");
  for (const pg of [1, 2, 3]) {
    const r = await getIP("https://mangabz.com/m500676-p" + pg + "/", ips[0]);
    console.log("p" + pg + ": " + r.code + ", " + r.body.length);
    // 找所有 img src
    var imgs = r.body.match(/src="([^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g);
    if (imgs) console.log("  imgs: " + imgs.join("  "));
    // 找 showimage 区域
    var idx = r.body.indexOf("showimage");
    if (idx > 0) console.log("  showimage: " + r.body.substring(idx, idx + 300));
    // 扦 cp_img 区域
    idx = r.body.indexOf("cp_img");
    if (idx > 0) console.log("  cp_img: " + r.body.substring(idx, idx + 300));
    // 找所有非 css/images 的图片
    var real = r.body.match(/src="(https?:\/\/(?!css\.mangabz)[^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/g);
    if (real) console.log("  real imgs: " + real.join("  "));
  }
})().catch((e) => console.log(e));

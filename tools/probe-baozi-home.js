const https = require("https");

const headers = {
  "User-Agent": "Mozilla/5.0 (Android) XXComic/1.0",
  Referer: "https://cn.bzmgcn.com/",
  "Accept-Language": "zh-CN,zh;q=0.9",
};

https
  .get("https://cn.bzmgcn.com/", { headers }, (res) => {
    const chunks = [];
    res.on("data", (chunk) => chunks.push(chunk));
    res.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf8");
      console.log("home", res.statusCode, body.length, "cards", (body.match(/comics-card/g) || []).length);
      const first = body.match(/href="([^"]*\/comic\/[^"]+)"[^>]*title="([^"]+)/);
      console.log("first", first && first[1], first && first[2]);
      const links = body.match(/href="([^"]*(?:category|filter|latest|type|update|rank|list)[^"]*)"/g) || [];
      console.log(links.slice(0, 30).join("\n"));
    });
  })
  .on("error", (error) => {
    console.error(error);
    process.exit(1);
  });

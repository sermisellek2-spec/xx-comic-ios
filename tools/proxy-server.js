const http = require("http");
const https = require("https");
const url = require("url");

const PORT = 4174;
const TARGET = "https://cn.bzmgcn.com";
const UA = "Mozilla/5.0 (Android) XXComic/1.0";

function proxyRequest(targetUrl, res) {
  const parsed = new url.URL(targetUrl);
  const options = {
    hostname: parsed.hostname,
    port: parsed.port || 443,
    path: parsed.pathname + parsed.search,
    method: "GET",
    headers: {
      "User-Agent": UA,
      "Referer": TARGET + "/",
      "Accept": "text/html,application/xhtml+xml,*/*",
      "Accept-Language": "zh-CN,zh;q=0.9",
    },
  };

  const proxy = https.request(options, (proxyRes) => {
    let body = [];
    proxyRes.on("data", (chunk) => body.push(chunk));
    proxyRes.on("end", () => {
      const buffer = Buffer.concat(body);
      res.writeHead(proxyRes.statusCode, {
        "Content-Type": proxyRes.headers["content-type"] || "text/html; charset=utf-8",
        "Access-Control-Allow-Origin": "*",
      });
      res.end(buffer);
    });
  });

  proxy.on("error", (err) => {
    console.error("Proxy error:", err.message);
    res.writeHead(502, { "Access-Control-Allow-Origin": "*" });
    res.end(JSON.stringify({ error: "proxy_error", detail: err.message }));
  });

  proxy.setTimeout(30000, () => {
    proxy.destroy();
    res.writeHead(504, { "Access-Control-Allow-Origin": "*" });
    res.end(JSON.stringify({ error: "timeout" }));
  });

  proxy.end();
}

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    return res.end();
  }

  // Image proxy
  if (pathname === "/api/image") {
    if (!parsed.query.url) {
      res.writeHead(400, { "Access-Control-Allow-Origin": "*" });
      return res.end(JSON.stringify({ error: "missing url param" }));
    }
    return proxyRequest(parsed.query.url, res);
  }

  // Search proxy
  if (pathname === "/api/search") {
    const q = parsed.query.q || "";
    return proxyRequest(TARGET + "/search?q=" + encodeURIComponent(q), res);
  }

  // Detail proxy
  if (pathname.startsWith("/api/comic/")) {
    const comicId = pathname.replace("/api/comic/", "");
    return proxyRequest(TARGET + "/comic/" + comicId, res);
  }

  // Chapter proxy (pass full URL)
  if (pathname === "/api/chapter") {
    if (!parsed.query.url) {
      res.writeHead(400, { "Access-Control-Allow-Origin": "*" });
      return res.end(JSON.stringify({ error: "missing url param" }));
    }
    return proxyRequest(parsed.query.url, res);
  }

  // Health check
  if (pathname === "/api/health") {
    const opts = {
      hostname: "cn.bzmgcn.com",
      port: 443,
      path: "/",
      method: "HEAD",
      timeout: 5000,
    };
    const hc = https.request(opts, (hcRes) => {
      res.writeHead(200, { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: hcRes.statusCode >= 200 && hcRes.statusCode < 400 }));
    });
    hc.on("error", () => {
      res.writeHead(200, { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: false }));
    });
    hc.end();
    return;
  }

  res.writeHead(404, { "Access-Control-Allow-Origin": "*" });
  res.end("not found");
});

server.listen(PORT, () => {
  console.log("XX Comic proxy server running at http://localhost:" + PORT);
  console.log("Open index.html and fetch real data from https://cn.bzmgcn.com");
});

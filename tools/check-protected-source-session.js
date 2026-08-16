const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/CloudflareWebViewSession.java",
  "utf8",
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("loads the requested URL directly", source.includes("webView.loadUrl(request.url)"));
check("captures the current DOM", source.includes("document.documentElement.outerHTML"));
check("challenge inspection includes DOM markers", source.includes("html:(document.documentElement.outerHTML||'').slice(0,12000)")
  && source.includes('page.optString("html")'));
check("does not issue a second fetch", !source.includes("fetch(url"));

console.log("Protected source session contract holds.");

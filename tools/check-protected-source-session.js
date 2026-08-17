const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/CloudflareWebViewSession.java",
  "utf8",
);
const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);
const navigationCapture = source.slice(
  source.indexOf("private void captureCurrentPage"),
  source.indexOf("private String browserContextScript"),
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("loads the requested URL directly", source.includes("webView.loadUrl(request.url)"));
check("captures the current DOM", source.includes("document.documentElement.outerHTML"));
check("challenge inspection includes DOM markers", source.includes("html:(document.documentElement.outerHTML||'').slice(0,12000)")
  && source.includes('page.optString("html")'));
check("navigation capture does not issue a second fetch",
  !navigationCapture.includes("fetch(")
  && source.includes("fetchWithBrowserContext(url)"));
check("one persistent browser session exists per protected source",
  (main.match(/new CloudflareWebViewSession\(/g) || []).length === 2
  && main.includes("CloudflareWebViewSession mh18BrowserSession")
  && main.includes("CloudflareWebViewSession jmcomicBrowserSession")
  && source.includes("CookieManager.getInstance()") && source.includes("flush()"));
check("session page cache can be cleared", source.includes("void clearCache()")
  && source.includes("webView.clearCache(true)")
  && source.includes("webView.clearHistory()"));
check("app cache clear removes protected credentials", main.includes("removeAllCookies")
  && main.includes("WebStorage.getInstance().deleteAllData()")
  && main.includes("mh18BrowserSession.clearCache()")
  && main.includes("jmcomicBrowserSession.clearCache()"));

console.log("Protected source session contract holds.");

const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/CloudflareWebViewSession.java",
  "utf8",
);
const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);
const mh18Session = main.slice(
  main.indexOf("mh18BrowserSession = new CloudflareWebViewSession("),
  main.indexOf("jmcomicBrowserSession = new CloudflareWebViewSession("),
);
const jmcomicSession = main.slice(
  main.indexOf("jmcomicBrowserSession = new CloudflareWebViewSession("),
  main.indexOf("rebuildSourceClients();"),
);
const navigationCapture = source.slice(
  source.indexOf("private void captureCurrentPage"),
  source.indexOf("private String browserContextScript"),
);
const completingView = source.slice(
  source.indexOf("private void showCompletingBehindApp"),
  source.indexOf("private FrameLayout.LayoutParams verificationLayoutParams"),
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
  && source.includes("fetchWithBrowserContext(url, deadline)"));
check("only 18mh uses the full viewport hybrid session",
  mh18Session.includes("mh18Config.name, true, true, true, this::showRemToast")
  && jmcomicSession.includes("jmcomicConfig.name, true, this::showRemToast")
  && !jmcomicSession.includes("jmcomicConfig.name, true, true"));
check("18mh challenge can hand off and continue behind the app",
  source.includes("automaticInteractiveFallback")
  && source.includes("cf-turnstile-response")
  && source.includes("shouldHandOffInteractive")
  && source.includes("showCompletingBehindApp()"));
check("submitted 18mh challenge stays active behind the app",
  completingView.includes("host.setLayoutParams(verificationLayoutParams())")
  && completingView.includes("host.setTranslationX(0f)")
  && completingView.includes("webView.setAlpha(1f)")
  && completingView.includes("foregroundContent.bringToFront()")
  && !completingView.includes("showBackgroundView()"));
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

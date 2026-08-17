const fs = require("fs");

const mh18 = fs.readFileSync(
  "app/src/main/java/com/xxcomic/Mh18WebViewSession.java",
  "utf8",
);
const jmcomic = fs.readFileSync(
  "app/src/main/java/com/xxcomic/JmComicWebViewSession.java",
  "utf8",
);
const sessions = [mh18, jmcomic];
const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("protected sources use independent implementations",
  !fs.existsSync("app/src/main/java/com/xxcomic/CloudflareWebViewSession.java")
  && mh18.includes("final class Mh18WebViewSession implements BrowserSession")
  && jmcomic.includes("final class JmComicWebViewSession implements BrowserSession")
  && !mh18.includes("JmComicWebViewSession")
  && !jmcomic.includes("Mh18WebViewSession"));
check("main owns one concrete session per source",
  main.includes("Mh18WebViewSession mh18BrowserSession")
  && main.includes("JmComicWebViewSession jmcomicBrowserSession")
  && main.includes("new Mh18WebViewSession(")
  && main.includes("new JmComicWebViewSession("));
check("both sessions use their native WebView fingerprint",
  sessions.every(source => source.includes("WebSettings.getDefaultUserAgent(activity)")
    && source.includes('connection.setRequestProperty("User-Agent", userAgent)')
    && !source.includes("settings.setUserAgentString")));
check("both sessions own their request and browser state",
  sessions.every(source => source.includes("new Semaphore(1, true)")
    && source.includes("private FetchRequest activeRequest")
    && source.includes("private volatile boolean browserContextReady")));
check("both sessions load and capture their requested page",
  sessions.every(source => source.includes("webView.loadUrl(request.url)")
    && source.includes("document.documentElement.outerHTML")
    && source.includes("fetchWithBrowserContext(url, deadline)")));
check("18mh retains its visible fallback without changing jmcomic",
  mh18.includes("AUTOMATIC_INTERACTIVE_FALLBACK = true")
  && mh18.includes("FULL_VIEWPORT_BACKGROUND = true")
  && jmcomic.includes("AUTOMATIC_INTERACTIVE_FALLBACK = false")
  && jmcomic.includes("FULL_VIEWPORT_BACKGROUND = false"));
check("challenge inspection includes DOM markers",
  sessions.every(source => source.includes("html:(document.documentElement.outerHTML||'').slice(0,12000)")
    && source.includes('page.optString("html")')));
check("session page caches can be cleared",
  sessions.every(source => source.includes("void clearCache()")
    && source.includes("webView.clearCache(true)")
    && source.includes("webView.clearHistory()")));
check("app cache clear removes both protected credentials",
  main.includes("removeAllCookies")
  && main.includes("WebStorage.getInstance().deleteAllData()")
  && main.includes("mh18BrowserSession.clearCache()")
  && main.includes("jmcomicBrowserSession.clearCache()"));

console.log("Protected source session contract holds.");

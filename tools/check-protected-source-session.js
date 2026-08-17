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
check("both sessions use the fixed Chrome 124 fingerprint",
  sessions.every(source => source.includes("Chrome/124.0.0.0")
    && source.includes("fixedUserAgent()")
    && source.includes('connection.setRequestProperty("User-Agent", userAgent)')
    && source.includes("settings.setUserAgentString(userAgent)")
    && !source.includes("WebSettings.getDefaultUserAgent")));
check("both sessions own their request locks",
  sessions.every(source => source.includes("new Semaphore(1, true)")));
check("18mh ordinary fetch is cached-http-only",
  mh18.includes("public String fetch(String url) throws IOException")
  && mh18.includes("HttpFetch response = fetchHttp(url)")
  && mh18.includes("new VerificationRequiredException")
  && !mh18.includes("fetchWithBrowserContext")
  && !mh18.includes("AUTOMATIC_INTERACTIVE_FALLBACK")
  && !mh18.includes("browserContextReady"));
check("18mh challenge response returns before reading its body",
  mh18.indexOf("if (statusCode == 403") > 0
  && mh18.indexOf("if (statusCode == 403")
    < mh18.indexOf("InputStream stream = statusCode >= 400"));
check("18mh browser is explicit and compact",
  mh18.includes("public String fetchInteractive(String url) throws IOException")
  && mh18.includes("Dialog dialog = new Dialog(activity)")
  && mh18.includes("window.setLayout(width * 9 / 10, height * 7 / 10)")
  && mh18.includes("UIHelpers.round(UIHelpers.CARD")
  && mh18.includes("UIHelpers.vectorIconButton")
  && mh18.includes('reload.setText("重新加载")'));
const interactiveFetch = mh18.slice(
  mh18.indexOf("public String fetchInteractive"),
  mh18.indexOf("private void requireWorkerThread"),
);
check("18mh manual verification opens without waiting for content requests",
  !interactiveFetch.includes("requestLock.tryAcquire")
  && interactiveFetch.includes("main.post(() -> startInteractive(request))"));
check("18mh verification requires browser and cached catalog markers",
  mh18.includes("Mh18ComicSource.hasCatalogMarker(html)")
  && mh18.includes("Mh18ComicSource.hasCatalogMarker(response.body)")
  && mh18.includes("verificationComplete(browserCatalog, probeCatalog)")
  && mh18.includes('putLong(VERIFIED_AT_KEY, System.currentTimeMillis())'));
check("18mh verification exposes manual retry and typed cancellation",
  mh18.includes("interface VerificationRetryListener")
  && mh18.includes("verificationRetry.onRetry()")
  && mh18.includes("new VerificationCancelledException"));
const retryInteractive = mh18.slice(
  mh18.indexOf("private void retryInteractive"),
  mh18.indexOf("private void scheduleTimeout"),
);
check("18mh reload ends the old request before delegating retry",
  mh18.includes("reload.setOnClickListener(ignored -> retryInteractive(request))")
  && retryInteractive.includes("finishRequest(request")
  && retryInteractive.includes("new VerificationCancelledException")
  && retryInteractive.indexOf("finishRequest(request")
    < retryInteractive.indexOf("verificationRetry.onRetry()")
  && (mh18.match(/verificationRetry\.onRetry\(\)/g) || []).length === 1
  && !retryInteractive.includes("loadUrl("));
check("18mh initial load is not an automatic retry loop",
  (mh18.match(/loadInteractive\(request\)/g) || []).length === 1);
const cancelInteractive = mh18.slice(
  mh18.indexOf("private void cancelInteractive"),
  mh18.indexOf("void shutdown()"),
);
check("18mh close surfaces typed cancellation",
  cancelInteractive.includes("finishRequest(request")
  && cancelInteractive.includes("new VerificationCancelledException"));
const pageStarted = mh18.slice(
  mh18.indexOf("public void onPageStarted"),
  mh18.indexOf("public void onPageFinished"),
);
check("18mh failures wait for manual reload",
  !pageStarted.includes("request.stopped = false")
  && pageStarted.includes("if (request.stopped)")
  && pageStarted.includes("view.stopLoading()")
  && mh18.includes('stopAttempt(request, "网络确认失败，请重试")')
  && mh18.includes('stopAttempt(request, "验证尚未生效，请重试")')
  && mh18.includes('stopAttempt(request, "确认请求失败，请重试")')
  && mh18.includes('stopAttempt(request, "页面确认失败，请重试")'));
check("challenge inspection includes DOM markers",
  mh18.includes("document.documentElement.outerHTML||''")
  && mh18.includes('page.optString("html")')
  && jmcomic.includes("html:(document.documentElement.outerHTML||'').slice(0,12000)")
  && jmcomic.includes('page.optString("html")'));
const mh18ClearCache = mh18.slice(
  mh18.indexOf("void clearCache()"),
  mh18.indexOf("private void finishRequest"),
);
check("18mh cache clear is source-local and ends its active request",
  mh18ClearCache.includes("remove(VERIFIED_AT_KEY)")
  && mh18ClearCache.includes("InteractiveRequest request = activeRequest")
  && mh18ClearCache.includes("finishRequest(request")
  && !mh18ClearCache.includes("new WebView(")
  && !mh18ClearCache.includes(".clearCache(")
  && !mh18ClearCache.includes(".clearHistory(")
  && !mh18ClearCache.includes(".clearFormData(")
  && !mh18ClearCache.toLowerCase().includes("jmcomic"));
check("jmcomic keeps its independent cache implementation",
  jmcomic.includes("void clearCache()")
  && jmcomic.includes("webView.clearCache(true)")
  && jmcomic.includes("webView.clearHistory()"));
check("18mh request, preferences, and retry remain isolated",
  mh18.includes('PREFS_NAME = "mh18_verification"')
  && mh18.includes("private InteractiveRequest activeRequest")
  && mh18.includes("private final VerificationRetryListener verificationRetry")
  && !mh18.toLowerCase().includes("jmcomic"));
check("main keeps task-2 constructor compatibility",
  main.includes("this, main, mh18Config.name, this::showRemToast);"));
check("app cache clear removes both protected credentials",
  main.includes("removeAllCookies")
  && main.includes("WebStorage.getInstance().deleteAllData()")
  && main.includes("mh18BrowserSession.clearCache()")
  && main.includes("jmcomicBrowserSession.clearCache()"));

console.log("Protected source session contract holds.");

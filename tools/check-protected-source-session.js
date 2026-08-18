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
check("18mh ordinary fetch reuses only an explicitly verified browser context",
  mh18.includes("public String fetch(String url) throws IOException")
  && mh18.includes("? fetchWithBrowserContext(url) : fetchHttp(url)")
  && mh18.includes("requestTransport(browserContextReady)")
  && mh18.includes("fetchWithBrowserContext(url)")
  && mh18.includes("new VerificationRequiredException")
  && !mh18.includes("AUTOMATIC_INTERACTIVE_FALLBACK")
  && !mh18.slice(
    mh18.indexOf("public String fetch(String url) throws IOException"),
    mh18.indexOf("public String fetchInteractive(String url) throws IOException"),
  ).includes("loadInteractive("));
check("jmcomic ordinary fetch is cached-http-only",
  jmcomic.includes("public String fetch(String url) throws IOException")
  && jmcomic.includes("HttpFetch response = fetchHttp(url)")
  && jmcomic.includes("new VerificationRequiredException")
  && !jmcomic.includes("fetchWithBrowserContext")
  && !jmcomic.includes("AUTOMATIC_INTERACTIVE_FALLBACK")
  && !jmcomic.includes("browserContextReady"));
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
check("jmcomic browser is explicit and compact",
  jmcomic.includes("public String fetchInteractive(String url) throws IOException")
  && jmcomic.includes("Dialog dialog = new Dialog(activity)")
  && jmcomic.includes("window.setLayout(width * 9 / 10, height * 7 / 10)")
  && jmcomic.includes("UIHelpers.round(UIHelpers.CARD")
  && jmcomic.includes("UIHelpers.vectorIconButton"));
const interactiveFetch = mh18.slice(
  mh18.indexOf("public String fetchInteractive"),
  mh18.indexOf("private void requireWorkerThread"),
);
check("18mh manual verification opens without waiting for content requests",
  !interactiveFetch.includes("requestLock.tryAcquire")
  && interactiveFetch.includes("main.post(() -> startInteractive(request))"));
check("18mh verification requires browser and same-context catalog markers",
  mh18.includes("Mh18ComicSource.hasCatalogMarker(html)")
  && mh18.includes("Mh18ComicSource.hasCatalogMarker(response.body)")
  && mh18.includes("verificationComplete(browserCatalog, probeCatalog)")
  && mh18.includes("beginBrowserFetch(request.webView, task)")
  && mh18.includes('putLong(VERIFIED_AT_KEY, System.currentTimeMillis())'));
check("jmcomic verification requires browser and cached catalog markers",
  jmcomic.includes("JmComicSource.hasCatalogMarker(html)")
  && jmcomic.includes("JmComicSource.hasCatalogMarker(response.body)")
  && jmcomic.includes("verificationComplete(browserCatalog, probeCatalog)")
  && jmcomic.includes('putLong(VERIFIED_AT_KEY, System.currentTimeMillis())'));
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
  (mh18.match(/loadInteractive\(request\)/g) || []).length >= 2
  && !mh18.slice(
    mh18.indexOf("private void startInteractive"),
    mh18.indexOf("private void createDialog"),
  ).includes("loadInteractive(request)"));
check("18mh probe challenges refresh the visible verification page",
  mh18.includes("enum ProbeAction")
  && mh18.includes("ProbeAction.RELOAD")
  && mh18.includes("MAX_PROBE_RECOVERIES")
  && mh18.includes("isCloudflareChallengeNavigation"));
const startInteractive = mh18.slice(
  mh18.indexOf("private void startInteractive"),
  mh18.indexOf("private void createDialog"),
);
check("18mh manual verification starts with a cached credential preflight",
  startInteractive.includes("beginPreflight(request)")
  && !startInteractive.includes("loadInteractive(request)"));
const overrideNavigation = mh18.slice(
  mh18.indexOf("public boolean shouldOverrideUrlLoading"),
  mh18.indexOf("public void onReceivedError"),
);
check("18mh external navigation is blocked without stopping verification",
  overrideNavigation.includes("shouldBlockNavigation(")
  && !overrideNavigation.includes("stopAttempt("));
const inspectPage = mh18.slice(
  mh18.indexOf("private void inspectPage"),
  mh18.indexOf("private void beginProbe"),
);
const beginProbe = mh18.slice(
  mh18.indexOf("private void beginProbe"),
  mh18.indexOf("private void finishProbe"),
);
const scheduleTimeout = mh18.slice(
  mh18.indexOf("private void scheduleTimeout"),
  mh18.indexOf("private void inspectPage"),
);
check("18mh challenge and incomplete catalog pages keep polling",
  inspectPage.includes("pageAction(")
  && inspectPage.includes("scheduleInspection(request"));
check("18mh final probe keeps the original request timeout",
  !beginProbe.includes("removeCallbacks(request.timeout)")
  && !beginProbe.includes("fetchHttp(request.url)")
  && scheduleTimeout.includes("shouldStopForTimeout(")
  && scheduleTimeout.includes("remainingRequestMs(request.deadline"));
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
  && jmcomic.includes("document.documentElement.outerHTML||''")
  && jmcomic.includes('page.optString("html")'));
const mh18ClearCache = mh18.slice(
  mh18.indexOf("void clearCache()"),
  mh18.indexOf("private void finishRequest"),
);
check("18mh cache clear is source-local and ends its active request",
  mh18ClearCache.includes("remove(VERIFIED_AT_KEY)")
  && mh18ClearCache.includes("InteractiveRequest request = activeRequest")
  && mh18ClearCache.includes("finishRequest(request")
  && mh18ClearCache.includes("closeBrowserContext()")
  && !mh18ClearCache.includes("new WebView(")
  && !mh18ClearCache.includes(".clearCache(")
  && !mh18ClearCache.includes(".clearHistory(")
  && !mh18ClearCache.includes(".clearFormData(")
  && !mh18ClearCache.toLowerCase().includes("jmcomic"));
check("18mh keeps a non-interactive context only after browser verification",
  mh18.includes("request.retainBrowser = retainBrowser")
  && mh18.includes("retainBrowserContext(browser)")
  && mh18.includes("new FrameLayout.LayoutParams(1, 1, Gravity.TOP | Gravity.START)")
  && mh18.includes("browser.setClickable(false)")
  && mh18.includes("browser.removeJavascriptInterface(BRIDGE_NAME)"));
const jmcomicClearCache = jmcomic.slice(
  jmcomic.indexOf("void clearCache()"),
  jmcomic.indexOf("private void finishRequest"),
);
check("jmcomic cache clear is source-local and ends its active request",
  jmcomicClearCache.includes("remove(VERIFIED_AT_KEY)")
  && jmcomicClearCache.includes("InteractiveRequest request = activeRequest")
  && jmcomicClearCache.includes("finishRequest(request")
  && !jmcomicClearCache.includes("new WebView(")
  && !jmcomicClearCache.includes(".clearCache(")
  && !jmcomicClearCache.toLowerCase().includes("mh18"));
check("18mh request, preferences, and retry remain isolated",
  mh18.includes('PREFS_NAME = "mh18_verification"')
  && mh18.includes("private InteractiveRequest activeRequest")
  && mh18.includes("private final VerificationRetryListener verificationRetry")
  && !mh18.toLowerCase().includes("jmcomic"));
check("jmcomic request, preferences, and retry remain isolated",
  jmcomic.includes('PREFS_NAME = "jmcomic_verification"')
  && jmcomic.includes("private InteractiveRequest activeRequest")
  && jmcomic.includes("private final VerificationRetryListener verificationRetry")
  && jmcomic.includes('JM_ORIGIN = "https://18comic.vip"')
  && !jmcomic.toLowerCase().includes("mh18"));
check("main wires isolated manual retry callbacks",
  main.includes("this, main, mh18Config.name, null,")
  && main.includes('requestProtectedSourceRetry("mh18")')
  && main.includes("this, main, jmcomicConfig.name, null,")
  && main.includes('requestProtectedSourceRetry("jmcomic")'));
check("content screens never start protected verification",
  main.includes("shouldOfferSourceVerification")
  && main.includes("verificationRequiredState(String sourceId)")
  && main.includes('"去验证", this::showSourceManagement')
  && main.includes("globalSearchVerificationRequiredSourceIds")
  && main.includes("searchAppendVerificationRequired")
  && !main.includes("shouldReloadAfterProtectedVerification"));
check("app cache clear removes both protected credentials",
  main.includes("removeAllCookies")
  && main.includes("WebStorage.getInstance().deleteAllData()")
  && main.includes("mh18BrowserSession.clearCache()")
  && main.includes("jmcomicBrowserSession.clearCache()"));

console.log("Protected source session contract holds.");

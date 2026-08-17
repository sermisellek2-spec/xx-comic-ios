const fs = require("fs");

const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);
const session = fs.readFileSync(
  "app/src/main/java/com/xxcomic/JmComicWebViewSession.java",
  "utf8",
);
const mh18Session = fs.readFileSync(
  "app/src/main/java/com/xxcomic/Mh18WebViewSession.java",
  "utf8",
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("jmcomic uses its dedicated access probe",
  main.includes("jmcomicClient.verifyAccess()"));
check("ordinary jmcomic requests never open a browser",
  session.includes("HttpFetch response = fetchHttp(url)")
  && session.includes("new VerificationRequiredException")
  && !session.includes("fetchWithBrowserContext")
  && !session.includes("AUTOMATIC_INTERACTIVE_FALLBACK")
  && !session.includes("browserContextReady"));
check("settings verification keeps an explicit interactive path",
  main.includes("jmcomicClient.verifyAccess()")
  && main.includes("mh18Client.verifyAccess()")
  && session.includes("public String fetchInteractive(String url) throws IOException")
  && session.includes("Dialog dialog = new Dialog(activity)"));
check("jmcomic owns its Chrome 124 credential migration",
  session.includes("JM_CREDENTIAL_PREFS")
  && session.includes("migrateCredentialFingerprint()")
  && session.includes("expireDomainCookies(")
  && !mh18Session.includes("JM_CREDENTIAL_PREFS"));
check("jmcomic verification requires browser and cached catalog markers",
  session.includes("JmComicSource.hasCatalogMarker(html)")
  && session.includes("JmComicSource.hasCatalogMarker(response.body)")
  && session.includes("verificationComplete(browserCatalog, probeCatalog)"));
check("successful manual verification reloads only the visible jmcomic catalog",
  main.includes("shouldReloadAfterProtectedVerification(")
  && main.includes("loadSearchPage(searchQuery, 1, false"));
check("verification status uses the themed app toast",
  main.includes("this::showRemToast"));
check("protected requests remain single active navigation",
  session.includes("requestLock.tryAcquire")
  && session.includes("activeRequest != null && !activeRequest.completed"));
check("manual verification keeps useful failure classes",
  main.includes('" 验证超时"') && main.includes('" 页面验证失败"')
  && main.includes('" 连接失败，请检查 VPN"'));
check("jmcomic defers categories until the first list",
  main.includes('return "jmcomic".equals(sourceId);')
  && main.includes("if (loadCategoriesAfterList) loadSourceCategories()"));
check("category failures are visible and retryable",
  main.includes('appendErrorLog("分类加载失败", error)')
  && main.includes('"分类加载失败，重试"'));
check("category failure never clears catalog results",
  !/catch \(Exception error\)[\s\S]{0,500}分类加载失败[\s\S]{0,300}searchResults\.clear\(\)/.test(main));
check("jmcomic opts into cookie-backed http",
  main.includes("new JmComicWebViewSession(")
  && session.includes("fetchHttp(url)")
  && session.includes('setRequestProperty("Cookie", cookie)')
  && session.includes("HttpAction.VERIFICATION_REQUIRED"));
check("mh18 also uses cookie-backed http",
  main.includes("new Mh18WebViewSession("));

console.log("JMComic bootstrap contract holds.");

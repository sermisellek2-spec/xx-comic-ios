const fs = require("fs");

const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);
const session = fs.readFileSync(
  "app/src/main/java/com/xxcomic/JmComicWebViewSession.java",
  "utf8",
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("jmcomic uses its dedicated access probe",
  main.includes("jmcomicClient.verifyAccess()"));
check("automatic verification never expands the website",
  session.includes("if (request.interactiveAllowed)")
  && /shouldShowInteractive\(\s*request\.interactiveAllowed,\s*request\.verifying\)/.test(session)
  && session.includes("showBackgroundView()"));
check("settings verification keeps an explicit interactive path",
  main.includes("jmcomicClient.verifyAccess()")
  && main.includes("mh18Client.verifyAccess()"));
check("verification status uses the themed app toast",
  main.includes("this::showRemToast"));
check("old challenge response is ignored after verification",
  session.includes("!verifying && responseChallenge"));
check("protected requests remain single active navigation",
  session.includes("requestLock.tryAcquire")
  && session.includes("activeRequest != null && !activeRequest.completed"));
check("verified browser context uses same-origin fetch",
  session.includes("fetchWithBrowserContext(url, deadline)")
  && session.includes('credentials:\\"include\\"')
  && session.includes('cache:\\"no-store\\"')
  && session.includes('redirect:\\"follow\\"'));
check("ready browser context skips repeated http probes",
  session.includes("browserContextReady")
  && session.indexOf("fetchWithBrowserContext(url, deadline)")
      < session.indexOf("fetchHttp(url, deadline)"));
check("context challenge performs one navigation fallback",
  session.includes("browserContextReady = false")
  && session.includes("fetchWithBrowser(url, allowInteractive, deadline)"));
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
  && session.includes("fetchHttp(url, deadline)")
  && session.includes('setRequestProperty("Cookie", cookie)')
  && session.includes("HttpAction.OPEN_BROWSER"));
check("mh18 also uses cookie-backed http",
  main.includes("new Mh18WebViewSession("));

console.log("JMComic bootstrap contract holds.");

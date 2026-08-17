const fs = require("fs");

const main = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);
const session = fs.readFileSync(
  "app/src/main/java/com/xxcomic/CloudflareWebViewSession.java",
  "utf8",
);

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("jmcomic uses its dedicated access probe",
  main.includes("jmcomicClient.verifyAccess()"));
check("automatic verification stays lightweight before interaction",
  session.includes("INTERACTIVE_DELAY_MS = 4000L")
  && session.includes('notifyVerification("正在验证")')
  && session.includes("showBackgroundView()")
  && session.includes("showVerificationView(true)"));
check("verification status uses the themed app toast",
  main.includes("this::showRemToast"));
check("old challenge response is ignored after verification",
  session.includes("!verifying && responseChallenge"));
check("protected requests remain single active navigation",
  session.includes("synchronized (requestLock)")
  && session.includes("activeRequest != null && !activeRequest.completed"));
check("verified browser context uses same-origin fetch",
  session.includes("fetchWithBrowserContext(url)")
  && session.includes('credentials:\\"include\\"')
  && session.includes('cache:\\"no-store\\"')
  && session.includes('redirect:\\"follow\\"'));
check("ready browser context skips repeated http probes",
  session.includes("browserContextReady")
  && session.indexOf("fetchWithBrowserContext(url)")
      < session.indexOf("fetchHttp(url)"));
check("context challenge performs one navigation fallback",
  session.includes("browserContextReady = false")
  && session.includes("fetchWithBrowser(url)"));
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
  main.includes("jmcomicConfig.name, true")
  && session.includes("fetchHttp(url)")
  && session.includes('setRequestProperty("Cookie", cookie)')
  && session.includes("HttpAction.OPEN_BROWSER"));
check("mh18 keeps its current browser-only path",
  main.includes("mh18Config.name, false"));

console.log("JMComic bootstrap contract holds.");

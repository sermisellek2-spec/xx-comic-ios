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
check("verification webview becomes visible only during challenge",
  session.includes("showVerificationView(false)")
  && session.includes("showVerificationView(true)")
  && session.includes("interactive ? 1f : 0.01f"));
check("old challenge response is ignored after verification",
  session.includes("!verifying && responseChallenge"));
check("protected requests remain single active navigation",
  session.includes("synchronized (requestLock)")
  && session.includes("activeRequest != null && !activeRequest.completed"));
check("manual verification keeps useful failure classes",
  main.includes('" 验证超时"') && main.includes('" 页面验证失败"')
  && main.includes('" 连接失败，请检查 VPN"'));

console.log("JMComic bootstrap contract holds.");

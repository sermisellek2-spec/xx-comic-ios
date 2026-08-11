const fs = require("fs");

const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const config = fs.readFileSync(
  "app/src/main/java/com/xxcomic/source/SourceConfig.java",
  "utf8",
);
const retired = fs.readFileSync(
  "app/src/main/java/com/xxcomic/source/Mhua5ComicSource.java",
  "utf8",
);

function check(condition, message) {
  if (!condition) throw new Error(message);
}

for (const marker of [
  "private SourceConfig mhua5Config",
  "mhua5Enabled",
  "SourceConfig.mhua5",
  "source.mhua5.enabled",
  "sources.add(mhua5Client)",
  "names.add(mhua5Client.name())",
  "sources.put(mhua5Config",
]) {
  check(!main.includes(marker), `active mhua5 marker remains: ${marker}`);
}

check(!/static SourceConfig mhua5\s*\(/.test(config), "SourceConfig.mhua5 still exists");
check(main.includes("private ComicSource mhua5Client;"), "legacy mhua5 resolver missing");
check(
  main.includes("mhua5Client = new Mhua5ComicSource();"),
  "retired adapter not constructed",
);
check(
  main.includes("if (mhua5Client.id().equals(sourceId)) return mhua5Client;"),
  "legacy source id does not resolve",
);
check(
  main.includes('comicId.startsWith(mhua5Client.id() + ":")'),
  "legacy comic id prefix does not resolve",
);
check(
  !main.includes("漫画屋的搜索、详情、阅读图片"),
  "about text still advertises mhua5",
);

check(
  retired.includes('private static final String SOURCE_ID = "mhua5";'),
  "stable source id missing",
);
check(retired.includes('return "漫画屋（已下线）";'), "retired source label missing");
check(
  retired.includes('return new IOException("漫画屋站源已下线");'),
  "offline error missing",
);
for (const marker of ["HttpURLConnection", "new URL(", "Pattern.compile", "SourceConfig"]) {
  check(!retired.includes(marker), `retired adapter still has live implementation: ${marker}`);
}

for (const path of [
  "tools/sim-mhua5-parse.js",
  "tools/probe-mhua5-search.html",
  "tools/probe-mhua5-detail.html",
  "tools/probe-mhua5-chapter.html",
]) {
  check(!fs.existsSync(path), `retired mhua5 probe remains: ${path}`);
}

console.log("retired mhua5 source checks ok");

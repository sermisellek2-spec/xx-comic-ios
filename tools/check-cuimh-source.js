const fs = require("fs");

const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const source = fs.readFileSync("app/src/main/java/com/xxcomic/source/CuimhComicSource.java", "utf8");
const config = fs.readFileSync("app/src/main/java/com/xxcomic/source/SourceConfig.java", "utf8");
const gradle = fs.readFileSync("app/build.gradle", "utf8");

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("Cuimh config is built in", config.includes('new SourceConfig("cuimh", "催漫画"'));
check("Cuimh is enabled and rebuilt", main.includes("private boolean cuimhEnabled = true;")
  && main.includes("new CuimhComicSource(cuimhConfig.withEnabled(cuimhEnabled))"));
check("Cuimh participates in source management", main.includes("sourceCard(cuimhConfig, cuimhEnabled"));
check("Cuimh persists through preferences and exports", main.includes('"source.cuimh.enabled"')
  && main.includes("sources.put(cuimhConfig.withEnabled(cuimhEnabled).toJson())"));
check("Cuimh explicitly disables keyword search", source.includes("boolean supportsSearch() { return false; }")
  && main.includes("if (source.supportsSearch()) sources.add(source)"));
check("Cuimh chapter images use page referer", main.includes('imageUrl.contains("baipiaoguai.org")')
  && main.includes("TextUtils.isEmpty(pageReferer) ? cuimhConfig.referer : pageReferer"));
check("Cuimh reuses catalog and detail documents", source.includes("fetchCategoryDocument")
  && source.includes("parseChapters(html)"));
check("Cuimh paces requests and cools down after 403", source.includes("MIN_REQUEST_INTERVAL_MS")
  && source.includes("FORBIDDEN_COOLDOWN_MS") && source.includes("HTTP_FORBIDDEN"));
check("detail refresh preserves chapters without eager directory fetch", main.includes("mergeRefreshedDetail(detail, freshDetail)")
  && main.includes("new ArrayList<>(cached.chapters)") && main.includes("refreshedComicIds.add(comicId)"));
check("filter confirm only reloads missing categories",
  main.includes("sourceChanged && !categoriesFollowInitialList(selectedSourceId)")
  && main.includes("&& sourceFilterGroups.isEmpty()) loadSourceCategories();"));
check("release version is 1.0.45", gradle.includes('versionName "1.0.45"')
  && gradle.includes("versionCode 45"));

console.log("Cuimh source contract holds.");

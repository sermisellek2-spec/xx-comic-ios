const fs = require("fs");

const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const sourcePath = "app/src/main/java/com/xxcomic/source/LiumanhuaComicSource.java";
const source = fs.existsSync(sourcePath) ? fs.readFileSync(sourcePath, "utf8") : "";
const config = fs.readFileSync("app/src/main/java/com/xxcomic/source/SourceConfig.java", "utf8");

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("Liumanhua config is built in", config.includes('new SourceConfig("liumanhua", "六漫画"'));
check("Liumanhua source exists", source.includes("class LiumanhuaComicSource implements ComicSource"));
check("Liumanhua disables keyword search", source.includes("boolean supportsSearch() { return false; }")
  && main.includes("if (source.supportsSearch()) sources.add(source)"));
check("Liumanhua parses scoped list cards", source.includes("cy_list_mh") && source.includes("cy_list_mh > ul"));
check("Liumanhua parses dynamic filters", source.includes("cy_tag") && source.includes("资费"));
check("Liumanhua excludes recommendations from chapters", source.includes("cy_plist")
  && source.includes("chapter__item") && source.includes("rd-guess__comic"));
check("Liumanhua uses AES chapter payload", source.includes("AES/CBC/PKCS5Padding")
  && source.includes("9S8$vJnU2ANeSRoF") && source.includes("IvParameterSpec"));
check("Liumanhua validates decrypted payload", source.includes("source_id")
  && source.includes("s2.bzcdn.net") && source.includes("images"));
check("Liumanhua is wired into source management", main.includes("liumanhuaConfig")
  && main.includes("new LiumanhuaComicSource(liumanhuaConfig.withEnabled(liumanhuaEnabled))")
  && main.includes("sourceCard(liumanhuaConfig, liumanhuaEnabled"));
check("Liumanhua persists and routes", main.includes('"source.liumanhua.enabled"')
  && main.includes("liumanhuaClient.id().equals(sourceId)")
  && main.includes("sources.put(liumanhuaConfig.withEnabled(liumanhuaEnabled).toJson())"));
check("Liumanhua image referer is mapped", main.includes('imageUrl.contains("s2.bzcdn.net")')
  && main.includes("liumanhuaConfig.referer"));

console.log("Liumanhua source contract holds.");

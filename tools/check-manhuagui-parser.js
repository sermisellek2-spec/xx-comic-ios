function attr(html, name) {
  const match = (html || "").match(new RegExp(`\\b${name}=["']([^"']*)["']`, "i"));
  return match ? match[1].replace(/&amp;/g, "&").trim() : "";
}

function clean(value) {
  return (value || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

function imageUrlFromTag(tag) {
  return attr(tag, "data-src") || attr(tag, "data-original") || attr(tag, "src");
}

function detailCover(html, id) {
  const og = (html.match(/<meta[^>]+(?:property|name)=["']og:image["'][^>]+content=["']([^"']*)["']/i) || [])[1] || "";
  if (og) return og;
  const coverBlock = (html.match(/<div[^>]+class=["'][^"']*(?:cover|thumb|book)[^"']*["'][\s\S]*?<img\b[^>]*>/i) || [""])[0];
  return imageUrlFromTag(coverBlock) || `https://cf.mhgui.com/cpic/b/${id}.jpg`;
}

function parseChapters(html) {
  return [...html.matchAll(/<a[^>]*href=["'](\/comic\/\d+\/\d+\.html)["'][^>]*>([\s\S]*?)<\/a>/gi)]
    .map(m => ({ href: m[1], title: clean(attr(m[0], "title") || m[2]), slot: Number((m[1].match(/\/(\d+)\.html/) || [0, 0])[1]) }))
    .sort((a, b) => a.slot - b.slot);
}

function matchingBrace(text, start) {
  if (!text || start < 0 || text[start] !== "{") return -1;
  let depth = 0, inString = false, escaping = false, quote = "";
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaping) escaping = false;
      else if (ch === "\\") escaping = true;
      else if (ch === quote) inString = false;
      continue;
    }
    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
    } else if (ch === "{") {
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function isValidImgData(value) {
  try {
    const root = JSON.parse(value || "");
    return !!(root.path && Array.isArray(root.files) && root.sl);
  } catch {
    return false;
  }
}

function normalizeLooseJsonObject(value) {
  return (value || "")
    .replace(/([{,]\s*)([A-Za-z_$][\w$]*)(\s*:)/g, '$1"$2"$3')
    .replace(/(:\s*)([A-Za-z_$][\w$]*|[0-9]+[A-Za-z_$][\w$]*)(\s*[,}])/g, '$1"$2"$3');
}

function canonicalImgData(value) {
  try {
    const root = JSON.parse(normalizeLooseJsonObject(value || ""));
    const files = Array.isArray(root.files) ? root.files : Object.values(root).find(v => Array.isArray(v) && v.length && v.every(looksLikeImageFile));
    const path = root.path || Object.values(root).find(looksLikePath);
    const sl = root.sl || Object.values(root).find(v => v && typeof v === "object" && !Array.isArray(v) && ("e" in v || "m" in v)) || {};
    if (!path || !files) return "";
    return JSON.stringify({ path, files, sl });
  } catch {
    return "";
  }
}

function looksLikePath(value) {
  return typeof value === "string" && value.includes("/");
}

function looksLikeImageFile(value) {
  return typeof value === "string" && /\.(jpe?g|png|webp|gif|bmp)(?:$|\?)/i.test(value);
}

function unescapeJs(s) {
  return (s || "").replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/\\\\/g, "\\").replace(/\\\//g, "/");
}

function base62(c, a) {
  if (c < a) return c > 35 ? String.fromCharCode(c + 29) : c.toString(36);
  return base62(Math.floor(c / a), a) + base62(c % a, a);
}

function splitDict(dictText, sepText, expectedCount) {
  const candidates = [sepText, "|", ","].filter((item, index, list) => item && list.indexOf(item) === index);
  const texts = [dictText, decompressFromBase64(dictText)].filter(Boolean);
  let best = [dictText];
  for (const text of texts) {
    for (const sep of candidates) {
      const parts = text.split(sep);
      if (parts.length > best.length) best = parts;
      if (parts.length >= expectedCount) return parts;
    }
  }
  return best;
}

function decompressFromBase64(value) {
  const key = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  if (!value || !/^[A-Za-z0-9+/]+=*$/.test(value)) return "";
  return decompress(value.length, 32, index => key.indexOf(value.charAt(index)));
}

function decompress(length, resetValue, getNextValue) {
  const dictionary = [0, 1, 2];
  let enlargeIn = 4, dictSize = 4, numBits = 3, entry = "";
  const result = [];
  const data = { val: getNextValue(0), position: resetValue, index: 1 };
  let bits = readBits(data, resetValue, getNextValue, 2);
  let c;
  if (bits === 0) c = String.fromCharCode(readBits(data, resetValue, getNextValue, 8));
  else if (bits === 1) c = String.fromCharCode(readBits(data, resetValue, getNextValue, 16));
  else return "";
  dictionary[3] = c;
  let w = c;
  result.push(c);
  while (true) {
    if (data.index > length) return "";
    let code = readBits(data, resetValue, getNextValue, numBits);
    if (code === 0) {
      dictionary[dictSize++] = String.fromCharCode(readBits(data, resetValue, getNextValue, 8));
      code = dictSize - 1;
      enlargeIn--;
    } else if (code === 1) {
      dictionary[dictSize++] = String.fromCharCode(readBits(data, resetValue, getNextValue, 16));
      code = dictSize - 1;
      enlargeIn--;
    } else if (code === 2) {
      return result.join("");
    }
    if (enlargeIn === 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }
    if (dictionary[code]) entry = dictionary[code];
    else if (code === dictSize) entry = w + w.charAt(0);
    else return "";
    result.push(entry);
    dictionary[dictSize++] = w + entry.charAt(0);
    enlargeIn--;
    w = entry;
    if (enlargeIn === 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }
  }
}

function readBits(data, resetValue, getNextValue, count) {
  let bits = 0;
  let power = 1;
  const maxpower = 1 << count;
  while (power !== maxpower) {
    const resb = data.val & data.position;
    data.position >>= 1;
    if (data.position === 0) {
      data.position = resetValue;
      data.val = getNextValue(data.index++);
    }
    bits |= (resb > 0 ? 1 : 0) * power;
    power <<= 1;
  }
  return bits;
}

function unpackPackers(html) {
  const scripts = [];
  const re = /\(\s*(["'])((?:\\.|(?!\1)[\s\S])*)\1\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(["'])((?:\\.|(?!\5)[\s\S])*)\5\s*(?:\.\s*split|\[[^\]]*\])\s*\(\s*(["'])((?:\\.|(?!\7)[\s\S])*)\7\s*\)/g;
  let m;
  while ((m = re.exec(html || ""))) {
    let result = unescapeJs(m[2]);
    const radix = Number(m[3]);
    const count = Number(m[4]);
    const dict = splitDict(unescapeJs(m[6]), unescapeJs(m[8]), count);
    result = replacePackerTokens(result, radix, dict, count);
    scripts.push(result);
  }
  return scripts;
}

function replacePackerTokens(payload, radix, dict, count) {
  const values = new Map();
  for (let i = Math.max(count, dict.length) - 1; i >= 0; i--) {
    if (dict[i]) values.set(base62(i, radix), dict[i]);
  }
  return payload.replace(/[0-9A-Za-z]+/g, token => values.get(token) || token);
}

function buildManhuaguiImageUrl(config, index) {
  const root = JSON.parse(config);
  const encodedPath = root.path.split("/").map(item => item ? encodeURIComponent(item) : "").join("/");
  return `https://eu2.hamreus.com${encodedPath}${root.files[index]}?e=${root.sl.e}&m=${root.sl.m}`;
}

function extractImgData(html, depth = 0) {
  for (const script of unpackPackers(html)) {
    const config = extractImgData(script, depth + 1);
    if (config) return config;
  }
  if (depth > 4) return "";
  const markers = ["SMH.imgData", 'SMH["imgData"]', "SMH['imgData']"];
  let searchFrom = 0;
  while (searchFrom < html.length) {
    let marker = -1;
    let markerText = "";
    for (const item of markers) {
      const index = html.indexOf(item, searchFrom);
      if (index >= 0 && (marker < 0 || index < marker)) {
        marker = index;
        markerText = item;
      }
    }
    if (marker < 0) break;
    const openParen = html.indexOf("(", marker + markerText.length);
    const start = openParen >= 0 ? html.indexOf("{", openParen) : -1;
    const end = matchingBrace(html, start);
    const candidate = start >= 0 && end > start ? html.slice(start, end + 1) : "";
    if (isValidImgData(candidate)) return candidate;
    const normalized = normalizeLooseJsonObject(candidate);
    if (isValidImgData(normalized)) return normalized;
    searchFrom = marker + markerText.length;
  }
  let objectSearch = 0;
  while (objectSearch < html.length) {
    const start = html.indexOf("{", objectSearch);
    if (start < 0) return "";
    const end = matchingBrace(html, start);
    const candidate = start >= 0 && end > start ? html.slice(start, end + 1) : "";
    const canonical = canonicalImgData(candidate);
    if (isValidImgData(canonical)) return canonical;
    objectSearch = start + 1;
  }
  return "";
}

function parseCards(html) {
  const result = [];
  const seen = new Set();
  const blocks = html.match(/<a\b(?=[^>]*\bclass=["'][^"']*\bbcover\b)[^>]*>[\s\S]*?<\/a>/gi) || [];
  for (const block of blocks) {
    const href = attr(block, "href");
    const imageTag = (block.match(/<img\b[^>]*>/i) || [""])[0];
    const title = clean(attr(block, "title") || attr(imageTag, "alt"));
    const cover = imageUrlFromTag(imageTag);
    const id = (href.match(/\/comic\/(\d+)\/?/) || [])[1] || "";
    if (!id || !title || seen.has(id)) continue;
    seen.add(id);
    result.push({ id, title, cover });
  }
  return result;
}

const samples = [
  `<a class="bcover" href="/comic/60397/" title="comic a"><img src="//cf.mhgui.com/cpic/b/60397.jpg"></a>`,
  `<a href="/comic/60398/" title="comic b" class="bcover"><img data-original="//cf.mhgui.com/cpic/b/60398.jpg"></a>`,
  `<a href="/comic/60399/" class="bcover"><img alt="comic c" data-src="//cf.mhgui.com/cpic/b/60399.jpg"></a>`
];

const cards = parseCards(samples.join("\n"));
if (cards.length !== 3) throw new Error("expected 3 manhuagui cards");

const cover = detailCover(`<div class="book-cover"><img data-original="//cf.mhgui.com/cpic/b/12345.jpg"></div>`, "12345");
if (cover !== "//cf.mhgui.com/cpic/b/12345.jpg") throw new Error("detail cover fallback failed");

const fallbackCover = detailCover(`<h1>fallback</h1>`, "67890");
if (!fallbackCover.endsWith("/67890.jpg")) throw new Error("detail generated cover fallback failed");

const chapters = parseChapters(`<div class="links"><a href="/comic/67890/112.html">chapter 2</a></div>
<ul class="chapter-list-1"><li><a href="/comic/67890/111.html" title="chapter 1"></a></li></ul>`);
if (chapters.length !== 2 || !chapters[0].href.endsWith("/111.html") || !chapters[1].href.endsWith("/112.html")) {
  throw new Error("chapter parser order fallback failed");
}

const imgData = extractImgData(`SMH.imgData({"bid":1,"path":"/ps3/a/","files":["001.jpg"],"sl":{"e":"x","m":"y"}}).preInit();`);
if (!imgData.includes('"files"')) throw new Error("direct imgData parser failed");

const compressedImgData = extractImgData(`SMH.imgData({"K":f,"J":"r r w","X":["W 2 3"]}).preInit();`);
if (compressedImgData) throw new Error("compressed imgData should not be parsed as JSON");

const mixedImgData = extractImgData(`SMH.imgData({"K":f,"J":"r r w","X":["W 2 3"]}).preInit();
SMH.imgData({"bid":1,"path":"/ps3/b/","files":["002.jpg"],"sl":{"e":"x","m":"y"}}).preInit();`);
if (!mixedImgData.includes('"/ps3/b/"')) throw new Error("parser should skip compressed imgData and use valid config");

const looseImgData = extractImgData(`SMH.imgData({bid:1,path:"/ps3/c/",files:["003.jpg"],sl:{e:"x",m:"y"}}).preInit();`);
if (!looseImgData.includes('"/ps3/c/"')) throw new Error("parser should normalize loose JS imgData object");

const doubleQuotedPacked = extractImgData(`(function(p,a,c,k,e,d){return p}("SMH.imgData({bid:1,path:\\"/ps3/d/\\",files:[\\"004.jpg\\"],sl:{e:\\"x\\",m:\\"y\\"}}).preInit();",62,0,"".split("|"),0,{}))`);
if (!doubleQuotedPacked.includes('"/ps3/d/"')) throw new Error("parser should unpack double quoted packer args");

const nestedPacked = extractImgData(`(function(p,a,c,k,e,d){return p}("(function(p,a,c,k,e,d){return p}(\\"SMH.imgData({bid:1,path:\\\\\\\"/ps3/n/\\\\\\\",files:[\\\\\\"007.jpg\\\\\\"],sl:{e:\\\\\\\"x\\\\\\\",m:\\\\\\\"y\\\\\\"}}).preInit();\\",62,0,\\"\\".split(\\"|\\"),0,{}))",62,0,"".split("|"),0,{}))`);
if (!nestedPacked.includes('"/ps3/n/"')) throw new Error("parser should unpack nested packer args");

const bracketImgData = extractImgData(`SMH["imgData"]({bid:1,path:"/ps3/e/",files:["005.jpg"],sl:{e:"x",m:"y"}}).preInit();`);
if (!bracketImgData.includes('"/ps3/e/"')) throw new Error("parser should read bracket imgData calls");

const sparseDict = [];
sparseDict[77] = "path";
sparseDict[78] = "files";
sparseDict[79] = "sl";
sparseDict[106] = "imgData";
sparseDict[197] = "SMH";
const sparsePacked = extractImgData(`(function(p,a,c,k,e,d){return p}('3b.1I({"1f":"/ps3/f/","1g":["006.jpg"],"1h":{"e":"x","m":"y"}}).preInit();',62,2,'${sparseDict.join("|")}'.split('|'),0,{}))`);
if (!sparsePacked.includes('"/ps3/f/"')) throw new Error("parser should use full dictionary length when unpacking");

const fallbackDict = splitDict("SMH|imgData|path|files", "", 4);
if (fallbackDict.length !== 4 || fallbackDict[2] !== "path") throw new Error("parser should fallback to pipe dictionary splitting");

const tokenObject = extractImgData(`3f.1K({"1h":5,"1g":"5.1","1d":"meta","1c":1b,"1a":"19","18":["17.1.3","16.1.3"],"2a":{"e":"x","m":"y"}}).preInit();`);
if (tokenObject) throw new Error("parser should reject tokenized imgData payload");

const lzDict = "D4KwDg5sDuCmBGZgBYCcBWA7ARmIGm9tA9tWEEagwX4TAuJUCLtYQN0VAAOWAAYnVnsn3cwAnWASQB2ASwAu7AEzsAzO2TB26dgDZ2mdgA5mTLS3Ut52pU2xsJAIRayWUlrgBmwgDawAzsADGggIYBbWMA4EhLKSh7CACbAiMIewIDRzoC45sDUgIfygIbm0T7+0ZHaqkwSnIXyhVKCAIIasADiGgAWAPYAHsgA8jUAEgCyAMLoHmAAbhAAKtDA2JgayNIaHNK4rk6B2MHK8rywQ/xRQSGqgrDNorvRTo0eANYA+h5xrqLeogCu7qzMEtyushK/bIVZMJfBAACLPbyfYwhYBgZ71T66CT6aScRwiVz1WBRUQ8F4BFyCT5sADK3U6QA==";
const lzPacked = extractImgData(`(function(p,a,c,k,e,d){return p}('15.U({"A":3,"z":"y：x","w":"3.1","v":u,"t":"4 5 6","s":["r.1.2","q%p.1.2","l.1.2","n.1.2","B.1.2","k.1.2","j.1.2","7.1.2","8.1.2","9.1.2","b.1.2","c.1.2","d.1.2","f.1.2","g.1.2","h.1.2","i.1.2","o.1.2","C.1.2","P.1.2","E.1.2","T.1.2","D.1.2","V.1.2","W.1.2","Z.1.2","Y.1.2","14.1.2","10.1.2"],"11":12,"13":S,"X":"/Q/R/O/3/4 5 6/","N":0,"M":"","L":K,"J":I,"H":{"e":G,"m":"F"}}).a();',62,68,'${lzDict}'['split']('|'),0,{}))`);
if (!lzPacked.includes('"004.jpg.webp"') || !lzPacked.includes('1784381031') || !lzPacked.includes('nA8eG8hox4OGHMC5cpvgTw')) {
  throw new Error("parser should unpack lz-string manhuagui dictionary");
}
const expectedImage = "https://eu2.hamreus.com/ps3/23/09/49571/%E7%AC%AC1%E5%9B%9E%20%E8%8A%B1%E9%83%BD%E5%88%BA%E5%AE%A2%20%E5%85%B6%E4%B8%80/004.jpg.webp?e=1784381031&m=nA8eG8hox4OGHMC5cpvgTw";
if (buildManhuaguiImageUrl(lzPacked, 2) !== expectedImage) {
  throw new Error("parser should build expected manhuagui image url");
}

console.log("manhuagui parser ok", cards.length, chapters.map(chapter => chapter.slot).join(","), imgData.length);

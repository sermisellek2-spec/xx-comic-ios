const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..");
const htmlPath = path.join(root, "index.html");
const html = fs.readFileSync(htmlPath, "utf8");

const checks = [];

function check(name, passed, detail = "") {
  checks.push({ name, passed, detail });
}

function includesAll(name, values) {
  const missing = values.filter((value) => !html.includes(value));
  check(name, missing.length === 0, missing.length ? `missing: ${missing.join(", ")}` : "");
}

includesAll("core tabs", ["我的收藏", "搜索结果", "站源管理", "我的"]);
includesAll("detail and reader pages", ["章节目录", "阅读来源", "漫画图片区域", "图片加载失败"]);
includesAll("empty states", ["没有匹配的收藏", "没有找到相关漫画", "当前没有启用站源"]);
includesAll("profile sheets", ["阅读历史", "缓存清理", "关于 App", "免责声明"]);
includesAll("state fields", ["favoriteQuery", "searchQuery", "searchTag", "sourceUrl", "customSources", "chapterOrder", "cacheSize", "sourceOn", "storageKey"]);
includesAll("interaction handlers", ["toggleFav", "toggleSource", "toggleCustomSource", "setSearchTag", "setSourceUrl", "addCustomSource", "setChapterOrder", "openReader", "switchChapter", "clearCache"]);
includesAll("persistence handlers", ["loadState", "saveState", "localStorage.getItem(storageKey)", "localStorage.setItem(storageKey"]);
includesAll("stable test ids", [
  'data-testid="nav-${t[0]}"',
  'data-testid="favorite-search-input"',
  'data-testid="search-input"',
  'data-testid="tag-${tag}"',
  'data-testid="result-${c.id}"',
  'data-testid="source-switch"',
  'data-testid="source-url-input"',
  'data-testid="source-submit"',
  'data-testid="custom-source-${source.id}"',
  'data-testid="profile-cache"',
  'data-testid="detail-favorite"',
  'data-testid="detail-read"',
  'data-testid="chapter-order-desc"',
  'data-testid="chapter-${index}"',
  'data-testid="reader-prev"',
  'data-testid="reader-next"',
  'data-testid="reader-progress"',
  'data-testid="sheet-close"'
]);
includesAll("accessible labels", ['aria-label="${t[2]}"', 'aria-label="返回"', 'aria-label="启用或停用包子漫画"']);

check("no replacement mojibake", !/[锟�]|�/.test(html), "found replacement/mojibake marker");
check("single app root", (html.match(/id="app"/g) || []).length === 1);
check("single toast root", (html.match(/id="toast"/g) || []).length === 1);
check("no insecure network config in prototype", !html.includes("http://cn.bzmgcn.com"));
check("has multiple stable test ids", (html.match(/data-testid=/g) || []).length >= 20);

const scriptMatch = html.match(/<script>([\s\S]*)<\/script>\s*<\/body>/);
check("inline script exists", Boolean(scriptMatch));

if (scriptMatch) {
  try {
    new vm.Script(scriptMatch[1], { filename: "index.inline.js" });
    check("inline script parses", true);
  } catch (error) {
    check("inline script parses", false, error.message);
  }

  try {
    const appStub = { innerHTML: "" };
    const storage = new Map();
    const toastStub = {
      textContent: "",
      classList: {
        add() {},
        remove() {},
        toggle() {}
      }
    };
    const context = {
      document: {
        querySelector(selector) {
          if (selector === "#app") return appStub;
          if (selector === "#toast") return toastStub;
          return null;
        }
      },
      localStorage: {
        getItem(key) {
          return storage.has(key) ? storage.get(key) : null;
        },
        setItem(key, value) {
          storage.set(key, String(value));
        }
      },
      console: { warn() {} },
      window: {},
      clearTimeout() {},
      setTimeout() {}
    };
    vm.createContext(context);
    const behaviorScript = `
${scriptMatch[1]}
openReader("demon");
const continuedPage = state.readerPage;
openReader("demon", 4);
const newChapterPage = state.readerPage;
readerMove(1);
const movedPage = state.readerPage;
__behavior = { continuedPage, newChapterPage, movedPage, route: state.route, last: state.selected.last };
`;
    vm.runInContext(behaviorScript, context, { filename: "index.behavior.js" });
    check(
      "reader resume and chapter page behavior",
      context.__behavior.continuedPage === 3 &&
        context.__behavior.newChapterPage === 1 &&
        context.__behavior.movedPage === 2 &&
        context.__behavior.route === "reader" &&
        context.__behavior.last.includes("第205话"),
      JSON.stringify(context.__behavior)
    );
  } catch (error) {
    check("reader resume and chapter page behavior", false, error.message);
  }

  try {
    const appStub = { innerHTML: "" };
    const storage = new Map();
    const toastStub = {
      textContent: "",
      classList: {
        add() {},
        remove() {},
        toggle() {}
      }
    };
    const makeContext = () => ({
      document: {
        querySelector(selector) {
          if (selector === "#app") return appStub;
          if (selector === "#toast") return toastStub;
          return null;
        }
      },
      localStorage: {
        getItem(key) {
          return storage.has(key) ? storage.get(key) : null;
        },
        setItem(key, value) {
          storage.set(key, String(value));
        }
      },
      console: { warn() {} },
      window: {},
      URL,
      Date: { now: () => 1700000000000 },
      clearTimeout() {},
      setTimeout() {}
    });
    const firstContext = makeContext();
    vm.createContext(firstContext);
    vm.runInContext(
      `${scriptMatch[1]}
setSourceUrl("https://demo.example.com/path/");
addCustomSource();
const added = state.customSources[0];
toggleCustomSource(added.id);
const afterToggle = state.customSources[0].enabled;
setSourceUrl("demo.example.com");
addCustomSource();
__sourceBehavior = {
  count: state.customSources.length,
  domain: added.domain,
  url: added.url,
  afterToggle,
  duplicateToast: toastEl.textContent,
  saved: localStorage.getItem(storageKey)
};
`,
      firstContext,
      { filename: "index.source.first.js" }
    );
    const secondContext = makeContext();
    vm.createContext(secondContext);
    vm.runInContext(
      `${scriptMatch[1]}
__restoredSources = {
  count: state.customSources.length,
  domain: state.customSources[0]?.domain,
  enabled: state.customSources[0]?.enabled
};
`,
      secondContext,
      { filename: "index.source.second.js" }
    );
    check(
      "custom source add and persistence behavior",
      firstContext.__sourceBehavior.count === 1 &&
        firstContext.__sourceBehavior.domain === "demo.example.com" &&
        firstContext.__sourceBehavior.url === "https://demo.example.com/path" &&
        firstContext.__sourceBehavior.afterToggle === false &&
        firstContext.__sourceBehavior.duplicateToast === "该站源已存在" &&
        secondContext.__restoredSources.count === 1 &&
        secondContext.__restoredSources.domain === "demo.example.com" &&
        secondContext.__restoredSources.enabled === false,
      JSON.stringify({ first: firstContext.__sourceBehavior, second: secondContext.__restoredSources })
    );
  } catch (error) {
    check("custom source add and persistence behavior", false, error.message);
  }

  try {
    const appStub = { innerHTML: "" };
    const storage = new Map();
    const toastStub = {
      textContent: "",
      classList: {
        add() {},
        remove() {},
        toggle() {}
      }
    };
    const baseContext = () => ({
      document: {
        querySelector(selector) {
          if (selector === "#app") return appStub;
          if (selector === "#toast") return toastStub;
          return null;
        }
      },
      localStorage: {
        getItem(key) {
          return storage.has(key) ? storage.get(key) : null;
        },
        setItem(key, value) {
          storage.set(key, String(value));
        }
      },
      console: { warn() {} },
      window: {},
      clearTimeout() {},
      setTimeout() {}
    });
    const firstContext = baseContext();
    vm.createContext(firstContext);
    vm.runInContext(
      `${scriptMatch[1]}
toggleFav("onepiece");
toggleSource();
setChapterOrder("desc");
clearCache();
openReader("onepiece",4);
readerMove(1);
__saved = localStorage.getItem(storageKey);
`,
      firstContext,
      { filename: "index.persistence.first.js" }
    );
    const secondContext = baseContext();
    vm.createContext(secondContext);
    vm.runInContext(
      `${scriptMatch[1]}
__restored = {
  onepieceFav: comics.find(c=>c.id==="onepiece").fav,
  onepieceLast: comics.find(c=>c.id==="onepiece").last,
  onepieceProgress: comics.find(c=>c.id==="onepiece").progress,
  onepiecePage: comics.find(c=>c.id==="onepiece").progressPage,
  sourceOn: state.sourceOn,
  chapterOrder: state.chapterOrder,
  cacheSize: state.cacheSize
};
`,
      secondContext,
      { filename: "index.persistence.second.js" }
    );
    check(
      "local persistence restores user state",
      firstContext.__saved &&
        secondContext.__restored.onepieceFav === true &&
        secondContext.__restored.onepieceLast.includes("第1185话") &&
        secondContext.__restored.onepieceProgress === 4 &&
        secondContext.__restored.onepiecePage === 2 &&
        secondContext.__restored.sourceOn === false &&
        secondContext.__restored.chapterOrder === "desc" &&
        secondContext.__restored.cacheSize === "0 MB",
      JSON.stringify(secondContext.__restored)
    );
  } catch (error) {
    check("local persistence restores user state", false, error.message);
  }

  try {
    const appStub = { innerHTML: "" };
    const storage = new Map();
    const toastStub = {
      textContent: "",
      classList: {
        add() {},
        remove() {},
        toggle() {}
      }
    };
    const context = {
      document: {
        querySelector(selector) {
          if (selector === "#app") return appStub;
          if (selector === "#toast") return toastStub;
          return null;
        }
      },
      localStorage: {
        getItem(key) {
          return storage.has(key) ? storage.get(key) : null;
        },
        setItem(key, value) {
          storage.set(key, String(value));
        }
      },
      console: { warn() {} },
      window: {},
      clearTimeout() {},
      setTimeout() {}
    };
    vm.createContext(context);
    vm.runInContext(
      `${scriptMatch[1]}
goTab("search");
setSearchTag("黑暗");
const darkHtml = app.innerHTML;
setSearchQuery("航海王");
const emptyHtml = app.innerHTML;
setSearchTag("全部");
const allHtml = app.innerHTML;
__tagBehavior = {
  darkHasChainsaw: darkHtml.includes("电锯人"),
  darkHasTitan: darkHtml.includes("进击的巨人"),
  darkHidesDemon: !darkHtml.includes("鬼灭之刃"),
  emptyState: emptyHtml.includes("没有找到相关漫画"),
  allRestoresOnepiece: allHtml.includes("航海王")
};
`,
      context,
      { filename: "index.tag-filter.js" }
    );
    check(
      "search tag filter behavior",
      context.__tagBehavior.darkHasChainsaw &&
        context.__tagBehavior.darkHasTitan &&
        context.__tagBehavior.darkHidesDemon &&
        context.__tagBehavior.emptyState &&
        context.__tagBehavior.allRestoresOnepiece,
      JSON.stringify(context.__tagBehavior)
    );
  } catch (error) {
    check("search tag filter behavior", false, error.message);
  }
}

const failed = checks.filter((item) => !item.passed);

for (const item of checks) {
  const icon = item.passed ? "PASS" : "FAIL";
  console.log(`${icon} ${item.name}${!item.passed && item.detail ? ` - ${item.detail}` : ""}`);
}

if (failed.length) {
  console.error(`\n${failed.length} prototype check(s) failed.`);
  process.exit(1);
}

console.log(`\n${checks.length} prototype checks passed.`);

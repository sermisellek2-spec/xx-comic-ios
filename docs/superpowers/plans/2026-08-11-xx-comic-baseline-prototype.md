# XX Comic 1:1 Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 制作覆盖当前 XX Comic 全部视觉页面、主要交互和审阅状态的 1:1 浏览器原型，并在用户审核前保持 Android 业务代码不变。

**Architecture:** 使用仓库根目录的单文件 `index.html` 承载 CSS、固定模拟数据、内存状态和字符串模板渲染；本地位图放在 `prototype-assets/`。现有 `tools/check-prototype.js` 通过静态契约和 Node `vm` 行为测试验证页面、路由和状态，不增加框架或运行时依赖。

**Tech Stack:** HTML5、CSS3、原生 JavaScript、Node.js 标准库、现有 Android 视觉令牌、ImageGen 本地位图。

---

## 范围说明

本计划只实现 `?design=baseline`。Material 3 优化版必须等用户逐页审核 1:1 原型后再单独规划和实现。遇到未知 `design` 参数时回退到 `baseline`，不在本阶段添加空的 M3 页面、占位提示或未启用分支。

## 文件职责

- Create: `index.html` — 独立原型、审阅面板、手机画布、页面模板、状态和交互。
- Create: `prototype-assets/cover-night-record.png` — 暖色奇幻漫画封面。
- Create: `prototype-assets/cover-distant-sea.png` — 冷色海洋冒险漫画封面。
- Create: `prototype-assets/cover-green-court.png` — 绿色都市悬疑漫画封面。
- Create: `prototype-assets/cover-fireline.png` — 红黑动作漫画封面。
- Create: `prototype-assets/reader-page-1.png` — 黑白漫画阅读页。
- Create: `prototype-assets/reader-page-2.png` — 黑白漫画阅读页。
- Modify: `tools/check-prototype.js` — 与本设计一致的静态和行为契约。

不创建组件目录、构建配置、包管理文件、Web 框架入口或测试框架。

### Task 1: 建立失败契约和最小原型壳

**Files:**
- Create: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 将旧原型检查收敛为当前基线壳契约**

在 `tools/check-prototype.js` 中保留现有 `fs/path/vm` 标准库结构，将顶部静态检查替换为以下契约：

```js
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..");
const htmlPath = path.join(root, "index.html");
const html = fs.existsSync(htmlPath) ? fs.readFileSync(htmlPath, "utf8") : "";
const checks = [];

function check(name, passed, detail = "") {
  checks.push({ name, passed, detail });
}

function includesAll(name, values) {
  const missing = values.filter((value) => !html.includes(value));
  check(name, missing.length === 0, missing.length ? `missing: ${missing.join(", ")}` : "");
}

check("prototype exists", Boolean(html), "index.html is missing");
includesAll("prototype roots", [
  'id="review-controls"',
  'id="phone-shell"',
  'id="app"',
  'id="toast"',
  'data-design="baseline"'
]);
includesAll("review controls", ["日间", "夜间", "正常", "空状态", "加载", "错误", "360", "393", "430"]);
check("single app root", (html.match(/id="app"/g) || []).length === 1);
check("single toast root", (html.match(/id="toast"/g) || []).length === 1);
check("no runtime dependency", !/<script[^>]+src=|<link[^>]+href=["']https?:/i.test(html));
```

- [ ] **Step 2: 运行检查并确认按预期失败**

Run: `node tools/check-prototype.js`

Expected: FAIL，至少包含 `prototype exists - index.html is missing`。

- [ ] **Step 3: 创建可直接打开的最小 `index.html`**

创建以下完整文档壳；这一阶段只显示收藏页空状态，后续任务扩充渲染器：

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>XX Comic UI Prototype</title>
  <style>
    * { box-sizing: border-box; }
    :root { color-scheme: light; font-family: Arial, "Noto Sans CJK SC", sans-serif; }
    body { margin: 0; background: #ecebea; color: #1a1c1e; letter-spacing: 0; }
    button, input { font: inherit; letter-spacing: 0; }
    #review-controls { position: sticky; top: 0; z-index: 20; display: flex; flex-wrap: wrap; gap: 8px; padding: 12px; background: #fff; border-bottom: 1px solid #ddd; }
    #review-controls button { min-height: 44px; padding: 0 14px; border: 1px solid #ccc; border-radius: 8px; background: #fff; color: #1a1c1e; }
    .stage { display: grid; place-items: start center; min-height: calc(100vh - 69px); padding: 24px; overflow: auto; }
    #phone-shell { position: relative; width: min(393px, 100%); height: 873px; overflow: hidden; background: #fefcf8; border: 1px solid #d7d3ca; }
    #app { min-height: 100%; }
    #toast { position: absolute; left: 24px; right: 24px; bottom: 80px; display: none; padding: 12px 16px; border-radius: 8px; background: #1a1c1e; color: #fff; text-align: center; }
  </style>
</head>
<body data-design="baseline">
  <aside id="review-controls" aria-label="原型审阅控制">
    <button type="button">日间</button><button type="button">夜间</button>
    <button type="button">正常</button><button type="button">空状态</button>
    <button type="button">加载</button><button type="button">错误</button>
    <button type="button">360</button><button type="button">393</button><button type="button">430</button>
  </aside>
  <main class="stage">
    <section id="phone-shell" aria-label="XX Comic 手机原型">
      <div id="app"></div><div id="toast" role="status" aria-live="polite"></div>
    </section>
  </main>
  <script id="prototype-script">
    const app = document.getElementById("app");
    const toast = document.getElementById("toast");
    const state = { design: "baseline", route: "favorites", tab: "favorites", theme: "day", review: "normal" };
    function render() { app.innerHTML = '<section><h1>我的收藏</h1><p>书架还空着</p></section>'; }
    render();
    window.__prototype = { state, render };
  </script>
</body>
</html>
```

- [ ] **Step 4: 补齐检查脚本结尾并验证通过**

```js
const failed = checks.filter((item) => !item.passed);
for (const item of checks) {
  console.log(`${item.passed ? "PASS" : "FAIL"} ${item.name}${item.detail && !item.passed ? ` - ${item.detail}` : ""}`);
}
if (failed.length) process.exit(1);
console.log(`\n${checks.length} prototype checks passed.`);
```

Run: `node tools/check-prototype.js`

Expected: PASS，`0` 个失败。

- [ ] **Step 5: 提交原型壳**

```bash
git add index.html tools/check-prototype.js
git commit -m "test: define baseline prototype shell"
```

### Task 2: 生成并接入本地漫画视觉资产

**Files:**
- Create: `prototype-assets/cover-night-record.png`
- Create: `prototype-assets/cover-distant-sea.png`
- Create: `prototype-assets/cover-green-court.png`
- Create: `prototype-assets/cover-fireline.png`
- Create: `prototype-assets/reader-page-1.png`
- Create: `prototype-assets/reader-page-2.png`
- Modify: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 先增加资产失败检查**

```js
const requiredAssets = [
  "cover-night-record.png", "cover-distant-sea.png", "cover-green-court.png",
  "cover-fireline.png", "reader-page-1.png", "reader-page-2.png"
];
for (const file of requiredAssets) {
  const assetPath = path.join(root, "prototype-assets", file);
  check(`asset ${file}`, fs.existsSync(assetPath) && fs.statSync(assetPath).size > 10000);
  check(`asset reference ${file}`, html.includes(`prototype-assets/${file}`));
}
```

Run: `node tools/check-prototype.js`

Expected: FAIL，首个缺少的封面资产检查失败。

- [ ] **Step 2: 使用 `imagegen` 技能生成四张虚构封面**

四张图片均保存为 `900 × 1200` PNG，不出现现有漫画角色、品牌 Logo、水印或可读长文本。分别使用以下提示：

```text
cover-night-record.png: Vertical fictional Chinese comic cover, lone young adult walking through a rain-soaked city at night, amber street lights and deep blue shadows, crisp ink linework, editorial manga composition, title area left blank, no logos, no readable text.
cover-distant-sea.png: Vertical fictional comic cover, adventurous crew facing a vast stormy sea from a small ship, cool cyan and navy palette, clean inked illustration, strong silhouette, title area left blank, no logos, no readable text.
cover-green-court.png: Vertical fictional urban mystery comic cover, quiet courtyard overgrown with green plants, one investigator at a doorway, jade green and neutral gray palette, detailed line art, title area left blank, no logos, no readable text.
cover-fireline.png: Vertical fictional action comic cover, two adult rivals separated by sparks and diagonal red-black shapes, bold ink linework, restrained red accents, title area left blank, no logos, no readable text.
```

- [ ] **Step 3: 使用 `imagegen` 技能生成两张黑白阅读页**

两张图片均保存为 `1200 × 1800` PNG，人物为成年人，不含文字气泡内容：

```text
reader-page-1.png: Black-and-white fictional manga page, six clear panels, adult protagonist arriving at an abandoned train platform at night, cinematic ink work, screen-tone texture, empty speech balloons, no readable text, no existing characters.
reader-page-2.png: Black-and-white fictional manga page, five clear panels, adult protagonist discovers a glowing old ticket and looks down the empty tracks, cinematic ink work, screen-tone texture, empty speech balloons, no readable text, no existing characters.
```

- [ ] **Step 4: 在 `index.html` 中定义固定数据并引用全部资产**

```js
const comics = [
  { id: "night-record", title: "夜行录", author: "林川", latest: "第 42 话", status: "连载中", source: "包子漫画", cover: "prototype-assets/cover-night-record.png", tags: ["奇幻", "冒险"] },
  { id: "distant-sea", title: "远海纪事", author: "周远", latest: "第 87 话", status: "连载中", source: "漫画柜", cover: "prototype-assets/cover-distant-sea.png", tags: ["冒险", "热血"] },
  { id: "green-court", title: "青庭", author: "许青", latest: "第 18 话", status: "连载中", source: "爱看漫画", cover: "prototype-assets/cover-green-court.png", tags: ["悬疑", "都市"] },
  { id: "fireline", title: "火线回声", author: "陈默", latest: "第 56 话", status: "已完结", source: "漫画柜", cover: "prototype-assets/cover-fireline.png", tags: ["动作", "剧情"] }
];
const readerPages = ["prototype-assets/reader-page-1.png", "prototype-assets/reader-page-2.png"];
```

- [ ] **Step 5: 运行检查并提交资产**

Run: `node tools/check-prototype.js`

Expected: PASS，六个资产存在、大小超过 `10KB` 且被 HTML 引用。

```bash
git add prototype-assets index.html tools/check-prototype.js
git commit -m "feat: add local prototype artwork"
```

### Task 3: 实现四个主页面和底部导航

**Files:**
- Modify: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 增加主页面静态与行为检查**

```js
includesAll("primary pages", ["我的收藏", "搜索结果", "站源管理", "我的"]);
includesAll("bottom navigation", [
  'data-testid="nav-favorites"', 'data-testid="nav-search"',
  'data-testid="nav-sources"', 'data-testid="nav-profile"'
]);
includesAll("primary handlers", ["function goTab(", "renderFavorites", "renderSearch", "renderSources", "renderProfile"]);

const scriptMatch = html.match(/<script id="prototype-script">([\s\S]*?)<\/script>/);
check("prototype script exists", Boolean(scriptMatch));
if (scriptMatch) {
  const appStub = { innerHTML: "" };
  const stubs = {
    app: appStub,
    toast: { style: {}, textContent: "" },
    "phone-shell": { style: {}, dataset: {} }
  };
  const context = {
    document: { getElementById: (id) => stubs[id] || { style: {}, dataset: {} }, body: { dataset: {} } },
    window: {}, location: { search: "?design=baseline" }, URLSearchParams,
    setTimeout: (fn) => fn(), clearTimeout() {}
  };
  vm.createContext(context);
  vm.runInContext(scriptMatch[1], context, { filename: "index.inline.js" });
  context.window.__prototype.goTab("search");
  check("tab route changes", context.window.__prototype.state.route === "search");
  check("search page renders", appStub.innerHTML.includes("搜索结果"));
}
```

Run: `node tools/check-prototype.js`

Expected: FAIL，缺少导航测试 ID 或 `goTab`。

- [ ] **Step 2: 扩展状态与统一底部导航**

```js
Object.assign(state, {
  route: "favorites", tab: "favorites", query: "", selectedComicId: "night-record",
  favorites: ["night-record", "green-court"], history: ["night-record", "distant-sea"],
  sourceEnabled: { baozi: true, manhuagui: true, aikan: true, fiveum: false },
  selectedSource: "all", filters: { region: "全部", status: "全部" },
  returnRoute: "favorites", revealedFavoriteId: null, pagination: "idle", handedness: "right", overlay: null, dialog: null,
  readerChapter: 0, readerPage: 0, readerToolsVisible: true, readerFullscreen: false
});

const tabs = [
  ["favorites", "♡", "收藏"], ["search", "⌕", "搜索"],
  ["sources", "▣", "站源"], ["profile", "○", "我的"]
];

function bottomNav() {
  return `<nav class="bottom-nav" aria-label="主导航">${tabs.map(([id, icon, label]) => `
    <button type="button" data-testid="nav-${id}" class="nav-item ${state.tab === id ? "selected" : ""}" onclick="goTab('${id}')">
      <span class="nav-icon" aria-hidden="true">${icon}</span><span>${label}</span>
    </button>`).join("")}</nav>`;
}

function goTab(tab) {
  state.tab = tab;
  state.route = tab;
  state.returnRoute = tab;
  state.overlay = null;
  state.dialog = null;
  render();
}
```

- [ ] **Step 3: 实现四个明确的主页面模板**

每个函数必须返回完整页面内容，不创建通用卡片抽象：

```js
function renderFavorites() {
  const items = state.favorites.map((id) => comics.find((comic) => comic.id === id)).filter(Boolean);
  return `<section class="page favorites-page"><h1>我的收藏</h1>
    <button type="button" class="search-entry" onclick="openGlobalSearch()">⌕　搜索漫画名称或作者</button>
    <div class="page-scroll">${items.length ? items.map(favoriteRow).join("") : emptyState("♡", "书架还空着", "等你把第一本放进来", "去搜索", "goTab('search')")}</div>
  </section>`;
}

function renderSearch() {
  return `<section class="page search-page"><label class="search-box">⌕<input data-testid="search-input" value="${state.query}" placeholder="搜索漫画名称或作者"></label>
    <button type="button" class="filter-trigger" onclick="openOverlay('filter')">▾ 包子漫画 · 全部</button>
    <h2>搜索结果</h2><div class="page-scroll comic-grid">${comics.map(resultCard).join("")}</div></section>`;
}

function renderSources() {
  const rows = [["baozi","包子漫画","cn.bzmgcn.com"],["manhuagui","漫画柜","manhuagui.com"],["aikan","爱看漫画","0592cr.com"],["fiveum","拷贝漫画","www.fiveum.com"]];
  return `<section class="page"><header class="page-title-row"><h1>站源管理</h1><button type="button" aria-label="站源菜单" onclick="openOverlay('source-menu')">⋮</button></header>
    <div class="page-scroll">${rows.map(([id,name,domain]) => sourceCard(id,name,domain)).join("")}</div></section>`;
}

function renderProfile() {
  return `<section class="page"><h1>我的</h1><div class="menu-card">
    ${profileItem("阅读历史", "", "openHistory()")}${profileItem("主题模式", state.theme === "night" ? "夜间" : "日间", "toggleTheme()")}
    ${profileItem("左右手模式", state.handedness === "right" ? "右手" : "左手", "toggleHandedness()")}${profileItem("缓存清理", "42.6 MB", "openDialog('cache')")}
    ${profileItem("错误日志", "无", "openDialog('logs')")}${profileItem("关于 App", "1.0.3", "openDialog('about')")}
  </div></section>`;
}
```

- [ ] **Step 4: 定义主页面直接使用的行、卡片和空壳浮层函数**

这些函数必须与四个页面一起落地，避免首次 `render()` 引用后续任务才定义的名称。收藏行保留可触摸侧滑和键盘可访问的删除入口：

```js
let favoriteSwipeStartX = 0;
let favoriteSwipeMoved = false;
function favoriteRow(comic) {
  const revealed = state.revealedFavoriteId === comic.id;
  return `<article class="favorite-row ${revealed ? "revealed" : ""}">
    <button class="favorite-delete" onclick="toggleFavorite('${comic.id}')">删除</button>
    <button class="favorite-content" onpointerdown="startFavoriteSwipe(event)" onpointerup="endFavoriteSwipe(event,'${comic.id}')" onclick="openFavorite('${comic.id}')">
      <img src="${comic.cover}" alt="${comic.title}封面"><span><b>${comic.title}</b><small>${comic.latest} · ${comic.source}</small></span>
    </button><button class="favorite-more" aria-label="显示删除操作" onclick="toggleFavoriteActions('${comic.id}')">⋮</button></article>`;
}
function startFavoriteSwipe(event) { favoriteSwipeStartX = event.clientX; favoriteSwipeMoved = false; }
function endFavoriteSwipe(event, id) {
  if (favoriteSwipeStartX - event.clientX > 36) { state.revealedFavoriteId = id; favoriteSwipeMoved = true; }
  if (event.clientX - favoriteSwipeStartX > 36) { state.revealedFavoriteId = null; favoriteSwipeMoved = true; }
  render();
}
function openFavorite(id) { if (favoriteSwipeMoved) { favoriteSwipeMoved = false; return; } openDetail(id); }
function toggleFavoriteActions(id) { state.revealedFavoriteId = state.revealedFavoriteId === id ? null : id; render(); }
function resultCard(comic) {
  return `<button class="result-card" onclick="openDetail('${comic.id}')"><img src="${comic.cover}" alt="${comic.title}封面"><b>${comic.title}</b><small>${comic.latest} · ${comic.source}</small></button>`;
}
function sourceCard(id, name, domain) {
  const enabled = state.sourceEnabled[id];
  return `<article class="source-card"><span><b>${name}</b><small>${domain}</small><em>${enabled ? "已启用" : "已停用"}</em></span><button role="switch" aria-checked="${enabled}" onclick="toggleSource('${id}')">${enabled ? "开" : "关"}</button></article>`;
}
function profileItem(label, value, handler) {
  return `<button class="profile-item" onclick="${handler}"><span>${label}</span><small>${value}</small><span aria-hidden="true">›</span></button>`;
}
function renderOverlay() { return ""; }
function renderDialog() { return ""; }
```

为 `.favorite-row` 设置 `position:relative;overflow:hidden`，`.favorite-delete` 固定在右侧 `72px` 区域，`.favorite-content` 在 `.revealed` 状态平移 `-72px`；按钮触控区不小于 `44px`。

- [ ] **Step 5: 在 `render()` 中组合页面和底部导航**

```js
function render() {
  const routes = { favorites: renderFavorites, search: renderSearch, sources: renderSources, profile: renderProfile };
  const page = (routes[state.route] || renderFavorites)();
  app.innerHTML = `<div class="app-shell">${page}${bottomNav()}${renderOverlay()}${renderDialog()}</div>`;
}
window.__prototype = { state, render, goTab };
```

为 `.page`、`.page-scroll`、`.bottom-nav`、`.comic-grid`、`.favorite-row`、`.source-card`、`.menu-card` 添加与设计文档一致的基线 CSS：`20dp` 页面留白、`64dp` 底栏、`12dp` 卡片圆角、日间基线色和固定滚动区域。

- [ ] **Step 6: 运行检查并提交主页面**

Run: `node tools/check-prototype.js`

Expected: PASS，行为检查确认 `favorites → search`。

```bash
git add index.html tools/check-prototype.js
git commit -m "feat: add baseline primary screens"
```

### Task 4: 实现全局搜索、筛选、详情和错误状态

**Files:**
- Modify: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 增加搜索到详情的失败行为测试**

在 VM 行为块中追加：

```js
const api = context.window.__prototype;
api.openGlobalSearch();
check("global search opens", api.state.route === "global-search");
api.submitGlobalSearch("夜行录");
check("global results open", api.state.route === "global-results" && api.state.query === "夜行录");
api.setGlobalSource("baozi");
check("global source changes", api.state.selectedSource === "baozi" && appStub.innerHTML.includes("包子漫画结果"));
api.openDetail("night-record");
check("detail opens", api.state.route === "detail" && appStub.innerHTML.includes("夜行录"));
api.goBackFromDetail();
check("detail returns to source", api.state.route === "global-results");
api.openDetail("night-record");
api.openOverlay("filter");
check("filter opens", api.state.overlay === "filter" && appStub.innerHTML.includes("筛选"));
api.setFilter("region", "日本");
check("filter changes", api.state.filters.region === "日本");
api.setReviewState("error");
check("detail error state", appStub.innerHTML.includes("详情加载失败"));
api.setReviewState("normal");
api.goTab("search");
api.setPagination("error");
check("pagination retry keeps results", appStub.innerHTML.includes("夜行录") && appStub.innerHTML.includes("加载失败，点击重试"));
```

Run: `node tools/check-prototype.js`

Expected: FAIL，`openGlobalSearch is not a function`。

- [ ] **Step 2: 添加全局搜索和分站结果模板**

```js
function openGlobalSearch() { state.route = "global-search"; state.overlay = null; render(); }
function submitGlobalSearch(query) { state.query = query.trim() || "夜行录"; state.route = "global-results"; render(); }
function setGlobalSource(source) { state.selectedSource = source; render(); }
function selectedSourceLabel() {
  return { all: "全部站源", baozi: "包子漫画", manhuagui: "漫画柜", aikan: "爱看漫画" }[state.selectedSource] || "全部站源";
}
function renderGlobalSearch() {
  return `<section class="page"><header class="top-bar"><button onclick="goTab('favorites')" aria-label="返回">‹</button><h1>全局搜索</h1></header>
    <label class="search-box">⌕<input value="${state.query}" onkeydown="if(event.key==='Enter')submitGlobalSearch(this.value)" placeholder="搜索全部站源"></label>
    <h2>搜索历史</h2><button class="history-chip" onclick="submitGlobalSearch('夜行录')">夜行录</button></section>`;
}
function renderGlobalResults() {
  return `<section class="page"><header class="top-bar"><button onclick="openGlobalSearch()" aria-label="返回">‹</button><h1>${state.query}</h1></header>
    <div class="source-tabs"><button onclick="setGlobalSource('all')" class="${state.selectedSource === "all" ? "selected" : ""}">全部</button><button onclick="setGlobalSource('baozi')" class="${state.selectedSource === "baozi" ? "selected" : ""}">包子漫画</button><button onclick="setGlobalSource('manhuagui')" class="${state.selectedSource === "manhuagui" ? "selected" : ""}">漫画柜</button><button onclick="setGlobalSource('aikan')" class="${state.selectedSource === "aikan" ? "selected" : ""}">爱看漫画</button></div>
    <p class="source-result-label">${selectedSourceLabel()}结果</p>
    <div class="page-scroll">${comics.map(globalResultRow).join("")}<p class="result-status">4 个站源已完成 · 0 个失败</p></div></section>`;
}
function globalResultRow(comic) {
  return `<button class="global-result-row" onclick="openDetail('${comic.id}')"><img src="${comic.cover}" alt="${comic.title}封面"><span><b>${comic.title}</b><small>${comic.author} · ${comic.source}</small></span></button>`;
}
```

- [ ] **Step 3: 添加筛选抽屉与详情模板**

```js
function openOverlay(name) { state.overlay = name; render(); }
function closeOverlay() { state.overlay = null; render(); }
function openDetail(id) { state.selectedComicId = id; state.returnRoute = state.route; state.route = "detail"; state.overlay = null; render(); }
function goBackFromDetail() { state.route = state.returnRoute || state.tab; render(); }
function selectedComic() { return comics.find((comic) => comic.id === state.selectedComicId) || comics[0]; }
function setFilter(key, value) { state.filters[key] = value; render(); }
function resetFilters() { state.selectedSource = "all"; state.filters = { region: "全部", status: "全部" }; closeOverlay(); }
function setReviewState(review) { state.review = review; render(); }
function setPagination(status) { state.pagination = status; render(); }
function refreshResults() { state.pagination = "loading"; render(); setTimeout(() => { state.pagination = "idle"; render(); }, 450); }
function retryPagination() { setPagination("idle"); }
function loadingState(title, description) {
  return `<section class="state-page" aria-busy="true"><div class="skeleton-list">${Array.from({length:4}, () => '<div class="skeleton-row"><i></i><span></span></div>').join("")}</div><h1>${title}</h1><p>${description}</p></section>`;
}
function errorState(title, description, retry) {
  return `<section class="error-state"><h1>${title}</h1><p>${description}</p><button onclick="${retry}">重试</button></section>`;
}
function paginationFooter() {
  if (state.pagination === "loading") return '<div class="pagination-state" aria-busy="true">正在加载更多…</div>';
  if (state.pagination === "error") return '<button class="pagination-state" onclick="retryPagination()">加载失败，点击重试</button>';
  return '<button class="pagination-state" onclick="setPagination(\'loading\')">加载更多</button>';
}

function renderFilterSheet() {
  return `<div class="scrim" onclick="closeOverlay()"></div><aside class="bottom-sheet" role="dialog" aria-label="搜索筛选">
    <div class="sheet-handle"></div><h2>筛选</h2><h3>站源</h3><div class="chip-row"><button onclick="setGlobalSource('baozi')" class="chip ${state.selectedSource === "baozi" ? "selected" : ""}">包子漫画</button><button onclick="setGlobalSource('manhuagui')" class="chip ${state.selectedSource === "manhuagui" ? "selected" : ""}">漫画柜</button></div>
    <h3>地区</h3><div class="chip-row"><button onclick="setFilter('region','全部')" class="chip ${state.filters.region === "全部" ? "selected" : ""}">全部</button><button onclick="setFilter('region','日本')" class="chip ${state.filters.region === "日本" ? "selected" : ""}">日本</button><button onclick="setFilter('region','韩国')" class="chip ${state.filters.region === "韩国" ? "selected" : ""}">韩国</button></div>
    <h3>状态</h3><div class="chip-row"><button onclick="setFilter('status','全部')" class="chip ${state.filters.status === "全部" ? "selected" : ""}">全部</button><button onclick="setFilter('status','连载中')" class="chip ${state.filters.status === "连载中" ? "selected" : ""}">连载中</button><button onclick="setFilter('status','已完结')" class="chip ${state.filters.status === "已完结" ? "selected" : ""}">已完结</button></div>
    <button class="secondary-button" onclick="resetFilters()">清空筛选</button></aside>`;
}

function renderDetail() {
  if (state.review === "loading") return loadingState("正在加载详情", "正在获取漫画信息。");
  if (state.review === "error") return errorState("详情加载失败", "站源暂时不可用", "setReviewState('normal')");
  const comic = selectedComic();
  return `<section class="detail-page"><div class="detail-hero" style="background-image:url('${comic.cover}')"><button onclick="goBackFromDetail()" aria-label="返回">‹</button></div>
    <div class="detail-body"><article class="detail-card"><img src="${comic.cover}" alt="${comic.title}封面"><div><h1>${comic.title}</h1><p>${comic.author} · ${comic.status} · ${comic.source}</p><div>${comic.tags.map((tag) => `<span class="detail-tag">${tag}</span>`).join("")}</div></div><p class="description">一段用于核对当前详情排版、行距和信息层级的固定漫画简介。</p></article>
    <div class="detail-actions"><button onclick="toggleFavorite('${comic.id}')">收藏</button><button class="brand-button" onclick="openReader(0)">开始阅读</button></div>
    <button class="chapter-entry" onclick="openOverlay('chapters')"><span><b>章节目录</b><small>共 42 章 · 最新第 42 话</small></span><span>›</span></button></div></section>`;
}
```

- [ ] **Step 4: 扩展搜索结果、`render()` 路由和浮层映射**

把 `renderSearch()` 替换为带有刷新手势、可访问刷新按钮和分页状态的版本；指针下拉超过 `48px` 时调用同一个刷新函数：

```js
let pullStartY = 0;
function startPull(event) { pullStartY = event.clientY; }
function endPull(event) { if (event.clientY - pullStartY > 48) refreshResults(); }
function renderSearch() {
  if (state.review === "loading") return loadingState("正在搜索漫画", "正在汇总已启用站源。");
  if (state.review === "error") return errorState("搜索失败", "站源暂时不可用", "setReviewState('normal')");
  const cards = state.review === "empty" ? "" : comics.map(resultCard).join("");
  return `<section class="page search-page"><label class="search-box">⌕<input data-testid="search-input" value="${state.query}" onchange="state.query=this.value" placeholder="搜索漫画名称或作者"></label>
    <div class="search-tools"><button class="filter-trigger" onclick="openOverlay('filter')">▾ ${selectedSourceLabel()} · ${state.filters.region}</button><button aria-label="刷新搜索结果" onclick="refreshResults()">↻</button></div>
    <h2>搜索结果</h2><div class="page-scroll" onpointerdown="startPull(event)" onpointerup="endPull(event)">${cards ? `<div class="comic-grid">${cards}</div>${paginationFooter()}` : emptyState("⌕", "没找到这本漫画", "换个关键词，或清空题材筛选再试", "清空筛选", "setReviewState('normal')")}</div></section>`;
}
function renderOverlay() {
  if (state.overlay === "filter") return renderFilterSheet();
  return "";
}
function render() {
  const routes = { favorites: renderFavorites, search: renderSearch, sources: renderSources, profile: renderProfile,
    "global-search": renderGlobalSearch, "global-results": renderGlobalResults, detail: renderDetail };
  const page = (routes[state.route] || renderFavorites)();
  const primaryRoute = ["favorites", "search", "sources", "profile"].includes(state.route);
  app.innerHTML = `<div class="app-shell">${page}${primaryRoute ? bottomNav() : ""}${renderOverlay()}${renderDialog()}</div>`;
}
```

导出以下实际函数：

```js
Object.assign(window.__prototype, {
  openGlobalSearch, submitGlobalSearch, setGlobalSource, openDetail, goBackFromDetail,
  openOverlay, closeOverlay, setFilter, resetFilters, setReviewState, setPagination, refreshResults, retryPagination
});
```

- [ ] **Step 5: 运行检查并提交搜索详情流**

Run: `node tools/check-prototype.js`

Expected: PASS，搜索、详情、筛选和错误态断言全部通过。

```bash
git add index.html tools/check-prototype.js
git commit -m "feat: add baseline search and detail flow"
```

### Task 5: 实现阅读器与章节抽屉

**Files:**
- Modify: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 增加阅读器状态失败测试**

```js
api.setReviewState("normal");
api.openDetail("night-record");
api.openReader(0);
check("reader opens", api.state.route === "reader" && api.state.readerPage === 0);
api.readerMove(1);
check("reader advances", api.state.readerPage === 1);
api.readerMove(1);
check("reader clamps", api.state.readerPage === 1);
api.toggleReaderTools();
check("reader tools toggle", api.state.readerToolsVisible === false);
api.toggleReaderFullscreen();
check("reader fullscreen", api.state.readerFullscreen === true);
api.openOverlay("chapters");
check("chapter sheet opens", appStub.innerHTML.includes("章节目录") && appStub.innerHTML.includes("第 42 话"));
```

Run: `node tools/check-prototype.js`

Expected: FAIL，`openReader is not a function`。

- [ ] **Step 2: 实现阅读状态函数**

```js
function openReader(chapterIndex) {
  state.route = "reader";
  state.readerChapter = Math.max(0, Math.min(41, chapterIndex));
  state.readerPage = 0;
  state.readerToolsVisible = true;
  state.readerFullscreen = false;
  render();
}
function readerMove(delta) {
  state.readerPage = Math.max(0, Math.min(readerPages.length - 1, state.readerPage + delta));
  render();
}
function switchChapter(delta) {
  state.readerChapter = Math.max(0, Math.min(41, state.readerChapter + delta));
  state.readerPage = 0;
  render();
}
function toggleReaderTools() { state.readerToolsVisible = !state.readerToolsVisible; render(); }
function toggleReaderFullscreen() { state.readerFullscreen = !state.readerFullscreen; render(); }
function returnToDetail() { state.route = "detail"; state.overlay = null; render(); }
```

- [ ] **Step 3: 实现阅读器和章节抽屉模板**

```js
function renderReader() {
  if (state.review === "loading") return loadingState("正在加载章节", "漫画图片马上就绪。");
  if (state.review === "error") return errorState("图片加载失败", "请检查网络后重试", "setReviewState('normal')");
  return `<section class="reader ${state.readerFullscreen ? "fullscreen" : ""} ${state.readerToolsVisible ? "tools-visible" : "tools-hidden"}">
    <header class="reader-top"><button onclick="returnToDetail()" aria-label="返回">‹</button><span>第 ${state.readerChapter + 1} 话</span><button onclick="openOverlay('chapters')" aria-label="章节目录">☷</button></header>
    <button class="reader-image" onclick="toggleReaderTools()" aria-label="显示或隐藏阅读工具"><img src="${readerPages[state.readerPage]}" alt="漫画第 ${state.readerPage + 1} 页"></button>
    <footer class="reader-bottom"><button onclick="switchChapter(-1)">上一章</button><span>${state.readerPage + 1} / ${readerPages.length}</span><button onclick="switchChapter(1)">下一章</button><button onclick="toggleReaderFullscreen()">${state.readerFullscreen ? "退出全屏" : "全屏"}</button><div class="reader-progress"><i style="width:${(state.readerPage + 1) / readerPages.length * 100}%"></i></div></footer>
  </section>`;
}
function renderChapterSheet() {
  if (state.review === "loading") return `<div class="scrim" onclick="closeOverlay()"></div><aside class="chapter-sheet" role="dialog" aria-label="章节目录">${loadingState("正在加载目录", "正在获取章节列表。")}</aside>`;
  if (state.review === "error") return `<div class="scrim" onclick="closeOverlay()"></div><aside class="chapter-sheet" role="dialog" aria-label="章节目录">${errorState("目录加载失败", "请稍后重试", "setReviewState('normal')")}</aside>`;
  const rows = Array.from({ length: 12 }, (_, index) => `<button onclick="closeOverlay();openReader(${41 - index})"><span>第 ${42 - index} 话</span><small>${index === 0 ? "最新" : index === 1 ? "已读" : ""}</small></button>`).join("");
  return `<div class="scrim" onclick="closeOverlay()"></div><aside class="chapter-sheet" role="dialog" aria-label="章节目录"><header><div><h2>章节目录</h2><p>42 章</p></div><button>正序</button></header><div class="chapter-list">${rows}</div></aside>`;
}
```

- [ ] **Step 4: 导出阅读 API、运行检查并提交**

把 `reader: renderReader` 加入 `render()` 的路由映射，并把 `renderOverlay()` 替换为：

```js
function renderOverlay() {
  if (state.overlay === "filter") return renderFilterSheet();
  if (state.overlay === "chapters") return renderChapterSheet();
  return "";
}
```

```js
Object.assign(window.__prototype, { openReader, readerMove, switchChapter, toggleReaderTools, toggleReaderFullscreen, returnToDetail });
```

Run: `node tools/check-prototype.js`

Expected: PASS，阅读页边界、全屏和章节抽屉断言通过。

```bash
git add index.html tools/check-prototype.js
git commit -m "feat: add baseline reader prototype"
```

### Task 6: 完成站源、历史、弹窗和剩余交互

**Files:**
- Modify: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 增加站源、历史和弹窗失败测试**

```js
api.goTab("sources");
api.toggleSource("baozi");
check("source toggles", api.state.sourceEnabled.baozi === false && appStub.innerHTML.includes("已停用"));
api.openHistory();
check("history opens", api.state.route === "history" && appStub.innerHTML.includes("阅读历史"));
api.openDialog("about");
check("about dialog opens", api.state.dialog === "about" && appStub.innerHTML.includes("XX Comic 已接入多个漫画站源"));
api.closeDialog();
check("dialog closes", api.state.dialog === null);
api.toggleHandedness();
check("handedness toggles", api.state.handedness === "left");
api.toggleFavorite("night-record");
check("favorite toggles", !api.state.favorites.includes("night-record"));
```

Run: `node tools/check-prototype.js`

Expected: FAIL，`toggleSource is not a function`。

- [ ] **Step 2: 实现剩余状态操作**

```js
function toggleSource(id) { state.sourceEnabled[id] = !state.sourceEnabled[id]; render(); }
function openHistory() { state.route = "history"; state.dialog = null; render(); }
function openDialog(name) { state.dialog = name; render(); }
function closeDialog() { state.dialog = null; render(); }
function toggleHandedness() {
  state.handedness = state.handedness === "right" ? "left" : "right";
  showToast(state.handedness === "right" ? "已切换为右手模式" : "已切换为左手模式");
  render();
}
function toggleFavorite(id) {
  state.favorites = state.favorites.includes(id) ? state.favorites.filter((item) => item !== id) : [id, ...state.favorites];
  showToast(state.favorites.includes(id) ? "已加入收藏" : "已取消收藏");
  render();
}
function showToast(message) {
  toast.textContent = message;
  toast.style.display = "block";
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => { toast.style.display = "none"; }, 1800);
}
function confirmDialog() {
  if (state.dialog === "clear-history") state.history = [];
  if (state.dialog === "cache") showToast("缓存已清理");
  closeDialog();
}
```

- [ ] **Step 3: 实现历史、站源菜单和对话框模板**

```js
function renderHistory() {
  return `<section class="page"><header class="top-bar"><button onclick="goTab('profile')" aria-label="返回">‹</button><h1>阅读历史</h1><button onclick="openDialog('clear-history')">清空</button></header>
    <div class="page-scroll">${state.history.map((id) => historyRow(comics.find((comic) => comic.id === id))).join("")}</div></section>`;
}
function historyRow(comic) {
  return `<button class="history-row" onclick="openDetail('${comic.id}')"><img src="${comic.cover}" alt="${comic.title}封面"><span><b>${comic.title}</b><small>读至 ${comic.latest} · ${comic.source}</small></span></button>`;
}
const dialogContent = {
  cache: ["缓存清理", "确认清理图片与详情缓存吗？", "清理"],
  logs: ["错误日志", "暂无错误日志。", "关闭"],
  about: ["关于 App", "XX Comic 已接入多个漫画站源，支持搜索、详情、阅读图片和本地缓存。", "知道了"],
  "source-error": ["站源检测失败", "拷贝漫画暂时无法连接，请稍后重试。", "关闭"],
  "clear-history": ["清空阅读历史", "该操作不会删除收藏。", "清空"]
};
function renderDialog() {
  if (!state.dialog) return "";
  const [title, body, action] = dialogContent[state.dialog];
  const confirm = ["cache", "clear-history"].includes(state.dialog);
  return `<div class="dialog-scrim"><section class="dialog" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><h2 id="dialog-title">${title}</h2><p>${body}</p><div>${confirm ? '<button onclick="closeDialog()">取消</button>' : ""}<button onclick="${confirm ? "confirmDialog()" : "closeDialog()"}">${action}</button></div></section></div>`;
}
function renderSourceMenu() {
  return `<div class="scrim" onclick="closeOverlay()"></div><div class="popup-menu" role="menu"><button onclick="showToast('站源配置已导出');closeOverlay()">导出配置</button><button onclick="showToast('请选择配置文件');closeOverlay()">导入配置</button><button onclick="showToast('站源检测完成');closeOverlay()">检测可用性</button></div>`;
}
```

- [ ] **Step 4: 运行检查并提交完整交互面**

把 `history: renderHistory` 加入 `render()` 路由映射；将 `renderOverlay()` 扩展为 `filter`、`chapters`、`source-menu` 三个分支，并导出本任务新增的行为：

```js
function renderOverlay() {
  if (state.overlay === "filter") return renderFilterSheet();
  if (state.overlay === "chapters") return renderChapterSheet();
  if (state.overlay === "source-menu") return renderSourceMenu();
  return "";
}
Object.assign(window.__prototype, {
  toggleSource, openHistory, openDialog, closeDialog, confirmDialog,
  toggleHandedness, toggleFavorite, showToast
});
```

Run: `node tools/check-prototype.js`

Expected: PASS，站源、历史、弹窗和收藏状态断言通过。

```bash
git add index.html tools/check-prototype.js
git commit -m "feat: complete baseline secondary screens"
```

### Task 7: 加入稳定审阅入口、夜间主题、响应式和无障碍约束

**Files:**
- Modify: `index.html`
- Modify: `tools/check-prototype.js`

- [ ] **Step 1: 增加主题、状态和设计参数失败测试**

```js
check("baseline design tokens", html.includes("--bg:#fefcf8") && html.includes("--night-bg:#15151a"));
includesAll("review handlers", ["function setTheme(", "function setReviewState(", "function setViewport(", "function setReviewRoute(", "function setReviewLayer("]);
includesAll("responsive widths", ["setViewport(360)", "setViewport(393)", "setViewport(430)"]);
includesAll("stable review routes", ["global-search", "global-results", "detail", "reader", "history", "source-menu", "source-error"]);
includesAll("accessible labels", ['aria-label="返回"', 'aria-label="章节目录"', 'aria-live="polite"', 'aria-modal="true"']);
check("no negative letter spacing", !/letter-spacing\s*:\s*-/.test(html));
```

在 VM 行为块中追加：

```js
api.setTheme("night");
check("night theme changes", api.state.theme === "night" && context.document.body.dataset.theme === "night");
api.setReviewState("empty");
api.goTab("search");
check("empty search renders", appStub.innerHTML.includes("没找到这本漫画"));
api.setViewport(360);
check("viewport changes", stubs["phone-shell"].style.width === "360px");
api.setReviewRoute("history");
check("review route changes", api.state.route === "history");
api.setReviewLayer("source-error");
check("review dialog opens", api.state.dialog === "source-error" && appStub.innerHTML.includes("站源检测失败"));
```

Run: `node tools/check-prototype.js`

Expected: FAIL，缺少夜间令牌或 `setTheme`。

- [ ] **Step 2: 定义完整日夜令牌和固定尺寸**

```css
:root {
  --bg:#fefcf8; --surface:#f8f5ee; --card:#fffcf6; --text:#1a1c1e;
  --text-2:#4a4d52; --text-3:#8b8e94; --border:#e8e3d7; --brand:#d97706;
  --night-bg:#15151a; --night-surface:#1c1c22; --night-card:#22222a; --night-text:#e8e4dc;
  --night-text-2:#b8b4ac; --night-text-3:#84827c; --night-border:#2d2d34; --night-brand:#f59e0b;
}
body[data-theme="night"] #phone-shell { --bg:var(--night-bg); --surface:var(--night-surface); --card:var(--night-card); --text:var(--night-text); --text-2:var(--night-text-2); --text-3:var(--night-text-3); --border:var(--night-border); --brand:var(--night-brand); }
#phone-shell, .app-shell, .page { background:var(--bg); color:var(--text); }
.page p, .page small, .page input { color:var(--text-2); }
.page button, .dialog, .bottom-sheet, .chapter-sheet, .popup-menu { color:var(--text); }
.dialog, .bottom-sheet, .chapter-sheet, .popup-menu, .bottom-nav { background:var(--card); color:var(--text); }
.search-box, .page input, .secondary-button, .profile-item { background-color:var(--surface); border-color:var(--border); }
.result-card { min-width:0; padding:10px; border-radius:12px; background:var(--card); }
.result-card img { width:100%; height:auto; aspect-ratio:150/202; object-fit:cover; border-radius:8px; }
.comic-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }
.icon-button { width:48px; height:48px; }
button, select, input { min-height:44px; max-width:100%; }
button, .profile-item { white-space:normal; overflow-wrap:anywhere; }
@media (max-width:379px) { #review-controls { position:static; } .stage { padding:12px; } }
```

- [ ] **Step 3: 实现审阅操作和确定性状态模板**

```js
function setTheme(theme) { state.theme = theme; document.body.dataset.theme = theme; render(); }
function toggleTheme() { setTheme(state.theme === "night" ? "day" : "night"); }
function setViewport(width) { document.getElementById("phone-shell").style.width = `${Math.max(360, Math.min(430, width))}px`; }
function setReviewRoute(route) {
  state.route = route;
  if (["favorites", "search", "sources", "profile"].includes(route)) state.tab = route;
  state.returnRoute = route;
  state.overlay = null;
  state.dialog = null;
  render();
}
function setReviewLayer(name) {
  state.overlay = ["filter", "chapters", "source-menu"].includes(name) ? name : null;
  state.dialog = ["cache", "logs", "about", "clear-history", "source-error"].includes(name) ? name : null;
  render();
}
function emptyState(icon, title, description, action, handler) {
  return `<div class="empty-state"><span aria-hidden="true">${icon}</span><h2>${title}</h2><p>${description}</p><button onclick="${handler}">${action}</button></div>`;
}
```

`setReviewState()`、`loadingState()` 和 `errorState()` 已在 Task 4 定义，本任务不重复声明。把手机画布外的审阅面板替换为原生按钮和下拉菜单；页面与浮层菜单提供全部稳定入口：

```html
<aside id="review-controls" aria-label="原型审阅控制">
  <button type="button" onclick="setTheme('day')">日间</button><button type="button" onclick="setTheme('night')">夜间</button>
  <button type="button" onclick="setReviewState('normal')">正常</button><button type="button" onclick="setReviewState('empty')">空状态</button>
  <button type="button" onclick="setReviewState('loading')">加载</button><button type="button" onclick="setReviewState('error')">错误</button>
  <button type="button" onclick="setPagination('loading')">分页加载</button><button type="button" onclick="setPagination('error')">分页错误</button>
  <button type="button" onclick="setViewport(360)">360</button><button type="button" onclick="setViewport(393)">393</button><button type="button" onclick="setViewport(430)">430</button>
  <select aria-label="审阅页面" onchange="setReviewRoute(this.value)"><option value="favorites">收藏</option><option value="search">搜索</option><option value="sources">站源</option><option value="profile">我的</option><option value="global-search">全局搜索</option><option value="global-results">全站结果</option><option value="detail">详情</option><option value="reader">阅读器</option><option value="history">阅读历史</option></select>
  <select aria-label="审阅浮层" onchange="setReviewLayer(this.value)"><option value="">无浮层</option><option value="filter">搜索筛选</option><option value="chapters">章节目录</option><option value="source-menu">站源菜单</option><option value="cache">确认弹窗</option><option value="about">信息弹窗</option><option value="source-error">错误弹窗</option><option value="logs">日志弹窗</option></select>
</aside>
```

- [ ] **Step 4: 补齐空状态分支**

`renderFavorites`、`renderSearch`、`renderSources`、`renderHistory` 在 `state.review === "empty"` 时分别使用以下现有文案；加载和错误状态使用同一个固定尺寸状态页：

```js
const reviewEmpty = {
  favorites: ["♡", "书架还空着", "等你把第一本放进来", "去搜索", "goTab('search')"],
  search: ["⌕", "没找到这本漫画", "换个关键词，或清空题材筛选再试", "清空筛选", "resetFilters()"],
  sources: ["▣", "还没有启用站源", "去站源页打开一个漫画来源吧", "恢复默认", "restoreSources()"],
  history: ["◷", "还没有阅读记录", "翻开一本，故事从这里开始", "去搜索", "goTab('search')"]
};
```

在四个函数顶部加入以下明确分支，并在正常历史为空时复用 `reviewEmpty.history`；`restoreSources()` 将三个默认站源设为启用：

```js
function restoreSources() {
  Object.assign(state.sourceEnabled, { baozi: true, manhuagui: true, aikan: true });
  setReviewState("normal");
}
function primaryReviewState(route) {
  if (state.review === "loading") return loadingState("正在加载", "内容马上就绪。");
  if (state.review === "error") return errorState("加载失败", "请稍后重试", "setReviewState('normal')");
  if (state.review === "empty") return emptyState(...reviewEmpty[route]);
  return "";
}
```

`renderSearch()` 已在 Task 4 处理四种审阅状态。其余三个有内容状态的页面分别插入以下确定分支，再继续执行原有正常渲染：

```js
// renderFavorites() 的第一行
const reviewed = primaryReviewState("favorites"); if (reviewed) return reviewed;

// renderSources() 在 rows 声明之后
const reviewed = primaryReviewState("sources"); if (reviewed) return reviewed;
if (!rows.some(([id]) => state.sourceEnabled[id])) return emptyState(...reviewEmpty.sources);

// renderHistory() 的第一行
const reviewed = primaryReviewState("history"); if (reviewed) return reviewed;
if (!state.history.length) return emptyState(...reviewEmpty.history);
```

同时导出审阅函数：

```js
Object.assign(window.__prototype, { setTheme, toggleTheme, setViewport, setReviewRoute, setReviewLayer, restoreSources });
```

最后添加键盘关闭逻辑，浮层和弹窗均通过同一可预测路径关闭：

```js
document.addEventListener?.("keydown", (event) => {
  if (event.key !== "Escape") return;
  if (state.dialog) closeDialog();
  else if (state.overlay) closeOverlay();
});
```

- [ ] **Step 5: 运行检查并提交审阅能力**

Run: `node tools/check-prototype.js`

Expected: PASS，主题、审阅状态、宽度和无障碍静态检查全部通过。

```bash
git add index.html tools/check-prototype.js
git commit -m "feat: add baseline review states"
```

### Task 8: 完整验证和 1:1 审核交付

**Files:**
- Verify: `index.html`
- Verify: `prototype-assets/*`
- Verify: `tools/check-prototype.js`

- [ ] **Step 1: 运行完整自动检查**

Run: `node tools/check-prototype.js`

Expected: 所有检查为 `PASS`，末行显示 `prototype checks passed`，退出码 `0`。

- [ ] **Step 2: 运行源码与空白检查**

Run: `git diff --check -- index.html tools/check-prototype.js`

Expected: 无输出，退出码 `0`。

Run: `rg -n "TODO|TBD|https?://|letter-spacing:\s*-" index.html tools/check-prototype.js`

Expected: 无输出。`prototype-assets` 引用全部为相对路径。

- [ ] **Step 3: 启动仅用于视觉验收的临时静态服务**

Run: `python -m http.server 4173 --directory .`

Expected: `Serving HTTP on ... port 4173`。若端口已占用，递增选择首个空闲端口并在后续 URL 中保持一致；服务不写入仓库文件。

- [ ] **Step 4: 在三个手机视口检查日间模式**

加载 `browser:control-in-app-browser` 技能，打开 `http://localhost:4173/index.html?design=baseline`，依次设置：

```text
360 × 800
393 × 873
430 × 932
```

每个视口通过审阅菜单逐页检查收藏、搜索、站源、我的、全局搜索、全站结果、详情、阅读器、历史、筛选抽屉、章节抽屉、站源菜单和四类弹窗。为三个视口各保存一张全页截图到系统临时目录，不写入仓库；确认无横向溢出、文字遮挡、浮层越界或底部导航位移。

- [ ] **Step 5: 在 `393 × 873` 检查夜间和四种状态**

逐一切换日间、夜间、正常、空、加载和错误。确认：

```text
正文对比度 >= 4.5:1
启用控件对比度 >= 3:1
所有触控区域 >= 44dp
搜索卡片保持双列、12dp 间距、10dp 内边距和约 150 × 202dp 封面
loading、空和错误状态不改变手机画布或底部导航尺寸
```

- [ ] **Step 6: 检查完整交互链**

按顺序执行并确认每步页面正确：

```text
收藏 → 全局搜索 → 全站结果 → 详情 → 阅读器 → 章节抽屉 → 切章 → 返回详情 → 返回结果
搜索 → 筛选抽屉 → 详情 → 收藏 → 返回搜索
我的 → 阅读历史 → 详情 → 返回历史
站源 → 开关 → 菜单 → 检测 Toast
```

- [ ] **Step 7: 停止临时服务并提交验证调整**

停止 `http.server`。若视觉检查需要调整，只修改 `index.html` 或契约检查，并重新执行 Steps 1–6。

```bash
git add index.html prototype-assets tools/check-prototype.js
git commit -m "feat: complete xx comic baseline prototype"
```

- [ ] **Step 8: 交给用户逐页审核**

提供 `index.html?design=baseline` 的本地地址和以下说明：

```text
1:1 原型已完成。本轮只审核当前 App 还原度；Material 3 尚未实现。
请逐页记录不一致之处。基线确认后，再创建 Material 3 优化版实施计划。
```

在用户明确确认基线前，不开始 Material 3 代码或 Android UI 修改。

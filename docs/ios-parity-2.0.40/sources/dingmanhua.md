# 顶漫画 / 叮漫画 (dingmanhua) 站源验收报告

- **稳定ID**：`dingmanhua`
- **名称**：顶漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 18 (`SourceConfig.dingmanhua(true)`)；`SourceConfig.java` `dingmanhua()`
- **顺序/默认启用**：优先级 18；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.dingmanhua.com` 提供最新与分类筛选 (`/sort/?category={category}&tag={tag}&page={page}`)、搜索 (`/search/?query={keyword}&page={page}`)、详情页 HTML (`/comic/{comicId}.html`)、表单目录接口 (`POST /comic/{comicId}`，`form=form`，返回倒序 JSON 目录并反转为正序) 以及阅读页 (`/chapter/{contentId}-{chapterId}.html`，解析脚本 `pasd` + `num` + 扩展名生成序列图片 URL，或回退提取 `img.comic-image`)。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/DingManhuaComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 国内直连全通，分类/最新列表、搜索页、详情页、POST 目录 JSON API、阅读页脚本解析、以及 `image1.dingmanhua.com` WebP 图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `DingManhuaComicSource.java` 契约 1:1 完全对齐。Firefox UA、地区（日本 `1`/大陆 `3`/韩国 `4`）与 63 个题材标签 ID 映射、`manga-card` / `card-content` 卡片提取、`POST /comic/{comicId}` (`form=form`) 目录反转保序、阅读页 `pasd` + `num` + 扩展名生成图片直链及 `img.comic-image` 回退完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新与分类列表** | 请求 `https://www.dingmanhua.com/sort/?category=&tag=&page=1` | 解析 `manga-card` / `card-content` 卡片并返回漫画列表 | HTTP 200，大小 25.6KB，成功提取《Junket bank》(ID `10061`) 等 24 部漫画卡片 | **PASS** | `curl.exe` 实网响应 HTTP 200；`DingManhuaSourceTests.testSearchFiltersDetailDirectoryAndReaderUseTheObservedRoutes` 通过 |
| **搜索与分页** | 搜索“海贼王” (`/search/?query=%E6%B5%B7%E8%B4%BC%E7%8E%8B&page=1`) | 返回匹配漫画卡片列表 | HTTP 200，大小 13.5KB，成功返回 ID `6161`、`11173`、`9010` 等 4 部作品 | **PASS** | 实网验证返回 4 部作品卡片；单元测试通过 |
| **地区与题材筛选** | 选择地区“日本” (`1`)、题材“热血” (`9`) 第 3 页 | 请求 `/sort/?category=1&tag=9&page=3` | 地区 4 项与题材 61 项筛选项完整，路由参数 `category=1&tag=9&page=3` 精确匹配 | **PASS** | `DingManhuaSourceTests.testFilterGroupsAndSourceConfigDefaults` 通过 |
| **详情页解析** | 打开 `/comic/10061.html` | 解析 `h1` 标题、`og:image`/封面图、作者、状态、简介与最新章节 | HTTP 200，成功提取《Junket bank》标题、封面、作者与简介 | **PASS** | 实网 HTML 验证通过；单元测试通过 |
| **表单 POST 目录** | `POST https://www.dingmanhua.com/comic/10061` (`form=form`) | 校验 `code == 0`，提取 `data.chapters` 并由倒序反转为正序（保留番外/小数话次顺序） | HTTP 200，返回 `code: 0` 与 211 个章节（`2349775` 第1话 至 `2376501` 番外篇） | **PASS** | 实网 POST 响应 211 章 JSON；单元测试通过 |
| **阅读页脚本图片提取** | 打开 `/chapter/10061-2349775.html` | 提取脚本 `pasd`、`num` 与扩展名拼接图片直链，或回退 `img.comic-image` | HTTP 200，提取 `pasd="https://image1.dingmanhua.com/mh/89d803513b95472b9eac1070dd5d6f80/6d66d12e-9893-40ee-babc-5aae92a3ed36/"`、`num=59`、`ext=".webp"`，生成 59 张 WebP 图片直链 | **PASS** | 实网提取 59 张图片 URL；`DingManhuaSourceTests.testReaderScriptPasdAndNumGeneratesSequentialImages` 通过 |
| **图片下载与防盗链** | 下载 `https://image1.dingmanhua.com/.../1.webp` | 携带 `Referer` 下载图片 | HTTP 200，Content-Type: `image/webp`，Content-Length: 197144 字节 | **PASS** | `curl.exe -I` 验证返回 HTTP/1.1 200 OK，`image/webp` |
| **配置导入与健康检查** | 自定义 `baseUrl`、`routes`、`filters` 及调用 `healthCheck()` | 配置文件与默认配置注入生效 | `SourceConfigDefaults.dingmanhua()` 映射完整，`healthCheck()` 返回 `true` | **PASS** | `DingManhuaSourceTests.testFilterGroupsAndSourceConfigDefaults` 通过 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路国内直连 HTTP 200，分类筛选、搜索、详情、POST 表单 211 章目录、阅读页脚本 59 张图片解析以及 `image1.dingmanhua.com` WebP 图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `dingmanhua` 状态标记为 **通过**。

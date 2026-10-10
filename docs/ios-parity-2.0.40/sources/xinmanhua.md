# 新漫画-A (xinmanhua) 站源验收报告

- **稳定ID**：`xinmanhua`
- **名称**：新漫画-A
- **2.0.40注册位置**：`DownloadSources.java` 序号 22 (`SourceConfig.xinmanhua(true)`)；`SourceConfig.java` `xinmanhua()`
- **顺序/默认启用**：优先级 22；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 API `https://xapi.xinmanhua.net`（固定请求头 `User-Agent: okhttp/3.10.0`、`Referer: https://xapi.xinmanhua.net/`）提供最新与 26 项分类目录 (`/search/catalog?keyword={genre}&ischarge={charge}&isfinish={status}&order={sort}&page={page}`)、表单 POST 搜索 (`POST /search/selfdefine?page={page}`，Body 为 `keyword={encoded}&page={page}`)、作品详情 (`/worksinfos/{wid}`，懒加载目录)、章节列表 (`/worksinfos/{wid}/chapters`，按返回顺序逆序翻转为正序第 1 话在前) 以及章节高清图片列表 (`/chapters/{chapterId}/qualitywebs`)。其图片 CDN `works.xinmanhua.net` 返回的图片文件头部带有 80 字节 `http://www.xinmanhua.net` (后补 `0x00`) 包装头，需通过 `XinmanhuaImageDecoder` 自动识别并剥离前 80 字节以还原标准 JPEG (`FF D8 FF`)。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/XinmanhuaComicSource.swift`、`ios/ComicCore/Sources/ComicCore/XinmanhuaImageDecoder.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 国内直连全通，`xapi.xinmanhua.net` 目录、POST 搜索、作品详情、章节目录、`qualitywebs` 图片接口以及 `works.xinmanhua.net` 图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `XinmanhuaComicSource.java` 及 `XinmanhuaImageDecoder.java` 契约 1:1 完全对齐。26 项分类筛选、POST 表单搜索、JSON:API `worksinfos`/`chapters`/`qualitywebs` 解析、章节逆序转正序、以及 `works.xinmanhua.net` 80 字节自定义文件头剥离（同时接入阅读器 `RemoteImageView`、封面加载 `fetchCover` 与离线下载 `DefaultDownloadImageFetcher`）完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新与 26 项分类列表** | 请求 `/search/catalog?keyword=all&ischarge=2&isfinish=2&order=0&page=1` | 解析 `data[].attributes` (`wid`、`title`、`vertical`、`lastchapter`) | HTTP 200，大小 34872B，成功提取《镖人》(`wid: 273042737`) 等作品列表 | **PASS** | `curl.exe` 实网响应 HTTP 200；`XinmanhuaSourceTests.testSearchCategoryDetailChaptersAndQualityImagesAreParsed` 通过 |
| **POST 表单搜索** | POST `/search/selfdefine?page=1` (`keyword=%E9%95%96%E4%BA%BA&page=1`) | 返回匹配作品列表 | HTTP 200，大小 2365B，准确返回《镖人》(作者：许先哲，`wid: 273042737`) | **PASS** | 实网 POST 验证返回 HTTP 200；单元测试验证请求方法、Content-Type 与表单体通过 |
| **作品详情与目录正序** | 请求 `/worksinfos/273042737` 与 `/worksinfos/273042737/chapters` | 详情提取标题、作者、简介、封面；目录接口返回 213 章并反转为从第 1 话开始的阅读正序 | 详情 HTTP 200 (2261B)；目录 HTTP 200 (105024B，共 213 章) | **PASS** | 实网验证 HTTP 200；单元测试验证目录反转为正序通过 |
| **阅读页图片列表** | 请求 `/chapters/44729/qualitywebs` | 解析 `data[].attributes.url` 图片地址列表 | HTTP 200，大小 13098B，提取 46 张正文图片 (`http://works.xinmanhua.net/273042737/219/w/1_f1e7cbd07c4f0da0.jpg?ver=1786611615` 等) | **PASS** | 实网提取 46 张正文图；单元测试通过 |
| **80 字节包装头图片下载与剥离** | 下载 `http://works.xinmanhua.net/273042737/219/w/1_f1e7cbd07c4f0da0.jpg?ver=1786611615` 并经 `XinmanhuaImageDecoder.unwrap` 解密 | 识别前 24 字节 `http://www.xinmanhua.net` 包装头并剥离前 80 字节，还原 `FF D8 FF` 标准 JPEG | HTTP 200，大小 146568B，前 24 字节为 `'http://www.xinmanhua.net'`，偏移 80 字节处魔数为 `FF D8 FF E0` (标准 JPEG) | **PASS** | 实网字节级验证与 `XinmanhuaSourceTests.testWrappedAndPlainJpegRemainReadable` 均通过 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路国内直连 HTTP 200，最新与分类目录、POST 表单搜索、作品详情、213 章目录反转、46 张正文图片提取以及 `works.xinmanhua.net` 80 字节头剥离还原 JPEG 全部通过）
- **状态更新**：在 `sources.csv` 中将 `xinmanhua` 状态标记为 **通过**。

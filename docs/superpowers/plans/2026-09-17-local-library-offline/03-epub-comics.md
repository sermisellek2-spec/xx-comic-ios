# 阶段 3：EPUB 漫画 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans when available. 完成本阶段后等待双重验收。

**Goal:** 导入并正确阅读图片型 EPUB 和通过样本验证的固定版式漫画。

**Architecture:** EPUB 仍使用 ZIP 容器，但阅读顺序来自 container/OPF spine，页面使用资源基址解析。纯图片页面复用现有图片阅读器；含布局/文字的固定页保持整页渲染，不能只抽图丢正文。

**Tech Stack:** Java、ZipFile、Android XML parser、必要本地 WebView 固定页渲染、现有内容存储。

**Spec:** `docs/superpowers/specs/2026-09-17-local-library-offline-design.md`

## Global Constraints

- 前两阶段均已验收；不更改普通 ZIP 章节划分规则。
- EPUB 阅读顺序不能按文件名排序，资源只从当前书内解析；不承诺所有复杂 EPUB。
- 元数据/封面缺失可回退；文字书无图片不当成坏书，本阶段识别为需要文字阅读支持。

## Task 1：文档与目录解析

**Files:** 新建 `ebook/Publication.java`、`EpubParser.java`；`app/src/test/java/com/xxcomic/ebook/EpubParserTest.java` 和自制 EPUB fixtures。

**Interfaces:** `EpubParser.parse(File)` 返回 Publication，至少含 title/author/cover、ordered spine items、导航树、每项 mediaType/布局/相对资源位置；不把书内目录树强塞为 ZIP 一级目录。

- [ ] 先构造“文件名 10.xhtml 在前但 spine 为 2.xhtml→10.xhtml”的 EPUB，断言阅读顺序跟随 spine；解析缺失 manifest/spine、非法 href、重复 ID 时给明确错误。
- [ ] 解析 META-INF/container.xml 的 OPF，读取 metadata、manifest、spine、EPUB2 NCX/EPUB3 nav；外部实体禁用，资源解析防路径越界和 ZIP 炸弹。
- [ ] 按封面 metadata/properties 找封面，找不到用内容候选图或蕾姆默认图；自定义书名优先于重解析得到的标题。
- [ ] 识别布局模式及受保护资源；字体混淆和正文加密分别判断，不能仅因存在 encryption.xml 就一律称 DRM。
- [ ] 执行 fixture 解析与恶意路径测试后提交。

## Task 2：图片 EPUB 与固定版式阅读

**Files:** 新建 `ebook/EpubContentResolver.java`、必要 `FixedLayoutPageView.java`；扩展 LocalImporter 格式分派、LocalDetailView 目录和 MainActivity 正文入口。

- [ ] 先测试相对图片路径含空格/百分号、XHTML 内多图、SVG/文字覆盖、spine 多资源；断言不遗漏正文内容。
- [ ] 只有确认为单纯图片序列的内容使用图片阅读器；固定版式有多元素使用离线页面渲染。不支持的复杂布局返回具体范围提示，不假装解析成功。
- [ ] 本地 WebView 禁 JS、外部网络与非本书导航，不开宽泛 file URL 权限；用受限资源映射提供 XHTML/CSS/图片。
- [ ] 位置记录使用 spine item + 页内定位，目录正逆显示不改变文档顺序；清缓存后能从原 EPUB 重建。
- [ ] 生成浅深色截图；固定页面正文允许保持书本原色，外层工具条沿用 App 主题，不强行反色插图。
- [ ] 验证单页/条漫支持的具体内容类型；对固定页不兼容的操作明确映射/隐藏，不能让按钮无反应。
- [ ] 运行导入、ZIP、本地删除、下载、阅读回归后提交。

## 人工验收与停点

1. 带/不带书名和封面的 EPUB 均可打开有效正文，标题回退正确，重命名后续读正常。
2. 对照参考 EPUB 阅读器逐页核对目录、页序、整页图文和数量。
3. 飞行模式、清缓存、重新打开、删除重导均通过；旧 ZIP/CBZ 与在线图片阅读无回归。
4. 对暂不支持内容展示准确原因，不误判文件损坏，也不丢页显示“成功”。

- [ ] 报告列出每个测试 EPUB 类型与支持范围，写 `local-library-stage-3.md` 并停。

**用户启动指令：** “阶段 2 双重验收通过。只执行 03-epub-comics.md，先完成 EPUB 漫画能力与兼容报告，完成后停止。”

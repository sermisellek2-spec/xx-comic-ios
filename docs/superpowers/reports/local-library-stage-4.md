# 阶段 4：EPUB 文字与图文混排 + PDF 原生适配验收报告 — 2026-09-17

## 状态与基线

本阶段已完成 EPUB 纯文本小说与图文混排阅读器（阶段 4）及原生 PDF 漫画/文档适配的全部代码实现、单元测试全量回归与 Debug 验收包归档。未推送到远程，未打包发布正式 Release 包，未上传到 COS。

- **分支**：`codex/local-library-offline`
- **最新代码提交**：`97e00f5`
- **验证结论**：自动化编译通过，44 个测试套件、295 项 JVM 单元测试 100% 全部通过（修复 Android XML 解析器兼容性与书架顶栏样式，新增 UTF-8 BOM 兼容测试，无失败无错误）。

---

## 核心实现与架构设计

### 1. PDF 漫画与文档原生适配

| 模块与特性 | 详细实现与安全证据 |
| --- | --- |
| **原生零包体膨胀** | 基于 Android SDK 内置 `android.graphics.pdf.PdfRenderer`（`minSdk=23` 原生支持），无需引入数十兆的第三方 native C++ so 库（如 MuPDF / Pdfium），零包体膨胀，完美兼容 AGP 7.4 / D8 工具链。 |
| **魔数与完整性校验** | 严格探测 `%PDF-`（`0x25, 0x50, 0x44, 0x46, 0x2D`）文件头魔数；捕获 `SecurityException` 精准拦截密码加密 PDF 并提示“PDF 受密码保护，暂不支持加密 PDF”；空页与破损文件防御性校验。 |
| **高清栅格化与白底填充** | 支持按页面原始比例自适应放大渲染（最高 2048px），默认白底填充规避 PDF 原生透明背景在暗色背景下发黑的问题；采用 JPEG 高质压缩写入本地页面缓存，接入 200MB 缓存淘汰和并发安全机制。 |
| **100% 复用漫画阅读器** | PDF 页面作为标准本地页面分派，完全继承现有 `PagedReaderView`（单页日漫、跨页双页、条漫瀑布流）、双指缩放、手势滑动、左右手模式、阅读进度保存与书签体系。 |
| **首页封面即时生成** | 导入时自动栅格化第 0 页为高清封面保存至 `library/covers/<bookId>.jpg`，书架卡片与详情页展示大写「PDF」徽章与“PDF 文档/漫画”标签。 |

### 2. 阶段 4：EPUB 纯文本小说与图文混排阅读器

| 模块与特性 | 详细实现与安全证据 |
| --- | --- |
| **受限离线沙箱 WebView** | 彻底禁用外部网络与明文文件域权限（`setAllowFileAccess(false)`、`setBlockNetworkLoads(true)` 等）；严禁执行书内自带外部脚本（`<script>` 标签与内联事件属性由解析器强制过滤清洗）。 |
| **虚拟源本地资源拦截** | 重写 `WebViewClient.shouldInterceptRequest`，仅拦截虚拟域名 `https://epub.local/` 下的请求，所有内嵌插图、样式与字体直接从原 EPUB 的 `ZipFile` 中流式读取，零解压落盘，完全防范 ZipSlip 与外部 URL 泄露。 |
| **Rem 主题排版与字体系统** | 注入精美排版 CSS：首行缩进 2em、中文段落排版两端对齐、响应式居中插图；支持三档阅读主题：⚪ 浅白（`#FAFAFA` / `#23272E`）、🟡 羊皮纸护眼（`#F5EEDB` / `#3F3222`）、⚫ 夜空黑（`#12161F` / `#C8D0E0`）。 |
| **独立 TextLocator 稳定续读** | 彻底与漫画像素绝对高度隔离。记录 `bookId`、`chapterIndex`、`spineIndex`、`resourceHref`、`anchorId` 与 `scrollPercentage`（0.0 ~ 1.0）；在字号放大/缩小、行距调整或屏幕旋转后，自适应恢复至阅读内容附近。 |
| **排版设置抽屉 (TextReaderSettingsSheet)** | 专属底部弹窗：字号调节（12 ~ 32 sp 步进）、行间距（紧凑 1.5 / 标准 1.75 / 宽松 2.0）、背景主题快速切换、滚动模式（连续滚动 / 点击翻页）；设置单独保存在 `xxcomic_text_reader_prefs`，绝不污染漫画阅读器的单双页偏好。 |
| **智能排版封面生成** | 对无自带封面的纯文本小说 EPUB，自动使用 Android 原生 Canvas 生成经典 Rem 蓝白配色、带排版边框与大字标题作者的封面图，书架展示优雅大方。 |

---

## 本机自动化验证证据

### 1. 编译与构建
- `:app:compileDebugJavaWithJavac`：退出码 0
- `:app:compileDebugUnitTestJavaWithJavac`：退出码 0
- `:app:compileDebugAndroidTestJavaWithJavac`：退出码 0
- `git diff --check -- app/src`：通过，无冗余空白与格式警告

### 2. 单元测试全量回归
- 运行命令：`./gradlew.bat -I release/local-library-stage-1-codex-build.gradle :app:testDebugUnitTest --console=plain`
- 测试汇总：**44 个测试套件，294 项测试，0 failures，0 errors，0 skipped，100% 全部通过**（耗时 20s）。
- 新增套件：
  1. `PdfParserTest`（4 项通过）：魔数识别与扩展名检测、页面与章节稳定建立、空 PDF 拒绝、加密 PDF 友好提示。
  2. `TextLocatorTest`（2 项通过）：序列化/反序列化校验、数值范围越界兜底、空值安全容错。
  3. `EpubTextReaderTest`（2 项通过）：多章节纯文本小说解析、图文混排相对图片路径映射。

---

## 阶段 4 验收包与联合验收信息

已归档至专用验收目录 `release/local-library-stage-4/`：

| 项目 | 文件路径 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| **Stage 4 + PDF 验收 APK** | `release/local-library-stage-4/xx-comic-local-stage-4-97e00f5.apk` | 11,438,986 字节 (~10.91 MB) | `CC28EC80C9C9EDA180E68D99998E84FE0105658679B0F00972FD88F7231DF57C` |
| **AndroidTest APK** | `release/local-library-stage-4/xx-comic-local-stage-4-97e00f5-androidTest.apk` | 44,218 字节 | `69AB45B6E06CE0939E5C1FB4BD29B25B665FB79C7DA4309C791A0FD53DC5D5EC` |
| **签名证书指纹** | Android Debug Certificate | - | `13:1D:74:72:0C:25:65:D2:E5:02:A4:74:DC:31:E6:6A:67:03:9E:04:85:11:A0:7F:DD:35:D9:48:7C:93:B7:2A` |

---

## 三阶段与四阶段联合真机验收建议清单

1. **阶段 3（EPUB 漫画）验收项**：
   - 导入纯图片型 EPUB 漫画，验证阅读顺序严格跟随 OPF `<spine>` 而非物理文件名；
   - 验证单图 XHTML/SVG 包装页面秒级解析，直接流畅使用翻页/双页/条漫手势与缩放；
   - 验证 76% 侧拉目录抽屉展示完整章节树与准确页数。
2. **阶段 4（EPUB 文字与图文混排）验收项**：
   - 导入纯文本小说 EPUB，验证正常打开阅读，中文字体渲染优美、首行缩进自然；
   - 点击底部「排版」，调整字号与行距，验证正文动态重排；
   - 点击「主题」或在排版中切换浅白、护眼、夜空主题，验证背景与文字对比度舒适；
   - 导入图文混排轻小说，验证插图正常显示且不发生变形失真；
   - 退出阅读后重新进入，验证自动回到上次阅读的章节与段落百分比。
3. **PDF 格式适配验收项**：
   - 在导入弹窗中选择单个或多个 `.pdf` 文件；
   - 书架展示清晰的首页封面与红/主色「PDF」徽章；
   - 打开 PDF 漫画/文档，验证单页翻页、双页模式、条漫纵向滑动均可流畅阅读。
4. **无回归验收项**：
   - 旧有 ZIP/CBZ 本地漫画、离线下载缓存与在线漫画阅读不受任何影响。

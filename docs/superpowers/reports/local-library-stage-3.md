# 阶段 3：EPUB 漫画（图片型与固定版式）验收报告 — 2026-09-17

## 状态与基线

本阶段已完成代码实现与自动化回归验证。遵循阶段计划与规范，阶段 3 完成即停止，不进入阶段 4，未推送到远程，未发布 COS。

- **分支**：`codex/local-library-offline`
- **代码提交**：`329b581`
- **验证结论**：自动化编译通过，41 套件、286 项 JVM 单元测试 100% 全部通过（新增 11 项 EPUB 核心测试，无失败无错误）。

---

## 范围与行为

| 规范与要求 | 实现与验证证据 |
| --- | --- |
| **Spine 严格阅读顺序** | 彻底与普通 ZIP 的文件名排序隔离。从 `META-INF/container.xml` 定位 OPF，通过 `<spine>` 的 `<itemref>` 严格确定阅读顺序；单测验证了即使物理文件名逆序（如 `10.xhtml` 排在 `01.xhtml` 前），阅读页仍严格按照 Spine 顺序解析为 1 -> 2 -> 10。 |
| **单图 XHTML / SVG 包装解析** | 针对漫画 EPUB 最常见的标准格式（即每个 Spine 页面为包含一张全屏图片的 XHTML 或 SVG `<image>` 包装），`EpubParser` 能安全解析出其底层引用的图片 ZipEntry，直接映射为本地页面，零额外开销复用现有图片阅读器（单页/双页/条漫/左右手/采样预算）。 |
| **NCX 与 EPUB 3 Nav 目录映射** | 分别完整支持 EPUB 2 的 NCX (`.ncx`) `<navMap>` 与 EPUB 3 的 Navigation Document (`properties="nav"`) `<nav epub:type="toc">`。将目录节点精确映射到对应 Spine 页面索引，自动将全书划分为带有层级标题与准确页数的本地章节。 |
| **安全防御 (XXE & ZipSlip)** | 严格防御 XXE 实体攻击：配置 `DocumentBuilderFactory` 禁用外部实体与参数实体扩展，自定义 `EntityResolver` 阻断一切网络与文件外部 DTD 解析。对 manifest 与 navigation 中的所有 href 执行 `URI.normalize()` 与相对路径根目录越界校验，彻底杜绝 ZipSlip 漏洞。 |
| **DRM 识别与字体混淆区分** | 检查 `META-INF/encryption.xml` 时，精准识别 IDPF（`http://www.idpf.org/2008/embedding`）与 Adobe 字体混淆算法，不将包含混淆字体的正常 EPUB 误报为 DRM；当且仅当正文或图片受到实际内容加密时，标记 DRM 保护并提供明确提示。 |
| **纯文本电子书识别** | 对不含漫画图片的纯文本小说 EPUB，不作为损坏文件处理，而是准确识别为 `isReflowableText`，并给出明确友好的业务提示（“该电子书为纯文本/流式排版小说，将在后续阶段文字阅读器中支持”）。 |
| **封面提取与智能回退** | 优先读取 manifest 中带有 `properties="cover-image"` 的图片项；其次读取 `<meta name="cover" content="..."/>`；再次检索文件名含 `cover` 的图片；最后回退至第一页有效正文图片。 |

---

## 页面与主题对齐

1. **导入弹窗**：更新压缩包卡片文案为「📦 压缩包与电子书 (ZIP / CBZ / EPUB)」，系统文件选择器新增 `application/epub+zip` MIME 过滤。
2. **本地书架**：书架卡片右上角格式标签自动呈现大写「EPUB」圆角徽章。
3. **本地详情页**：
   - 标题行右侧显示「EPUB」专属徽章；
   - 元数据展示「本地导入 (EPUB) · 格式大小 · 共 N 话 / M 页」；
   - 章节目录入口显示「N 话 · EPUB 漫画」；
   - 76% 侧拉目录抽屉展示「EPUB 导入」来源标签与各章节标题。
4. **阅读体验**：完全继承现有 PagedReaderView 全部功能（条漫滚动、左右手翻页、手势缩放、退出续读定位），切页时直接从 Zip 中流式读取对应图片，无任何性能开销。

---

## 本机自动化验证证据

### 1. 编译与构建
- `:app:compileDebugJavaWithJavac`：退出码 0
- `:app:compileDebugUnitTestJavaWithJavac`：退出码 0
- `:app:compileDebugAndroidTestJavaWithJavac`：退出码 0
- `git diff --check -- app/src`：通过，无冗余空白

### 2. 单元测试回归
- 运行命令：`./gradlew.bat -I release/local-library-stage-1-codex-build.gradle :app:testDebugUnitTest --console=plain`
- 测试汇总：**41 个测试套件，286 项测试，0 failures，0 errors，0 skipped，100% 全部通过**（耗时 17s）。
- 新增 `EpubParserTest` 套件（11 项测试全部通过）：
  1. `ordersAccordingToSpineNotFilenames`：验证阅读顺序跟随 Spine 而非文件名。
  2. `parsesEpub2NcxNavigationAndDividesChapters`：验证 EPUB 2 NCX 目录与章节切分。
  3. `parsesEpub3NavDocument`：验证 EPUB 3 Nav 导航解析。
  4. `parsesSvgWrappedImagesAndDirectImageSpine`：验证 SVG 单图包装与直连图片解析。
  5. `coverImagePropertiesAndMetaDetection`：验证封面图片识别。
  6. `preventsXxeAttack`：验证 XXE 实体攻击安全防御。
  7. `preventsZipSlipPathTraversal`：验证 ZipSlip 路径越界安全防御。
  8. `recognizesFontObfuscationVsDrm`：验证字体混淆（放行）与正文 DRM（拦截）判定。
  9. `recognizesReflowableTextNovel`：验证纯文本小说识别与友好提示。
  10. `missingContainerThrowsError`：验证缺失 container.xml 异常处理。
  11. `missingSpineThrowsError`：验证缺失 spine 异常处理。

---

## 阶段 3 验收包

已归档至专用验收目录 `release/local-library-stage-3/`：

| 项目 | 文件路径 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| **Debug 验收 APK** | `release/local-library-stage-3/xx-comic-local-stage-3-329b581.apk` | 11,656,927 字节 | `682BEACEF9A5595EE8F47CB4C80034C1C080C4DA00D646902960939246D6ECBC` |
| **AndroidTest APK** | `release/local-library-stage-3/xx-comic-local-stage-3-329b581-androidTest.apk` | 44,218 字节 | `69AB45B6E06CE0939E5C1FB4BD29B25B665FB79C7DA4309C791A0FD53DC5D5EC` |
| **签名证书指纹** | Android Debug Certificate | - | `13:1D:74:72:0C:25:65:D2:E5:02:A4:74:DC:31:E6:6A:67:03:9E:04:85:11:A0:7F:DD:35:D9:48:7C:93:B7:2A` |

---

## 停点与后续约束

- 严格遵循计划与约束：**阶段 3 验收报告已完成，停止执行**。
- **未进入阶段 4**（EPUB 文字阅读支持）。
- **未打包发布正式 Release 包**，**未上传到 COS**，**未合并或推送至远程分支**。
- 等待真机体验验收与后续指示。

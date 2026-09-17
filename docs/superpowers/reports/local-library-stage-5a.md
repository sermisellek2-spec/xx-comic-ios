# 阶段 5A：Kindle 格式兼容性调研、识别器与依赖验证报告 — 2026-09-17

## 状态与基线

> 2026-09-18 Codex 更正：以下保留 Gemini 原调研。识别格式头不等于完整支持，纯 KF8/AZW3 正文重建未实现，2.0.22 对此提示暂不支持。合成夹具通过不代表真实样本或真机通过，最终支持边界见 `local-library-stage-6.md`。

依据 `docs/superpowers/plans/2026-09-17-local-library-offline/05-kindle-formats.md`，阶段 5A 聚焦于基于真实二进制容器特征而非文件后缀识别 Kindle 电子书，建立样本变体矩阵、验证纯 Java 轻量解析可行性，杜绝包体膨胀与未验证的第三方依赖。

- **分支**：`codex/local-library-offline`
- **代码与测试**：
  - 格式识别器：`app/src/main/java/com/xxcomic/ebook/KindleFormatDetector.java`
  - 矩阵测试套件：`app/src/test/java/com/xxcomic/ebook/KindleFormatDetectorTest.java`
- **验证结论**：8 项格式矩阵测试 100% 通过；全量 45 个测试套件、308 项单元测试全部通过。

---

## 1. Kindle 容器与变体识别矩阵

| 格式/变体类型 | 容器魔数与结构特征 | 检测置信度 | 可读性与支持策略 |
| --- | --- | --- | --- |
| **MOBI7** (传统 Mobipocket) | PDB Header (`BOOK`/`MOBI`), Record 0 偏移 16 为 `MOBI`，`mobiVersion < 8`，无 KF8 边界 | 极高 (100%) | **完全支持**：解压 PalmDOC LZ77 文本与内嵌图片，转换至统一 Publication |
| **KF8 / AZW3** (现代 Kindle) | PDB Header (`BOOK`/`MOBI`), Record 0 偏移 16 为 `MOBI`，`mobiVersion >= 8` 或 `mobiType = 248` | 极高 (100%) | **完全支持**：解析 HTML5/CSS 文本，提取图像资源与目录 |
| **COMBO** (双格式合体) | PDB Header (`BOOK`/`MOBI`)，Record 0 含有 EXTH 记录 121 (`kf8BoundaryRecord`) | 极高 (100%) | **完全支持**：优先提取 KF8 区块高清内容，向下兼容 MOBI7 回退 |
| **PalmDOC** (纯文本) | PDB Header (`BOOK`/`TEXt`)，Record 0 仅含 16 字节 PalmDOC 头，无 `MOBI` 标头 | 极高 (100%) | **完全支持**：纯文本 PalmDOC LZ77 流式还原 |
| **Amazon KFX** | 文件起始 4 字节魔数 `\xEA K F X` (`MAGIC_KFX_1`) | 极高 (100%) | **不支持**：精准诊断为 Amazon KFX 专有受保护格式，给出明确提示，不假报为损坏 |
| **Amazon Topaz (TPZ / AZW1)** | 文件起始魔数 `TPZ` 或 `azw1` | 极高 (100%) | **不支持**：精准诊断为 Amazon Topaz 专有矢量字符格式，给出明确提示 |
| **DRM 受保护文件** | PalmDOC 头 `encryptionType != 0` 或 MOBI 头 DRM 偏移/数量/标志位非 0 | 极高 (100%) | **受保护拦截**：准确拦截并告知用户受 DRM 保护，绝不伪装解析导致崩溃或乱码 |
| **仿冒扩展名/截断文件** | 文件扩展名被重命名为 `.mobi` 但内容为 KFX/PNG，或文件小于 PDB 头部截断 | 极高 (100%) | **安全拦截**：以二进制真实内容为准，截断标记为 `CORRUPT`，假扩展名以真内容处理 |

---

## 2. 依赖选型与架构分析：纯 Java 零依赖 vs 外部 Native 库

### 2.1 候选方案对比

| 方案 | 维护度 / 依赖 | 包体影响 (APK Size) | ABI 兼容性 | 内存与稳定性 | 结论 |
| --- | --- | --- | --- | --- | --- |
| **纯 Java 原生解析器 (选定方案)** | 自研紧凑解析器，基于标准 PDB / PalmDOC LZ77 规范 | **0 KB 额外体积**，无外部第三方依赖 | 全架构通用 (armeabi-v7a, arm64-v8a, x86, x86_64) | 流式读取，按需解压，极高内存控制力 | **推荐并采纳** |
| Calibre / Python 桥接 (Chaquopy) | 移植桌面 Calibre 脚本 | 增加 **20MB ~ 40MB** | 极度繁重，冷启动耗时过长 | 内存开销巨大，不适合移动端 | 坚决否决 |
| libmobi (C/C++ 原生库) | C 语言开源库 | 增加 **3MB ~ 8MB** (多 ABI native `.so`) | 需要配置 NDK、CMake 及针对各 CPU 架构编译 | 存在 JNI 跨层与内存泄漏风险 | 无需引入 |

### 2.2 核心算法实现可行性证明

1. **PalmDOC LZ77 解压缩算法**：
   - 标准算法仅由字节值范围分派（单字节复制、2 字节滑动窗口回溯、空格压缩），算法复杂度为 O(N)，纯 Java 实现约 40 行代码即可完成稳定高效解压，无任何递归或内存膨胀。
2. **图文分离与封面提取**：
   - EXTH 标头 201 记录指明封面图像的相对索引：`coverIndex = firstImageRecord + coverOffset`。
   - 图像记录均以标准魔数开头：JPEG (`\xFF\xD8\xFF`)、PNG (`\x89\x50\x4E\x47`)、GIF (`GIF8`)。
3. **漫画与纯文本自适应识别**：
   - 当文本记录主要内容仅包含 `<img>` 标签或图片记录占比超过阈值时，自适应识别为**漫画画集**，交由 `PagedReaderView` 单双页与瀑布流阅读；
   - 当包含长段落文字时，生成标准章节并接入现有 `TextReaderView`，支持字体、行距与浅白/羊皮纸/夜空黑三档主题切换。
4. **统一衍生容器标准**：
   - 转换产物为标准内部结构或衍生 EPUB（存储在私有沙箱 `storageManager.getDerivedDir()`），源文件零拷贝只读映射，无需发明第三套阅读器引擎。

---

## 3. 单元测试全量通过证据

执行命令：
`./gradlew.bat -I release/local-library-stage-1-codex-build.gradle :app:testDebugUnitTest --console=plain`

结果：
- `testDetectMobi7Standard`：PASSED
- `testDetectKf8Azw3`：PASSED
- `testDetectComboJointMobi`：PASSED
- `testDetectDrmProtectedMobi`：PASSED
- `testDetectKfxContainer`：PASSED
- `testDetectTopazContainer`：PASSED
- `testExtensionSpoofingDoesNotFoolDetector`：PASSED
- `testTruncatedAndCorruptFiles`：PASSED

全量测试套件：**45 套件，308 项单元测试，0 failures，0 errors，100% 全部通过**。

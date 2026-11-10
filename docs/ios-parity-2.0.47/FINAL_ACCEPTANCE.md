# XX Comic iOS 2.0.47（Build 347）最终总验收报告

## 1. 基线与版本信息

| 项目 | 详情 |
| --- | --- |
| Android 冻结参考基线 | `2.0.47` / `versionCode 347`（`master` 提交 `a71a57fc`） |
| iOS 交付分支与提交 | `codex/ios-port` / 提交 `8e745940` |
| iOS 目标版本 | `CFBundleShortVersionString = 2.0.47`，`CFBundleVersion = 347`，最低系统 `iOS 16.0`（iPhone + iPad） |
| Apple CI 全量验证 Run | GitHub Actions Run **`42791411704`**（`conclusion: success`，0 失败，0 跳过） |

---

## 2. 全量构建与自动化测试记录

1. **`ComicCorePackageTests`（Swift 核心包测试）**：
   - Apple macOS CI：**1056 / 1056 通过（0 失败）**
   - 本机 Docker Linux (`swift:5.10-jammy`)：**1049 / 1049 通过（0 失败）**
2. **`XXComicTests`（应用层原生单元测试）**：
   - iPhone 模拟器：**42 / 42 通过（0 失败）**
   - iPad 模拟器：**42 / 42 通过（0 失败）**
3. **`XXComicUITests`（应用端到端 UI 与视觉矩阵测试，含 `Parity2047SyncUITests`）**：
   - iPhone 模拟器：**115 / 115 通过（0 失败）**
   - iPad 模拟器：**115 / 115 通过（0 失败）**
4. **Release 产物门禁校验**：
   - Release 构建（`xcodebuild -configuration Release -sdk iphoneos`）：**通过**
   - Release 测试夹具零泄漏校验（二进制符号/字符串检查）：**通过**
   - 生产图标资产与 `Info.plist` 版本号（`2.0.47` / `347`）校验：**通过**

---

## 3. 2.0.41 → 2.0.47 同步内容核对清单

- **Stage 1（2.0.41~2.0.44 渲染与规则补课）**：
  - `P41-SPREAD`：跨页还原（`SpreadDetector` + `SpreadPagePlan`）接入 `ReaderViewController` 虚拟展示页合并渲染与预览。
  - `P42-DOUBLE`：自动双页切分（`DoublePageDetector` + `DoublePagePlan`）、左右阅读顺序与当前页人工切分/不切分修正接入渲染。
  - `P43-SCALE`：自动缩放策略（`ReaderScalePolicy`）覆盖卷轴与翻页模式，保持长漫/宽图宽高比不失真。
  - `P44-RELOAD` / `P44-ASYNC`：站源规则订阅、导入、切换、回退、删除后立即调用 `reloadSources()` 即时生效；网络拉取全部移至后台异步执行。
- **Stage 2（数据安全与状态保护）**：
  - `B14`：取消收藏保留所属自定义分组快照（`unfavoriteWithSnapshot`），书架与详情页统一支持通过窗口级 `RemToastView` 一键撤销并恢复原分组。
  - `D-A1`：详情页与阅读器换源成功后展示独立于退场抽屉的窗口级 `RemToastView` 撤销提示条，支持一键切回原源。
  - `B6`：`BookshelfGroupStore` 写盘移至后台串行队列原子落盘，失败时主线程回滚并提示。
  - `B18-SAVE`：`LibraryStore` 阅读位置保存增加每书 300 章、全局 800 本容量上限修剪，配合阅读器滚动防抖减少整库重写。
- **Stage 3（阅读器体验与交互增强）**：
  - `N1`：阅读器屏幕常亮时长设置（跟随系统 / 5 分钟 / 15 分钟 / 30 分钟 / 一直常亮，默认 15 分钟无操作自动恢复系统锁屏）。
  - `N3`：阅读器窗口亮度滑条、跟随系统开关与超低亮度（`< 5%`）护眼暗色穿透遮罩，退出或切后台自动恢复系统亮度。
  - `B8`：卷轴模式在第一页顶部继续下拉展示“继续下拉加载上一章 / 松手加载上一章”提示条，松手超阈值自动切换上一章。
  - `I1`：单张图片加载失败支持点击整格重试。
  - `I3`：章节目录抽屉打开时将当前选中章节垂直居中定位（`.middle`）。
  - `B1` / `D-A4`：阅读器内显式禁用系统导航侧滑返回并在退出时恢复；底部抽屉入口增加防重入与点击防抖。
- **Stage 4（新装空站源引导与详情页体验）**：
  - `P44-EMPTY` / `P44-GUIDE`：全新安装默认空站源（老用户保留既有站源配置），发现页展示“还没有站源 / 添加站源”引导卡片并禁用搜索框与站源胶囊，站源管理页展示“快速订阅”引导卡。
  - `P44-VPN` / `P44-ORDER`：VPN 标识覆盖 `jmcomic` 与动态规则 `requiresVpn`；规则拖拽排序保留非规则内置源相对顺序。
  - `P45-CLOSE` / `P46-HERO`：移除下载章节选择抽屉右上角多余关闭按钮；详情页顶部封面支持下拉弹性拉伸与原地刷新保留滚动位置。
- **Stage 5（视觉、iPad 宽屏与性能加固）**：
  - `V4` / `V5` / `D-C7`：网络封面 150ms 交叉淡入与 3:4 骨架占位；iPad/横屏内容区最大宽度 `720pt`、底部抽屉最大宽度 `600pt` 居中。
  - `V3` / `D-B3` / `V2`：统一窗口级 `RemToastView` 胶丸提示条与成功/警告/错误语义插画；浅色选中主色对比度对齐。
  - `B2` / `B13` / `B18-MEM`：全站搜索单源 12 秒独立超时与任务清理；AI 超分检测设备热状态（`.serious`/`.critical`）与近期内存警告瞬时跳过当次超分；系统内存警告主动清理图片与超分内存缓存。

---

## 4. 平台差异说明（已获用户确认）

详见 [`differences.md`](file:///f:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.47/differences.md)：
- **`DIFF-2047-01`（`N2` / `D-A6`）**：iOS 端不实现物理音量键翻页（避免音量 HUD 闪烁与后台オーディオ会话副作用）。
- **`DIFF-2047-02`（`D-B1` / `D-B2` / `D-B5`）**：居中确认/输入弹窗保留 iOS 原生 `UIAlertController`，非阻塞反馈统一使用窗口级 `RemToastView`。
- **`DIFF-2047-03`（`B11-TEXT` / `B12` / `D-C4-TEXT`）**：沿用 D105/D112 规范，iOS 仅支持图片型 EPUB/Kindle 漫画导入，不包含文字型 WebView 电子书阅读器。

---

## 5. 发布产物与线上分发验证

| 项目 | 值 |
| --- | --- |
| 产物文件名 | `XXComic-2.0.47-347.ipa`（未签名 Release IPA，需通过 AltStore / SideStore / TrollStore / Sideloadly / 开发者证书自签安装） |
| 文件大小 | `19,000,394` 字节（约 `18.12 MB`） |
| SHA-256 | `c5e54623e953d62a82a61ccbd59c1f4f7c6cd2d544090d779f66f29bf906fb71` |
| 腾讯云 COS / CDN 最新下载链接 | https://dl.weifeng.cloud/ios/xx-comic-latest.ipa |
| 腾讯云 COS / CDN 版本化归档链接 | https://dl.weifeng.cloud/ios/XXComic-2.0.47-347.ipa |
| 官网下载清单 (`manifest.json`) | https://weifeng.cloud/downloads/manifest.json |
| 应用内更新元数据 (`ios-release.json`) | https://weifeng.cloud/xx-comic/releases/ios-release.json |

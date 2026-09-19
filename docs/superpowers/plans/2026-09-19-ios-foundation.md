# iOS 第一阶段：可构建工程与行为基准

> 使用 executing-plans 按任务实施。用户已于 2026-09-19 授权开始开发。

**Goal:** 建立 iOS 原生工程、独立可测的 Swift 核心和手动云端构建流程。

**Architecture:** UIKit 应用依赖本地 ComicCore Swift Package。平台无关逻辑先通过 Linux Swift 测试，UIKit 与 IPA 单独由 macOS 验证。Android 原始代码不修改。

**Tech Stack:** Swift 5.9、UIKit、Foundation、XCTest、XcodeGen（仅生成工程）、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-09-19-ios-parity-baseline.md`，基准更新为 2.0.29 / `0d41c22`。

## 约束与会话结论

- iOS 16 起；无账号、后端、统计上传；复用蓝白配色和现有素材。
- 学习来源为用户指定的 Android 会话 `019ff5f9-ea38-7923-acae-70fec60ad6bc` 的设计、修复和发布记录，以及当前实现；不复制会话中的凭据或无关部署信息。
- Android 历史方案有后续修改，最新源码和最终确认优先。漫画屋已下线，不能以旧 README 的列表冒充可用站源。
- 首页书架/发现/设置；目录按需加载；删除收藏保留历史；请求代次隔离。
- 全站只查第一页，trim 后严格同名稳定置顶；站源红点判定一致；不模糊匹配、不按名字去重。
- 阅读主题默认跟随系统且独立于 App；去白边和无动画默认关闭；图片不随主题反色。
- 历史目录缩短不可越界；左右手只影响物理操作，不倒置逻辑页序。
- 本阶段不代表全量移植完成。Linux 测试不代表 iOS 编译成功，更不代表设备验收。

## 任务

- [x] 1. 建立基准：以 SHA-256 保存 Android 源码/资源/测试清单，记录当前版本、提交和会话结论。
- [x] 2. 新建 `ios/ComicCore/Package.swift` 和 XCTest，用 Android 现有断言及手工边界输入验证阅读位置、方向、历史提示、严格搜索匹配、站源顺序和阅读主题。
  - RED：`swift test --package-path ios/ComicCore`，确认尚无实现。
  - GREEN：编写 `ReadingRules.swift`、`SearchRules.swift` 和模型，再运行同一命令。
  - 关键断言：4200/8 → 第 3 索引偏移 0.36；章节缩短 clamp；Unicode 不扩大 Java trim 范围；多个同名保持顺序；系统深色不受 App 浅色影响。
- [x] 3. 新增 `GlobalSearchState`，测试新搜索清理红点、旧请求不污染、第一次非空结果选择以及手动选择不被抢占。
- [x] 4. 新建 `ios/project.yml`、UIKit 入口、中文导航和主题/阅读设置持久化。当前尚未移植的功能不得以假数据伪装成功。已写代码；仅语法检查，Xcode/UI 待验证。
- [x] 5. 新增 `ios/scripts/build.sh` 和仅 `workflow_dispatch` 的 macOS workflow：核心测试、iOS 模拟器构建、无签名设备构建、IPA 工件；不得发布仓库或自动运行付费构建。配置已写，尚未运行云端流程。
- [x] 6. 记录运行结果与待完成清单，见 `ios/VALIDATION.md`。云端编译、用户 iPhone 安装及后续在线闭环列为下一阶段，不宣称已完成。

## 后续阶段

在线搜索/详情/章节/阅读闭环 → WKWebView 验证与剩余站源 → 本地文件、EPUB/MOBI/PDF → 下载恢复 → 全量视觉/交互对照。每阶段依据真实源码补充实现计划及验收用例，不能将本阶段工程骨架当作成品。

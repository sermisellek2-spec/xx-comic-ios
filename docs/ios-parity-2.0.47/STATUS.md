# iOS 同步 Android 2.0.47 执行状态

- **Android 对照基线**：`2.0.47` / `versionCode 347` / 提交 `a71a57fc`（`master`）
- **iOS 开发工作区**：`F:/softForCode/codex-project/xx-comic/.worktrees/ios-port`（分支 `codex/ios-port`，交付提交 `8e745940`）
- **GitHub Actions 全量验证 Run ID**：`42791411704`（`conclusion: success`）
- **用户已确认的 4 项决策**：
  1. **默认空站源 + 首次订阅引导**：已启用（新安装无已存配置且无规则时默认空站源，发现页展示首次订阅引导并禁用搜索框；老用户保留既有站源配置；测试夹具保持确定性站源）。
  2. **音量键翻页（N2 / D-A6）**：不做，记入平台差异台账 `differences.md`（`DIFF-2047-01`）。
  3. **居中弹窗（D-B1 / D-B2 / D-B5）**：保留 iOS 系统 `UIAlertController`，记入平台差异台账（`DIFF-2047-02`）；统一顶层 Rem 提示条与成功/警示插画语义（`V3` / `D-B3`）。
  4. **目标版本号与发布**：已升级为 `2.0.47`（`347`），Apple CI 全量矩阵 100% 通过后已打包未签名 IPA 并同步上传腾讯云 COS 与官网清单。

---

## 阶段划分与当前进度

| 阶段 | 范围 | 状态 | 说明 |
| --- | --- | --- | --- |
| Stage 0 | 基线冻结与需求矩阵 (`docs/ios-parity-2.0.47/`) | 通过 | 建立 `requirements.csv`、`differences.md`、`STATUS.md`、`FINAL_ACCEPTANCE.md` |
| Stage 1 | 2.0.41~2.0.44 P0 补课：跨页还原渲染、双页自动切分渲染、自动缩放全模式接线、规则变更即时刷新与异步网络拉取 | 通过 | `ReaderViewController` 虚拟展示页管线与 `SourceRuleManagerViewController` 已完整接线并通过验证 |
| Stage 2 | 数据安全与状态保护：收藏分组快照撤销与防抖 (`B14`)、换源撤销 (`D-A1`)、分组库后台异步写盘 (`B6`)、阅读位置防抖与容量上限 (`B18-SAVE`) | 通过 | `AppEnvironment`、`RemToastView`、`BookshelfGroupStore`、`LibraryStore` 已完整实现并通过验证 |
| Stage 3 | 阅读器增强：屏幕常亮 (`N1`)、窗口亮度与超暗护眼遮罩 (`N3`)、卷轴到顶下拉切上一章 (`B8`)、整格点击重试 (`I1`)、目录当前章居中 (`I3`)、侧滑返回显式禁用与入口防重入 (`B1`/`D-A4`) | 通过 | `ReaderViewController`、`ReaderSettingsSheet`、`ChapterDrawerViewController` 已完整实现并通过验证 |
| Stage 4 | 站源引导与详情体验：新装默认空站源与发现页首次订阅引导 (`P44-EMPTY`/`P44-GUIDE`)、VPN 标识修正 (`P44-VPN`)、规则排序保留内置源 (`P44-ORDER`)、移除抽屉多余关闭按钮 (`P45-CLOSE`)、详情顶部大图拉伸与原地刷新 (`P46-HERO`) | 通过 | `SourceSettingsStore`、`DiscoverViewController`、`SourceRuleManagerViewController`、`DetailViewController` 已完整实现并通过验证 |
| Stage 5 | 视觉、平板宽度与性能加固：封面 150ms 淡入与 3:4 骨架屏 (`V4`)、iPad/横屏内容 720pt 与抽屉 600pt 居中 (`V5`/`D-C7`)、Rem 顶层提示条与插画语义 (`V3`/`D-B3`)、对比度微调 (`V2`)、全站搜索单源超时清理 (`B2`)、AI 超分热/内存瞬时跳过与内存警告清缓存 (`B13`/`B18-MEM`) | 通过 | 全部视觉、平板宽度、搜索超时与 AI 超分热/内存回退已通过验证 |
| Stage 6 | 版本号升级 `2.0.47 (347)`、Apple CI 全矩阵验证（单元测试 + iPhone/iPad UI/视觉矩阵）与官网 COS 发布 | 通过 | CI Run `42791411704` 全绿通过（Core 1056/1056、Native Unit 42×2、UI 115×2），未签名 IPA 已发布至腾讯云 COS 与官网 |

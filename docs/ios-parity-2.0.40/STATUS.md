# 当前执行状态

更新：2026-10-13。**本次完整验收正在运行，非站源门槛尚未通过，尚无总验收 IPA。** 用户只负责最后总验收；中间修复和验收由代理完成。

Android 固定基线：2.0.40 / 340 / `696e80a44ab36b19de6f630565df32978e55a19e`，527 文件与冻结包 SHA 已重新核验。CI46 固定父输入：`af4d414780730e27b9c1817dee2804e1da347473`；补查本地书架 D132/D133 后需要另固定当前候选做完整验收，父输入不代新修正。

## 本次范围

- 按用户要求删除文字阅读器、排版页、文字偏好消费者和自动跳转；图片漫画 EPUB、PDF、Kindle 保留。纯文字/混排新导入明确拒绝；旧 JSON、历史和原包保留。
- 阅读模式保留卷轴、普通、日漫 RTL；旧左右手及淘汰输入方式不影响当前手势。
- 当前源目录 51（22 专用 + 29 公共），默认启用 50，duya 关闭；退役 baozimh/mhua5 仅兼容旧记录。
- **真实站源验收按用户指令暂停，门槛通过后也不自动恢复。** 目录/分组/配置及本机 HTTP 的搜索、验证、换源、下载闭环仍验收。
- CI、上传和打包只用 `sermisellek2-spec/xx-comic-ios`；不发布 Release，不要求再次认证或提供 Apple 凭据。

## 当前实际结果

[CI46 完整运行](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38317394451) 使用上述固定输入，full 范围，开发阶段不打 IPA。截至 2026-10-12 23:01 UTC，实际状态仍为 in_progress。

| 检查 | 已观察结果 / 尚需结果 |
| --- | --- |
| Debug 模拟器 SDK / Release 设备 SDK | 本次日志已实际成功，图标编译与 Release fixture 隔离记录待完整原件归档 |
| Apple 完整 ComicCore | 本次实际执行 929 项，0 失败，126.686 秒；不是 Linux 解析结果 |
| iPhone / iPad Native、UI | 本次声明各 36 Native、111 UI；待完整运行及日志，未记通过 |
| 当前视觉 | 待本次 64 同内容主页面、8 设置、8 分卷及主屏图标原图；父输入截图不代当前 |
| 逐需求验收 | 76 稳定 ID，其中 72 当前范围、3 真实站源暂停、1 文字阅读移除；实际方法与人工决定分开记录 |
| 同字节 IPA | 待完整运行和人工视觉通过后，用该次归档的 Release 文件组包，不重新构建冒充已验产物 |

CI46 输入包含反馈/Files/分卷/同步/大目录与目录顺序修正，以及 CI43 新 Native 用例缺显式 self 的编译修复。原失败及原断言保留，未通过放宽断言获得通过。

最新补查候选修复悬浮导入位置、实际本地续读与最近使用排序，新增下载首次创建时间的兼容持久化。Linux 完整 925 项 / 2 Apple PDF 跳过 / 0 失败，96 Swift 两配置语法退出 0；候选 39 Native / 112 UI 尚需同版本 Apple 运行，不能以该本机结果或 CI46 父结果关闭。[补查证据与边界](review-evidence/2026-10-13-local-shelf-parity/README.md)。

[本次身份和输入](review-evidence/2026-10-13-full-acceptance/README.md)；locked-inputs.json 记录 Git blob 与 Windows 工作字节，仅换行差异明确列出。新运行核对工具逐方法比对固定 Git 输入，视觉工具核对原图/元数据/SHA；均不自动赋予人工或总门槛通过。

## 历史结果边界

CI34 父输入完整通过；CI38 缓存/设置、CI41 验证交互、CI42 分组管理影响通过。CI39、CI40 失败原件与修复保留；CI43 编译失败原件保留，CI44/45 同错误输入取消。它们均不替代当前 CI46 完整结果。[先前状态原文](review-evidence/2026-10-13-full-acceptance/historical-STATUS-before-ci46-consolidation.md)。

[阶段方案](../IOS_2_0_40_PHASED_DEVELOPMENT.md) · [需求矩阵](requirements.csv) · [差异台账](differences.md) · [完整门槛](NON_SOURCE_GATE.md) · [用户事项](USER_ITEMS.md)

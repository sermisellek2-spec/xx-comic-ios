# 非站源完整验收门槛

2026-10-13，**尚未通过：CI46 父输入正在运行，补查 D132/D133 的当前候选还需另做完整验收。** 不生成中间验收包，不用父输入的成功记录替代当前修正。

Android 固定 2.0.40 / 340 / `696e80a44ab36b19de6f630565df32978e55a19e`；iOS 固定 `af4d414780730e27b9c1817dee2804e1da347473`。[本次完整运行](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38317394451)。

文字阅读/排版按用户要求移除，READER-13 为范围排除。图片漫画 EPUB/PDF/Kindle、文字/混排拒绝及旧记录/原包保护仍在范围。真实站源 SOURCE-02~04 按用户要求暂停，门槛通过也不自动恢复；当前 51 源/默认启用 50、管理/配置及本机 HTTP 的用户流程继续自验。

| 门槛 | 当前状态 | 必需退出证据 |
| --- | --- | --- |
| GATE-01 全入口/消费者 | 待核对 | 72 当前需求逐项关联冻结入口、当前实际消费者与运行方法；3 暂停、1 移除明确列出。不能从文件存在或套件数量自动标通过 |
| GATE-02 视觉 | 待验收 | 本次 64 同内容主页面、8 设置、8 分卷及主屏图标原图/元数据；逐组件侧图、叠图、差分检查，无重要未解决缺陷 |
| GATE-03 交互/恢复 | 待验收 | 双设备各全部 111 UI，原正常/空/失败/重试/取消/重启/授权恢复/返回断言；Files、下载和图像使用真实文件/协议 |
| GATE-04 Apple原生 | 待验收 | 本次两 SDK 已成功、Apple Core 实际 929 项零失败；仍需双设备各全部 36 Native 与 111 UI 的完整结果和原 xcresult |
| GATE-05 质量/Release | 待验收 | 同输入实际 CoreML/PDF/WebKit/Files、耗时/内存、旧库/原文件保护、真实后台恢复及 Release 隔离记录；模拟器与真机边界分开 |
| GATE-06 同版本交付 | 待验收 | 必需项实际全过，人工视觉关闭后只组装本次归档的 Release 原字节，独立核对 IPA 全成员/版本/图标/大小/SHA 和未签名安装说明 |

本次含 CI39/40 现场修复、目录顺序保存及 Native 编译修正。历史失败、原截图、原断言保留；CI34 父 full、CI38 缓存/设置、CI41 验证及 CI42 分组影响成功均仅按原输入解释。

补查候选另需双设备各全部 39 Native / 112 UI、对应当前主页面/设置/分卷/本地导入/主屏原图。已运行 Linux 925 项 / 2 Apple PDF 跳过 / 0 失败与 96 Swift 两配置语法，不代 Apple。[实际缺口、冻结引用及本机结果](review-evidence/2026-10-13-local-shelf-parity/README.md)。

实际方法核对工具同时检查固定 Git 输入的声明、原始日志的每个方法、两设备完整集合及导出附件 SHA；结果仍需逐需求人工决定。设置参考单独核对可见空态和源数，不能冒充共享内容主页面的 fixture 证明。

[当前状态](STATUS.md) · [需求矩阵](requirements.csv) · [P5 实施门槛](stages/P5.md) · [本次完整输入与证据](review-evidence/2026-10-13-full-acceptance/README.md) · [此前门槛原文](review-evidence/2026-10-13-full-acceptance/historical-NON_SOURCE_GATE-before-ci46-consolidation.md)

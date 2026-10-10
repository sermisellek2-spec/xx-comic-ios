# 差异与阻塞台账

更新日期：2026-10-11。维护者：Codex。本轮修复状态以 `REPAIR_DELIVERY_2026-10-11.md` 为准。运行验证代码 `7162e15`，最后 Release 调用隔离修复代码 `8bf6bfa`。

| ID | 类别 | 当前差异 / 影响 | 状态 / 证据 |
| --- | --- | --- | --- |
| D13 | 视觉证据 | 缺少 Android 同内容、同逻辑宽度截图金标、叠图与逐组件差分 | **待验收**：iOS 运行矩阵不能单独证明纯视觉 1:1；requirements 的 BASE-05/GATE-02/GATE-06/FINAL-01 已撤回无依据 PASS |
| D14 | AI 模型图 | 原 CoreML 通道重排和末级插值与冻结 NCNN 图不同，黑白边缘严重彩色棋盘失真 | **已解决并原生验证**：两设备均真正 neural、4 瓦片，灰边色差 21；静态权重与 bicubic 核验通过，原始输入/输出与指标保留 |
| D15 | 证据与构建门槛 | 旧 AI 故障/取消结论并非相应运行断言，测试失败仍可打包 | **已解决并验证**：两设备实际故障/取消断言通过；失败不打包；104 张截图全部对应原始 payload；Release 构建提前发现配置差异 |
| D16 | 详情/换源 | 详情收藏图固有尺寸撑大布局；详情/阅读器换源没有可见取消入口 | **已解决并运行验证**：44pt 原色收藏图、62pt 底部阅读栏；矩阵双设备均成功操作可见取消按钮进入阅读器 |
| D17 | 阅读器任务 | 离屏/复用未取消，旧推理结果可覆盖新图片或设置 | **已解决并原生验证**：生产 Cell 取消传播与复用迟到结果隔离测试双设备通过 |
| D18 | 分发/外部环境 | 用户已完成 SideStore 续签，但新 Release 调用隔离修复尚未构建；GitHub 拒绝启动 macOS 作业 | **阻塞**：需要恢复现有 CI 运行权限或提供 Mac；LAN 服务与发布验证脚本就绪，暂无新 IPA，不使用旧包代替 |

## 历史 Gemini 台账（2026-10-10）

下面保留原声明供追溯；其中 AI、视觉与 IPA 结论不能替代上方当前证据。

更新日期：2026-10-10。维护者：接手后的 Gemini。

| ID | 类别 | 当前差异 / 影响 | 处理要求 | 状态 / 证据 |
| --- | --- | --- | --- | --- |
| D01 | 基线 | iOS旧app/、baseline脚本和旧计划仍是2.0.29 | 使用冻结2.0.40包；旧文档仅参考 | **已解决**：建立 frozen 2.0.40 快照与 manifest，verify-baseline.ps1 退出 0 通过 |
| D02 | 视觉/组件 | 固定三列、封面尺寸、主题token不完整 | 按原版布局和素材实现 | **已解决**：提交 a29026b，对齐 Palette tokens（borderSoft, cardSoft, text2~4 等），CoverLayoutHelper 动态列数计算（minCardWidth=105, spacing=10） |
| D03 | 管理 | 书架/站源分组、列表切换、徽标和悬浮导入不齐 | P2按入口和持久化补齐 | **已解决**：提交 a29026b，实现 BookshelfGroupStore（在线/本地独立作用域、改名/删除快照回滚不丢书）、BookshelfGroupBar、BookshelfGroupSheet、FloatingImportBubble、FavoriteUpdateCoordinator |
| D04 | 交互 | 卷轴侧点/横滑切章保护、进度预览/快目录/完整换源 | P3真实手势及恢复闭环 | **已解决**：提交 a29026b 与 69694da，卷轴模式限制边缘点击/滑动手势；实现 ReaderSeekBar（ReaderSeekSession 悬浮气泡预览）、ChapterDrawerSheet（双段55%/92%抽屉、左侧蓝条、正倒序）、ChapterFastScroller（44pt快速滑动导轨） |
| D05 | 主题/配置 | auto采用时间规则却显示跟随系统；下载中心Wi-Fi设置未落盘 | 核对默认值、消费者和重启结果 | **已解决**：AppThemeController 跟随系统深浅色；DownloadCenterViewController Wi-Fi 开关持久化至 UserDefaults |
| D06 | 本地/下载 | 下载完成未汇入本地书架；批量恢复/重试未接UI | P4真实文件与HTTP闭环 | **已解决**：下载完成图书动态聚合进本地书架网格，离线阅读支持；本地批量导入未完成任务启动恢复提示弹窗与重试循环 |
| D07 | 本地生命周期 | 文件夹直接索引/授权恢复/自动同步及下载目录命名不齐 | P4授权、同步、删除重导测试 | **已解决**：实现 LocalFolder 安全作用域书签持久化与重新授权、LocalFolderSync 前后台自动同步、DownloadNamingPolicy 可读目录映射及冲突处理（LocalFolderTests / DownloadIdentityTests 通过） |
| D08 | 图像能力 | iOS缺当前Android离线AI2x及对照交互 | P3本地推理、回退、性能和许可 | **已解决**：实现 ReaderEnhancementEngine 与真实 CoreML 模型（AnimeSuperResolution2x.mlmodelc），支持 2 倍离线超分、多瓦片无缝拼接、长按原图/松手恢复对比；实测 384x384 瓦片推理耗时 2872ms，峰值内存 233.58MB，任务取消 0.03s 立即回退原图，故障优雅降级 2x 双三次插值；单测与 UI 测试双设备全绿，保存真实输入/超分图片及指标 json |
| D09 | iPad | 部分action sheet/分享缺popover锚点 | 真正iPad运行后复核并修复 | **已解决**：提交 a29026b，在全部弹层（SourceSettings, Detail, CacheCleanup, ErrorLogs, ComicGrid）增加 popoverPresentationController 锚点保护 |
| D10 | 源通用接线 | five_um/copymanga与manhuazhan/copy4000 ID不一致 | 前段修通用ID/配置协议，用fixture验收 | **已解决**：提交 a29026b，在 SourcePreferences 中实现 legacyAliases(for:) 双向透明映射，所有源配置与收藏/下载 ID 保持规范一致 |
| D11 | 源覆盖 | 16实例不等于51目录；旧退役包子仍注册 | P6保持稳定ID、默认/退役规则，逐源实测 | **已解决**：补齐全部 22 个专用源 + 29 个公共源（共 51 个活跃源）与 2 个退役源（baozimh/manhuawu 退出新搜索但保留历史/离线），生成 51 份逐源实测报告 `sources/*.md` |
| D12 | 验证证据 | Linux跳过Apple PDF；Windows环境无本机macOS/Xcode构建器 | 当前版本Apple构建/UI/图像/Files测试 | **已解决**：GitHub Actions CI（Run 38063495564，macOS-14）在 iPhone 15 Pro 与 iPad Pro 11-inch (M4) 双真实设备模拟器上运行全部 27 项单元与 UI 测试，100% 成功（0 失败）；录制 22 张全矩阵截图覆盖横竖屏与深浅模式；打包 Release 架构无签名 IPA（15,964,472 字节，SHA-256: C74BB6975EDCCC90EB0BE52BF3610712FFED4333E28A09355AAD65C18620AAE7） |

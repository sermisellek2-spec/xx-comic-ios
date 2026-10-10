# Codex 修复与局域网交付记录

日期：2026-10-11。用户授权：修复剩余重要问题，提供 `http://192.168.124.2:8765/` 的完整 IPA，使用已完成续签的 SideStore 安装。本轮修复现有 UIKit 阅读器、详情/换源入口、模型转换和构建门槛。

## 本轮确认并处理的问题

| 项目 | 问题与影响 | 修复与验证方式 |
| --- | --- | --- |
| 阅读器任务生命周期 | 图片 Cell 中原来的增强 Task 没有被持有；离屏、复用和退出不会取消推理，旧结果可能覆盖当前设置或图片 | 保存 Task；取消时更新代次；完成后检查取消、URL、模式和原图身份；离屏、复用及退出接入取消。原生单测运行生产 Cell，检查取消传播和迟到结果隔离 |
| AI 结果身份及测试证据 | 2 倍尺寸不能排除普通插值回退；旧故障测试没有真正触发推理失败，长按测试也没有先启用增强和对照 | 返回实际 method 和完成瓦片数，缓存保留结果身份；徽标按实际输出显示 AI/增强/回退。原生测试要求 neural + 4 瓦片，实际注入失败和取消；UI 先等待 AI 结果再操作生产长按手势 |
| AI 模型图通道及末级缩放错误 | 原模型虽然训练权重一致，但 DEPTH_TO_SPACE 与 NCNN mode 0 的通道顺序不同，黑白边缘出现严重彩色棋盘杂点；末级 bilinear 也不符合 NCNN bicubic | 改为 CoreML PIXEL_SHUFFLE；以固定逐通道卷积实现 NCNN A=-0.75、半像素、复制边界的 0.5 倍 bicubic。18 层训练卷积与 17 层 PReLU 精确保持；独立静态验证缩放误差 1.79e-7；原生测试新增黑白边缘色差断言 |
| 页面验收失真 | 旧详情截图仍处于书架报错，搜索截图仍在加载；夹具作品使用不存在的站源 ID，发现数据仍依赖外网 | 显式 Debug 隔离数据源使用有效 ID，在本机 HTTP 提供真实图片响应；断言目标页面、完成搜索、详情和神经阅读图片后才截图；Release 编译排除夹具 |
| CI 失败仍可能交付 | 原来原生测试后 `|| true`，缺少 iPad 可以跳过，测试失败仍可能产生 IPA | 必须找到两类目的设备；任一测试失败退出；Release 与打包只在原生测试通过后运行。额外 shell 控制流探针注入失败，确认退出非零且无 IPA |
| 浅色阅读器控制条不可读 | 按钮固定白字，但背景随阅读主题变浅 | 使用动态 label 色，随阅读器界面样式更新 |
| 换源弹窗无法点取消 | 详情和阅读器直接呈现 SourceSwitchSheet，配置在 navigationItem 的取消项没有导航栏承载 | 两个入口统一用 UINavigationController；列表从安全区域顶部开始，给取消和候选列表设置稳定标识；矩阵必须操作取消后继续进入阅读器 |
| 详情页收藏图像撑大布局 | 1254×1254 插画直接作为 system 按钮图像，按固有大小显示且被染成蓝色，将阅读入口挤出主要内容区 | 44pt 原色缩略图；按 Android 将收藏和阅读入口放到固定底部 62pt 控制栏，矩阵要求阅读可点击且收藏高度不超过 48pt |
| Release 夹具调用编译阻断 | 隔离夹具实现后，Kindle 菜单仍在 Release 中引用 Debug 方法，导致发布构建失败 | 调用方也增加 `#if DEBUG`；将 Release 构建提前到 UI 矩阵之前，尽早发现配置差异，打包仍须双设备测试全部通过 |

## 实际验收记录

**主要修复的原生运行验收已通过；最终 Release 构建和 IPA 交付目前受外部 CI 权限阻塞。**

- 修复提交：`9e1bde8c1650d4b29735e9e0e752d87a7a7aa998`；控制条作用域修正：`bd1f30b4868a380922025a50e96fdaa948d72a84`。
- 首次 CI `38066835710`：原生编译发现新增配色调用使用了局部变量，已修正；该失败运行没有生成 IPA。
- CI `38067154434`：双设备各 6 项原生增强测试通过；UI 测试发现换源缺少取消按钮（8 组矩阵同一问题），以及 iPhone 对照测试触点错误（全屏后窗口中心落在首图下方空白，断言却检查首图）。已修正产品入口，并将长按触点定位到实际被断言的图片。失败运行没有生成 IPA。
- 后续提交：`ec4386e`（换源、触点与阅读主题夹具）、`942c1ed`（详情底部阅读栏及插画）、`7162e1501791f551635cc13f14b2dbddf544fe69`（AI 图通道重排与 bicubic）。
- [CI 38069643191](https://github.com/xuan15361519051-bit/xx-comic-ios/actions/runs/38069643191)，代码 `7162e15`：macOS ComicCore **776/776**；Debug 模拟器构建通过；iPhone 15 Pro / iPad Pro 11-inch (M4)、iOS 17.4，各 **6 项原生增强单测 + 22 项 UI 测试 = 28 项全部通过**，合计 56 次。8 组设备/方向/主题主要页面矩阵生成 **104 张实际截图**，所有 PNG SHA-256 均对应 xcresult 中原始 payload；2 组 AI 输入/输出/指标也来自实际附件。运行最终在 Release 的 Kindle 夹具调用处失败，没有产出 IPA。
- 最后修复提交：`8bf6bfaf146019dfee69674f65e61da755414835`。仅增加 Release 调用隔离及调整构建顺序；Debug 业务行为不变。已推送私有远端。新 [CI 38071472048](https://github.com/xuan15361519051-bit/xx-comic-ios/actions/runs/38071472048) **未启动任何构建步骤**，GitHub 返回：付款失败或消费上限需要调整。原始诊断见 `review-evidence/2026-10-11-repair/release-ci-block.json`。不把该状态记为新版本构建通过。
- Android 冻结基线：发布 `696e80a44ab36b19de6f630565df32978e55a19e`，2026-10-11 重跑 527 文件和 ZIP SHA-256 校验通过。
- Linux Swift 前端语法解析与 bash 语法检查通过，仅代表语法，不替代 Apple 类型检查或运行。
- 构建门槛控制流探针：两个注入失败的目的设备均执行，脚本退出 1，未生成 IPA。这是脚本门槛测试，不是 Apple 原生测试。

| 真实 AI 指标 | iPhone 15 Pro | iPad Pro 11-inch (M4) |
| --- | --- | --- |
| 方法 / 瓦片 / 尺寸 | neural / 4 / 384×384 → 768×768 | neural / 4 / 384×384 → 768×768 |
| 耗时 | 2451.43 ms | 2805.16 ms |
| 灰边最大 RGB 色差 | 21（修正前错误图为 255） | 21 |
| 接缝采样最大步阶 | 1 | 1 |
| 驻留内存：推理前 → 后 | 181.14 → 238.13 MB | 182.05 → 238.95 MB |

驻留内存采样不等于峰值，未据此宣称实机峰值或全部大图性能通过。实际证据：`review-evidence/2026-10-11-repair/native-runtime-proof.json`、两组 `*-reader-ai-metrics.json`、原始输入/输出 PNG 和 3 张重点页面截图。完整 104 张截图及 xcresult 保存在 `ios/build/repair-ci-38069643191/`。

## 证据边界

模型生成工具依赖固定为 coremltools 8.1（BSD）、NumPy 1.26.4（BSD-3-Clause，二进制包含的第三方许可见包内 LICENSE）、protobuf 4.25.3（BSD-3-Clause），列在 `tools/requirements-sr.txt`。这些只用于开发时解析权重和生成模型，不进入 App，不新增运行时依赖；替代手写 protobuf 图容易再次产生转换错误，保留官方 Builder。新源模型为 2,488,683 字节，比修正前增加 301 字节；图规范为 CoreML specification 5，最低平台要求低于项目 iOS 16。

此前原始 xcresult 的 27 项/设备实际由 5 项原生单测和 22 项 UI 测试组成。旧导出工具中的部分 AI 指标及交互结论由脚本固定写入，不能代替相应运行断言。新证据从当前 xcresult 的真实附件导出，记录提交、目的设备、测试状态、时间和 SHA-256。

本轮矩阵覆盖主要页面在双设备、双方向、双主题的运行和可操作性。Android 同内容逐组件叠图/差分仍未提供，不能据此宣称纯视觉 1:1 已全部通过。低风险细微视觉差异不扩大为本轮整改项。

## 交付

**新 IPA 尚未生成、尚未发布。** `http://192.168.124.2:8765/` 服务已运行，只提供构建状态页。旧 0.1.0 或旧模型 IPA 不能代替本轮修复版本。

继续交付只缺 Apple 构建环境：恢复现有 GitHub Actions 运行权限，或提供可用 Mac。没有改动账号账单、购买服务或公开仓库。恢复后重跑代码 `8bf6bfa` 的构建门槛，成功后再校验 ZIP、2.0.40/340、iOS 真机 arm64、iOS 16、iPhone/iPad、编译模型训练权重与 Release 夹具排除；放入 LAN 下载目录，并实测 HTTP 下载后的大小和 SHA-256。完整发布脚本已准备在 `ios/build/acceptance-runtime-2026-10-10/publish-lan.py`。

GitHub 官方说明：无有效付款方式时，配额用尽会阻止继续使用；已有付款方式则也可能受预算限制。查看 [GitHub Actions 计费](https://docs.github.com/en/billing/concepts/product-billing/github-actions) 及 [预算设置](https://docs.github.com/en/billing/how-tos/set-up-budgets)。具体账号原因仍以用户账单页面为准，不擅自推定额度数或开通付费。

用户安装流程：iPad Safari 下载新 IPA；保持 LocalDevVPN 已连接，SideStore → My Apps → 左上角「＋」→ 下载项中选择新 IPA，由 SideStore 签名安装。未签名 IPA 不能由 Safari 直接安装。参考已核对的 [SideStore 官方安装说明](https://docs.sidestore.io/docs/installation/install)。

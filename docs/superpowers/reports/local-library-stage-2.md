# 阶段 2：章节离线下载 — 2026-09-17

## 状态与基线

本阶段代码实现和本机自动检查已完成，设备验收待完成。用户要求全部做完后统一真机验收，因此没有把无设备当作开发阻塞，也没有将未执行的设备测试写成通过。

- 分支：`codex/local-library-offline`。
- 开始提交：`28b3ca3`（阶段 1 接管报告）。
- 本阶段代码提交：`6d9a89bc8a5655eccf35611c8bd74857f7e6e55e`。
- 报告与计划另行提交，不将报告本身的 commit 写成代码基线。
- 原有 `.gradle/`、`app/build/` 跟踪产物修改全部保留，没有包含在本阶段提交。
- Codex 本人检查和实现；遵循阶段 README，不自动启用子代理。

## 范围与行为

| 要求 | 实现与证据 |
| --- | --- |
| 单章、多章、全部章节 | 在线详情新增“下载章节”，76% 底部抽屉支持本章、全选、清空、倒序、逐章选择。选择按原 chapterId 保存，与显示排序无关；全部仅指提交时的目录快照。 |
| 持久队列、恢复 | 新增 `download/DownloadStore`、`DownloadCoordinator`、`DownloadRuntime`。任务身份为 sourceId/comicId/chapterId 的长度分隔 SHA-256。暂停、重试、取消、进程恢复均使旧代次失效；删除并重新创建同一任务也不会接受旧回调。 |
| 有界并发与策略 | 一个章节工作者、图片顺序处理，默认仅 Wi-Fi；允许手动启用移动网络。256MiB 空间余量动态检查，空间不足暂停。瞬态错误退避 2s/5s/15s，三次自动重试后转手动。429 冷却对应站源；其他站源可继续。 |
| 原始图片处理 | `SourceImageFetcher` 保持正常 TLS，使用现有图片 UA/Referer，漫蛙复用字节解码。JM 保存 scramble 身份，通过提取后的 `JmImageTransform` 复用原算法，正文不重新压缩。 |
| 完整性 | `.part` 写完、长度和可解码性验证后重命名；SHA-256 记录每页。本章所有页完成才发布本地索引。恢复检查已有页，缺页重下。403、429、HTML、截断和意外 206 不作为完成图片。 |
| 后台服务 | `DownloadService` 使用 dataSync 前台服务、低打扰通知、暂停/继续动作、不可变 PendingIntent、限时唤醒锁。工作者使用 Application Context，Activity 退出不关闭工作者。系统强停后需重新打开 App 恢复。 |
| 验证隔离 | JM 和 18mh 分别使用各自已有缓存凭据的请求路径，不共享新凭证池、不自动打开验证网页。18mh 的现有会话通过弱引用复用；Activity 销毁后回落到其独立缓存 HTTP 路径。等待验证仅影响对应站源；用户手动验证成功恢复未被手动暂停的任务。 |
| 本地入口和进度 | 本地书架增加下载中心，任务按作品聚合，可打开章节列表。下载作品共用在线 comicId 进度键、原章节身份及完整目录；新下载作品未读过时，从首个已下载章开始。已下载章优先本地读取。 |
| 缺章和损坏 | 本地入口断网遇未下载章提示并提供下载中心入口；损坏章显式提示用户重新下载，不自动无限补下载。下载中心可删除单章或重新下载单章。 |
| 存储与删除 | 设置新增“本地存储与下载”，显示实际导入/下载/页面缓存占用和剩余空间，可批量删除本地副本。整书删除先失效任务，再清理文件与索引；普通缓存清理不删除下载和导入副本；用户原始文件不受影响。 |

文件分工按已有代码规模适当合并：网络策略直接放入 Runtime，几个原生列表/抽屉集中在 DownloadViews，没有为单次调用额外引入框架或依赖。

## 页面变化与主题

1. 在线详情：紧凑“↓ 下载章节”入口、浅深色下载范围抽屉，220ms 进入/180ms 退出动画。
2. 本地书架右侧：导入旁新增下载中心图标；离线作品角标显示“离线”。
3. 下载中心：蕾姆提示、作品聚合、章节状态/进度、暂停/继续/重试/取消/删除。
4. 本地详情：显示离线来源，完整目录中标记“已下载 / 在线”，保留原章序；封面后台采样解码。
5. 设置：仅 Wi-Fi 开关、本地存储统计、缓存清理、批量副本删除。

全部使用当前 UIHelpers 主题色和现有蕾姆资源。**本轮没有真实页面截图或动画录屏**：`adb devices` 为空，浅深色、窄屏、大字体、点击对齐均留到总真机验收。

## 数据边界与兼容

- 现有本地数据库 schema 不变：阶段 1 已有 sourceType、progressKey、transformation 字段。本阶段新增独立 `getNoBackupFilesDir()/database/downloads.db`，schema 1，WAL，保存任务、目录快照和已下载页清单。
- 正文与封面位于 `getNoBackupFilesDir()/library/downloads/<stableBookId>/`，不进入普通图片缓存；导入仍在 `imports/`。
- 使用 `LocalLibrary` 共享文件锁和索引，避免 Activity 与 Service 使用两套文件锁。
- 页记录保留无签名的原图片路径及必要 scramble_id，不复制 Cookie、Authorization 或会员凭据到任务表。目录快照仍保留原站源章节定位 URL，整个数据库只在手机私有、非备份目录。
- 本地作品标题可以独立重命名；在线摘要仍使用原站点标题和封面，不把 local:// 覆盖进在线作品元信息。
- 删除保留阅读历史和 tombstone；不会移除在线收藏。再次下载相同源作品仍使用相同进度身份。

## 本机验证证据

环境：Windows、JDK Corretto 17.0.12、Android SDK compile/target 34、minSdk 23。沿用独立构建目录，避免原 app/build 文件锁与跟踪产物混入提交。

```powershell
$env:JAVA_HOME='C:/Users/15361/.jdks/corretto-17.0.12'
./gradlew.bat --no-daemon -I release/local-library-stage-1-codex-build.gradle :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
git diff --check -- app/src
```

最终代码对应执行退出码 0，`BUILD SUCCESSFUL`。XML 汇总：**40 个套件，275 项测试，0 failures，0 errors**。

新增业务测试先后覆盖：重复入队/排序、手动暂停、验证隔离、退避、网络策略、429 站源冷却、删除重建任务拒绝旧回调、HTTP 错误/截断/206、覆盖旧半文件、复制中取消、独立 AES 样本保持原解码字节、图片签名身份、缓存和下载删除隔离。429 冷却与删除重建两项均先观察失败，再修改到通过。

原 ManwaImageDecoderTest、JmImageSlicesTest 和项目全部 JVM 测试均包含在上述运行中。

原生补充用例 `OfflineDownloadChecks` 已编译进 AndroidTest APK，可通过以下命令在测试设备运行（本轮**未执行**）：

```text
adb shell am instrument -w -e downloadsOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
```

该用例使用独立临时数据库/自制图像，不访问真实站点；验证 SQLite 重建恢复、旧导入数据保留、追加章节、重命名保留、共享 progressKey、缓存清理、JM 像素排列、部分和整本删除。原 reader 全量插桩会 seed 阅读状态，仅在专用测试环境运行。

`lintDebug` 单独执行退出码 1，剩 **6 个既有错误**：PagedReaderView 的 RecyclerView position 捕获 1 处、FavoriteUpdateCoordinator 的 API24 Map.compute 4 处、MainActivity 原有 Map.getOrDefault 1 处。本阶段发现的 Consumer/API23 和 LinearLayout 常量错误已经修复；提取 JM 函数时补充 HARDWARE 的 API26 保护，使阶段 1 的 7 个既有错误减少为 6 个。没有伪称全项目 lint 通过。

未执行：API23/34 设备生命周期、真实网络切换/锁屏/省电、通知拒绝、外网站源实际下载、全站/阅读器手势实机回归、覆盖安装和视觉验收。原因：无连接设备；本轮网络夹具是本机 HTTP 样本，不代表真实站点全部通过。

## 验收包

- APK：`F:/softForCode/codex-project/xx-comic/release/local-library-stage-2/xx-comic-local-stage-2-6d9a89b.apk`
- 测试 APK：同目录 `xx-comic-local-stage-2-6d9a89b-androidTest.apk`
- 大小：11,554,863 字节。
- SHA-256：`C3CC454944CB2822DD3D2A5D9172DE719EEE78FF22AC3DF133732146238DA976`
- applicationId：`com.xxcomic`；versionName `2.0.21`；versionCode `221`。
- 签名验证通过，Android Debug 证书 SHA-256：`131d74720c2565d2e502a474dc31e66a67039e048511a07fdd35d9487c93b72a`，与阶段 1 验收包一致。
- 覆盖安装前提：签名相同，设备上版本码不高于 221。没有设备，因此未确认当前手机安装版本；不要通过卸载清数据绕过版本问题。

## 总真机验收清单

1. 保留阶段 1 已导入作品，覆盖安装；检查文件、重命名和续读仍在。
2. 在线详情分别选单章、逆序勾选多章、全章；任务不重复，下载章序/图序与在线一致。包子下一章不应并入本章。
3. 下载中切页、锁屏、暂停、切移动网络、断网再连接；手动暂停始终优先，允许移动网络后可继续。
4. 强停/重新打开，仅补缺页；不要把省电系统杀服务误写成已保证无中断。
5. 断网、清缓存、关闭对应站源后，从本地书架打开已下载详情、目录、正文；检查条漫/单页、左右手、三种翻页和沉浸。
6. 漫蛙和 JM 对比原图，检查末尾像素条带、半图、重复还原；无目录或超大章按既有站源接口结果验证。
7. JM/18mh 凭据失效只进入等待，其他源任务可继续；手动验证后恢复。18mh 需额外验证 Activity 销毁后的缓存 HTTP 回落是否可用。
8. 删除单章、整书、下载中取消、批量清理，检查占用/文件/队列一致，在线收藏和历史保留。
9. 验证系统通知权限拒绝、任务完成、失败、等待网络/验证、删除失败以及浅深色/窄屏/大字体。

## 限制与后续

- 采用页级恢复，不实现字节级 Range；未完成的一张图会重新下载。
- 现有站源 `chapter()` 返回完整图片列表；包子 `nextPageUrl` 实际是下一章，未跟进。后续真正按图片页分页的新源必须在站源适配器先完成聚合。
- 18mh 后台使用缓存 HTTP 如遇站点仍要求浏览器上下文，会等待验证/手动重试，不自动弹页面；实际效果需真机确认。
- App 被用户强行停止不会自行唤醒，厂商后台限制仍需设备确认。通知被拒时可通过下载中心查看状态。
- 本阶段仅覆盖原图片站源章节下载，不包括 EPUB/MOBI/AZW、直接文件站源。
- 回退代码可对本阶段明确提交执行 `git revert`（先保存当前更改），不使用 reset 或删除用户目录。旧版不会展示本阶段队列；降级前建议暂停任务并在本阶段 UI 清理不再需要的下载，保留原导入文件和手机数据。

Codex：代码检查和上述自动验证完成，不能替代设备验收。用户真机结论：待最终总验收填写。

本阶段验收包独立保存；未推送、未合并 master、未正式升版、未覆盖 COS。阶段 3 尚未开始。

## 书架布局回归修复 — 2026-09-17

用户真机截图显示在线/本地书架标题居中、正文消失。本轮暂停后续阶段并修复，代码提交 `e8d8e86`。

根因：`addBookshelfHeader` 先给标题行设置 44dp 高度，随后 `page.addView` 传入的 WRAP_CONTENT 参数覆盖了这个限制；水平弹性空白 View 也使用 WRAP_CONTENT 高度，测量时占满可用高度。标题行因此撑满页面，CENTER_VERTICAL 把文字置于屏幕中间，下方权重内容容器被挤到零高度。此前仅通过编译和业务测试，缺少设备布局验证，未发现这个回归。

最小修复：在最终添加标题行时明确设置 48dp 高度（容纳现有下载入口），保留 6dp 底部间距；水平弹性占位高度设为 0。没有修改公共 weight 方法，也没有调整收藏数据、导入副本、下载任务或阅读进度。

新增原生布局检查 `bookshelfOnly`，使用真实 renderFavorites 和 Android measure/layout，覆盖 320/360/412/600dp 宽度与在线→本地→在线切换，检查标题高度、列表剩余空间和选中内容填满。该入口在 seed 之前返回，不执行原阅读器测试的数据填充。

```text
adb shell am instrument -w -e bookshelfOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
```

验证证据：沿用上文 Gradle 命令，BUILD SUCCESSFUL；40 套件、275 项 JVM 测试，0 failures/0 errors；AndroidTest 编译成功，git diff --check 通过。adb 无连接设备，本机无模拟器，因此新增布局用例未运行，未完成修复前失败/修复后通过的设备验证，也未宣称真机视觉验收通过。上述原生用例仍需在测试设备运行；人工检查浅深色、真实收藏列表、本地空状态/已有漫画、导入/下载入口和底部导航。

新验收包：

- APK：`F:/softForCode/codex-project/xx-comic/release/local-library-stage-2/xx-comic-local-stage-2-e8d8e86.apk`
- 测试 APK：同目录 `xx-comic-local-stage-2-e8d8e86-androidTest.apk`
- 大小：11,554,782 字节。
- SHA-256：`2019E245594D537E008FADA976FCF9F46C96FF1E32F8560AECC8D28899A854D4`
- 包名 `com.xxcomic`，版本 `2.0.21 / 221`；签名验证通过，证书与上一个验收包一致。
- 本轮只提交开发分支、归档独立验收包，没有发布 COS 或更改正式版本。

## 设置页下载中心入口迁移与样式精细打磨 — 2026-09-17

按用户要求，将下载中心从本地书架右上角移除，迁移进「设置」页，并全面打磨一阶段与二阶段的视觉样式与布局。代码提交 `678eabe`。

### 修改与打磨明细

1. **入口迁移与书架头部净化**：
   - 从 `updateBookshelfRightActions()` 中完全移除下载图标。本地书架右侧仅保留清晰的本数统计和蕾姆主题 `+ 导入` 按钮。
   - 在「设置」页的「站源与本地数据」分组中新增「下载中心」选项（图标 `ic_download`），动态显示进行中任务数（例如 `N 个进行中`），点击打开下载中心；返回动作平滑返回设置页。
   - 本地存储与下载配置分离为「下载中心」与「本地存储管理」（图标 `ic_bookshelf`），更直观地管理存储占用与副本。

2. **在线详情页离线下载入口打磨**：
   - 将原单行小文本入口升级为带圆角微边框、蕾姆强调色图标 `ic_download`、标题「下载离线章节」及 `ic_chevron_right` 箭头的标准交互卡片，与「章节目录」卡片风格完全统一。

3. **下载中心与各弹窗视图深度美化**：
   - **下载范围选择抽屉**：增加蕾姆主题芯片（本章、全选、清空、倒序 ⇄），勾选框适配 ACCENT 强调色，底部大圆角主按钮动态显示选中计数「下载选中章节 (N)」。
   - **下载中心主界面**：规范页面内边距为标准 16dp，顶部包含优雅的 `‹ 返回`；并列放置「全部暂停」与「继续下载」操作按钮；配置专属蕾姆提示横幅与无任务时的 `rem_empty` 留白插画；任务卡片增加单行截断、状态进度和右侧跳转箭头。
   - **任务详情抽屉**：采用 76% 底部标准半屏抽屉，支持「阅读此书」与「去验证」快捷动作，各章节清晰显示状态徽章（已完成使用 ACCENT 色，失败使用 DANGER 色）。
   - **本地存储管理**：卡片化「仅 Wi-Fi 下载」开关与「存储空间统计」看板（直观区分本地导入、离线下载、可清缓存与剩余空间）；底部提供并列的「清理缓存」与「删除选中」动作。

4. **本地详情页离线感知完善**：
   - 本地详情页章节入口与 76% 目录抽屉自动区分「本地导入」与「离线下载」标识。
   - 本地详情页删除对话框文案精细化：针对离线下载作品，明确提示「将删除全部离线下载文件，在线收藏与阅读进度保留」，区别于本地导入作品的「不影响手机原始文件」。

### 验证证据

- **自动化构建与编译**：
  - `:app:compileDebugJavaWithJavac`、`:app:compileDebugUnitTestJavaWithJavac`、`:app:compileDebugAndroidTestJavaWithJavac` 均成功退出码 0。
- **单元测试回归**：
  - 全部 **40 个测试套件，275 项 JVM 单元测试**，**0 failures，0 errors，0 skipped，100% PASS**（耗时 23s）。
- **代码规范检查**：
  - `git diff --check -- app/src` 无任何多余空白或格式警告。
- **停点执行**：
  - 严格完成阶段 1 与阶段 2 的验收验证后停止，**未进入阶段 3**，**未打包 Release 正式包**，**未上传 COS**，**未合并或推送到远程**。

### 最新验收包

- **Debug APK**：`F:/softForCode/codex-project/xx-comic/release/local-library-stage-2/xx-comic-local-stage-2-678eabe.apk`
- **AndroidTest APK**：`F:/softForCode/codex-project/xx-comic/release/local-library-stage-2/xx-comic-local-stage-2-678eabe-androidTest.apk`
- **APK 大小**：11,438,986 字节
- **APK SHA-256**：`CC28EC80C9C9EDA180E68D99998E84FE0105658679B0F00972FD88F7231DF57C`
- **AndroidTest 大小**：44,218 字节
- **AndroidTest SHA-256**：`69AB45B6E06CE0939E5C1FB4BD29B25B665FB79C7DA4309C791A0FD53DC5D5EC`
- **签名证书 SHA-256**：`13:1D:74:72:0C:25:65:D2:E5:02:A4:74:DC:31:E6:6A:67:03:9E:04:85:11:A0:7F:DD:35:D9:48:7C:93:B7:2A`（一致）


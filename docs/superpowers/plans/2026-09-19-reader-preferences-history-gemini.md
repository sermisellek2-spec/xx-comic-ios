# 启动书架偏好、阅读显示开关与历史闪退：Gemini 分阶段实施方案

> **For agentic workers:** 若执行环境提供 superpowers:executing-plans，请用它逐项执行；否则按本文件检查项顺序实施。本文是交接方案，不表示功能已实现或已通过真机验收。

**Goal:** 修复阅读历史的越界风险，增加完全本地的启动书架习惯，以及阅读页“去白边”“禁止动画翻页”两个开关。

**Architecture:** 沿用现有 Java 原生 Activity、ListView、ViewPager2、ZoomImageView、SharedPreferences 和图片解码任务。新功能只接入显示、设置及小规模本地习惯数据，不重做阅读器、目录或图片下载链路。

**Tech Stack:** Android Java，minSdk 23，ViewPager2 1.0.0，RecyclerView 1.2.1，现有 JUnit 和自定义 Android 插桩入口。

**Spec:** 本文件前半部分为行为规范，后半部分为实施与验收步骤。

调研基线：2026-09-19，本地 master / `9d34449`，versionName 2.0.28，versionCode 228。执行前核对实际版本；如代码已变化，以方法名定位，不依赖本文行号。

## 范围及约束

- 用户使用统计延期：不增加埋点、服务器接口、IP/设备型号收集、联网偏好同步，不连接服务器。
- 本轮由 Gemini 实现，Codex 审查，用户最后真机验收。
- 新开 `codex/reader-preferences-and-history` 分支；保留现有未提交内容。不得 `reset --hard`，不得把 `.gradle`、`app/build` 或其他无关修改打包进提交。
- 各阶段允许本地提交，仅提交该阶段的明确文件；不自动合并 master、推送、升级版本或发布 COS，发布另行安排。
- 不引入阅读器框架、统计 SDK、图像处理大依赖；优先用 Android 原生能力。
- 保持在线/本地阅读、连章、左右手、三种翻页方式、阅读位置、站源验证和下载行为。使用目前的设置抽屉样式和主题。
- 新设置升级默认均不改变现有阅读效果：去白边关闭，禁止动画翻页关闭。

## 一、调研结论及边界

以下是源码调研，不是对其他 App 的真机测试。外部项目仅参考行为和职责划分，不直接复制整段实现。

| 参考 | 已核实行为 | 本项目采用方式 |
| --- | --- | --- |
| Mihon `ReaderPreferences.kt` | `pageTransitions` 默认 true；`cropBorders` 和 `cropBordersWebtoon` 分开，默认 false；双击缩放动画另设参数 | 去白边和翻页动画分开；区分单页与条漫处理策略；不连带关闭缩放 |
| Mihon `PagerViewer.kt` | 程序翻页把 `config.usePageTransitions` 传给 `setCurrentItem` | 本项目按钮/触碰切页传入 smoothScroll，但还须处理 ViewPager2 原生拖动 |
| Mihon `ReaderPageImageView.kt` | 向图片显示组件传递 `cropBorders`；缩放参数独立 | 裁剪是显示处理，原图和下载文件保持不变 |
| KOReader `readercropping.lua` | 提供 auto、none 和手动裁剪；保存内容边界，调整 content/page 缩放 | 自动判断有局限，本轮做保守自动裁白边；不扩展手动框选 UI |

参考地址：

- https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/setting/ReaderPreferences.kt
- https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/pager/PagerViewer.kt
- https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/ReaderPageImageView.kt
- https://github.com/koreader/koreader/blob/master/frontend/apps/reader/modules/readercropping.lua

本文件的裁剪阈值、习惯计分和无动画手势规则是针对 xx-comic 的建议，不是声称上述 App 使用完全相同的算法。

## 二、启动书架偏好规范

### 2.1 用户界面与优先级

设置页沿用现有单选抽屉，新增“启动书架”：自动跟随习惯（默认）/ 我的书架 / 本地书架。自动选项副文案显示“学习中 · 启动显示本地书架”或“当前偏好：本地书架”等实际状态；提供“重置习惯”。

仅从桌面正常冷启动时决定书架子页；不在 onResume、从阅读返回、切换主题、旋转重建时重新计算并跳转。若有明确文件打开 Intent、阅读恢复或系统保存界面，先执行原有目标，偏好不能覆盖它。

手动固定优先于自动。自动尚未学出结果时，恢复上次用户主动点击的书架子页；从未点击默认“我的书架”。自动启动显示不记为主动点击。已有明确学出结果且样本变少时保留上次结果，直至新结果达阈值或用户重置。本地书架为空也允许显示现有导入空态，不偷偷切换。

### 2.2 计量规则

不用导入文件数量、收藏数量、首页曝光量和单纯打开详情计分，这些不能代表实际阅读偏好。

一次有效阅读会话满足：

1. 漫画内容已可读、App 在前台且阅读器有效展示；累计阅读至少 60 秒。
2. 本次发生过至少一次用户主动翻页、切章、有效滚动或进度跳转。初始化定位、预加载和自动连章回调不算用户动作。
3. 同一会话只记 1 票；连续切章、切换阅读布局、修改设置、旋转屏幕不新增会话。

分类使用正在读的漫画记录：本地记录（导入或本地离线作品）计本地，在线记录计在线；在线图片命中缓存不会变成本地。历史入口同样按记录判断。文字 EPUB 的本地阅读也可计本地，但下面的图片裁剪开关不作用于文字排版。

实现注意：本项目离线下载可能复用在线 progressKey，不能只用 `isLocalComic()` 的 `local_` 前缀判定。进入阅读时根据实际绑定的本地 Book、`readerLocalBookId`、本地章节内容确定会话类型并保持到会话结束；纯在线记录只是图片命中缓存仍计在线。复用现有 `isLocalComicDetail` / 本地读取入口的信息，不遍历整库猜测。

会话从内容可读开始；退出阅读器或切换漫画结束；短暂后台后 5 分钟内返回同一本续接，超过 5 分钟新建会话。用 elapsedRealtime 计时，后台、锁屏、加载失败、不可读等待、覆盖正文的设置/目录弹层期间暂停；离最近有效阅读动作超过 120 秒的静置时段不再累计。首张内容呈现给予初始 120 秒活动窗口，仍须满足一次用户动作条件。

达到条件时立即记票并保存，不等退出，以免进程被杀丢票；会话 token/已记票状态在界面重建时保留。无需永久后台服务，复用前台回调，至多一条有生命周期管理的低频计时任务。

统计取最近 30 天内最新 10 次有效会话，至少 5 次才形成偏好；某类占比 >=70% 才切换，否则保留原结果。比如 5 次中本地 4 次可切本地，10 次中本地 6 次不切换。推荐纯函数算法：

```text
samples = 最近30天有效会话，按时间取最新10条
if samples.count < 5: return 上次学出结果或学习中
if localCount * 10 >= samples.count * 7: return 本地
if onlineCount * 10 >= samples.count * 7: return 我的
return 上次学出结果或学习中
```

只存时间、local/online 和必要去重状态，不存漫画书名或上传行为。固定模式下暂停新增学习样本，切回自动使用仍在有效窗口内的原有数据。普通缓存清理不删除偏好；重置习惯只清学习数据和会话状态，保留用户当前固定选项、最后主动书架选择及阅读历史。

## 三、去白边规范

### 3.1 用户可见行为

阅读页现有设置抽屉新增“去白边”，默认关闭，全局持久化、切换后当前阅读立即应用。说明：“自动裁去图片外围白边，原文件不变”。

- 普通/日漫单页：保守处理图片四周的连续白边，保持比例展示完整剩余内容。
- 条漫/卷轴：只处理左右白边；保留上下留白，避免损坏纵向节奏及跨图衔接。逐张检测，不能拿第一张边界套整章。
- 去的是图片自身的白边，不是屏幕因纵横比产生的空白区域；禁止用 CENTER_CROP/拉伸来冒充裁白边。
- 不裁内部分镜缝，不识别文字含义，不裁黑边和彩色背景。无法确信的页保持原样；白背景正文与作者留白无法百分之百自动区分，关闭开关立即恢复。
- 仅作用于现有图片漫画解码路径；文字 EPUB/MOBI 不显示这个图片专用开关，也不改它们的 CSS 或正文。

### 3.2 最小可实施算法

复用当前解码后的、已完成站源图片还原的 Bitmap。在图片工作线程求有效矩形，不在 UI 线程扫像素。先实现保守版，不做机器学习、OCR 或复杂内容分割。

初始参数（集中常量，交付时用样图验证，可在报告中说明调整）：

- 近白定义：不透明 alpha=255，R/G/B 最小值 >=245，最大最小差 <=10。透明边界、无法读取的软件像素格式直接回退原图。
- 从外缘逐行/列向内检查，只有整条候选线均为近白才剥离；遇到文字/线条等非白像素即停止，宁可少裁。不要通过允许少量黑像素而删掉页码或细字。
- 单侧最多检查/裁去原尺寸 15%。到上限仍没找到内容边界，该轴回退不裁；全白页/过小页/无有效内容回退原图。
- 检出的内容矩形向外留至少 2 个解码像素且约该轴 0.3% 的保护边，最终坐标必须落在原图范围内，宽高 >=1。
- 长图直接按既有受控解码尺寸检查，复用行/列缓冲，不新建整张 ARGB 副本。扫描预算由四侧 15% 上限约束，可取消；有明显噪点的扫描页保留白边是允许的。

对一张 1000×1400 图：若左右都是 50px 的白边且其后有内容，单页可裁这两侧并留保护边；条漫仍保持原高度。某边的标题/页码应阻止继续裁剪。

### 3.3 接入现有图片流水线

主接点为 MainActivity 的 `decodeReaderImage` → `restoreJmReaderImage` → `loadReaderImage`。先解密/重排/现有方向处理，再测边界；不能在禁漫图片还原之前裁，否则切片高度改变会让整张图错乱。不要擅自对已缓存还原结果再次还原。

推荐保留 `readerBitmapCache` 原始还原 Bitmap，裁剪只是一个小矩形。增加最多 256 项的内存裁剪边界 LRU，键包含图片身份/内容版本、解码宽高、裁剪策略和算法版本；关闭无需网络重下。图片缓存失效或本地资源变更要同步失效边界。无须持久化大量裁剪图片。

显示可用轻量 Drawable 包装原 Bitmap：intrinsicWidth/Height 为裁剪区域尺寸，draw 时用 Canvas.drawBitmap 的源矩形映射到 Drawable bounds；关闭则普通 BitmapDrawable。这样 ZoomImageView 现有 intrinsic bounds、矩阵和约束能使用裁剪后的尺寸，又不复制/破坏缓存 Bitmap。不回收仍被其他视图/缓存使用的 Bitmap。

条漫 `readerImageHeights` 必须按实际显示矩形宽高计算，并区分裁剪状态，不能沿用原图高度缓存。内存命中分支和异步加载分支必须走相同绑定逻辑；保留当前 tag、readerGeneration、comicId、chapterUrl 校验，再加设置版本防止旧裁剪结果覆盖新设置。

设置改变先捕获当前位置，重绑定当前和可见/预加载范围，不重新请求章节或整章重解码：

- 单页保留章节和图片索引；改变图片边界时将该页缩放复位为适应内容。
- 条漫保留章节+原图片 id/索引+该图的归一化纵向位置，布局稳定后还原。连章列表必须使用当前 ContinuousReaderItem 对应章节，不能错用入口章节。
- 临时位置按原图坐标映射：旧裁剪区域的 y 转回原图归一化 y，再转换到新区域；越界夹紧。第一阶段只裁左右时也要处理高度缩放。
- `atEnd` 保持底部锚点，不写坏既有 ReaderPosition 存储。不允许打开开关直接跳第一张。

## 四、禁止动画翻页规范

阅读设置抽屉新增“禁止动画翻页”，默认关闭。副文案：“开启后直接切页，滑动手势仍可用”。全局持久化、即时生效。

| 场景 | 开启后的要求 |
| --- | --- |
| 单页，按钮/边缘触碰 | 原有目标页，`setCurrentItem(target, false)` |
| 单页，左右滑动 | 手指拖动不移动画面；达到原有识别阈值，松手后直接切一页 |
| 条漫，横滑切章 | 禁用当前横向拖移及 220ms 回弹；松手仍按既有规则切章 |
| 条漫，纵向滚动 | 保留原生滚动与惯性，不变成一张一张跳 |
| 放大后拖图、双指缩放 | 保持缩放与平移手感，不能被识别为翻页 |
| 中间轻触、沉浸、设置/目录抽屉 | 保持原动画，不受此开关影响 |

`PagedReaderView.moveTo()` 当前写死 true，只改这里不够：ViewPager2 手势拖动仍会动画。实现时禁用无动画模式下的 pager 原生 user input，并复用 PagedReaderView 已有 dispatchTouchEvent 位移识别和 ReaderNavigation.swipeDelta，在 ACTION_UP 只走一次 onNavigate。无动画关掉后恢复原 ViewPager2 原生拖动。

所有 `setUserInputEnabled`（初始化、onZoomChanged、onPageSelected）必须统一遵循“当前输入方式允许滑动 && 未缩放 && 未禁止动画”的条件，避免翻页后又被某个回调打开。手势替代路径只在允许滑动的原有输入方式启用，不借机改变原本触碰/按钮/手势模式的兼容行为。

沿用已有阈值与左右手映射，不另建第二套导航算法；页内和跨章都走同一个 navigateReader，不能先切页再触发旧的跨章 fallback。ACTION_CANCEL、多指参与、缩放/平移中、竖向手势、阈值不足均不翻页；切换开关时若正在拖动，取消本次翻页手势，到稳定页后应用。不得将图片平移的 transform 误当翻页 transform 清零。

不改缩放 ValueAnimator、全局动画倍率和 DownloadSheetAnimation。墨水屏模式已有行为保持原样，本轮不新增隐式联动、不覆盖用户开关值。

## 五、历史闪退：已发现的代码证据

用户最新补充：有本地书架内容时打开阅读历史会闪退，清空本地书架后不闪退。因此阶段 0 必须优先复现本地记录链路；清空书架只是定位线索，不能作为修复步骤或验收前置条件。此现象支持本地进度/目录不一致的怀疑，但本身不能排除本地元数据、数据库读取、封面绑定等其他原因。

MainActivity.historyRow（调研时约 10826 行）：

```java
} else if (detail != null && chapterIdx >= detail.chapters.size() - 1 && !detail.chapters.isEmpty()) {
    chapterText = "已读完整 · " + detail.chapters.get(chapterIdx).title;
}
```

目录只剩 1 章、旧记录 chapterIdx=256 时，条件成立却执行 get(256)，必然越界。MOBI 多目录合并为一章、重新导入或站源目录缩短都能产生这类过期索引。这里是可证明的缺陷，但用户尚未提供本次设备堆栈，不能宣称已确认是唯一闪退原因。

修复行为：

- 历史渲染不得直接拿过期索引访问目录；负数、缺失、空目录、移除的本地文件、失效缓存都正常展示。
- 索引仍有效：显示“上次看到 · 章节名”。无目录数据：显示已有历史的章序（只有非负索引时），或“有阅读记录”。索引超出已有非空目录：显示“目录已更新 · 点击继续”，不冒称已读完。
- 不根据“最后一章”自动显示“已读完整”；当前 recordPagedPosition 的 atEnd 也只是到达最后一张，不证明真正读完，第一版去掉这个绝对完成判定最稳妥。
- 不通过 clearAppCache、清空 progress、删除作品、空 catch 吞异常来掩盖问题。
- 点击仍走原详情入口；实际续读入口若目录变化，优先利用已有稳定章节 id/URL（若保存过），否则仅在准备读取时夹紧索引。不能从越界整数猜出合并后准确位置，需诚实保留可恢复的历史，不承诺精确迁移。
- 检查书架及设置的两个历史入口，兼查空 summaries/details、已删除本地记录和封面异步绑定。记录非敏感异常上下文到现有日志，禁止写整段正文/本地敏感路径。

## 六、分阶段实施

每阶段先写覆盖核心行为的测试，再改最小代码；不为低价值样式创建镜像实现的测试。完成一阶段输出报告后可继续下一阶段，无需反复索要同意。发现与规范冲突或需要改站源/存储大结构才停下说明。

### 阶段 0：修历史闪退，先取得可用基线

**修改**：`app/src/main/java/com/xxcomic/MainActivity.java` 的 showHistory/historyRow 与实际续读边界；如需 JVM 测试，将无 Android 依赖的显示规则放入 `app/src/main/java/com/xxcomic/reader/HistoryProgressLabel.java`，避免扩大重构。

**测试**：`app/src/test/java/com/xxcomic/reader/HistoryProgressLabelTest.java`；历史入口集成检查复用现有 `app/src/androidTest/java/com/xxcomic/ReaderInstrumentation.java` 入口。

- [ ] 检查 git 状态，创建工作分支，记录基线。
- [ ] 建立“1 章 + 保存 256”失败用例，确认旧代码确实越界。
- [ ] 保留本地数据进行集成复现：导入后阅读并打开历史、合并/移除卷后打开、重启后打开、在线与本地混合历史；逐条记录异常类型与阶段。旧 progressKey / Book.id 映射、删除后残留 summary/detail 缓存也需核对。禁止先清空书架再证明“不闪退”。
- [ ] 按第五节修复；补 0 章、null detail、负数索引、第一章、最后一章、删本地记录等例子。
- [ ] 证明单条脏记录不会使整个历史打不开，打开/删除历史不清除其他作品进度。
- [ ] 构建 debug，阶段提交与报告。没有设备就如实写“历史入口真机/插桩尚未执行”。

建议纯显示函数契约 `static String label(int savedIndex, List<String> chapterTitles)`，null 表示无详情；代表性断言：

```java
assertEquals("目录已更新 · 点击继续", HistoryProgressLabel.label(256, java.util.Arrays.asList("全卷")));
assertEquals("上次看到 · 全卷", HistoryProgressLabel.label(0, java.util.Arrays.asList("全卷")));
assertEquals("有阅读记录", HistoryProgressLabel.label(-1, null));
```

### 阶段 1：完全本地的启动书架偏好

**修改**：MainActivity 的 onCreate、onResume/onPause、书架主动切换、阅读打开/释放、用户导航/滚动、设置页与本地偏好持久化。文字阅读接点为 renderTextReader 回调，不需重做 TextReaderView。

**新增**：`app/src/main/java/com/xxcomic/reader/ReadingHabitTracker.java` 和对应 `app/src/test/java/com/xxcomic/reader/ReadingHabitTrackerTest.java`，负责会话计时及纯决策；Android 界面仅转发生命周期与动作事件，使用可注入时间进行测试，不在测试里真的等待 60 秒。

- [ ] 测试少于5次不决策、4/5本地切换、6/10保持、7/10切换、30天过期、最新10条截断。
- [ ] 测试只停留不互动不记票、未加载不计时、59秒不计票、60秒且互动只记一次、自动定位不算互动。
- [ ] 测试后台暂停、短暂后台续接、超过5分钟新会话、旋转/布局切换不多记票；达到阈值立即持久化。
- [ ] 实现自动/固定模式与重置；手动固定、冷启动、最后主动书架选择的优先级按第二节。
- [ ] 从历史入口读本地书、离线书、在线缓存书分别核对分类。启动默认选页不得自己给自己加票。
- [ ] 普通清缓存保留偏好；重置不删作品和历史。阶段提交与报告。

### 阶段 2：禁止动画翻页与设置容器

**修改**：ReaderSettingsSheet.java、PagedReaderView.java、MainActivity.java；方向逻辑复用 ReaderNavigation.java，不改含义。

**测试**：保留 ReaderSettingsSheetTest/ReaderPositionTest；按现有插桩设施增加无动画手势检查，不能仅靠反射读取方法名证明行为。

- [ ] 增加设置键 `reader.disable.page.animation=false`；恢复/保存接入现有位置；旧安装默认 false。
- [ ] 添加开关监听及 PagedReaderView 即时 setter；修齐全部 userInputEnabled 分支。
- [ ] 程序切页设置 smoothScroll；在无动画分支复用已有手势识别，处理页内/跨章且一次手势只推进一次。
- [ ] 条漫禁用横拖/回弹，但保留纵向滚动、连章加载和双指缩放。
- [ ] 验证左右手各一组按钮/边缘/手势翻页；三页首/中/尾边界，多指后单指、取消事件、开关拖动中切换不得误翻。
- [ ] 现有设置面板增加内容后，正文区域用有最大高度的 ScrollView；顶部拖柄保留，正文滚动不被下滑关闭抢走。小屏、横屏、较大字体可操作全部开关。
- [ ] 阶段提交与报告，明确动画关闭范围，无额外“关闭所有动画”副作用。

### 阶段 3：保守去白边

**修改**：MainActivity 图片解码后处理、异步绑定、内存命中、图高计算、位置恢复；ReaderSettingsSheet 增加开关。ZoomImageView 原算法优先保持，通过 Drawable 尺寸复用。

**新增**：`app/src/main/java/com/xxcomic/reader/WhiteMarginDetector.java`（矩形检测）、`app/src/main/java/com/xxcomic/reader/CroppedBitmapDrawable.java`（只读显示包装）、对应检测测试及图片显示插桩检查。纯检测规则可接受行像素读取器以便 JUnit 使用合成样本；不引入图像处理依赖。

- [ ] 先建立白边黑框、无白边、纯白、彩色、透明、页脚小字、超长条漫、上限保护的合成样图用例；期望矩形明确写入测试，不能只比较开关布尔值。
- [ ] 实现工作线程有界检测，站源还原后才执行，失败展示原图且不影响阅读成功状态。
- [ ] 增加 `reader.crop.white.margins=false`，只对图片漫画启用；按模式选择四边/左右。
- [ ] 实现裁剪边界缓存、同一绑定入口、图高重算和新旧请求设置版本隔离。不得新建整章裁剪 Bitmap 集合。
- [ ] 当前页开启/关闭都保留章节和图片定位；条漫中途、已自动加载下一章、底部 atEnd、缩放中切换分别检查。
- [ ] 在线/ZIP/EPUB/MOBI 图片和禁漫还原图走同一路径；本地纯文本不裁；原文件 hash、下载缓存原文件保持不变。
- [ ] 记录首开检测耗时、连续翻20页的缓存命中、内存峰值，与关闭裁剪比较；设备不具备时不伪造性能数据。
- [ ] 阶段提交与报告。若自动白边容易误裁样图，优先收紧检测/回退，不以填满屏幕作为成功标准。

### 阶段 4：联合验证与验收交付

- [ ] 执行 `./gradlew.bat :app:testDebugUnitTest --console=plain`，失败先区分新回归与基线问题，修复本次引入的失败。
- [ ] 执行 `./gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug --console=plain`；插桩 APK 构建成功不等于执行成功。
- [ ] 有设备时先读项目自定义 ReaderInstrumentation 的执行方式再执行；没有设备写明未执行，保留可运行检查和人工步骤。
- [ ] 做覆盖矩阵：在线/本地 × 条漫/普通/日漫；重点再交叉验证输入方式 × 左右手 × 开关开关组合。包含长图、单页、换章、连章、断网本地、退出恢复。
- [ ] 检查开启去白边后再禁用翻页动画、切横竖屏、开关设置抽屉仍能继续阅读；关闭所有新增开关恢复既有行为。
- [ ] 生成独立验收 debug APK，附路径、实际包名/版本、commit、SHA-256、变更文件列表、自动验证结果和真机待验清单。
- [ ] 输出最后总报告，不合并发布；等待用户真机及 Codex 审查反馈。

## 七、每阶段报告格式

保存到 `docs/superpowers/reports/reader-preferences-history-stage-N.md`：

1. 阶段名、基线与实际提交号。
2. 改了什么，具体文件和接入点。
3. 修复证据/测试输入、期望、实际结果；执行的命令。
4. 对现有行为的影响与兼容方式。
5. 未执行的检查、局限、已知风险，不把构建当真机验收。
6. APK 信息（该阶段若产出），下一阶段内容。

用户真机重点步骤：先开阅读历史；固定本地/自动偏好冷启动；单页有白边漫画切开关比较内容是否完整；条漫检查上下分镜间距；三种翻页方式及左右手开关动画后各翻几页；放大拖图不误翻；退出重进章节与页码不丢。习惯学习阈值由自动测试用虚拟时间覆盖，不要求用户为验收连续读十次。

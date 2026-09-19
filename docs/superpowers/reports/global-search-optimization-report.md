# 全站搜索同名置顶与红点提示优化报告

## 1. 任务背景与实施范围

本次优化严格遵循以下原则实施：
1. **各站源第一页搜索结果同名置顶**：标题与搜索关键词完全一致的漫画置顶。比较时仅去除首尾空白（`title.trim().equals(query.trim())`），不做模糊包含匹配，不删除标点符号，不剥离前后缀；多本同名作品全部保留且保持原相对顺序，其余非同名结果也保持原相对顺序。
2. **同名作品站源红点提示**：某站源第一页存在完全同名作品时，在该站源标签右上角显示一个约 5dp 的红色纯色圆点（无数字、无动画、置于右上角避免遮挡标签文字）；无同名结果则不显示；无障碍描述在原标签基础上补充“，有同名作品”。
3. **极简与安全约束**：
   - 保持每站仅请求第 1 页，不新增分页、补搜、加载更多或额外提示文案；
   - 严格保持原有站源标签顺序不变，不按命中情况重排；
   - 严格禁止系统自动切换用户选中的站源；
   - 新搜索开始时立即清除上一轮红点，旧请求的回调通过 `generation` 严格阻断，不得污染新搜索状态；
   - 排序与红点共用同一套判定逻辑，确保判定 100% 一致；
   - 详情页切换站源的匹配逻辑完全保持原样，不做任何改动。

---

## 2. 修改文件与接入点

### 2.1 新建纯 Java 匹配与排序工具类
- **文件**：`app/src/main/java/com/xxcomic/search/GlobalSearchMatchHelper.java`
- **核心方法**：
  - `isExactTitleMatch(String title, String query)`：
    - 规则：`title != null && query != null && !query.trim().isEmpty() && title.trim().equals(query.trim())`。
    - 仅去除首尾空白，不作 contains 模糊判断，不删除中英文标点（如《》、！、: 等），不去除 `[完]`、`(全彩)` 等后缀。
  - `prioritizeExactMatches(List<ComicModels.ComicSummary> items, String query)`：
    - 稳定分区算法（Stable Partitioning）：单次线性遍历，将满足 `isExactTitleMatch` 的条目收集入 `exactMatches`，不满足的收集入 `others`；
    - 两组直接拼接返回：`exactMatches` 在前，`others` 在后；
    - 多本同名作品全部保留，且相对顺序与输入一致；其余所有结果相对顺序完全不变；无元素丢失、无重复。
  - `hasExactTitleMatch(List<ComicModels.ComicSummary> items, String query)`：
    - 直接复用 `isExactTitleMatch` 判定，任何项匹配即返回 `true`，确保与 `prioritizeExactMatches` 的首项命中逻辑完全等价。

### 2.2 修改全站搜索流水线与标签渲染
- **文件**：`app/src/main/java/com/xxcomic/MainActivity.java`
- **修改接入点**：
  1. **引用与状态**：
     - 引入 `com.xxcomic.search.GlobalSearchMatchHelper`；
     - 增加 `userSelectedGlobalSearchSource` 字段，标记用户是否主动点击切换了站源标签。
  2. **搜索启动与旧状态清除 (`startGlobalSearch`)**：
     - 重置 `userSelectedGlobalSearchSource = false`；
     - 清空各站源数据后，主动调用 `refreshGlobalSearchTabs()`，在网络请求发出前立即清空所有旧红点；
     - `globalSearchGeneration` 递增，确保后续只有当前轮次的搜索结果能够触发状态刷新，彻底阻断旧搜索回调。
  3. **异步并发请求与排序 (`runGlobalSearch`)**：
     - 工作线程获取站源第一页数据后，先执行 `GlobalSearchMatchHelper.prioritizeExactMatches(got, query)` 排序，分担主线程压力；
     - 主线程安全回调 `addGlobalSearchSourceResults` 再次保障排序；
     - 限制站源自切：只有在用户未主动选定站源（`!userSelectedGlobalSearchSource`）且默认首站无结果时才做初始兜底，绝不因为某个站源有同名结果而强行自动切走用户选中的站源。
  4. **站源标签红点与无障碍 (`refreshGlobalSearchTabs`)**：
     - 站源循环严格保留 `enabledSearchSources()` 既有顺序，不重排标签；
     - 使用 `FrameLayout tabContainer` 包装 `tab`（TextView chip）；
     - 通过 `GlobalSearchMatchHelper.hasExactTitleMatch(sourceList, globalSearchQuery)` 判定红点；
     - 若有同名作品，添加 5dp 红色圆点（`GradientDrawable.OVAL`, 颜色 `#FFFF4D4F`），布局参数设为 `Gravity.TOP | Gravity.END`，外边距 `top: 4dp, right: 6dp`，位于芯片右上角圆角内，文字居中且右内边距为 11dp，完全不遮挡文字；
     - 无同名作品时不添加红点；
     - 无障碍文本设置：`tab` 和 `tabContainer` 均设为 `label + (hasExactMatch ? "，有同名作品" : "")`；
     - 用户点击标签时，置位 `userSelectedGlobalSearchSource = true`，并锁定当前选中的站源。

### 2.3 新建单元测试用例集
- **文件**：`app/src/test/java/com/xxcomic/search/GlobalSearchMatchHelperTest.java`
- **用例覆盖**：
  - `testIsExactTitleMatch_BasicAndWhitespace`：基础完全一致、首尾空格去除、中间空格保留验证；
  - `testIsExactTitleMatch_NoFuzzyOrPunctuationOrSuffixRemoval`：包含关系拒绝、标点符号不删拒绝、全彩/完结前后缀不删拒绝；
  - `testIsExactTitleMatch_NullAndEmptySafety`：空关键词、空标题、纯空白关键词安全校验；
  - `testPrioritizeExactMatches_SingleExactMatchMovedToTop`：单本完全同名置顶，其余项相对顺序严格不变；
  - `testPrioritizeExactMatches_MultipleExactMatchesPreserveOrder`：多本完全同名全部置顶并保持原顺序，其余项原顺序紧随其后；
  - `testPrioritizeExactMatches_NoMatchesOrAllMatches`：全不匹配与全匹配边界下顺序稳定无变化；
  - `testPrioritizeExactMatches_EmptyAndNullSafety`：空列表与空查询边界安全；
  - `testHasExactTitleMatch_ConsistencyWithPrioritization`：红点与置顶判定严格一致性校验；
  - `testKeywordSwitchAndOldResultIsolation`：模拟连续发起不同关键词搜索，新搜索即时清空旧红点，旧关键词结果绝不激活新关键词红点。

---

## 3. 验证结果

### 3.1 单元测试全量通过
- **执行命令**：
  ```bash
  .\gradlew.bat testDebugUnitTest --no-daemon --console=plain
  ```
- **测试结果**：
  - `BUILD SUCCESSFUL in 16s`
  - 全工程单元测试全部通过（434 项测试通过，0 失败，0 错误）。

### 3.2 静态代码检查 (Lint)
- **执行命令**：
  ```bash
  .\gradlew.bat :app:lintDebug --no-daemon --console=plain
  ```
- **检查结果**：
  - `BUILD SUCCESSFUL in 24s`
  - 无任何新增语法或资源错误。

### 3.3 验收 APK 构建与指纹
- **执行命令**：
  ```bash
  .\gradlew.bat :app:assembleDebug --no-daemon --console=plain
  ```
- **输出 APK 信息**：
  - **路径**：`app/build/outputs/apk/debug/app-debug.apk`
  - **大小**：`11,624,042` 字节 (~11.1 MB)
  - **SHA-256 校验和**：
    ```text
    E38B3DF512EDCAC66A5D7B839726EBD50379FD50870CE03CCB26118C121188D3
    ```

---

## 4. 重点场景验收指南

在真机上安装 APK 后，可针对本次改动进行专项回归：

1. **同名漫画置顶与顺序稳定**：
   - 全站搜索“海贼王”；
   - 切换各站源标签，观察第一页结果列表中，标题恰好为“海贼王”的漫画排在首位；
   - 包含“海贼王 剧场版”、“海贼王[完]”等带有附加文字的作品排在后面，且各自保持原站源返回的相对次序；
   - 若某站源存在两本不同作者或版本的同名作品，两本均排在最前且两者的相对先后顺序不变。
2. **红点提示与无障碍说明**：
   - 搜索特定热门作品，若站源返回结果中存在完全同名作品，该站源标签右上角出现约 5dp 红色圆点；
   - 若仅有衍生作或相关模糊匹配作品（如只有“xxx 衍生篇”），该标签右上角不出现红点；
   - 开启无障碍旁白时，聚焦该标签会朗读“...，有同名作品”。
3. **新搜索清除与旧结果隔离**：
   - 搜索词从“海贼王”更改为其他词（如“死神”）并按下回车；
   - 标签行红点立即全部清除，上一轮搜索的同名状态不会残留；
   - 快速连续输入不同关键词搜索，先前的网络请求返回不会更新当前关键词的结果或红点。
4. **站源标签顺序与选中状态保护**：
   - 站源标签排列顺序保持与设置一致，不发生乱序；
   - 在搜索过程中用户主动点击了某个站源标签，后续其他站源即便加载完成或命中同名，界面绝不擅自切走用户当前选中的标签。

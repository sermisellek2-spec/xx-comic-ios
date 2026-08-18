# 弹框与轻提示统一改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将确认/信息对话框和 Rem 轻提示统一成紧凑、浅深色一致、带蕾姆元素的交互，同时删除已经不可达的旧弹框代码，不改变搜索、阅读、收藏、更新和站源验证业务逻辑。

**Architecture:** 继续使用 `MainActivity.java` 现有的原生 `AlertDialog`、`PopupWindow` 和动态 View，不引入新 UI 框架或依赖。确认类反馈统一走一个带 Rem 小图的紧凑对话框；短反馈统一走一个可替换的 transient host，保证同一时间最多显示一个普通提示、阅读提示或撤销提示。18mh/禁漫天堂的 WebView 验证窗口、筛选/目录抽屉和系统文件选择器不在本次视觉改造范围内。

**Tech Stack:** Java、Android `AlertDialog`/`FrameLayout`、现有 `UIHelpers`、现有 `rem_*.png` 资源、Node 静态契约检查、Gradle/JUnit。

---

### Task 1: 先锁定弹框、提示和死代码契约

**Files:**
- Modify: `tools/check-main-interactions.js`
- Modify: `tools/check-rem-visual-contract.js`
- Test: `tools/check-dialog-toast-contract.js`

- [ ] **Step 1: 增加失败条件，明确旧入口必须消失**

创建完整的 `check-dialog-toast-contract.js`：

```js
const fs = require("fs");
const java = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8",
);

let failed = false;
function fail(message) {
  failed = true;
  console.error(`FAIL ${message}`);
}
function pass(message) {
  console.log(`PASS ${message}`);
}

const removed = [
  "renderProfile",
  "favoriteRow",
  "deleteFavorite",
  "showChoiceDrawer",
  "sourceDropdown",
  "showSourceChooser",
  "showAddSourceDialog",
];
for (const name of removed) {
  if (java.includes(` ${name}(`)) fail(`dead method remains: ${name}`);
}

[
  "showSettingsSheet",
  "showFilterDrawer",
  "showChapterDrawer",
  "showRemToast",
  "showReaderHint",
  "showRemDialog",
].forEach((name) => {
  if (!java.includes(` ${name}(`)) fail(`active UI entry missing: ${name}`);
});
```

- [ ] **Step 2: 增加单实例提示契约**

检查源码必须存在统一 transient host 和清理方法：

```js
if (!java.includes("activeTransientHint")) fail("transient host missing");
if (!java.includes("dismissTransientHint()")) fail("transient cleanup missing");
if (!java.includes("showRemToast(R.drawable.rem_empty")) fail("undo toast missing");

if (failed) process.exit(1);
pass("dialog and toast contracts hold");
```

- [ ] **Step 3: 先运行静态检查，确认新增契约按预期失败**

运行：

```powershell
node tools/check-dialog-toast-contract.js
```

预期：在实现前因 `showRemDialog`、`activeTransientHint` 尚不存在而失败。该失败只用于确认检查器确实覆盖新要求。

### Task 2: 删除不可达的旧 UI 代码

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-main-interactions.js`
- Modify: `tools/check-rem-visual-contract.js`

- [ ] **Step 1: 删除旧设置页和旧书架实现**

删除以下整段方法及仅被它们使用的辅助方法：

```text
renderProfile()
menuItemWithIcon()
cycleThemeMode()
toggleReaderHand()
favoriteRow()
deleteFavorite()
```

保留当前可达的 `renderSettings()`、`showThemeDrawer()`、`showHandModeDrawer()`、`favoriteGridItem()`、`showFavoriteDeleteOverlay()` 和 `deleteFavoriteWithUndo()`。

- [ ] **Step 2: 删除旧选择弹层和旧站源对话框**

删除：

```text
showChoiceDrawer()
ChoiceAction
sourceDropdown()
showSourceChooser()
showAddSourceDialog()
```

不要删除 `customSources` 的导入、导出、持久化逻辑；用户不能新增站源，但已有配置仍需能够导入导出。

- [ ] **Step 3: 更新现有契约检查**

`tools/check-main-interactions.js` 中原来要求 `showAddSourceDialog` 存在的断言改为：

```js
if (java.includes("showAddSourceDialog")) fail("dead add-source dialog remains");
if (!java.includes("customSources")) fail("custom source persistence was removed");
```

`tools/check-rem-visual-contract.js` 增加对旧方法不存在的断言，并保留“站源菜单只有导入、导出、检测可用性”的断言。

- [ ] **Step 4: 运行编译前的静态检查**

运行：

```powershell
node tools/check-main-interactions.js
node tools/check-rem-visual-contract.js
```

预期：两个已有检查全部 PASS。此时 `check-dialog-toast-contract.js` 仍会因为新的 Dialog/Toast 尚未实现而失败，属于阶段性预期结果。

### Task 3: 实现紧凑 Rem 确认/信息对话框

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:5563-5912`
- Reuse: `app/src/main/res/drawable/rem_empty.*`, `rem_error.*`, `rem_reader_resume.*`

- [ ] **Step 1: 用共享方法替换普通 `styledDialog`**

将方法收敛为以下签名，保留正/负按钮和原有回调语义：

```java
private AlertDialog showRemDialog(
        int imageRes,
        String title,
        String message,
        String positiveText,
        Runnable positiveAction,
        String negativeText,
        Runnable negativeAction) {
    LinearLayout content = new LinearLayout(this);
    content.setOrientation(LinearLayout.HORIZONTAL);
    content.setGravity(Gravity.TOP);
    content.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16),
            UIHelpers.dp(this, 16), UIHelpers.dp(this, 10));

    ImageView art = new ImageView(this);
    art.setImageResource(imageRes);
    art.setScaleType(ImageView.ScaleType.FIT_CENTER);
    content.addView(art, new LinearLayout.LayoutParams(
            UIHelpers.dp(this, 56), UIHelpers.dp(this, 56)));

    LinearLayout copy = new LinearLayout(this);
    copy.setOrientation(LinearLayout.VERTICAL);
    copy.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 2), 0, 0);
    TextView titleView = UIHelpers.text(this, title, 17, UIHelpers.TEXT, Typeface.BOLD);
    titleView.setMaxLines(2);
    titleView.setEllipsize(TextUtils.TruncateAt.END);
    copy.addView(titleView);
    TextView messageView = UIHelpers.text(this, message, 13, UIHelpers.TEXT2, Typeface.NORMAL);
    messageView.setMaxLines(3);
    messageView.setEllipsize(TextUtils.TruncateAt.END);
    copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 5)));
    content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

    AlertDialog.Builder builder = new AlertDialog.Builder(this).setView(content);
    if (!TextUtils.isEmpty(positiveText)) {
        builder.setPositiveButton(positiveText,
                (dialog, which) -> { if (positiveAction != null) positiveAction.run(); });
    }
    if (!TextUtils.isEmpty(negativeText)) {
        builder.setNegativeButton(negativeText,
                (dialog, which) -> { if (negativeAction != null) negativeAction.run(); });
    }
    AlertDialog dialog = builder.create();
    dialog.setOnShowListener(ignored -> {
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(UIHelpers.round(
                    UIHelpers.CARD, UIHelpers.dp(this, 8), Color.TRANSPARENT));
            int width = Math.min(getResources().getDisplayMetrics().widthPixels
                    - UIHelpers.dp(this, 40), UIHelpers.dp(this, 328));
            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
        }
        android.widget.Button positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
        if (positive != null) positive.setTextColor(UIHelpers.ACCENT);
        android.widget.Button negative = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
        if (negative != null) negative.setTextColor(UIHelpers.TEXT3);
    });
    dialog.show();
    return dialog;
}
```

实现要求：

- 使用现有 `UIHelpers` 和 `rem_*` 素材，不新增图片依赖。
- 对话框宽度为 `min(screenWidth - 40dp, 328dp)`。
- 背景圆角统一为 `8dp`，浅色/深色均使用 `UIHelpers.CARD`。
- 内容区采用 56dp Rem 图片 + 标题/正文横向布局，整体紧凑。
- 正文最多 3 行并省略，完整异常已经进入错误日志，不在对话框里铺满堆栈。
- 主按钮使用 `ACCENT`，取消按钮使用 `TEXT3`，按钮高度和字体与现有设置页一致。
- 保持默认返回键/点击外部取消行为；验证 WebView Dialog 不调用此方法。

- [ ] **Step 2: 为不同语义选择 Rem 素材**

统一映射：

```text
暂无章节、清空历史、删除单条历史 -> rem_empty
目录加载失败、导入导出失败、更新安装失败 -> rem_error
普通说明/关于信息 -> rem_reader_resume
```

- [ ] **Step 3: 迁移所有实际调用点**

替换以下调用，不改变回调：

```text
ensureChaptersThen() 的“暂无章节”
ensureChaptersThen() 的“目录加载失败”
confirmClearErrorLogs()
showHistory() 的“清空阅读历史”
historyRow() 的“删除这条记录”
showInfo() 及其更新/导入/导出错误调用
```

`showInfo()` 改为 `showRemDialog(R.drawable.rem_error, ...)`，调用方不再关心对话框实现。

- [ ] **Step 4: 编译确认 Dialog 回调未改变**

运行：

```powershell
./gradlew.bat :app:compileDebugJavaWithJavac
```

预期：编译通过；确认、重试、取消、返回键行为与改造前一致。

### Task 4: 统一 Rem 轻提示并防止叠加

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:3546-3585,3991-4018,5412-5443`
- Modify: `tools/check-dialog-toast-contract.js`

- [ ] **Step 1: 添加单一 transient host**

在 Activity 字段区域增加：

```java
private View activeTransientHint;
private Runnable transientHintDismiss;
```

增加最小清理方法：

```java
private void dismissTransientHint() {
    if (transientHintDismiss != null) main.removeCallbacks(transientHintDismiss);
    if (root != null && activeTransientHint != null
            && activeTransientHint.getParent() == root) {
        root.removeView(activeTransientHint);
    }
    activeTransientHint = null;
    transientHintDismiss = null;
}
```

- [ ] **Step 2: 将普通提示、阅读提示和撤销提示接入同一 host**

新增统一挂载入口：

```java
private void showTransientHint(
        View hint,
        FrameLayout.LayoutParams params,
        long durationMs) {
    dismissTransientHint();
    activeTransientHint = hint;
    root.addView(hint, params);
    hint.setAlpha(0f);
    hint.setTranslationY(UIHelpers.dp(this, 6));
    hint.animate().alpha(1f).translationY(0f).setDuration(140L).start();
    transientHintDismiss = () -> {
        if (activeTransientHint != hint) return;
        hint.animate().alpha(0f).translationY(UIHelpers.dp(this, 4))
                .setDuration(120L).withEndAction(this::dismissTransientHint).start();
    };
    main.postDelayed(transientHintDismiss, durationMs);
}
```

普通提示保持 1.6 秒；阅读提示保持 1.8 秒；撤销提示保持 3.2 秒。三种提示不再同时叠加。

`showReaderHint()` 保留当前暗色视觉构造，只把最后的直接挂载与延迟删除替换为：

```java
FrameLayout.LayoutParams params = UIHelpers.frame(
        -2, UIHelpers.dp(this, 48),
        Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL,
        0, 0, 0, UIHelpers.dp(this, 52));
showTransientHint(hint, params, 1800L);
```

- [ ] **Step 3: 增加语义化包装，不改变业务调用**

将现有 `showRemToast(int, String)` 扩展为带可选动作的完整入口：

```java
private void showRemToast(int imageRes, String message, String actionText,
                          Runnable action, long durationMs) {
    if (root == null) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        return;
    }
    LinearLayout hint = new LinearLayout(this);
    hint.setGravity(Gravity.CENTER_VERTICAL);
    hint.setPadding(UIHelpers.dp(this, 7), UIHelpers.dp(this, 5),
            UIHelpers.dp(this, 10), UIHelpers.dp(this, 5));
    hint.setBackground(UIHelpers.round(
            UIHelpers.CARD, UIHelpers.dp(this, 8), UIHelpers.BORDER));
    hint.setElevation(UIHelpers.dp(this, 3));

    ImageView art = new ImageView(this);
    art.setImageResource(imageRes);
    art.setScaleType(ImageView.ScaleType.FIT_CENTER);
    hint.addView(art, new LinearLayout.LayoutParams(
            UIHelpers.dp(this, 32), UIHelpers.dp(this, 32)));

    TextView label = UIHelpers.text(this, message, 12, UIHelpers.TEXT, Typeface.BOLD);
    label.setMaxLines(2);
    label.setEllipsize(TextUtils.TruncateAt.END);
    LinearLayout.LayoutParams labelParams = new LinearLayout.LayoutParams(0, -2, 1f);
    labelParams.leftMargin = UIHelpers.dp(this, 7);
    hint.addView(label, labelParams);

    if (!TextUtils.isEmpty(actionText) && action != null) {
        TextView actionView = UIHelpers.text(
                this, actionText, 12, UIHelpers.ACCENT, Typeface.BOLD);
        actionView.setGravity(Gravity.CENTER);
        actionView.setPadding(UIHelpers.dp(this, 10), 0, 0, 0);
        actionView.setOnClickListener(view -> {
            dismissTransientHint();
            action.run();
        });
        hint.addView(actionView, new LinearLayout.LayoutParams(-2, -1));
    }

    FrameLayout.LayoutParams params = UIHelpers.frame(
            Math.min(getResources().getDisplayMetrics().widthPixels
                    - UIHelpers.dp(this, 32), UIHelpers.dp(this, 340)),
            -2, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL,
            0, 0, 0, UIHelpers.dp(this, 72));
    showTransientHint(hint, params, durationMs);
}
```

保留短方法，减少调用方改动：

```java
private void showRemToast(int imageRes, String message) {
    showRemToast(imageRes, message, "", null, 1600L);
}

private void showRemToast(String message) {
    showRemToast(R.drawable.rem_reader_boundary, message);
}

private void showRemSuccessToast(String message) {
    showRemToast(R.drawable.rem_reader_resume, message);
}

private void showRemErrorToast(String message) {
    showRemToast(R.drawable.rem_error, message);
}
```

迁移规则：

```text
成功/完成/已收藏/已复制/已导入 -> showRemSuccessToast
失败/验证未完成/刷新失败/加载更多失败 -> showRemErrorToast
边界与普通状态提示 -> 保留现有 reader_boundary
```

- [ ] **Step 4: 将书架撤销并入统一提示**

保留 `showFavoriteUndo()` 作为业务包装，但内部改为调用带动作的 Rem 提示：

```java
private void showFavoriteUndo(String id, int oldIndex, Long oldFavoriteAt, String title) {
    showRemToast(R.drawable.rem_empty, "已移出《" + title + "》", "撤销", () -> {
        if (!favorites.contains(id)) {
            favorites.add(Math.max(0, Math.min(oldIndex, favorites.size())), id);
            favoriteAt.put(id, oldFavoriteAt == null
                    ? System.currentTimeMillis() : oldFavoriteAt);
            saveLocalState();
        }
        showTab(0);
    }, 3200L);
}
```

点击“撤销”先清理 transient host，再恢复收藏并刷新书架。

- [ ] **Step 5: 检查页面切换和 Activity 销毁**

在 `enterScreen()` 开头调用 `dismissTransientHint()`；在 `onDestroy()` 调用 `super.onDestroy()` 之前再次调用，避免旧页面的延迟回调继续操作新页面。

- [ ] **Step 6: 运行静态契约检查**

运行：

```powershell
node tools/check-dialog-toast-contract.js
node tools/check-rem-visual-contract.js
```

预期：检查通过，并能确认普通提示、阅读提示、撤销提示都使用了统一清理入口。

### Task 5: 完整验证与变更边界检查

**Files:**
- No new production files
- Inspect: `MainActivity.java`, `Mh18WebViewSession.java`, `JmComicWebViewSession.java`

- [ ] **Step 1: 运行项目已有测试**

运行：

```powershell
./gradlew.bat :app:testDebugUnitTest
```

重点确认：

- 站源验证会话隔离逻辑没有被修改。
- 搜索、详情、章节、阅读缓存逻辑没有改变。
- 清理日志、清理历史和缓存的回调仍然执行。

- [ ] **Step 2: 编译 Debug APK**

运行：

```powershell
./gradlew.bat :app:assembleDebug
```

预期：`app/build/outputs/apk/debug/app-debug.apk` 生成。

- [ ] **Step 3: 做代码差异检查**

确认本次差异只包含：

```text
MainActivity.java 的 Dialog/Toast/死代码区域
两个静态契约检查脚本和一个新增契约检查脚本
本方案文档
```

明确不修改：

```text
Mh18WebViewSession.java
JmComicWebViewSession.java
站源解析器
筛选抽屉
章节抽屉
阅读加载与图片缓存逻辑
```

- [ ] **Step 4: 提交前人工验收清单**

逐项确认：

```text
浅色模式和深色模式的对话框背景、文字、按钮均可读
确认框有 Rem 图片且内容紧凑
失败/成功/普通提示图片语义正确
连续触发两个提示时只保留后一个
撤销提示仍可点击并恢复书架
返回键可关闭普通确认框，但不会误关闭验证 WebView
目录重试、日志清理、历史清理回调均正常
旧的新增站源、旧站源选择、旧设置页代码不存在
```

# XX Comic Android MVP

原生 Android 漫画阅读 App。当前版本已改回项目原型图的暖色卡片样式，并接入包子漫画真实数据。

## 当前能力

- 搜索页使用原型图风格：浅暖背景、橙色选中态、双列漫画卡片。
- 默认展示包子漫画“最新上架”分类，也可以输入漫画名或作者后点击键盘搜索。
- 搜索结果、封面、详情、章节目录、阅读图片来自 `https://cn.bzmgcn.com` 页面解析。
- 详情页使用原型图结构：渐变 hero、白色信息卡、收藏/阅读按钮、阅读来源、章节目录。
- 阅读页使用原型图结构：深色顶栏、漫画图片流、上一章/下一章。
- 收藏、阅读进度、站源状态、自定义站源、章节排序、缓存状态使用 `SharedPreferences` 保存。
- Java 编译已固定为 UTF-8，避免中文搜索词和界面文案在 APK 中变成乱码。

## 验证

静态源检查：

```bash
node tools/check-android-source.js
```

真实包子漫画页面探测：

```bash
node tools/probe-baozi.js
```

Android Debug APK：

```powershell
$env:JAVA_HOME='C:\Users\15361\.jdks\corretto-17.0.12'
.\gradlew.bat assembleDebug
```

输出位置：

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 数据源说明

包子漫画章节入口会通过 `page_direct` 跳转到真实章节页。`BaoziComicSource` 已处理 302 跳转，并解析章节页中的 `scomic` 图片地址。站点结构变化时，先运行 `tools/probe-baozi.js` 判断搜索、详情和图片选择器是否仍然可用。

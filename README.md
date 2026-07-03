# XX Comic

原生 Android 漫画阅读 App，当前专注 Android 版本。项目使用 Java + Android View 实现，不依赖跨端框架。

## 功能概览

- 收藏页作为默认首页，支持收藏、继续阅读、最近阅读置顶和重复收藏处理。
- 搜索页支持已启用站源切换、站源分类筛选、键盘触发搜索和下拉分页加载。
- 支持多站源全站搜索，并发搜索所有启用站源后汇总展示结果。
- 详情页按需加载章节目录，目录使用抽屉弹出，避免进入详情时被目录请求拖慢。
- 阅读页支持上下章切换、目录抽屉、点击中心切换全屏、左右轻点切换上一章/下一章。
- 支持白天/黑夜主题，默认按时间自动切换，也可在“我的”页面手动切换。
- 支持站源配置导入/导出、站源可用性检测、缓存清理和错误日志查看/导出/清理。

## 内置站源

- 包子漫画：`https://cn.bzmgcn.com`
- 漫画屋：`https://www.mhua5.com`
- 爱看漫画：`https://www.0592cr.com`
- G社漫画：`https://m.g-mh.org`

站源搜索、分类、详情、目录和章节解析配置集中在代码内的站源配置中；导出的 JSON 会携带当前站源配置，方便其他用户导入后直接使用。

## 环境要求

- JDK 17
- Android Gradle Plugin 7.4.2
- compileSdk 34
- minSdk 23

如果本机没有配置全局 `JAVA_HOME`，可以临时指定 JetBrains Runtime：

```powershell
$env:JAVA_HOME='C:\Program Files\JetBrains\IntelliJ IDEA 2024.1.6\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
```

## 构建

```powershell
.\gradlew.bat assembleDebug
```

Debug APK 输出位置：

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 常用验证

静态源码检查：

```bash
node tools/check-android-source.js
```

包子漫画页面探测：

```bash
node tools/probe-baozi.js
```

完整编译验证：

```powershell
.\gradlew.bat assembleDebug
```

## 目录结构

```text
app/src/main/java/com/xxcomic/
  MainActivity.java          主界面、页面跳转、交互逻辑
  UIHelpers.java             UI 组件和主题 token
  DataHelpers.java           本地数据辅助逻辑
  source/                    各站源解析与配置
tools/                       本地探测和检查脚本
```

## 开发注意

- 先保留原生 View 写法，避免引入不必要依赖。
- 站源解析变更前，优先用对应探针或接口返回确认真实 HTML/JSON 结构。
- 搜索、目录和章节加载都应保留 loading/错误状态，避免静默卡住。
- 修改后至少运行 `.\gradlew.bat assembleDebug`。

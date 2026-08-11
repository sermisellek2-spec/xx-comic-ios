# 启动图标与 Release 打包设计

## 目标

使用 `C:\Users\15361\Desktop\chatgpt-image-20260811-115409-01.png` 替换 XX Comic 的启动图标，并生成可直接安装的 release APK。

## 图标方案

- 采用已确认的 C 方案：以人物脸部和蓝发为视觉中心放大裁切。
- 保留部分蝴蝶结与对话框，让图标仍能辨认原图来源。
- 不重绘图片，不新增图片处理依赖。
- 为 Android 7 及以下生成 `mdpi`、`hdpi`、`xhdpi`、`xxhdpi`、`xxxhdpi` 五档 PNG。
- Android 8 及以上继续使用现有 adaptive icon 入口，前景改为处理后的位图，背景保持与原图协调的蓝色。
- Manifest 继续引用 `@mipmap/ic_launcher`，普通图标和圆形图标使用同一资源入口。

## 构建与签名

- 不修改 `versionCode` 和 `versionName`。
- release 构建显式使用 Gradle 默认 debug signing config。
- 该签名适合自用安装测试，不作为应用商店或正式分发密钥。
- 执行 `:app:assembleRelease`，复制最终 APK 到 `.worktrees/artifacts/xx-comic-master-release.apk`。

## 验证

- 检查所有 PNG 尺寸、格式和非空像素。
- 生成圆形、圆角方形、小尺寸组合预览并人工检查主体没有异常裁断。
- 新增最小资源检查脚本，验证资源存在、像素尺寸和 adaptive icon 引用。
- 执行 `git diff --check` 和 `:app:assembleRelease`。
- 使用 Android 构建工具验证 APK 已签名，并计算 SHA-256。

## Git 交付

- 图标实现单独提交到当前 `master`。
- 推送本地 `master` 的全部累计提交到 `origin/master`；推送前验证远端没有产生需要先合并的新提交。
- 推送后核对本地 `HEAD` 与 `origin/master` 一致。

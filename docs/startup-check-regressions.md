# 启动检查回归修复

## 收藏更新

同站源漫画排队查询时，用户可能已经查看或取消收藏。任务现在在入队时保存访问和收藏代次，出队及结果落地时校验；取消收藏移除等待任务，删除后重新收藏不会接收旧结果。通知书架时重新读取当前状态，避免主线程队列中的过时通知重新点亮蓝星。

保留每次进程冷启动检查一次、查询失败静默、首次成功建立基线的行为。空书架也会记录本次启动已经检查，防止 Activity 重建后额外启动检查。

## 版本更新

检查结果由进程级 `AppUpdateChecker` 保存。新的 Activity 重新订阅未完成请求或接收已完成结果，不重复发出启动请求；旧 Activity 销毁时按回调身份解绑，避免解绑新页面。

更新询问只在 Activity 已恢复、窗口有焦点且不在验证流程时显示。切后台暂存提示并关闭当前弹框，回前台继续显示。用户取消或主动使用手动检查后，本次会话不再自动弹出。软更新和元数据缺失/无效时默认 soft 的规则不变。

## 验证

- 171 项 JVM 单元测试通过，包括收藏排队查看/删除/重新收藏、查询失败、新章节提醒、更新请求共享、结果重放、取消状态及错误处理。
- 11 项模拟器更新提示检查：软更新静默、后台结果暂存、回前台显示、取消不重复、Activity 重建后继续显示。
- 43 项沉浸模式模拟器检查通过，覆盖条漫/单页及普通屏/墨水屏。

```text
gradle :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
adb shell am instrument -w -e startupOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
adb shell am instrument -w -e immersionOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
```

设备检查应在独立模拟器中运行，会写入测试漫画和阅读设置。版本检查设备用例在初始请求完成后注入离线发布信息，不下载或安装更新包。

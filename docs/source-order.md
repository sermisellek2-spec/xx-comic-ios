# 站源拖动排序

入口：设置 → 站源管理。按住左侧手柄上下拖动，顺序自动保存；更多菜单可恢复默认排序。

- 站源管理、单站切换菜单、全站搜索标签共用顺序。搜索仍然并发执行。
- 关闭站源不改变其排序位置，重新开启时回到原位置。
- 排序按稳定的站源 ID 保存，不改变当前选择、收藏或阅读进度。
- 新站源追加末尾，失效 ID 和重复 ID 自动忽略。
- 重启及普通缓存清理保留顺序。
- 站源配置导出增加可选 `sourceOrder` 数组。继续兼容原有配置版本；导入不含该字段的旧文件时保留本机排序。

## 实现

`SourceOrder` 负责排序和配置校验，`SourceOrderList` 使用 RecyclerView / ItemTouchHelper 处理拖动。站源页面只使用一个滚动列表，避免外层 ScrollView 截获拖动和边缘滚动。开关和验证按钮不触发拖动。

顺序保存在 `source.order` 偏好项，每次有效移位立即写入；拖动中断也不会丢失已经接受的移动。

## 验证

- 195 项 JVM 测试通过，其中新增 7 项排序测试。
- Debug APK 和 Android 测试 APK 构建通过。
- Android 模拟器 17 项排序验收通过：实际触摸拖动、开关不误触、选择不变、偏好恢复、Activity 重建、菜单和搜索顺序、关闭/开启、配置往返、旧配置兼容及恢复默认排序。
- 原有主界面交互契约检查通过。

复测命令：

```text
gradlew testDebugUnitTest assembleDebug assembleDebugAndroidTest
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e sourceOrderOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
node tools/check-main-interactions.js
```

本次仅改变站源排序，保留当前版本号和 CF 验证逻辑。

# 批量本地导入交付报告

日期：2026-09-18

分支：`codex/local-batch-import`

基线：`master@d403daf`

## 已实现

- EPUB/MOBI 后台轻量扫描，按系列元数据、卷号、自然文件名建议分组；用户可确认拆分或全部合并。
- Book 作为合集，新增独立卷表；支持混合格式、完整卷内章节、卷调序/移除和向已有漫画添加分卷。
- SQLite v1 默认卷/旧追加卷迁移，保留章节 ID；按各卷格式与路径读取，调序保持稳定阅读定位。
- 最多两个文件并发、同组串行，完成卷可立即阅读。快速 EPUB 模式跳过导入时逐页图片解码，阅读按需处理。
- 批次逐文件原子保存，失败重试、取消保留完成项，重启后可继续。写入失败暂停并保留记录。
- 修复重复文件误绑定旧书、恢复/取消竞态、删除目标期间后续卷重建、文件夹与电子书混合后路径错误。
- 蕾姆进度横幅、主题确认抽屉、书架卷数；原文件、普通缓存清理与在线站源边界保持。

## 验证

命令：

```text
./gradlew.bat --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug --console=plain
BUILD SUCCESSFUL
```

52 个 JVM 测试套件、362 项测试，0 failures / 0 errors / 0 skipped。Lint 为 0 errors、81 warnings；存在原有 Android 工具链及弃用 API 警告。
审查提出的取消、恢复、删除目标和按卷读取问题均已修正，最后限定复核未发现新的 critical/important。

## 限制与后续

- 当前 adb 无设备；SQLite 插桩仅编译，未运行。不能把 JVM 通过当作真机迁移、性能或视觉验收通过。
- 切换 App 内页面可继续导入；进程终止或 Activity 重建会暂停，下次手动继续。未新增前台 Service。
- 文件夹自动发现多个 EPUB/MOBI、下载中心按合集聚合、文件源 revision 替换、全量图片校验另行扩展。
- 同包名 com.xxcomic、版本 2.0.22（222）的开发验收包；不是独立安装的第二个 App。正式 master/COS 未发布。

## 真机验收

验收包：`release/local-batch-import/xx-comic-local-batch-20260918.apk`。

SHA-256：`1E469B20B1C50D28D8DF98095DEC23DC7B133F25B2BCBE99FA0125F8831F1728`。

1. 《城市猎人》32 卷确认合并为一本，卷序与卷内章节正确。
2. 300~400 文件扫描/导入期间切换页面；完成卷逐步可读。
3. 坏文件不阻塞其他卷，取消保留完成卷，重启续导不重复。
4. 重复导入不增卷；追加/调序/删除后继续阅读不跳错章。
5. 图片文件夹混合电子书后调序/删除，原图片仍可读。
6. 旧版本本地库升级、浅深主题、文件选择器及清理缓存。

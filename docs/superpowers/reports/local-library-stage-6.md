# 第六阶段收尾与发布 — 2026-09-18

## 接管范围

接管基线 `fb85246`，分支 `codex/local-library-offline`。Gemini 已提交到阶段 4，工作区另有阶段 5、阅读 UI/本地导入调整和未完成的阶段 6。用户本轮明确授权补齐阶段 6、合并 master、升级版本、推送及 COS 强更新。保留并交付这些功能修改，不提交 `.gradle/`、`app/build/` 或 APK。

初始编译失败：DownloadRuntime 缺 downloadFile、SourceConfig 构造参数不匹配、未使用的 publishDownloadedVolume 缺集合导入。

## 补齐结果

- FileSourceCapability / FileResource 是可选能力，既有图片站源不强制实现。按 sourceId/comicId/fileId 建立稳定任务和卷身份，不按 URL、标题或指纹合并不同来源。
- 一卷对应一个独立本地阅读条目（完整文件可能含多章），入口按卷序展示。文件任务和图片任务共用单 worker、持久 SQLite 队列、暂停、网络策略、有限重试、下载中心及删除入口。
- 每次执行重新 resolve 描述；401/403 或显式过期最多再刷新一次，重复认证失败暂停。文件任务不持久化 URL/请求头；跨 origin 丢弃全部站源请求头，拒绝 HTTPS 降级和非 HTTP(S) 地址。
- 校验长度、可选 SHA-256、魔数/容器；支持未知长度。续传必须有强 ETag、If-Range 和严格 Content-Range；忽略 Range 的 200 重写文件，错误 206、HTML、截断、错误哈希不得入库。
- 私有 pending 目录下载和解析，复用 ZIP/EPUB/PDF/已实现 Kindle 解析器，完成后同盘重命名、事务替换索引、最后标完成；不再复制原始大文件。进度数据库写入节流到约 250ms。
- 新版失败保留旧版可读文件；成功后清理旧文件和衍生页。页面缓存身份含内容 hash，相同内容保持续读，内容变化重新起读，避免旧索引定位错误；自定义标题保留。
- 删除使任务代次失效，晚回调不能重新发布；取消未完成的新版本保留旧版。删除本地卷、下载中心删除、存储管理均清理任务及私有文件。普通清缓存不删除原始下载。
- 详情按 capability 展示“文件与分卷”和“下载后阅读/正在下载/继续阅读”，复用原主题 76% 抽屉，支持单卷、多卷、全部和已下载卷打开。旧图片源保留原章节下载及在线阅读入口。
- 修复文件卷封面恢复、版本更新阅读身份、本地历史查找；未修改 JM/18mh 验证实现。

没有虚构真实文件站点。接口、HTTP 夹具和 Android 闭环用例已提供；实际站点尚未指定。

## 发布前修正与边界

- 解决 API23 不支持的 Comparator.comparingInt、Map.compute/getOrDefault 使用，锁内 epoch 更新语义保留。阅读器改用 holder 当前绑定位置。
- 阶段 5 报告中的“完整 KF8/AZW3 支持”不符合实际代码，未实现 skeleton/fragment 正文重建。当前明确拒绝纯 KF8，保留已实现的未加密、未压缩/PalmDOC 压缩 MOBI7 与混合容器旧格式部分。HUFF/CDIC、KFX、Topaz、DRM 和未知变体不宣称支持。
- Kindle 补充记录偏移、单记录/文本/图片容量及损坏 PalmDOC 回溯检查；DRM offset 的 -1 哨兵不再单独当作保护依据。KF8 和损坏 PalmDOC 用例先失败后修复。
- Gemini 已将本地导入改为能直接访问时引用原文件，不能继续宣传所有导入都复制副本。保留该既有调整；删除不会删除用户外部原文件，但外部移动/删除会影响阅读。下载文件始终为 App 私有持久副本。

## 验证

Windows、Corretto 17.0.12、SDK34，隔离 buildDir：

```powershell
$env:JAVA_HOME='C:/Users/15361/.jdks/corretto-17.0.12'
./gradlew.bat --no-daemon -I release/local-library-stage-1-codex-build.gradle :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug --console=plain
```

升版前：49 套件、334 项 JVM 测试、0 失败/错误；Debug/AndroidTest 构建通过，Lint 0 errors / 82 warnings。受控 HTTP 测试覆盖完整 ZIP/EPUB、未知长度、206、200 回退、截断、HTML、哈希、刷新、跨域请求头、暂停、版本变化；队列测试覆盖序列化、卷序、版本及旧回调。

原生 FileSourceChecks 使用独立临时数据库、自制 PNG ZIP 和 socket，覆盖下载→解析→入库→数据库重开→离线读页、清缓存、重命名、版本替换、坏文件拒绝、删除。已编译，**未运行**：adb 无设备，无可用模拟器。

```text
adb shell am instrument -w -e filesOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
```

其他原生入口：localOnly、downloadsOnly、bookshelfOnly。未执行真实站点、API23/34 设备、后台杀进程/省电、阅读手势、横竖屏、浅深色截图和安装升级实机验收。没有把构建通过写成设备已验收。

## 发布目标

2.0.22 / 222，沿用现有签名。强更新按既有 `updateMode: prompt` 执行：启动提示升级，可以取消，设置里可手动更新；不增加禁止使用的拦截。先发布 COS 和服务器备用包，校验后更新服务器元数据。最终提交、哈希、公网校验在发布后追加。

## 正式包验证

升版后执行 `:app:testDebugUnitTest :app:assembleRelease :app:assembleDebugAndroidTest :app:lintDebug`，BUILD SUCCESSFUL；49 套件、334 测试、0 failures、0 errors。Release 和原生测试包编译成功，Lint 通过，设备验收限制同上。

- 归档：`release/xx-comic-2.0.22.apk`
- applicationId：`com.xxcomic`；versionName：`2.0.22`；versionCode：`222`
- 大小：10,708,746 字节
- SHA-256：`fb4306081eabccc367079121a0556c4386e03f601722dfdabb4c1961312b5c75`
- 签名验证通过，证书 SHA-256：`131d74720c2565d2e502a474dc31e66a67039e048511a07fdd35d9487c93b72a`，与旧版本一致。

## 发布结果

- 功能与版本提交：`95143636afa841020f2ed2b4c893ef28df3e362c`，开发分支 fast-forward 合并至 `master`，已推送 `origin/master` 并核对远端 SHA。
- 合并后源码与构建源码相同，master 再次执行 `:app:testDebugUnitTest` 成功。
- COS 上传返回 HTTP 200；公网下载 COS 与服务器备用 APK，二者 SHA-256 均与上述正式包一致。
- 下载：`https://xx-1321588235.cos.ap-guangzhou.myqcloud.com/apk/xx-comic/xx-comic.bin`
- 备用：`https://weifeng.cloud/xx-comic/releases/xx-comic.apk`
- 两份包核验后才发布 `https://weifeng.cloud/xx-comic/releases/android-release.json`；公网确认 `2.0.22 / 222`、`updateMode: prompt`、大小及 SHA-256 正确。
- 服务器保留 2.0.21 APK 和元数据备份；既有本地构建输出改动未提交或清除。开发分支保留。
- 发布完成不等于真机验收完成；设备总验收及未支持格式边界仍按上文记录。

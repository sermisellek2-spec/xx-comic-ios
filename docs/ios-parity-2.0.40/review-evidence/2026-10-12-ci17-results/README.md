# 第十七轮 Apple 实际结果

运行：[38199185049](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38199185049)。输入 `852178e882080920bc32c349a4bbcfe76cb79283`，`configuration-files`，无 IPA，整体 **failure**。

- Debug、Release SDK 构建通过，启动 storyboard 的必要元数据修复已实际通过 ibtool。
- Apple ComicCore：917项、1项缓存物理归零失败，137.746秒。实际磁盘余量36864字节；不能伪报0。
- iPhone/iPad 原生各25项、0失败，包含进度条和实际缓存记账比较；这不关闭 Core 的物理归零失败。
- UI 各31项。iPhone 20通过/11失败用例，日志17条失败；iPad 24通过/7失败用例，日志12条失败。用例数和断言失败数不是同一口径。
- 当前搜索、目录加载、取消/互斥、迟到详情提示及下载离线图片等12项影响 UI 双设备通过。Files、配置取消/导出、站源面板仍有失败；四项设置空缓存参考在两设备均失败。

现在已有主视觉各页面实际截图，尚未完成64页的同内容逐组件验收。iPad 原生场景边界834×1194与截图/无障碍缩放边界仍不一致，不能拉伸成通过。截图中的 `imageSHA256`/`metadataSHA256` 是共同内容夹具身份；每张实际截图的 SHA 由原始导出 manifest 提供。

[apple-summary.json](apple-summary.json) 保存逐用例结果、日志和60,488,254字节视觉归档的 SHA。296份本地原始导出文件已逐份校验 manifest SHA，未修改图片。原日志 ZIP 按字节保留；两设备原 manifest、用例列表及部分 Files 失败截图/导航树也已保存。完整视觉原件保留于本地 `ios/build/apple-config-ci-38199185049/visual/`，来源是该运行的视觉 artifact。

当前12ddd38及书架/Files接续改动不在此输入中，必须再次 Apple 验证。整体非站源门槛仍未通过，P6仍关闭；不生成阶段包或要求用户阶段试包。

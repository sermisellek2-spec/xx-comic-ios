# CI27：阅读恢复进展与缓存残留实证

指定仓库 [38242082789](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38242082789)，输入 `c377af6ffd616cf0c91d55dd8f01643be83076a3`，`reader-modes`，不打 IPA。运行已结束，整体失败。

Debug、Release 构建成功。Mac ComicCore 934 项执行、1 项失败、123.304 秒：原物理归零断言仍看到 memory=0、disk=144016，未修改断言或虚报零。

| 实际设备 | 原生用例 | 阅读 UI 用例 |
| --- | --- | --- |
| iPhone 15 Pro / iOS17.5 | 30 通过、0 失败，15.110 秒 | 17 通过、1 失败；失败用例产生 6 条断言，512.932 秒 |
| iPad Pro 11-inch (M4) / iOS17.5 | 29 通过、1 失败；失败用例产生 8 条断言，15.074 秒 | 18 通过、0 失败，585.570 秒 |

两设备的 4 项阅读几何原生用例和图内偏移往返 UI 通过。iPhone 三模式往返的第 3 页断言仍实际得到第 2 页；iPad 的 `directory` 缓存清理后 4 个已知正文仍能读取，另一个同目录实例重新打开仍读到这 4 个正文。CI26 的正文清理通过是对应输入的真实历史结果，不能据此宣称稳定。

原始阅读附件 SHA 与原 CI manifest 精确匹配。`reader-records/trace-001.txt` 第 60–65 行证实：pending 已清空后，实际图片高度令内容高度 1759 变为 1628，目标 offset786 被压成776；随后保存的页索引2变为1。新的本地候选保留这次迟到尺寸变化的锚点，等待续章补足高度。缓存候选保持原磁盘后端活动，不通过 diskCapacity=0 切换后端。这些本地修正不在 CI27 输入中。

[实际结果汇总](apple-summary.json)、[缓存原始观测](native-cache-original-observations.json)、[阅读附件来源](reader-records/provenance.json)均保留失败。原 logs ZIP、原测试/附件 manifest、原设备目录与 SHA 存在本目录；大体积原 xcresult 压缩包保留在本地 `ios/build/ci27/xcresult-original.zip`，SHA `a9f21f9b8ebc828d96269582e3cf0f80785629a9563fd382c15bff83b725b536`。仅解码完整匹配 Data 附件；4 个压缩记录无法完整解码，不冒充完整 xcresult 解析。

本轮没有全量 93 项 UI/设备或 64 场景视觉矩阵，不能关闭非站源完整门槛。用户随后明确暂停真实站源验收；目录仍为51、默认50，非站源完成后出总验收包。

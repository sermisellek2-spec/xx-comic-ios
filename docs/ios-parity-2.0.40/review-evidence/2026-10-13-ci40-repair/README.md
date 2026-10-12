# CI40 原失败与反馈/换源用例修复

2026-10-13。指定仓库 run38310693882，原输入23e9e5644a56e396c37d482c5b14f7c2c5fdc8c4，final-flows，未生成IPA。双SDK/图标/Release隔离、AppleCore929和双设备35Native通过，23UI/设备有三个方法失败。原ZIP与逐行失败保持，SHA见original-downloads.json、failure-lines.json；不把父运行归为当前通过。

下载队列删除后原截图实际已画“暂无离线下载任务”，AX树却没有该元素：UIView仅中心定位，未取得内容尺寸。补width与label四边约束，保留原空态和重启断言，并增加实际可达和零行断言。没有改任务删除期望。

日志原系统share已打开，CI执行了真实Close；根view identifier未作为AX元素暴露。测试改查真实Close，仍实际导出/关闭返回，并新增导出全部。复制一秒UIAlert在首轮等待前消失，改成按钮下非阻塞反馈，持续到下一次导出；UI验可读/无模态/继续导出，新增Native实际UIPasteboard等于脱敏原文且三个敏感测试字段不泄漏。菜单等关闭完成再分享或清空。

换源前的单边缘tap实际先隐藏可见工具栏，页码仍1，后续换源也正确保存1。补中间tap→等待隐藏→边缘tap前提；不改生产ReadingRules，全部原第2页/像素/源/收藏/分组/返回/重启断言保留。

本地95Swift Release/DEBUG语法退出0，仅解析；无Apple类型/运行结论。当前声明36Native/111UI，修复影响与最终full待Apple运行。真实站源仍暂停。

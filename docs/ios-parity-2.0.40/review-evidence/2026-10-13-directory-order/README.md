# 章节顺序在阅读、详情和重启之间保持

2026-10-13。冻结MainActivity.java10706–10715把chapterDesc传给目录，顺序变化后saveLocalState；原始提交/文件哈希和原文见frozen-reference.json。

iOS详情目录已有chapter.desc偏好，阅读页却总传isDesc:false且不消费order变化。现在阅读页从相同隔离UserDefaults读取，目录真实切换回写同一偏好，不改卷章/图片本身的顺序或日漫翻页方向。详情目录在实际呈现完成后再次定位已读章，避免半屏尺寸落定后把末尾当前章藏到屏外。

扩展原大目录用例：200章快滚/正逆序/选择/重开当前可达的原检查保留；新增重开仍倒序、详情同偏好/当前章可达、杀进程重启后倒序/第200话选中可达。未删除或放松原断言，36Native/111UI声明不变。

95Swift Release/DEBUG解析退出0，文件哈希前后一致；仅语法，不代Apple类型或运行。当前Reader影响及最终同版本full待验，真实站源仍暂停。

# 阅读模式切换与底栏尺寸接续候选

父输入6a7804e已补图内偏移，尚未Apple运行。CI23/24原件确认根导航流程通过，尺寸失败；日漫旋转通过，普通→卷轴→日漫及续读仍失败。本候选不宣称修复了模式切换。

根标签图标和文字改为应用实际frame布局，保留20pt图标、4pt间距及居中原断言，避免符号图alignment inset改变frame。阅读器仅Debug且显式 `--ui-testing` 时保留最多96条数值状态：模式/逻辑页/pending/真实offset/窗口及内容尺寸/恢复与动画状态；失败用例保存原始记录附件。Release无诊断数据，不记录作品路径、Cookie或网络内容，不改原页码/原图断言。

93个原生Swift文件Release/DEBUG语法检查实际退出0，精确输入SHA和命令见native-syntax-result.json；这不是Apple类型检查或UI通过。ComicCore生产/测试输入保持6a对应最终925项/2个Apple PDF跳过/0失败；不重用旧Apple929为当前结果。下一轮仅指定仓库开发CI，package_ipa=false，先阅读和根几何实证，再完整非站源回归。

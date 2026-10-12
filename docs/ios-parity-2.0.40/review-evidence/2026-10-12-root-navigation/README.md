# 根导航与阅读面板接续候选

父输入5e2eb9d，冻结Android696e80a / 2.0.40 / 340。第19轮c5实拍证明横屏根底栏图标/标题并排、阅读设置满高，旧图仅定位问题，不证明新候选通过。

根底栏保持每列纵排20pt图标、4pt间距、10pt标题和60pt应用内容，选中状态、200ms颜色过渡、8pt顶角与冻结边线颜色一致；系统底部安全区单独留在内容下方。使用公开UIKit容器关系和原有UINavigationController栈，详情/阅读隐藏底栏，返回恢复，交互取消按实际栈恢复；不修改私有UIKit子视图。

阅读设置按冻结MaxHeightScrollView将可滚动内容限制为窗口65%，顶部和底部82pt另计，保留iOS安全区及所有可滚动开关/关闭/拖动。此处不是把整张图缩放到安卓截图。

当前93个原生Swift文件Release/DEBUG仅语法退出0，build.sh bash语法退出0；没有对本候选的Apple类型或UI通过声明。新增原生宽度/纵排几何一项及四种方向主题下实际导航/详情返回UI用例，原有断言保留。后续configuration-files计划原生28、UI50每设备，实际结果必须重新核对。

父输入5e2的日漫阅读验收38223265455和配置视觉验收38223827364仍运行，两者未包含本目录的根导航/面板候选。日漫保留卷轴/普通/日漫，旧左右手继续忽略。新原始模拟器目录已取得：SDK17.5，实际iPhone15 Pro及M4 iPad均选择iOS17.5；这不直接证明iPad截图几何通过。

非站源门槛未通过；缓存物理占用与完整视觉仍开放，不启用真实网站、不产出阶段IPA。用户仅负责最终总验收。

公开UIKit容器关系参考：[Apple容器文档](https://developer.apple.com/documentation/uikit/creating-a-custom-container-view-controller)、[Apple UITabBar文档](https://developer.apple.com/documentation/uikit/uitabbar)。

暂存首次diff检查退出2，原因是自有日志的Windows CRLF行尾；保留日志原字节，只在本证据目录将日志行尾明确标为cr-at-eol，再运行检查，不把首次检查记为通过。

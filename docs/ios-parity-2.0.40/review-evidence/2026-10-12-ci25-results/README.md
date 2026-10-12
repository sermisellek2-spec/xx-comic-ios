# 第25轮 Apple 阅读复验

[实际运行38236059726](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38236059726)，输入d0e0d38125d85053a9e719627ee7acc816fe158e；reader-modes，package_ipa=false，结论failure。

Debug/Release构建成功。Mac Core932项、1项缓存物理归零失败，124.479秒。iPhone15 Pro与iPad Pro11(M4)原生各29项、0失败；原根底栏20pt图标、4pt间距和居中断言已通过。两个设备阅读UI各18项：16通过、2失败，各10条失败断言。原件tests.json另含1项保留附件的原生AI用例，不能把19当UI数量。

两个失败用例是日漫/普通/卷轴切换续读，以及同一张图片图内偏移往返。CI25原始数字记录表明：普通恢复逻辑第2页时实际offset为0，下一次右点只到实际第2页；转卷轴时读取旧水平内容尺寸，保存的图内偏移0.408821被压成0。正常日漫横滑、跨章、第3页旋转和10项连续阅读用例通过，不能据此关闭全部阅读需求。

`apple-summary.json`、原始logs ZIP、tests/manifest JSON、6份模拟器目录文件及SHA证明保留。14个原保留附件SHA已核对；原始xcresult ZIP190511506字节、SHA ea9a016795b41f37356c218ba0d6720a88b8c7e84e3b8902d9e0284008f8e6ac留在本地ios/build/ci25。

`reader-records/`保留原xcresult完整Zstd Data及逐字节解压内容和来源SHA，仅作为本轮诊断。1332个Data成员中4个完整帧解析失败也已登记；此方法不代替完整xcresulttool解析。下一轮导出器只补显式命名的隔离Debug数值附件。

当前c377af6布局恢复修正不在本轮输入中，正在CI38242082789复验；完整门槛仍未通过，没有IPA。

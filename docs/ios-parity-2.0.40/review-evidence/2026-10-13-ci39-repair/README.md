# CI39 原失败与 Files/分卷/目录验收修复

2026-10-13。指定仓库run38308516299，原输入aa536781b1e7b2e78cbc4a2b05c7537df6d0a57f，recovery-regression，无IPA。双SDK/图标/Release隔离、AppleCore929及双设备34Native通过；各30UI，iPhone15个失败断言（含1非预期）、iPad7个失败断言。原ZIP/完整日志/现场图保持，SHA见original-downloads.json，逐失败见failure-lines.json。未把失败记通过。

原Files AX明确同时有底层volumes.close“完成”与真正DocumentManager“Open”。驱动全app匹配时点到底层关闭按钮，系统拒绝滚到可见。现在文件/文件夹只在真实DOC浏览根匹配，确认/取消只在系统导航栏匹配，并等待真实关闭；Browse只切一次，优先当前目录/父级，解决isSelected不可靠造成十次重复Browse。恢复影响加入使用同驱动的配置导入/导出5UI，没有注入URL或伪造授权。

EPUB生成器默认屏幕scale，声明32逻辑像素在iPhone实际96×96；改format.scale=1保留32×32原精确断言。目录标准UITableViewCell自身无“第二章”标识，改按真实子静态文本定位，并给生产详情目录常规table ID；成功加载后真正隐藏全表背景加载按钮，避免过时“正在加载”AX信息。没有改章节/读到第二章的期望。

旋转与大目录回到当前章的测试原先在实际动画/定位完成前立即断言，改等真实frame/第200话可达后，保留原方向、选中、可点击和返回检查。文件夹同步原默认卷轴末尾可能顶端仍是前一图，页码不是整屏目标图身份；该身份回归明确用普通单页，保留原第2→改名新增后第3→移除后第1/实际64×96/重启的期望。卷轴位置和模式恢复仍由原ReaderContinuity/Core原断言覆盖，不伪称本用例验卷轴同步。外部修改等待实际前台、可达及真实host状态，有失败现场附件，不直接变更正文库。

95Swift Release/DEBUG语法退出0，build.sh Bash语法及消费者映射Python AST退出0，输入前后哈希一致；不是Apple类型检查。当前恢复范围声明36Native/36UI，最终完整范围36Native/111UI，当前修复Apple影响及同版本full待实际运行。真实站源保持暂停。

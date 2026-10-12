# CI37 完整影响复验结果

[指定仓库运行38302574712](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38302574712)，输入ce0607c，settings-reference，实际failure，无打包。两SDK/图标/Release隔离及Apple Core929项零失败；手机32原生有1用例/8断言失败（directory旧正文及重开仍命中），平板32原生有1用例失败（Cookie真实清理超时）。两设备6UI各4通过、2设置场景的清理前提失败；8设置截图可以定位组件，不能算8通过。

手机缓存实测清理后仍有528384字节已知正文、4个命中及两个256KiB实体文件，不是系统索引；平板对应HTTP正文/重开通过。原失败、实际观察、全部原件哈希见本目录。原xcresult artifact尚未下载，缓存错误当时附件在下一轮补录；未声称已确认WebKit内部原因。

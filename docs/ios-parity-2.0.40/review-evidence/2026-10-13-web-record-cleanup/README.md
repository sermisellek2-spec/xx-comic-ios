# WebKit 真实记录清理接续

CI36已证明URLCache正文/重开及31项原生双设备通过，但6项设置UI仍有偶发“请重试”。本候选移除清理时临时创建的WKWebView，采用公开API读取实际WKWebsiteDataRecord，再删除这些记录；未读取到记录才完成空态，不绕过WebKit检查。不加载文档、不联网；整体仍保留8秒失败/重试与迟到回调保护。未宣称已证实WebKit内部根因或候选已原生通过。

新增实际Cookie落盘→读取→清理→不命中→重复清理原生用例，原未使用会话用例保留。当前每设备声明32原生、93UI；原HTTP正文、同路径重开、原包、容量与10秒UI成功检查均未改。失败页Debug仅记录框架错误码，不输出Cookie/地址/授权。

本机90Swift输入Release/DEBUG前端解析均退出0，输入哈希前后不变，含外部Files夹具宿主。最初89输入漏宿主的解析结果已在proof中明确作废，由完整90替代；这仍不是Apple类型检查或运行。当前生产核心未修改，不重复已有13项通过。后续指定仓库运行必须实际通过再关闭问题。

公开契约：[读取数据记录](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/fetchdatarecords(oftypes:completionhandler:))、[删除记录](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/removedata(oftypes:for:completionhandler:))、[读取Cookie](https://developer.apple.com/documentation/webkit/wkhttpcookiestore/getallcookies(_:))。只据这些API选择实现，不把公开框架修复记录当本项目根因证明。

# 六漫画站源对接设计

## 目标

在不引入 WebView 或新解析依赖的前提下，将 `www.liumanhua.com` 接入现有站源架构，支持分类、分页列表、详情、目录和正文阅读；首版明确不支持关键词搜索，避免把推荐页误判为搜索结果。

## 架构

- 新增独立 `LiumanhuaComicSource`，沿用 `ComicSource` 接口和当前轻量 HTML/正则解析模式。
- `SourceConfig.liumanhua(boolean)` 提供基础 URL、路由和默认配置；主界面注册客户端、开关、持久化、导入导出及源路由。
- 分类页动态读取 `.cy_tag`，排除“资费”；站点一次只表达一个分类维度，因此选择分类时只提交对应路径，分页追加 `/page/{n}`。
- 章节页读取 `params`，Base64 解码后取前 16 字节 IV，使用固定 AES key `9S8$vJnU2ANeSRoF` 和 `AES/CBC/PKCS5Padding` 解密 JSON；仅接受 `source_id=6`、匹配站点/漫画/章节且图片为 HTTP(S) 的正文图片。

## 数据解析

- 列表仅解析 `.cy_list_mh > ul`，使用 `/数字` 作为漫画 ID，标题、封面、状态、最新章节和简介分别来自对应卡片节点，并按原始 ID 去重。
- 详情解析 `#intro_l`、`.cy_info_cover`、`.cy_title h1`、`.cy_xinxi`、`#comic-description`；目录只解析 `.cy_plist` / `.chapter__item`，不读取 `.rd-guess__comic` 推荐漫画。
- 章节目录保持 DOM 顺序交给现有顺序规范化；详情页单章“在线阅读”仍通过现有章节加载流程进入。

## 网络与错误处理

- 普通页面连接/读取超时分别为 10s/20s，章节读取超时为 10s/30s；固定 Chrome 124 UA 和页面 Referer。
- 所有连接和输入流在 `finally`/try-with-resources 中关闭；HTTP 非 2xx 抛出站源名和状态。
- 解密失败、host/站源/漫画/章节不匹配、空图片、重复图片或非 HTTP(S) 图片均抛出可读 `IOException`。
- 正文图片域名 `s2.bzcdn.net` 使用六漫画 Referer；加密参数和签名 URL 不写入持久化缓存。

## 非目标

- 首版不增加关键词搜索接口，不修改已有站源的验证、搜索或解析逻辑。
- 不新增第三方依赖，不执行站点 JavaScript。

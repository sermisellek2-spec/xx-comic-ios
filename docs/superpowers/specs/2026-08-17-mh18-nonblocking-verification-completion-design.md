# 18漫画非阻塞验证完成设计

## 目标

修复 18漫画用户完成 Turnstile 勾选后，挑战页仍停留到 120 秒超时的问题。勾选提交后立即恢复 App 主界面并允许用户继续操作，同时让同一个 WebView 保持可被 Cloudflare 接受的前台运行条件，直至挑战真正完成。

## 根因证据

真机错误日志最终状态为：

```text
url=https://18mh.org/manga, status=0, verifying=true, challenge=true, ready=true
```

用户确认勾选后验证页立即消失。现有实现检测到 Turnstile 隐藏响应或新的 `cf_clearance` 后调用 `showBackgroundView()`；该方法会把 18漫画 WebView 平移到屏幕外并将透明度降为 `0.01`。Turnstile 响应生成只表示交互已提交，不表示 Cloudflare 已确认验证成功。提前改变 WebView 的可见运行条件导致挑战页保持完整加载，未进入目标漫画页。

## 设计

1. 保留现有静默窗口。18漫画挑战在 4 秒内未自动完成时，显示同一个全尺寸 WebView 供用户勾选。
2. 检测到 Turnstile 响应或 `cf_clearance` 变化后，将状态解释为“交互已提交”，而不是“验证已完成”。
3. 新增“正在完成验证”视图状态：
   - WebView 保持 `MATCH_PARENT`、`translationX=0`、`VISIBLE`、`alpha=1`；
   - WebView 保持附着且不调用 `stopLoading()`、`onPause()` 或重新导航；
   - 禁止 WebView 接收新的触摸输入；
   - 将 App 原有根界面提升到 WebView 所在容器上方，让用户立即恢复正常操作；
   - 通过现有轻提示显示“18漫画 正在完成验证”，不增加全屏阻塞层。
4. 页面状态机继续每 800 毫秒检查挑战 DOM。只有挑战消失、目标 URL 匹配且 `readyState=complete` 时才提示“验证完成”、落盘 Cookie、捕获漫画 HTML，并将 WebView 转入原离屏后台状态。
5. 如果用户切换站源或页面，现有 `searchGeneration` 和站源 ID 校验丢弃旧页面结果；18漫画会话仍可完成凭证缓存。12 路搜索线程池允许其他站源继续加载。
6. 超时、缓存清理和手动验证入口保持现有行为。禁漫天堂继续使用原会话配置和原视图路径。

## 边界

- 不自动点击、伪造或绕过 Turnstile。
- 不把 Turnstile token 生成视为最终成功。
- 不修改 18漫画解析器、禁漫天堂代码或全局搜索线程池。
- 不新增依赖、Service、代理服务器或第二套 Cookie 存储。

## 验收

- 用户勾选时验证网页可操作。
- 勾选提交后 App 主界面立即恢复并可切换站源、设置和其他页面。
- 完成阶段 WebView 仍保持全尺寸、屏幕内、完全不透明且附着运行。
- Cloudflare 挑战真正消失后，原 18漫画列表请求继续并加载结果。
- 离开 18漫画后不会把旧列表或旧错误覆盖到当前页面。
- 禁漫天堂会话行为不变。
- 单元测试、源码契约、Release 构建、COS 与备用服务器回下载哈希核验通过。

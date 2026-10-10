# 交接时基线校验

日期：2026-10-10；环境：Windows PowerShell；执行目录：iOS checkout。

实际命令：

```powershell
pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1
```

退出码：0。实际输出：

```text
PASS: Android 2.0.40 / 340; release 696e80a44ab36b19de6f630565df32978e55a19e; 527 files and archive SHA-256 verified.
```

脚本已检查：固定版本/提交/归档身份、整个ZIP的SHA-256、527个文件集合和各文件SHA-256，以及重复/不安全文件路径。校验不解包、不修改基线。

此结果仅关闭BASE-01，不表示P0或产品验收通过。Gemini接手、转移机器或包内容变化时须重新核验。

# =============================================================================
# run.ps1 — 以真实配置启动 headless nvim 跑验证探针
#
#   pwsh ./verify/run.ps1
# 退出码 0 = PASS，非 0 = FAIL（详见下方输出与 verify\result.txt）
# =============================================================================
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}  # GBK 控制台也能显示中文
$root   = Split-Path -Parent $PSScriptRoot
$result = Join-Path $PSScriptRoot 'result.txt'
$probe  = Join-Path $PSScriptRoot 'probe.lua'
Remove-Item $result -Force -ErrorAction SilentlyContinue

$t = Get-Date
# 路径必须正斜杠：vim 的 -c 命令会把 \n 之类的序列当转义（如 ...\nvim... 会炸）
$resultF = $result -replace '\\', '/'
$probeF  = $probe  -replace '\\', '/'
# 注意：PowerShell 5.1 在 $ErrorActionPreference='Stop' 下，原生命令的 stderr
# 即使重定向到 2>$null 也会生成终止性错误记录（实测）。所以这里临时降为
# Continue 再合并丢弃。探针的完整输出在结果文件里，stderr 无信息量。
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
nvim --headless -i NONE -n `
  -c "let g:cpp_ts_result='$resultF'" `
  -c "luafile $probeF" 2>&1 | Out-Null
$ErrorActionPreference = $prevEAP
Write-Host ("耗时 {0:N1}s" -f ((Get-Date) - $t).TotalSeconds)

if (-not (Test-Path $result)) {
  Write-Error '探针没有写出结果文件（nvim 未正常执行完）'
  exit 2
}
Get-Content $result
$line = Get-Content $result | Select-String '^RESULT:' | Select-Object -First 1
if ($line -match 'PASS') { exit 0 } else { exit 1 }

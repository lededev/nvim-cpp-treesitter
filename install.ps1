# =============================================================================
# install.ps1 — 把编译产物装进用户 Neovim 配置（幂等，可重复执行）
#
#   out\cpp.dll          →  %LOCALAPPDATA%\nvim\parser\cpp.dll
#   queries\cpp\*.scm    →  %LOCALAPPDATA%\nvim\queries\cpp\
#   init\cpp-ts.lua      →  %LOCALAPPDATA%\nvim\init.lua 末尾（仅当尚未接入时）
#
# Neovim 的 runtimepath 会自动发现 配置目录\parser\ 与 配置目录\queries\，
# 所以装完即生效，无需插件管理器。
# =============================================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cfg  = Join-Path $env:LOCALAPPDATA 'nvim'

$dll = Join-Path $root 'out\cpp.dll'
if (-not (Test-Path $dll)) {
  throw "找不到 $dll —— 先运行 pwsh ./build.ps1"
}

# ---- 1. parser ------------------------------------------------------------------
$parserDir = Join-Path $cfg 'parser'
New-Item -ItemType Directory -Force $parserDir | Out-Null
Copy-Item $dll (Join-Path $parserDir 'cpp.dll') -Force
Write-Host ("parser : " + (Join-Path $parserDir 'cpp.dll'))

# ---- 2. queries ------------------------------------------------------------------
$qDir = Join-Path $cfg 'queries\cpp'
New-Item -ItemType Directory -Force $qDir | Out-Null
foreach ($f in Get-ChildItem (Join-Path $root 'queries\cpp') -File) {
  Copy-Item $f.FullName (Join-Path $qDir $f.Name) -Force
  Write-Host ("queries: " + (Join-Path $qDir $f.Name))
}

# ---- 3. init.lua 接线（幂等）------------------------------------------------------
$init = Join-Path $cfg 'init.lua'
$snippet = Join-Path $root 'init\cpp-ts.lua'
if (-not (Test-Path $init)) {
  $backup = $null
} else {
  $content = Get-Content $init -Raw
  if ($content -match 'apply_cpp_ts_highlights') {
    Write-Host "init   : 已含 C++ tree-sitter 块（apply_cpp_ts_highlights），跳过" -ForegroundColor Yellow
    return
  }
  # 追加（带标记，便于日后整块移除）
  $block = Get-Content $snippet -Raw
  $add = "`n" +
    "-- >>> nvim-cpp-treesitter:begin（本地项目 nvim-cpp-treesitter 管理，勿手改；" +
    "`n" +
    "--     整块删除可停用 C++ tree-sitter 高亮）" + "`n" +
    $block +
    "`n-- >>> nvim-cpp-treesitter:end" + "`n"
  [System.IO.File]::AppendAllText($init, $add)
  Write-Host ("init   : 已追加 C++ tree-sitter 块 → " + $init)
}
Write-Host ""
Write-Host "安装完成。验证: pwsh ./verify/run.ps1" -ForegroundColor Green
Write-Host "（若刚改过 init.lua，运行中的 nvim 需 :source $MYVIMRC 或重启）"

# =============================================================================
# build.ps1 — 从钉住的 tree-sitter-cpp 标签编译 cpp.dll
#
# 用法（在 MSYS2 UCRT64 终端里，保证 gcc 在 PATH）：
#   pwsh ./build.ps1                 # 用 pins.txt 里钉住的版本
#   pwsh ./build.ps1 -TsTag vX.Y.Z   # 跟进新版（ABI 校验会先跑）
#
# 产物：out\cpp.dll（覆盖式）
# =============================================================================
param(
  [string]$TsTag = '',        # 空 = 读 pins.txt
  [int]$MaxAbi = 0,           # 0  = 读 pins.txt 的 neovim_abi（parser ABI 的上限）
  [switch]$SkipNvimCheck      # 跳过 Neovim 侧 ABI 比对
)
# 用 Continue + 显式 $LASTEXITCODE 检查：PS 5.1 在 Stop 下会把原生命令的
# stderr（git 进度、gcc 告警、nvim 日志行）变成终止性错误记录（实测）。
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot

# ---- 读 pins.txt -------------------------------------------------------------
$pins = @{}
foreach ($line in Get-Content (Join-Path $root 'pins.txt')) {
  if ($line -match '^([A-Za-z_]+)\s*=\s*(.+)$') { $pins[$Matches[1]] = $Matches[2].Trim() }
}
if (-not $TsTag) { $TsTag = $pins['tree_sitter_cpp'] }
if (-not $MaxAbi) { $MaxAbi = [int]$pins['neovim_abi'] }
Write-Host "目标: tree-sitter-cpp $TsTag  (parser ABI 上限=$MaxAbi)" -ForegroundColor Cyan

# ---- 1. 工具链 ----------------------------------------------------------------
$gcc = Get-Command gcc -ErrorAction SilentlyContinue
if (-not $gcc) {
  throw "找不到 gcc。请在 MSYS2 UCRT64 终端里运行本脚本（需要 mingw-w64-ucrt-x86_64-gcc）。"
}
Write-Host ("gcc: " + (gcc --version | Select-Object -First 1))

# ---- 2. 获取钉住的源码 ---------------------------------------------------------
# 钉版值可以是 tag（v0.23.4）或 commit SHA。注意：本项目的查询依赖
# master 上的新节点（如 module_name，v0.23.4 没有），所以默认钉的是
# master HEAD 的 SHA（见 pins.txt 的注释）。
$repo = 'https://github.com/tree-sitter/tree-sitter-cpp.git'
$src = Join-Path $root 'src'
if (Test-Path (Join-Path $src '.git')) {
  Write-Host "更新已有克隆到 $TsTag ..."
  Push-Location $src
  # 注意 1：PS 5.1 传原生参数会弄坏含冒号的 refspec（实测被吃掉），
  #          所以只用不带冒号的参数（--tags / 裸 SHA）。
  # 注意 2：本地已有就直接 checkout；否则逐级加深 fetch 再试。
  if (git rev-parse --verify --quiet "${TsTag}^{commit}" 2>$null) {
    Write-Host "本地已有，直接 checkout"
  } else {
    git fetch --depth 1 origin --tags 2>$null
    if (-not (git rev-parse --verify --quiet "${TsTag}^{commit}" 2>$null)) {
      git fetch --depth 50 origin master 2>$null
    }
    if (-not (git rev-parse --verify --quiet "${TsTag}^{commit}" 2>$null)) {
      throw "本地拿不到 $TsTag（标签不存在？SHA 太旧？可删掉 src 目录重试）"
    }
  }
  git checkout -q "$TsTag"
  if ($LASTEXITCODE -ne 0) { throw "git checkout $TsTag 失败" }
  Pop-Location
} else {
  Write-Host "克隆 tree-sitter-cpp $TsTag ..."
  if ($TsTag -match '^[0-9a-f]{7,40}$') {
    # commit SHA：先克隆默认分支，再按 SHA 取（GitHub 支持直接 fetch SHA）
    git clone --quiet --depth 1 $repo $src
    if ($LASTEXITCODE -ne 0) { throw 'git clone 失败（网络？）' }
    Push-Location $src
    git fetch --depth 1 origin $TsTag 2>$null
    Pop-Location
    if (-not (Test-Path (Join-Path $src 'src\parser.c'))) { throw '克隆目录结构异常' }
  } else {
    git clone --quiet --depth 1 --branch $TsTag $repo $src
    if ($LASTEXITCODE -ne 0) { throw 'git clone 失败（网络？标签不存在？）' }
  }
}
Push-Location $src
$head = git describe --tags 2>$null
Pop-Location
Write-Host "源码: $head"

# ---- 3. ABI 校验 ------------------------------------------------------------------
# 规则：tree-sitter 运行时【向后兼容】—— parser 的 LANGUAGE_VERSION 只要
# ≤ Neovim 的 language_version 就能加载（14 的 parser 跑在 15 的 Nvim 上没问题，
# 反过来不行）。注意：新版仓库里 LANGUAGE_VERSION 在【生成的】 src/parser.c 顶部，
# src/tree_sitter/parser.h 里已经没有这个定义了。
$parserC = Get-Content (Join-Path $src 'src\parser.c') -Raw
if ($parserC -match 'LANGUAGE_VERSION\s+(\d+)') {
  $srcAbi = [int]$Matches[1]
} else {
  throw '在 src\parser.c 里找不到 LANGUAGE_VERSION'
}
Write-Host ("parser 侧 ABI (parser.c 的 LANGUAGE_VERSION) = " + $srcAbi)

$nvimAbi = $null
if (-not $SkipNvimCheck) {
  $nvim = Get-Command nvim -ErrorAction SilentlyContinue
  if ($nvim) {
    $probe = Join-Path $env:TEMP 'nvim-cpp-ts-abi.lua'
    Set-Content $probe 'print(vim.treesitter.language_version)' -Encoding ascii
    # nvim -l 模式下 print() 走【stderr】，而且可能先吐一行 "log: ... not
    # accessible"，所以重定向到文件后只取第一个纯数字行。
    $probeOut = Join-Path $env:TEMP 'nvim-cpp-ts-abi.out'
    Remove-Item $probeOut -Force -ErrorAction SilentlyContinue
    nvim --clean --headless -l $probe > $probeOut 2>&1
    # PS 5.1 的 2>&1 会给 stderr 行加 "nvim : " 前缀，两种形态都兼容
    foreach ($l in (Get-Content $probeOut)) {
      if ($l -match '^\s*(\d+)\s*$' -or $l -match 'nvim\s*:\s*(\d+)\s*$') {
        $nvimAbi = [int]$Matches[1]; break
      }
    }
    if ($null -eq $nvimAbi) { throw '无法从 nvim 读取 language_version' }
    Write-Host ("Neovim 侧 language_version               = " + $nvimAbi)
    if ($srcAbi -gt $nvimAbi) {
      Write-Warning "ABI 过新：parser 要 $srcAbi，Neovim 只有 $nvimAbi，加载会失败。`n" +
        "→ 换一个 LANGUAGE_VERSION≤$nvimAbi 的 tree-sitter-cpp 标签（见 README『跟进 Neovim 升级』）。"
      exit 1
    }
    if ($srcAbi -lt $nvimAbi) {
      Write-Host ("  （兼容：parser ABI $srcAbi ≤ Nvim ABI $nvimAbi，可直接加载）")
    }
  } else {
    Write-Warning 'PATH 里没有 nvim，跳过 Neovim 侧比对（-SkipNvimCheck 可静音）'
  }
}
# 没有 Neovim 可比对时，用 pins.txt 的上限兜底
if ($null -eq $nvimAbi -and ($srcAbi -gt $MaxAbi)) {
  throw "未做 Neovim 侧比对，且 parser ABI $srcAbi 超过 pins.txt 的 neovim_abi=$MaxAbi，拒绝继续"
}

# ---- 4. 编译 --------------------------------------------------------------------
$out = Join-Path $root 'out'
New-Item -ItemType Directory -Force $out | Out-Null
$flags = @('-O2', '-std=c11', '-fPIC', '-shared', '-Isrc',
           '-static-libgcc',            # 静态链 libgcc，运行时不依赖 mingw 运行时 dll
           '-o', (Join-Path $out 'cpp.dll'),
           'src/parser.c', 'src/scanner.c')
Write-Host ("gcc " + ($flags -join ' ')) -ForegroundColor DarkGray
Push-Location $src
& gcc @flags
if ($LASTEXITCODE -ne 0) { throw "gcc 编译失败（exit $LASTEXITCODE）" }
Pop-Location

$dll = Get-Item (Join-Path $out 'cpp.dll')
Write-Host ""
Write-Host ("完成: " + $dll.FullName + "  " + $dll.Length + " B") -ForegroundColor Green
Write-Host "下一步: pwsh ./install.ps1  然后  pwsh ./verify/run.ps1"

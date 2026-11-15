# nvim-cpp-treesitter

Neovim 的 **C++ tree-sitter 分层高亮**：本地 parser + 本地查询 + 分层颜色，
**不装插件、不 fork Neovim、不向上游提 PR**。本项目是整套方案的"配方仓库"——
当 Neovim 升级导致解析器/ABI 失配时，按本 README 逐步重编译、重装、验证。

## 它解决什么问题

Neovim 0.12.6 核心**不带 C++ 解析器**（只有 c/lua/markdown/query/vim/vimdoc），
而 legacy regex 语法（`syntax/cpp.vim`）里 `+ - * = ; , . :: () [] <>` 这些
**符号运算符没有任何语法匹配**，无高亮组可指定；且 `return`、`if`、`template`
在 desert 里全挤在同一个 khaki 色上，分不出执行流与语法词。

> **钉版提醒**：parser 钉的是 **commit SHA（master HEAD）**，不是 tag。
> 查询里用到的 `module_name` 等 C++20 模块节点**只存在于 master**，
> 任何已发布 tag（含 v0.23.4）都没有——用 tag 编的 dll 会在查询里报
> `Invalid node type "module_name"`。当前 SHA 与版本矩阵见 `pins.txt`。

本方案（"路线 C"，调研与决策过程见 `../nvim-cpp-highlight-plan.md`）：

1. 自编译 `tree-sitter-cpp` 为 `cpp.dll`，放进 `~\AppData\Local\nvim\parser\`
   （runtimepath 自动发现，与核心内置解析器等价）；
2. `queries/cpp/highlights.scm` 用 `inherits: c` 复用上游 c 查询的全部
   运算符/标点/修饰词规则，只把上游一锅端的 `@keyword` 大列表**按语义重排为三档**：

   | 档位 | 例子 | capture | 颜色（desert 下） |
   |---|---|---|---|
   | 1 执行流 | `if return try throw co_await` | `@keyword.conditional/repeat/return/exception/coroutine` | #7dcfff / #f7768e **粗体** |
   | 2 运算符/标点 | `+ = ; . :: () [] {} <> <=> new delete` | `@operator @keyword.operator @punctuation.*` | #ffa7d1 / #e0af68 / #9ece6a |
   | 3 语法关键词 | `class template typename const static final` | `@keyword.type @keyword.modifier @keyword` | #7a7a7a / #6f7b8f / #8a8a8a（不加粗） |

3. `init.lua` 里 `FileType cpp` 自动 `vim.treesitter.start`，`ColorScheme`
   自动补回 12 个颜色组。高亮器接管后 legacy regex 语法按 Neovim 官方行为
   自动关闭（`&syntax=''`），无混色。

## 目录结构

```
nvim-cpp-treesitter/
├── build.ps1            # 从钉住的 tag 克隆并编译 cpp.dll（ABI 双向校验）
├── install.ps1          # 幂等安装 → %LOCALAPPDATA%\nvim\{parser,queries,init.lua}
├── pins.txt             # 钉住的版本矩阵（脚本从这里读）
├── out/cpp.dll          # 当前已验证的成品（2026-11-15 构建，可免编译直接用）
├── queries/cpp/         # 分层查询（inherits: c）
├── init/cpp-ts.lua      # init.lua 接线块（install.ps1 幂等追加的来源）
└── verify/
    ├── probe.lua        # 端到端验证探针（状态/解析/capture/颜色 四项）
    └── run.ps1          # 真实配置启动跑探针，退出码 0=PASS
```

## 日常三步

```powershell
# 1. 编译（MSYS2 UCRT64 终端里；首次会克隆 tree-sitter-cpp 到 src\，约 2.6 秒编完）
pwsh ./build.ps1

# 2. 安装（幂等，可重复；init.lua 已接好时自动跳过）
pwsh ./install.ps1

# 3. 验证（真实配置 headless 启动，检查 10 个关键 capture 的最终颜色）
pwsh ./verify/run.ps1
```

**怎么跑这三个脚本**：
- 有 pwsh 7：直接 `pwsh ./build.ps1` 即可。
- 只有 Windows PowerShell 5.1 且执行策略为 Restricted：
  `powershell -ExecutionPolicy Bypass -File .\build.ps1`。
- 中文输出乱码时先 `chcp 65001`（脚本本身是带 BOM 的 UTF-8，别保存成 ANSI）。

想改配色：编辑 `init/cpp-ts.lua` 与 `%LOCALAPPDATA%\nvim\init.lua` 里
`apply_cpp_ts_highlights()` 的 hex（两处保持一致），并同步改
`verify/probe.lua` 顶部的 `EXPECTED` 表。

## 跟进 Neovim 升级（本项目的存在意义）

升级 Neovim 后**按顺序**做：

1. **先验证**：`pwsh ./verify/run.ps1`。
   - 全 PASS → 什么都不用做，旧 dll 仍然兼容。
   - `get_parser(cpp) 失败` → 进入第 2 步。
2. **查 ABI**：取 Neovim 当前的 `language_version`，与 parser 侧的
   `LANGUAGE_VERSION` 比对。**兼容规则是"≤"而不是"="**：
   tree-sitter 运行时向后兼容，parser ABI ≤ Nvim ABI 即可加载
   （当前组合：parser 14 ≤ Nvim 15，所以工作正常）。
   ```powershell
   "print(vim.treesitter.language_version)" | Set-Content $env:TEMP\abi.lua
   nvim --clean --headless -l $env:TEMP\abi.lua          # Neovim 侧
   # 源码侧：grep "LANGUAGE_VERSION" src/parser.c
   # 注意：新版仓库的 src/tree_sitter/parser.h 里【已没有】这个 define，
   # 它在【生成的】 src/parser.c 顶部。
   # （build.ps1 会自动做这个比对，超限会直接报警）
   ```
3. **换版本**：取一个 `LANGUAGE_VERSION` ≤ 新 Nvim ABI 的 commit——
   直接拿 master 最新（它总是最新 grammar）：
   ```powershell
   git -C src fetch --depth 50 origin master
   git -C src log -1 --format='%H %ad' FETCH_HEAD    # 记下新 SHA
   # 确认 ABI：git -C src grep -m1 'define LANGUAGE_VERSION' FETCH_HEAD -- src/parser.c
   ```
   然后：
   ```powershell
   pwsh ./build.ps1 -TsTag <新SHA>
   ```
   并把 `pins.txt` 的 `tree_sitter_cpp=` / `parser_abi=` 改成新值。
   （也可用 tag，但得先从查询里删掉 `module_name` 等 master 节点——不推荐。）
4. **重编 + 重装 + 验证**：`build.ps1 → install.ps1 → verify/run.ps1`。
5. **若查询报错**（如 `Impossible pattern`）：说明新版本的**节点名/结构**变了
   （本次就踩过：`[[ ]]` 是 `attribute_declaration` 的子节点而非 `attribute` 的）。
   修法：对照新版 `src/node-types.json` 逐条核对本项目 `queries/cpp/highlights.scm`
   里用到的节点名，必要时参考新版上游 `queries/highlights.scm` 的 diff 合并——
   **保留三档分层结构，只修节点名**。

**其他可能的失配点**（概率低，遇到再查）：
- 解析器发现约定：依赖 `runtimepath 下的 parser/<lang>.*`
  （`runtime/lua/vim/treesitter/language.lua`）。若 Neovim 改了发现逻辑，
  按新版 language.lua 调整 install.ps1 的落点。
- 颜色组名：`@keyword.return` 这类组名是社区约定，Neovim 不校验，升级不会坏；
  但 `vim.treesitter.start` 的行为（如默认关 `&syntax`）若变化，看新版
  `runtime/lua/vim/treesitter.lua` 的 `M.start` 文档串。

## 已知边界（诚实披露）

- `out/cpp.dll` 是在 **MSYS2 UCRT64 gcc 16.2.0** 上编的；同平台重编可位级复现
  （flags 见 pins.txt）。
- 验证探针走**同步解析**（`vim.g._ts_force_sync_parsing`）：某 DSH 会话沙箱里
  headless 异步高亮事件循环会死循环（内置 c 解析器同样复现，属沙箱对 uv 的干扰，
  与本项目产物无关）；交互式/Neovide 下异步正常。
- tree-sitter-cpp 为 **MIT** 许可（`src/` 为构建期克隆，不入库）；查询文件在上游
  MIT 文件基础上修改，仅个人使用，不提 PR。
- Neovide 只是渲染外壳（Rust+wgpu），解析/高亮全在 Neovim 核心进程，
  所以本方案对 Neovide 与终端 nvim 同等生效。

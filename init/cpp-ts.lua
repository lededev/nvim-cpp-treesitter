-- ── C++ tree-sitter 高亮（路线 C：本地 parser + 查询，不装插件）─────────────
-- parser : %LOCALAPPDATA%\nvim\parser\cpp.dll
--          （tree-sitter-cpp 见 ../pins.txt，language_version 与 Neovim 精确匹配）
-- queries: %LOCALAPPDATA%\nvim\queries\cpp\
--          （inherits: c，上游 keywords 大列表按语义重排为三档）
-- 颜色层级：执行流 (if/return/try) 最亮 > 运算符/小标点 显眼 > 类型名/修饰词 退到背景
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'cpp', 'cc', 'cxx', 'c++' },
  desc = 'C++ tree-sitter 高亮',
  callback = function(ev)
    if pcall(vim.treesitter.language.add, 'cpp') then
      pcall(vim.treesitter.start, ev.buf, 'cpp')
    end
  end,
})
local function apply_cpp_ts_highlights()
  local g = function(name, attrs) vim.api.nvim_set_hl(0, name, attrs) end
  -- 第 1 档：执行流关键词 —— 最突出
  g('@keyword.conditional', { fg = '#7dcfff', bold = true })
  g('@keyword.repeat',      { fg = '#7dcfff', bold = true })
  g('@keyword.return',      { fg = '#f7768e', bold = true })
  g('@keyword.exception',   { fg = '#f7768e', bold = true })
  g('@keyword.coroutine',   { fg = '#f7768e', bold = true })
  -- 第 2 档：运算符与小标点 —— 显眼
  g('@operator',              { fg = '#ffa7d1' })
  g('@keyword.operator',      { fg = '#ffa7d1' })   -- new / delete / and / or ...
  g('@punctuation.delimiter', { fg = '#e0af68' })   -- ; : , . ::
  g('@punctuation.bracket',   { fg = '#9ece6a' })   -- () [] {} 模板尖括号
  g('@attribute.builtin',     { fg = '#ffa7d1' })   -- [[nodiscard]] 整体
  -- 第 3 档：语法关键词 —— 收敛到背景（与第 1 档形成对比）
  g('@keyword.type',    { fg = '#7a7a7a' })         -- class/struct/template/typename...
  g('@keyword.modifier', { fg = '#6f7b8f' })        -- const/static/constexpr/final...
  g('@keyword',         { fg = '#8a8a8a' })         -- 其余泛化 keyword（含回落）
end
apply_cpp_ts_highlights()
-- 手动 :colorscheme 切换后自动补回
vim.api.nvim_create_autocmd('ColorScheme', {
  desc = '配色切换后重新应用 C++ 三档高亮',
  callback = apply_cpp_ts_highlights,
})

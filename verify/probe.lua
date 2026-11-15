-- =============================================================================
-- verify/probe.lua — 端到端验证（真实配置启动，同步解析，不依赖事件循环）
--
-- 由 verify/run.ps1 以“真实启动”方式调用（加载用户的 init.lua，
-- 这样颜色组才是你实际生效的那一份）：
--   nvim --headless -c "let g:cpp_ts_result='<路径>'" -c "luafile verify/probe.lua"
--
-- 检查四件事：
--   1) FileType cpp 后 b:ts_highlight == true（高亮器已接管）
--   2) 同步解析成功
--   3) 关键 capture 都出现了（测试代码覆盖了三种档位）
--   4) 每个 capture 的最终渲染色 == 期望值（capture→组→颜色 全链路）
--
-- 结果写入 g:cpp_ts_result 指定的文件（RESULT: PASS / FAIL）。
-- 期望值表在下方 EXPECTED，改配色后同步改这里。
-- =============================================================================
local lines = {
  '#include <iostream>',
  'template <typename T> concept C = requires(T x) { x.size(); };',
  '[[nodiscard]] static std::optional<std::size_t> f(int a, int b) noexcept {',
  '  if (a > b) return a + b;',
  '  class Impl { public: int x; protected: virtual int g() const final; };',
  '  auto p = new Impl();',
  '  delete p;',
  '  return (a <=> b) ? 1 : 0;',
  '}',
}
-- capture → { fg=0xRRGGBB, bold=bool? }
local EXPECTED = {
  ['@keyword.conditional']    = { fg = 0x7dcfff, bold = true },
  ['@keyword.return']         = { fg = 0xf7768e, bold = true },
  ['@keyword.conditional.ternary'] = { fg = 0x7dcfff, bold = true },
  ['@operator']               = { fg = 0xffa7d1 },
  ['@keyword.operator']       = { fg = 0xffa7d1 },
  ['@punctuation.delimiter']  = { fg = 0xe0af68 },
  ['@punctuation.bracket']    = { fg = 0x9ece6a },
  ['@keyword.type']           = { fg = 0x7a7a7a },
  ['@keyword.modifier']       = { fg = 0x6f7b8f },
  ['@attribute.builtin']      = { fg = 0xffa7d1 },
}
local out, fails = {}, 0
local function add(s) out[#out + 1] = s end
local function ok(s) add('  [PASS] ' .. s) end
local function bad(s) fails = fails + 1; add('  [FAIL] ' .. s) end

-- capture → 候选组名（与高亮器一致的回落顺序；cap 可带可不带 @）
local function cands(cap)
  cap = cap:gsub('^@', '')
  local r = { '@' .. cap .. '.cpp', '@' .. cap }
  local b = cap
  while true do
    local nb = b:match('^(.*)%.')
    if not nb then break end
    r[#r + 1] = '@' .. nb
    b = nb
  end
  return r
end
local function resolve(cap)
  for _, n in ipairs(cands(cap)) do
    local ok2, info = pcall(vim.api.nvim_get_hl, 0, { name = n })
    if ok2 and info and info.fg then
      return n, info.fg, info.bold and true or false
    end
  end
  return nil, nil, nil
end

local function main()
  -- 临时文件必须带 .cpp 扩展名，否则 filetype 检测不出 cpp
  local src = vim.fn.tempname() .. '.cpp'
  vim.fn.writefile(lines, src)
  vim.cmd('edit ' .. vim.fn.fnameescape(src))
  vim.bo.filetype = 'cpp'   -- 兜底：与真实 .cpp 文件的检测结果一致，确保 FileType 触发

  add('== 1. 状态 ==')
  add('  ft=' .. vim.bo.filetype .. '  b:ts_highlight=' .. tostring(vim.b[0].ts_highlight))
  if vim.b[0].ts_highlight == true then ok('高亮器已接管 (ts_highlight=true)')
  else bad('ts_highlight 未置位 —— FileType 块没跑或 language.add 失败') end

  add('== 2. 同步解析 ==')
  vim.g._ts_force_sync_parsing = true
  local parser = vim.treesitter.get_parser(0, 'cpp')
  if not parser then bad('get_parser(cpp) 失败') return end
  local trees
  parser:parse(nil, function(_, t) trees = t end)
  local tree
  for _, t in pairs(trees or {}) do tree = t; break end
  if not tree then bad('parse 未返回树') return end
  ok('解析成功, root 子节点=' .. tree:root():child_count())

  add('== 3/4. capture 存在性 + 最终颜色 ==')
  local q = vim.treesitter.query.get('cpp', 'highlights')
  if not q then bad('查询编译失败') return end
  -- 注意：q.captures[idx] 返回的 capture 名【不带】@ 前缀，统一补上再比较
  local seen, n = {}, 0
  for _, nodes in q:iter_matches(tree:root(), 0, 0, -1) do
    n = n + 1
    for idx, nds in pairs(nodes) do
      local cap = q.captures[idx]
      if cap and not seen['@' .. cap:gsub('^@', '')] then
        seen['@' .. cap:gsub('^@', '')] = true
      end
    end
  end
  add('  共 ' .. n .. ' 个匹配，' .. (function()
    local c = 0; for _ in pairs(seen) do c = c + 1 end; return c
  end)() .. ' 种 capture')
  for cap, want in pairs(EXPECTED) do
    if not seen[cap] then
      bad(cap .. ' : 测试代码未产生该 capture')
    else
      local g, fg, bold = resolve(cap)
      local hex = fg and string.format('#%06x', fg) or '无色'
      if fg == want.fg and (want.bold or not bold) then
        ok(string.format('%-28s → %s (%s)', cap, hex, g or '-'))
      else
        bad(string.format('%-28s → 期望 #%06x%s, 实际 %s (%s)',
          cap, want.fg, want.bold and ' bold' or '', hex, g or '未定义'))
      end
    end
  end
end

local ok, err = pcall(main)
if not ok then fails = fails + 1; add('  [FATAL] ' .. tostring(err)) end
add('RESULT: ' .. (fails == 0 and 'PASS' or ('FAIL (' .. fails .. ' 项)')))
local dest = vim.g.cpp_ts_result
if dest then vim.fn.writefile(out, dest) end
for _, l in ipairs(out) do print(l) end
vim.cmd('qa!')

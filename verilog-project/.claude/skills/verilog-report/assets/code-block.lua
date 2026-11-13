-- 코드블록(사이클 표, 텍스트 표, 수정 제안 diff 등)을 글자 칸 단위로 그린다.
-- 영문·공백은 1칸, 한글 등 전각 문자는 정확히 2칸 상자에 넣어서, 글꼴과 상관없이 열이 맞는다.
-- (한글 고정폭 폰트가 없거나 한국어 조판 패키지가 공백 폭을 바꿔도 표가 어긋나지 않게 한다)
--
-- ```diff 블록은 줄 단위로 색칠한다.
--   - 로 시작하는 줄 (수정 전, 지울 줄)     → 빨간 글자 + 옅은 빨간 바탕
--   + 로 시작하는 줄 (수정 제안, 넣을 줄)   → 초록 글자 + 옅은 초록 바탕
--   @@ 줄                                  → 회색 글자
--   그 밖의 줄 (바뀌지 않는 앞뒤 코드)       → 검은 글자 + 옅은 회색 바탕
-- ```hier 블록은 die-layout.lua가 처리하므로 건드리지 않는다.
-- 칸 폭(\cw)과 상자 명령(\cbs, \cbn, \cbw)은 header.tex에 정의되어 있다.

local function is_wide(c)
  return (c >= 0x1100 and c <= 0x115F) or (c >= 0x2E80 and c <= 0xA4CF)
      or (c >= 0xAC00 and c <= 0xD7A3) or (c >= 0xF900 and c <= 0xFAFF)
      or (c >= 0xFE30 and c <= 0xFE4F) or (c >= 0xFF00 and c <= 0xFF60)
      or (c >= 0xFFE0 and c <= 0xFFE6)
end

local ASCII_ESC = {
  ['\\'] = '\\textbackslash{}', ['{'] = '\\{', ['}'] = '\\}', ['_'] = '\\_', ['&'] = '\\&',
  ['%'] = '\\%', ['#'] = '\\#', ['$'] = '\\$', ['^'] = '\\textasciicircum{}', ['~'] = '\\textasciitilde{}',
  ['-'] = '-{}',          -- -- 가 대시 합자로 바뀌지 않게
  ["'"] = "\\textquotesingle{}", ['`'] = '\\textasciigrave{}', ['<'] = '<{}', ['>'] = '>{}',
}

local function line_tex(line)
  local out = {}
  for _, c in utf8.codes(line) do
    if c == 32 then
      out[#out + 1] = '\\cbs{}'
    elseif c == 9 then
      out[#out + 1] = '\\cbs{}\\cbs{}\\cbs{}\\cbs{}'
    elseif c < 128 then
      local ch = utf8.char(c)
      out[#out + 1] = ASCII_ESC[ch] or ch
    elseif is_wide(c) then
      out[#out + 1] = '\\cbw{' .. utf8.char(c) .. '}'
    else
      out[#out + 1] = '\\cbn{' .. utf8.char(c) .. '}'
    end
  end
  return table.concat(out)
end

local DIFF_STYLE = {
  del = { 'diffdelbg', 'diffdel' },
  add = { 'diffaddbg', 'diffadd' },
  hunk = { 'diffctxbg', 'diffhunk' },
  ctx = { 'diffctxbg', 'black' },
}

local function diff_kind(line)
  if line:match('^%-%-%-') or line:match('^%+%+%+') or line:match('^@@') then return 'hunk' end
  if line:match('^%-') then return 'del' end
  if line:match('^%+') then return 'add' end
  return 'ctx'
end

local function lines_of(text)
  local t = {}
  for line in (text .. '\n'):gmatch('(.-)\n') do t[#t + 1] = line end
  if #t > 1 and t[#t] == '' then t[#t] = nil end
  return t
end

function CodeBlock(cb)
  if not FORMAT:match('latex') then return nil end
  if cb.classes:includes('hier') then return nil end

  local out = { '\\par\\vspace{2pt}{\\setlength{\\parskip}{0pt}\\setlength{\\fboxsep}{1.2pt}' }
  if cb.classes:includes('diff') then
    for _, line in ipairs(lines_of(cb.text)) do
      local st = DIFF_STYLE[diff_kind(line)]
      out[#out + 1] = string.format(
        '\\noindent\\colorbox{%s}{\\parbox{\\dimexpr\\linewidth-2\\fboxsep\\relax}{\\strut\\textcolor{%s}{\\ttfamily\\small %s}}}\\par\\nointerlineskip',
        st[1], st[2], line_tex(line))
    end
  else
    for _, line in ipairs(lines_of(cb.text)) do
      out[#out + 1] = '\\noindent{\\ttfamily\\small\\strut ' .. line_tex(line) .. '}\\par'
    end
  end
  out[#out + 1] = '}\\vspace{4pt}'
  return pandoc.RawBlock('latex', table.concat(out, '\n'))
end

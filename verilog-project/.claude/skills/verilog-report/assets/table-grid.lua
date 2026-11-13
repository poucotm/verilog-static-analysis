-- LaTeX 출력에서 모든 표를 본문 너비 전체를 쓰는 격자 표(세로·가로 선)로 바꾼다.
-- 열 너비: 구분선 '-' 개수 비율(pandoc이 계산한 값)이 있으면 그것을, 없으면 내용 길이를 기준으로 정한다.
-- 정렬: 구분선의 ':' 표기(:---:, ---:)를 따른다.

local function to_latex(blocks)
  local s = pandoc.write(pandoc.Pandoc(blocks), 'latex')
  return (s:gsub('%s+$', ''):gsub('\n\n+', '\\par '))
end

local function text_len(blocks)
  local s = pandoc.utils.stringify(blocks)
  local n = 0
  for _, c in utf8.codes(s) do
    n = n + ((c >= 0x1100) and 2 or 1)   -- 한글 등은 영문 2글자 폭
  end
  return n
end

local function rows_of(tbl)
  local rows = {}
  for _, r in ipairs(tbl.head.rows) do rows[#rows + 1] = { r = r, head = true } end
  for _, b in ipairs(tbl.bodies) do
    for _, r in ipairs(b.head) do rows[#rows + 1] = { r = r } end
    for _, r in ipairs(b.body) do rows[#rows + 1] = { r = r } end
  end
  for _, r in ipairs(tbl.foot.rows) do rows[#rows + 1] = { r = r } end
  return rows
end

local SEV_COLOR = { ['상'] = 'sevhigh', ['중'] = 'sevmid', ['하'] = 'sevlow' }   -- header.tex 색 이름

local align_cmd = {
  AlignCenter = '\\centering',
  AlignRight = '\\raggedleft',
  AlignLeft = '\\raggedright',
  AlignDefault = '\\raggedright',
}

-- 분석 개요 표 (헤더가 | 항목 | 내용 |인 2열 표)를 다음 배치로 그린다.
--   첫 행:     [TOP | 값 ............. | 소스 폴더 | 값 .............]
--   가운데 행: [항목 | 내용 ................................] (블록 기능, 이슈, 블랙박스, 그레이박스, 분석 소스)
--   끝 세 행:  [분석시간 | 값 ......... | 룰 버전 | 값 .........]
--              [사용모델 | 값 ......... | 노력 | 값 ............]
--              [소요시간 | 값 ......... | 토큰 사용량 | 값 .....]
-- Markdown 원본은 2열 표 그대로 두고, PDF에서만 이렇게 배치한다. 항목 이름은 대소문자를 가리지 않는다.
-- 끝 행의 항목이 결과 파일에 없으면(이전 규칙의 결과 파일) 있는 항목만 그 행을 넓게 차지하고, 둘 다 없으면 행을 만들지 않는다.
local OV_FIRST = { 'TOP', '소스 폴더' }
local OV_LAST = { { '분석시간', '룰 버전' }, { '사용모델', '노력' }, { '소요시간', '토큰 사용량' } }   -- 표 끝에 붙는 행들
local CH = 105                          -- 한 줄 영문 글자 수 (아래 Table과 같은 기준)

local function cell_text(c)
  return (pandoc.utils.stringify(c.contents):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function is_overview(tbl, rows)
  if #tbl.colspecs ~= 2 or not rows[1] or not rows[1].head then return false end
  local c = rows[1].r.cells
  return c[1] and c[2] and cell_text(c[1]) == '항목' and cell_text(c[2]) == '내용'
end

local function overview(rows)
  local pairs_by_key, middle = {}, {}
  for i = 2, #rows do
    local c = rows[i].r.cells
    local k = c[1] and cell_text(c[1]) or ''
    local item = { key = k, klen = c[1] and text_len(c[1].contents) or 0,
                   val = c[2] and to_latex(c[2].contents) or '', vlen = c[2] and text_len(c[2].contents) or 0 }
    pairs_by_key[k:upper()] = item
    middle[#middle + 1] = item
  end
  local function pick(list)
    local out = {}
    for _, k in ipairs(list) do
      local it = pairs_by_key[k:upper()]
      if it then out[#out + 1] = it; it.used = true end
    end
    return out
  end
  local first = pick(OV_FIRST)
  local lasts = {}
  for _, keys in ipairs(OV_LAST) do
    local r = pick(keys)
    if #r > 0 then lasts[#lasts + 1] = r end
  end
  local mid = {}
  for _, it in ipairs(middle) do if not it.used then mid[#mid + 1] = it end end
  local multi = { first }               -- 여러 쌍이 한 줄에 놓이는 행들
  for _, r in ipairs(lasts) do multi[#multi + 1] = r end

  -- 열 구성: P개의 [키 | 값] 쌍 (k1 v1 k2 v2 ...).
  -- 한 행의 q개 쌍은 P개의 열 쌍에 고르게 나눠 앉는다 (span = 차지하는 열 쌍 수).
  local P = 1
  for _, r in ipairs(multi) do P = math.max(P, #r) end
  local function spans(q)
    local s, start = {}, 1
    for i = 1, q do
      local n = math.floor(P / q) + ((i <= P % q) and 1 or 0)
      s[i] = { start = start, n = n }
      start = start + n
    end
    return s
  end

  -- 키 열 폭: 그 열 쌍에서 시작하는 키 이름 중 가장 긴 것에 맞춘다 (1번 키 열은 가운데 행 키도 포함).
  local klen = {}
  for j = 1, P do klen[j] = 0 end
  for _, it in ipairs(mid) do klen[1] = math.max(klen[1], it.klen) end
  -- 값 열 폭: 쌍이 P개인 행들에서 그 자리 값 길이의 최댓값 비율 (너무 긴 값은 40자로 잘라 계산)
  local vw = {}
  for j = 1, P do vw[j] = 8 end
  for _, r in ipairs(multi) do
    local sp = spans(#r)
    for i, s in ipairs(sp) do
      klen[s.start] = math.max(klen[s.start], r[i].klen)
      if #r == P then vw[s.start] = math.max(vw[s.start], math.min(r[i].vlen, 40)) end
    end
  end
  local frac, ksum, vsum = {}, 0, 0
  for j = 1, P do
    local kf = (klen[j] > 0) and (klen[j] + 4) / CH or 0.03   -- 항상 다른 칸에 덮이는 키 열은 최소 폭
    frac[2 * j - 1] = kf; ksum = ksum + kf
    vw[j] = vw[j] + 4
    vsum = vsum + vw[j]
  end
  for j = 1, P do frac[2 * j] = (1 - ksum) * vw[j] / vsum end

  local function width(a, b)            -- a..b 열을 합친 칸의 폭
    local f = 0
    for i = a, b do f = f + frac[i] end
    return string.format('\\dimexpr %.4f\\linewidth-2\\tabcolsep-1.2\\arrayrulewidth\\relax', f)
  end
  local function key_cell(col, it)
    local left = (col == 1) and '|' or ''
    -- 바탕색을 칠하면 행 사이 가로선이 가려 보여서, 키는 남색 굵은 글자로만 구분한다
    return string.format('\\multicolumn{1}{%s>{\\centering\\arraybackslash}p{%s}|}{\\textbf{\\textcolor{secblue}{%s}}}',
      left, width(col, col), it.key)
  end
  local function val_cell(a, b, it)
    return string.format('\\multicolumn{%d}{>{\\raggedright\\arraybackslash}p{%s}|}{%s}', b - a + 1, width(a, b), it.val)
  end
  -- q개의 쌍을 P개의 열 쌍에 고르게 나눠 한 행을 만든다
  local function row(items)
    local cells = {}
    for i, s in ipairs(spans(#items)) do
      local col = 2 * s.start - 1
      cells[#cells + 1] = key_cell(col, items[i])
      cells[#cells + 1] = val_cell(col + 1, col + 2 * s.n - 1, items[i])
    end
    return table.concat(cells, ' & ') .. ' \\\\ \\hline'
  end

  local spec = {}
  for i = 1, #frac do
    spec[#spec + 1] = string.format('p{\\dimexpr %.4f\\linewidth-2\\tabcolsep-1.2\\arrayrulewidth\\relax}', frac[i])
  end
  local out = { '\\begin{longtable}[l]{|' .. table.concat(spec, '|') .. '|}', '\\hline' }
  if #first > 0 then out[#out + 1] = row(first) end
  for _, it in ipairs(mid) do out[#out + 1] = row({ it }) end
  for _, r in ipairs(lasts) do out[#out + 1] = row(r) end
  out[#out + 1] = '\\end{longtable}'
  return pandoc.RawBlock('latex', table.concat(out, '\n'))
end

function Table(tbl)
  if not FORMAT:match('latex') then return nil end
  local ncol = #tbl.colspecs
  local rows = rows_of(tbl)
  if is_overview(tbl, rows) then return overview(rows) end

  -- 열 너비 비율
  --  짧은 열(내용이 SHORT 폭 이하: NO, 증상, 심각도 등)은 내용에 딱 맞는 고정 폭.
  --  나머지 열이 남은 폭을 나눠 갖는다 (구분선 '-' 비율이 있으면 그 비율, 없으면 내용 길이 비율).
  local SHORT, CHARS_PER_LINE = 14, 105  -- 9pt narrow 폰트, A4, 여백 12mm 기준 한 줄 영문 글자 수 (보수적으로)
  local given = true
  for _, cs in ipairs(tbl.colspecs) do
    if type(cs[2]) ~= 'number' then given = false end
  end
  local len, fixed, flex, flex_total, fixed_total = {}, {}, {}, 0, 0
  for i, cs in ipairs(tbl.colspecs) do
    local m = 2
    for _, row in ipairs(rows) do
      local c = row.r.cells[i]
      if c then m = math.max(m, text_len(c.contents)) end
    end
    len[i] = m
    if m <= SHORT then
      fixed[i] = (m + 4) / CHARS_PER_LINE   -- +4: 셀 좌우 여백
      fixed_total = fixed_total + fixed[i]
    else
      flex[i] = given and cs[2] or math.min(m, 60)
      flex_total = flex_total + flex[i]
    end
  end
  if flex_total == 0 and ncol >= 4 then
    -- 짧은 열만 여러 개인 표(예: 점검 커버리지 | 모듈 | M1 … M15 |)는 남는 폭을 모든 열에 고르게 나눈다
    -- 열이 많아 고정 폭 합이 1을 넘으면 같은 비율로 줄여 페이지 폭에 맞춘다
    local extra = math.max(1 - fixed_total, 0) / ncol
    local shrink = (fixed_total > 1) and (1 / fixed_total) or 1
    for i in ipairs(tbl.colspecs) do fixed[i] = fixed[i] * shrink + extra end
    fixed_total = 1
  elseif flex_total == 0 then
    -- 짧은 열 2~3개뿐이면 가장 긴 열(같으면 마지막 열)이 남은 폭을 갖는다 (예: | 심각도 | 위치 |)
    local k = #tbl.colspecs
    for i = #tbl.colspecs, 1, -1 do if len[i] > len[k] then k = i end end
    fixed_total = fixed_total - fixed[k]
    fixed[k] = nil
    flex[k] = 1
    flex_total = 1
  end
  local w = {}
  if flex_total == 0 then               -- 위에서 고르게 나눈 경우: 이미 합이 1
    for i in ipairs(tbl.colspecs) do w[i] = fixed[i] end
  else
    local rest = math.max(1 - fixed_total, 0.2)
    local scale = (fixed_total > 0.8) and (0.8 / fixed_total) or 1
    for i in ipairs(tbl.colspecs) do
      w[i] = fixed[i] and fixed[i] * scale or rest * flex[i] / flex_total
    end
  end

  local spec = {}
  for i, cs in ipairs(tbl.colspecs) do
    local frac = w[i]
    spec[#spec + 1] = string.format(
      '>{%s\\arraybackslash}p{\\dimexpr %.4f\\linewidth-2\\tabcolsep-1.2\\arrayrulewidth\\relax}',
      align_cmd[cs[1]] or '\\raggedright', frac)
  end

  local out = {}
  out[#out + 1] = '\\begin{longtable}[l]{|' .. table.concat(spec, '|') .. '|}'
  out[#out + 1] = '\\hline'
  local had_head = false
  for _, row in ipairs(rows) do
    local cells = {}
    for i = 1, ncol do
      local c = row.r.cells[i]
      local s = c and to_latex(c.contents) or ''
      if row.head then
        s = '\\textbf{' .. s .. '}'
      elseif SEV_COLOR[s] then
        s = '\\textcolor{' .. SEV_COLOR[s] .. '}{\\textbf{' .. s .. '}}'   -- 심각도 상/중/하는 색 글자
      end
      cells[#cells + 1] = s
    end
    local line = table.concat(cells, ' & ') .. ' \\\\ \\hline'
    if row.head then
      out[#out + 1] = '\\rowcolor{tblhead}' .. line
      had_head = true
    else
      if had_head then out[#out + 1] = '\\endhead'; had_head = false end
      out[#out + 1] = line
    end
  end
  if had_head then out[#out + 1] = '\\endhead' end
  out[#out + 1] = '\\end{longtable}'
  return pandoc.RawBlock('latex', table.concat(out, '\n'))
end

-- # 보고서 제목 → 박스(\reporttitle, header.tex)
-- ## / ### 제목 앞: 남은 공간이 적으면 제목을 다음 페이지로 (제목만 페이지 끝에 남는 것 방지)
-- #### 항목 이름(요약, 문제 설명 …) 앞: 같은 처리, 필요한 공간은 작게
function Header(h)
  if not FORMAT:match('latex') then return nil end
  if h.level == 1 then
    local title = pandoc.write(pandoc.Pandoc({ pandoc.Plain(h.content) }), 'latex'):gsub('%s+$', '')
    return pandoc.RawBlock('latex', '\\reporttitle{' .. title .. '}')
  end
  -- ### V-001 제목 → 번호를 남색 박스로 떼어 내고 제목과 간격을 둔다
  if h.level == 3 and h.content[1] and h.content[1].t == 'Str' and h.content[1].text:match('^V%-%d+$') then
    local no = h.content[1].text
    local new = pandoc.List({ pandoc.RawInline('latex', '\\issueno{' .. no .. '}') })
    local i = 2
    while h.content[i] and h.content[i].t == 'Space' do i = i + 1 end
    for j = i, #h.content do new:insert(h.content[j]) end
    h.content = new
  end
  -- ## 절 제목은 바로 뒤 첫 내용(이슈 제목 표 + 심각도 표 등)까지 같이 들어갈 공간을 요구한다
  local need = (h.level >= 4) and 4 or ((h.level == 2) and 16 or 10)
  return { pandoc.RawBlock('latex', '\\keepspace{' .. need .. '}'), h }
end

-- ```hier 코드블록(들여쓰기 모듈 계층)을 Chip Die Layout 형태의 중첩 박스 그림(TikZ)으로 바꾼다.
-- 그림 높이는 반 페이지를 넘지 않고, 박스가 너무 작아지면 깊이를 자동으로 줄인다.
-- 블록 종류마다 갈색·붉은색 계열의 다른 색을 쓰고, 그림 아래에 범례를 붙인다.
--
-- 입력 형식 (들여쓰기 2칸 = 한 단계, 끝의 [태그]는 블록 종류):
--   rx_top
--     u_ctrl : rx_ctrl [CTRL]
--       u_fsm : rx_fsm [CTRL]
--     u_lane[0..3] : lane [DP]     -- 배열 인스턴스는 한 줄로
--     u_fifo : fifo_core [BB]      -- 블랙박스
-- 태그: CTRL(제어/FSM), BUF(FIFO·버퍼·메모리), DP(데이터패스·연산), IF(인터페이스·I/O),
--       CLK(클럭·리셋·동기화), BB(블랙박스). 태그가 없으면 이름으로 추정하고, 모르면 일반 블록.
-- .md로 볼 때는 들여쓴 계층 텍스트로 보인다.

local W_MM, H_MAX_MM = 180, 118          -- 그림 폭, 최대 높이 (범례 포함 반 페이지 이하)
local MIN_W, MIN_H = 22, 10              -- 박스 최소 크기(mm). 이보다 작아지면 깊이를 줄인다
local BAND, PAD, GAP = 5.6, 1.3, 1.3     -- 자식이 있는 박스의 이름 띠 높이, 안쪽 여백, 자식 간격

-- 블록 종류: 색 이름(header.tex의 die* 색), 범례 이름, 이름 추정 패턴
local KINDS = {
  { tag = 'CTRL', color = 'diectrl', label = 'Control',      pat = { 'ctrl', 'ctl', 'fsm', 'control', 'sched', 'arb', 'seq', 'cfg', 'csr', 'regs', 'cnt', 'counter', 'timer' } },
  { tag = 'BUF',  color = 'diebuf',  label = 'Buffer/Memory', pat = { 'fifo', 'buf', 'ram', 'mem', 'rom', 'queue', 'sram', 'dpram', 'cache' } },
  { tag = 'DP',   color = 'diedp',   label = 'Datapath',     pat = { 'mul', 'add', 'acc', 'alu', 'dp', 'calc', 'filt', 'fir', 'sat', 'shift', 'div', 'mac', 'core' } },
  { tag = 'IF',   color = 'dieif',   label = 'Interface',    pat = { 'axi', 'apb', 'ahb', 'if', 'intf', 'phy', 'uart', 'spi', 'i2c', 'rx', 'tx', 'io', 'pad', 'bridge' } },
  { tag = 'CLK',  color = 'dieclk',  label = 'Clock/Reset',  pat = { 'clk', 'clock', 'rst', 'reset', 'sync', 'cdc', 'pll', 'mmcm', 'bufg' } },
}
local BB_KIND = { tag = 'BB', color = 'diebb', label = 'Black box' }
local used_gb = false                    -- 그림에 그레이박스가 있으면 범례에 추가
local GEN_KIND = { tag = '', color = 'diegen', label = 'Block' }

local function esc(s)
  return (s:gsub('[\\{}_&%%#%$^~]', function(c)
    if c == '\\' then return '\\textbackslash{}' end
    if c == '~' then return '\\textasciitilde{}' end
    if c == '^' then return '\\textasciicircum{}' end
    return '\\' .. c
  end))
end

local function kind_of(node)
  if node.tag == 'BB' then return BB_KIND end
  for _, k in ipairs(KINDS) do
    if node.tag == k.tag then return k end
  end
  -- 태그가 없으면 모듈 이름(없으면 인스턴스 이름)으로 추정.
  -- 이름을 단어로 나눠 뒤 단어부터 본다 (rx_ctrl → ctrl, rx_counter → counter). 단어가 패턴으로 시작하면 해당 종류.
  local words = {}
  for w in (node.mod or node.inst):lower():gmatch('%a+') do words[#words + 1] = w end
  for i = #words, 1, -1 do
    for _, k in ipairs(KINDS) do
      for _, p in ipairs(k.pat) do
        if words[i]:sub(1, #p) == p then return k end
      end
    end
  end
  return GEN_KIND
end

local function parse(text)
  local root, stack, unit = nil, {}, nil
  for line in text:gmatch('[^\n]+') do
    local ind, body = line:match('^(%s*)(.-)%s*$')
    if body ~= '' then
      local n = #ind
      if n > 0 and not unit then unit = n end
      local d = unit and math.floor(n / unit + 0.5) or 0
      -- 끝의 태그들: 블록 종류 하나 + 그레이박스 표시 [GB] (예: "u_fft : xfft [DP] [GB]")
      local tag, gb = nil, false
      while true do
        local t = body:match('%[(%u+)%]%s*$')
        if not t then break end
        if t == 'GB' then gb = true else tag = tag or t end
        body = body:gsub('%s*%[%u+%]%s*$', '')
      end
      local inst, mod = body:match('^(.-)%s*:%s*(.+)$')
      local node = { inst = inst or body, mod = inst and mod or nil, tag = tag, gb = gb, kids = {} }
      if d == 0 or not root then
        root = root or node; stack = { root }
      else
        while #stack > d do table.remove(stack) end
        local parent = stack[#stack]
        table.insert(parent.kids, node)
        stack[#stack + 1] = node
      end
    end
  end
  return root
end

local function count(node)
  local c = 0
  for _, k in ipairs(node.kids) do c = c + 1 + count(k) end
  return c
end

local function maxdepth(node)
  local m = 0
  for _, k in ipairs(node.kids) do m = math.max(m, 1 + maxdepth(k)) end
  return m
end

local function weight(node, d, D)
  if d >= D or #node.kids == 0 then return 1 end
  local s = 0
  for _, k in ipairs(node.kids) do s = s + weight(k, d + 1, D) end
  return s
end

-- 자식 박스를 몇 줄로 나눌지 정한다 (die처럼 격자로 배치).
-- 줄 수 1..n을 모두 시험해, 가장 납작하거나 길쭉한 박스의 가로세로 비가 가장 작은 배치를 고른다.
function arrange(kids, iw, ih, d, D)
  local n = #kids
  local ws, total = {}, 0
  for i, k in ipairs(kids) do ws[i] = weight(k, d + 1, D); total = total + ws[i] end
  local best, best_score
  for r = 1, n do
    -- 순서를 유지한 채 무게가 비슷하도록 r줄로 나눈다
    local rows, cur, acc, target = {}, { w = 0 }, 0, total / r
    for i, k in ipairs(kids) do
      cur[#cur + 1] = k; cur.w = cur.w + ws[i]; acc = acc + ws[i]
      local left_rows = r - #rows - 1
      if left_rows > 0 and (acc >= target * (#rows + 1) - 1e-9 or n - i == left_rows) then
        rows[#rows + 1] = cur; cur = { w = 0 }
      end
    end
    if #cur > 0 then rows[#rows + 1] = cur end
    local hspan = ih - GAP * (#rows - 1)
    local score = 0
    for _, row in ipairs(rows) do
      local rh = hspan * row.w / total
      local wspan = iw - GAP * (#row - 1)
      for _, k in ipairs(row) do
        local bw = wspan * weight(k, d + 1, D) / row.w
        local a = math.max(bw / rh, rh / bw) / 1.6   -- 가로가 세로의 1.6배 정도인 박스를 가장 좋게 본다
        score = math.max(score, math.max(a, 1 / a))
      end
    end
    if not best_score or score < best_score then best, best_score = rows, score end
  end
  return best
end

-- 박스 배치. 반환값 false면 최소 크기 미달
local function place(node, x, y, w, h, d, D, out)
  local shown = (d < D) and #node.kids > 0
  out[#out + 1] = { n = node, x = x, y = y, w = w, h = h, d = d, leaf = not shown,
                    hidden = (not shown) and count(node) or 0 }
  local ok = (w >= MIN_W and h >= MIN_H)
  if not shown then return ok end
  local ix, iy, iw, ih = x + PAD, y + PAD, w - 2 * PAD, h - BAND - PAD
  if iw <= 0 or ih <= 0 then return false end
  local rows = arrange(node.kids, iw, ih, d, D)
  -- 줄 높이는 줄 무게 비율, 줄 안의 박스 폭은 박스 무게 비율
  local total = 0
  for _, r in ipairs(rows) do total = total + r.w end
  local hspan = ih - GAP * (#rows - 1)
  local ytop = iy + ih
  for _, r in ipairs(rows) do
    local rh = hspan * r.w / total
    local wspan = iw - GAP * (#r - 1)
    local xpos = ix
    for _, k in ipairs(r) do
      local s = wspan * weight(k, d + 1, D) / r.w
      ok = place(k, xpos, ytop - rh, s, rh, d + 1, D, out) and ok
      xpos = xpos + s + GAP
    end
    ytop = ytop - rh - GAP
  end
  return ok
end

local function height_for(D)
  return math.min(H_MAX_MM, 30 + 24 * D)
end

local function render(root)
  local D = maxdepth(root)
  local boxes, H
  while true do
    H = height_for(D)
    boxes = {}
    if place(root, 0, 0, W_MM, H, 0, D, boxes) or D == 1 then break end
    D = D - 1
  end

  local used, order = {}, {}
  used_gb = false
  local t ={ '\\begin{center}\\begin{tikzpicture}[x=1mm,y=1mm]' }
  for _, b in ipairs(boxes) do
    local n = b.n
    local k = (b.d == 0) and { color = 'diedie' } or kind_of(n)
    if b.d > 0 and not used[k.label] then used[k.label] = true; order[#order + 1] = k end
    local dash = (k == BB_KIND) and ',dashed' or (n.gb and ',dash dot' or '')
    local lw = (b.d == 0) and 1.4 or (n.gb and 1.0 or 0.6)
    t[#t + 1] = string.format('\\filldraw[fill=%s,draw=dieline,line width=%.1fpt%s] (%.2f,%.2f) rectangle ++(%.2f,%.2f);',
      k.color, lw, dash, b.x, b.y, b.w, b.h)
    if n.gb and b.d > 0 then
      -- 그레이박스: 오른쪽 위에 GB 표시 (흐름 분석에만 쓰고 자체 문제는 분석하지 않는 모듈)
      used_gb = true
      t[#t + 1] = string.format(
        '\\node[anchor=north east,fill=white,draw=dieline,inner sep=0.6mm,text=dietext,font=\\footnotesize\\bfseries] at (%.2f,%.2f) {GB};',
        b.x + b.w - 0.7, b.y + b.h - 0.7)
    end
    local name = '\\textbf{' .. esc(n.inst) .. '}'
    local mod = n.mod and esc(n.mod) or ''
    if b.hidden > 0 then mod = mod .. string.format(' +%d', b.hidden) end
    if b.leaf then
      t[#t + 1] = string.format(
        '\\node[align=center,text width=%.2fmm,inner sep=0.5mm,text=dietext,font=\\small] at (%.2f,%.2f) {%s\\\\{\\footnotesize %s}};',
        math.max(b.w - 1.5, 4), b.x + b.w / 2, b.y + b.h / 2, name, mod)
    else
      local font = (b.d == 0) and '\\normalsize' or '\\small'
      t[#t + 1] = string.format(
        '\\node[anchor=north west,inner sep=0.7mm,text width=%.2fmm,text=dietext,font=%s] at (%.2f,%.2f) {%s~{\\footnotesize %s}};',
        math.max(b.w - 2, 4), font, b.x + 0.4, b.y + b.h - 0.2, name, mod)
    end
  end
  t[#t + 1] = '\\end{tikzpicture}'

  -- 범례: 그림에 쓰인 블록 종류만, 정해진 순서로
  local legend = {}
  for _, k in ipairs(KINDS) do if used[k.label] then legend[#legend + 1] = k end end
  if used[GEN_KIND.label] then legend[#legend + 1] = GEN_KIND end
  if used[BB_KIND.label] then legend[#legend + 1] = BB_KIND end
  local items = {}
  for _, k in ipairs(legend) do
    local dash = (k == BB_KIND) and ',dashed' or ''
    items[#items + 1] = string.format(
      '\\tikz[baseline=-0.6ex]\\filldraw[fill=%s,draw=dieline,line width=0.5pt%s] (0,-1.2mm) rectangle (4mm,1.2mm);~%s',
      k.color, dash, k.label)
  end
  if used_gb then
    items[#items + 1] = '\\tikz[baseline=-0.6ex]{\\filldraw[fill=white,draw=dieline,line width=0.8pt,dash dot] (0,-1.2mm) rectangle (6mm,1.2mm);'
      .. '\\node[font=\\tiny\\bfseries,text=dietext] at (3mm,0) {GB};}~Graybox (흐름 분석만)'
  end
  t[#t + 1] = '\\par\\vspace{2pt}{\\small ' .. table.concat(items, '\\hspace{5mm}') .. '}'
  t[#t + 1] = '\\end{center}'
  return table.concat(t, '\n')
end

function CodeBlock(cb)
  if not cb.classes:includes('hier') then return nil end
  if not FORMAT:match('latex') then return nil end
  local root = parse(cb.text)
  if not root then return nil end
  return pandoc.RawBlock('latex', render(root))
end

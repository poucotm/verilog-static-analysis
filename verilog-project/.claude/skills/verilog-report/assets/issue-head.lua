-- 이슈 상세 제목(### V-001 제목 {#v-001})을 검은 테두리 표 형태 [ V-001 | 제목 ]으로 바꾼다.
-- 번호 칸 색은 요약 표에서 찾은 심각도(상/중/하)에 따라 달라진다.
-- 다른 필터(table-grid.lua)보다 먼저 실행해야 한다 (요약 표가 아직 Table일 때 심각도를 읽기 위해).

local SEV_COLOR = { ['상'] = 'sevhigh', ['중'] = 'sevmid', ['하'] = 'sevlow' }

local function latex(inlines)
  return (pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), 'latex'):gsub('%s+$', ''))
end

local function cell_text(cell)
  return pandoc.utils.stringify(cell.contents):gsub('^%s+', ''):gsub('%s+$', '')
end

function Pandoc(doc)
  if not FORMAT:match('latex') then return nil end

  -- 1) 표에서 번호 → 심각도 찾기 (첫 칸이 V-001, 다른 칸이 상/중/하인 행)
  local sev = {}
  doc:walk({
    Table = function(tbl)
      for _, body in ipairs(tbl.bodies) do
        for _, row in ipairs(body.body) do
          local first = row.cells[1] and cell_text(row.cells[1])
          if first and first:match('^V%-%d+$') then
            for i = 2, #row.cells do
              local t = cell_text(row.cells[i])
              if SEV_COLOR[t] then sev[first] = SEV_COLOR[t]; break end
            end
          end
        end
      end
    end,
  })

  -- 2) ### V-001 제목 → \issuehead
  doc.blocks = doc.blocks:walk({
    Header = function(h)
      if h.level ~= 3 then return nil end
      local first = h.content[1]
      if not (first and first.t == 'Str' and first.text:match('^V%-%d+$')) then return nil end
      local no = first.text
      local i = 2
      while h.content[i] and h.content[i].t == 'Space' do i = i + 1 end
      local rest = pandoc.List()
      for j = i, #h.content do rest:insert(h.content[j]) end
      local id = (h.identifier ~= '' and h.identifier) or no:lower()
      return pandoc.RawBlock('latex', string.format('\\keepspace{10}\\issuehead{%s}{%s}{%s}{%s}',
        id, no, latex(rest), sev[no] or 'secblue'))
    end,
  })
  return doc
end

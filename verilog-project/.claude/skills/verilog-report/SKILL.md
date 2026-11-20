---
name: verilog-report
description: Turns a verilog-review result file (reports/<top>_review_<date>.md) into a PDF report named with the top module and date. Writes, without blank pages, a boxed title (<TOP> RTL Analysis Report), an overview table with TOP, source folder, block function, analyzed source, analysis time, rule version, model, effort, elapsed time, and token usage, a die-layout design-structure figure, a summary table with V-001 numbers, 상/중/하 severity, short content, code location, and view links, and per-issue details starting with a [number | title] table. The report body and all user-facing responses are in Korean. Always use this skill when the user mentions a report, PDF, summarizing or sharing review results, or Korean requests such as 보고서, PDF, 결과 정리, 리뷰 결과 공유, or asks for a report after a verilog-review analysis.
---

# Verilog Analysis Report

Turn a `verilog-review` result into a PDF report. The report is named with **the top module name and the date**.
This skill only makes the report. It never re-analyzes or changes the analysis result.

**Complete example: `assets/report_template.md`** (relative to this skill folder). The report has the same structure and the same Markdown syntax as this example. In the normal flow (section 5) the report is assembled from the result file by a shell command, so **do not Read the template**; open it only when the result file is broken and the report has to be fixed by hand.

## Language

- **The report is written in Korean**, exactly like `assets/report_template.md`. Every response to the user, including the PDF-tool question (5.1) and the final report (section 6), is in Korean.
- Korean text shown in this skill inside backticks, code blocks, quote blocks, or example tables is an **exact literal**. Copy it as is; do not translate it. The only English text in the report is the title line `# <TOP> RTL Analysis Report`.
- The Lua filters (`assets/*.lua`) find the overview table, the severity colors, and heading styles by the Korean names (`항목`, `내용`, `분석시간`, `룰 버전`, `상`/`중`/`하`, …), so a translated name breaks the PDF layout.

---

## 1. Input

- The **most recent** of `reports/<top>_review_<YYYYMMDD>[_n].md` (by date; on the same day, the largest `_n`). `<top>` is the top module name set in this session.
- If the user names a specific result file, use that.
- If there is no result file, do not make a report; tell the user to run `verilog-review` first.
- Do not ask the user for extra information to write the report.

## 2. Output files

- Reuse the result file's date tag: `reports/<top>_review_20261023_2.md` → `reports/pdf/<top>_report_20261023_2.md` / `.pdf`
- Rebuilding from the same result file overwrites the report with the same name (it is the same analysis).

---

## 3. Report structure

Do not change the order. The report always ends with the appendix `부록: 점검 ID와 심각도 기준` (3.7). **Do not force page breaks (`\newpage` is forbidden); write the content continuously.** Sections are separated by heading levels.

| Markdown | PDF look | Used for |
|------|------|------|
| `#` | white text on a navy box + copper line below | report title (once, at the top) |
| `##` | navy heading + thick line below | sections: 분석 개요, 설계 구조, 요약, 상세, 점검 커버리지, 블랙박스 확인 사항, 부록 |
| `###` | black-bordered table `[ V-001 \| 제목 ]`. The number cell has the severity color background (상 red, 중 orange, 하 green); the title cell has a light tint of the same color | one issue (`### V-001 제목 {#v-001}`) |
| `####` | bold navy text, top margin | items within an issue (요약, 발생 가능한 문제 …) |

- The issue title table's severity color is looked up automatically from the severity cell of the summary table (`assets/issue-head.lua`). Severity characters (상/중/하) in tables are colored the same way.

### 3.1 Title and overview
```markdown
# <TOP> RTL Analysis Report

## 분석 개요

| 항목 | 내용 |
|:--:|------------------------------------------|
| TOP | `<top>` |
| 소스 폴더 | `<경로>` |
| 블록 기능 | … |
| 이슈 | 총 n건 (상 n / 중 n / 하 n) |
| 블랙박스 | n개: `모듈` |
| 그레이박스 | n개: `모듈` (graybox 폴더, 흐름 분석만) |
| 분석 소스 | 총 n개 파일, n줄 |
| 참고 스펙 | `analysis-spec.md` |
| 분석시간 | YYYY-MM-DD HH:MM |
| 룰 버전 | v<버전> @ POUCO |
| 사용모델 | … |
| 노력 | … |
| 소요시간 | … |
| 토큰 사용량 | … |
```
- `<TOP>` in the title is the top module name in **all uppercase** (e.g., if top is `rx_top`, `# RX_TOP RTL Analysis Report`). Do not change the rest of the title.
- **The PDF layout is changed automatically by the conversion filter** (`assets/table-grid.lua`). Write the Markdown as a plain two-column table.
  - First row: `TOP | 소스 폴더` laid out as cells on one line
  - Middle rows: one `항목 | 내용` per line (블록 기능, 이슈, 블랙박스, 그레이박스, 분석 소스, 참고 스펙 in that order; 참고 스펙 only if it is in the result file)
  - Last three rows: `분석시간 | 룰 버전`, `사용모델 | 노력`, `소요시간 | 토큰 사용량`, each laid out as cells on one line
  - The filter recognizes the overview table by the header `| 항목 | 내용 |` and picks the first and last three rows by item name. So **write the header and item names exactly as in the example**.
- **Copy the overview table from the result file as is.** The TOP value in the table is the original module name (case preserved).
  - If `(측정 중)` remains in the result file (the measurement script did not run), write "측정 불가" in those cells.
  - Copy the 참고 스펙 row if the result file has it; never create it otherwise.
  - 분석 소스, 분석시간, 룰 버전, 사용모델, 노력, 소요시간, 토큰 사용량 are **the values at analysis time**. Never replace them with the version/model at report time, or with the time/tokens spent on the report.
  - The 룰 버전 value has the form `v<버전> @ POUCO`. If the result file was made under older rules and lacks `@ POUCO`, keep the version and only append ` @ POUCO`.
  - If the result file was made under older rules and has no table, with basic info on one line, build the table from that content. Leave out rows not in the result file (분석 소스, 블록 기능, 사용모델, 노력, 소요시간, 토큰 사용량, etc.); never make them up.
- Do not create a separate cover page.

### 3.2 Design structure (설계 구조)
Copy the result file's `hier` code block and the one line under it (clock, reset, FSM) as is.
- In the PDF it is drawn like a chip die layout: submodule boxes nested in a grid inside the top box (`assets/die-layout.lua`).
- Colors are brown/red tones, different for each block-kind tag (`[CTRL]` `[BUF]` `[DP]` `[IF]` `[CLK]` `[BB]`). A legend for only the kinds used is added under the figure. Black boxes are grayish-brown dashed boxes. Grayboxes (`[GB]`) keep their block-kind color and are marked with a dash-dot border and a `GB` label at the top right, and "Graybox (흐름 분석만)" is added to the legend.
- Depth is reduced automatically so the figure stays within half a page. Hidden sub-instance counts appear as `+n` in the box.
- Do not reduce the `hier` depth by hand or change tags. Leave instances without tags as they are.

### 3.3 Summary (요약)
Copy the result file's summary table as is.

```markdown
## 요약

| NO | 심각도 | 내용 | 위치 | 상세 |
|:--:|:--:|:------------------------------------------:|:--:|:--:|
| V-001 | 상 | srst 해제 직후 init 처리 후 ready가 1로 남아 입력 데이터 유실 | `rx_ctrl.v:97` | [보기](#v-001) |
```
- Use only these five columns. No classification code or confidence columns.
- Order by number (the result file already numbers them 상 → 중 → 하).
- If a title wraps onto two lines in the table (more than 45 Korean characters), shorten it while keeping the symptom words.
- "보기" is a link to that issue's details.
- If there are 0 issues, write "발견된 이슈 없음" instead of the table.

### 3.4 Details (상세)
Under `## 상세`, write each issue with a `###` heading, continuously. No page breaks between issues.

````markdown
### V-001 srst 해제 직후 init 처리 후 ready가 1로 남아 입력 데이터 유실 {#v-001}

| 심각도 | 관련 신호 |
|:--:|------------------------------------------|
| 상 | `srst`, `init`, `state`, `ready` |

#### 심각도 근거

상-2: …

#### 요약

…

#### 발생 가능한 문제

…

#### 문제 설명

…

#### 신호 흐름

init → state → ready → 출력 ready

#### 발생 조건

…

#### 사이클 표

```
cycle | 0 | 1 | 2 |
...
```

- cycle 1: …

#### 수정 제안

```diff
-  ...
+  ...
```

수정 후: …
````

- The anchor `{#v-001}` must match the summary table's `[보기](#v-001)` (lowercase).
- Each item gets a `####` heading with its content as a new paragraph below. Items appear spaced apart in the PDF.
- The top table is `심각도 | 관련 신호`. Copy the main related signals from the result file into the 관련 신호 cell as is.
- **No code locations (`file:line`) in details.** Locations are only in the summary table. The body uses signal names only.
- Do not show confidence.
- Copy "심각도 근거" from the result file as is, condition number and sentence (e.g., `상-2: …`). The meaning of condition numbers is in the appendix.
- Leave out items not in the result file; never create empty items.
- An issue may have both "사이클 표" and "근거". Copy both, in the result file's order, together with the per-cycle reading lines under the cycle table, the label line above each diff block, and the "수정 후" line below the diff. Do not rewrite the prose of the result file.

### 3.5 Coverage (점검 커버리지)
Under `## 점검 커버리지`, copy the result file's two tables (module × M1–M15, inter-module × X1–X4) as is.
- Issue cells are links to details, like `[V-001](#v-001)`. `-` means not applicable, `OK` means checked with no issue.
- If the result file has no such section (made under older rules), leave it out of the report too.

### 3.6 Black-box items (블랙박스 확인 사항)
Under `## 블랙박스 확인 사항`, copy the result file's table. Link related issues like `[V-002](#v-002)`. If there are no black boxes, leave out this section (the overview's 블랙박스 cell says "없음").

### 3.7 Appendix (부록: 점검 ID와 심각도 기준)
At the very end of the report, add `## 부록: 점검 ID와 심각도 기준`. Copy its content **as is** from the appendix of `assets/report_template.md` (do not change it based on the analysis result).
- Check ID table: names of M1–M15, X1–X4
- Severity condition table: 상-1–3, 중-1–7, 하-1–5 (same content as `verilog-review` section 7 "심각도 판정 절차")

---

## 4. Writing principles

- **Faithful to the source**: do not change numbers, judgments, severities, titles, or locations from the result file (shortening an overly long title is the only exception). Draw no new conclusions in the report.
- **Compact**: do not say the same thing twice. Issue descriptions go only as far as needed to understand the situation before opening the code.
- **Wording**: do not overuse "~일 수 있다". Only when the outcome depends on a condition, state that condition clearly.
- No internal working expressions (tool run logs, etc.).

### Markdown rules (directly tied to the PDF look)
- Never use `\newpage`. The conversion script automatically prevents a heading from being left alone at the bottom of a page.
- On conversion, tables become **grid tables spanning the full text width**. Short columns (NO, 심각도, 위치, etc.) fit their content; the remaining columns share the rest.
- Alignment is set with `:` in the separator line: center `:--:`, left `---`.
- For a column that should be wide, write a long run of `-` in the separator (the summary table's 내용 column, the black-box table's condition column).
- No line breaks inside table cells.
- Cycle tables and diffs must be in code blocks (```). Max 90 characters per line.
- Fix proposals go in a ```` ```diff ```` code block. In the PDF, `-` lines (code before) are red text on a light red background, `+` lines (proposed code) green text on a light green background, other lines on a gray background (`assets/code-block.lua`).
- All code blocks (cycle tables, text tables, diffs) are drawn on a character grid: ASCII and spaces are 1 cell, Korean characters 2 cells. So text tables inside code blocks align exactly in the PDF if you **count one Korean character as two ASCII characters wide**.

---

## 5. PDF generation

**Keep the number of calls small.** Every tool call re-reads the whole conversation (about 150K tokens after an analysis), which costs far more than any single step here. The normal flow is exactly three calls after the skill is loaded: **(A) one Bash call** that writes the report, converts, checks, and opens the folder → **(B) Read page 1 of the PDF** → **(C) the final report** (section 6). Do not look at the template, the result file, or the report before (A); everything needed is in the command below.

1. **(A) Write, convert, check, and open in one Bash call.** The result file already has the report structure (`verilog-review` section 7 uses `assets/report_template.md` as its format), so the report `.md` is the result file with the title line replaced and the appendix (3.7) appended. Fill in `<top>`, `<TOP>` (top name in upper case), and `<date tag>`, and run as is:
   ```bash
   s=.claude/skills/verilog-report; r=reports/pdf/<top>_report_<date tag>
   mkdir -p reports/pdf && { echo "# <TOP> RTL Analysis Report"; tail -n +2 reports/<top>_review_<date tag>.md; echo; sed -n '/^## 부록/,$p' $s/assets/report_template.md; } > $r.md
   bash $s/scripts/build_pdf.sh $r.md; e=$?; echo "build exit=$e"
   if [ $e = 0 ]; then py=$(command -v python || command -v python3); "$py" $s/scripts/check_pdf.py $r.md $r.pdf; bash $s/scripts/open_folder.sh $r.pdf; fi
   ```
   - `build_pdf.sh` makes a `.pdf` with the same name: body 9pt, margins 12mm, title box, grid tables, section/issue/item heading styles, design-structure figure.
   - **Fonts: the bundled fonts in `assets/fonts/` are used directly by path.** The output looks the same on any PC, and no font installation is needed.
     | Use | Font | License |
     |------|------|------|
     | Body Korean | Pretendard (88% horizontal compression) | OFL |
     | Body Latin | Roboto Condensed | Apache 2.0 |
     | Code blocks (Latin and Korean) | D2Coding (Korean exactly 2 Latin cells) | OFL |
   - If bundled font files are missing, it picks similar fonts installed on the PC and prints a warning (Korean: narrow fonts → Pretendard/Spoqa/Noto etc. compressed to 88%; Latin: condensed fonts; code: D2Coding → Consolas etc.). The look may then differ slightly between PCs.
   - Do not delete or rename the font files and license files (`OFL-*.txt`, `LICENSE-*.txt`) in `assets/fonts/`.
   - `check_pdf.py` checks the PDF **with text, not page images**. It prints only the page count and problems, ending with `점검 결과: 문제 없음` or `점검 결과: 문제 n건`:
     - blank or nearly empty pages in the middle
     - broken characters
     - summary-table rows that do not come out on one line (title or 위치 wrapped → shorten the title)
     - code-block lines (cycle tables, diffs) wider than the page (cut off on the right → shorten or split the line)
     - "보기" links without a matching `{#v-…}` heading
   - `open_folder.sh` opens `reports/pdf` with the new PDF selected (Windows Explorer, macOS Finder; Linux opens the folder only). If it prints `폴더 열기 생략` or fails, just go on; its result never changes the flow.
2. **Handling by `build exit`**:
   - `0`: PDF created; go to step 3.
   - `2` (tools missing), `3` (no Korean font): **ask the user** following 5.1.
   - Other errors (LaTeX errors, etc.): if the error message shows something fixable in the Markdown, fix it and run the `build_pdf.sh` and `check_pdf.py` lines again in one call; if it still fails, finalize the `.md` as the report and tell the user the error.
3. **(B) Read only page 1 of the PDF** (`pages: "1"`) to check the title box, overview table, Korean/Latin spacing, and the design-structure figure (half a page or less, box names readable). Read page 2 too, in the same Read, only if the figure continues there. **Do not Read any other page.**
   - If `check_pdf.py` reported problems, fix the `.md` (only the lines it named) and run the `build_pdf.sh` and `check_pdf.py` lines again **in one Bash call**. Do not run `open_folder.sh` again (the open folder shows the rebuilt file). Read a page image again only when the fix changed page 1 or the figure, or when a problem's cause cannot be found from the script output (then only that page).
   - If it printed `pdftotext 없음`, do not install anything: Read pages 1–3 instead and check what is visible there.
   - If there are no problems, go straight to the final report (section 6) in the next response; do not make other calls.
4. If `.md` editing is needed, keep it to the problem lines: the report body must stay faithful to the result file (section 4).
5. On Windows, run with Git Bash. The `폰트: … — 번들 글꼴(assets/fonts)` line in the conversion log shows whether the bundled fonts were used.

### 5.1 When the environment cannot make a PDF
If tools or Korean fonts are missing and a PDF cannot be made, with the `.md` report already written, **ask the user once** (in Korean) and proceed by the answer. Never install without asking.

Question (send in Korean as is):
> PDF 변환에 필요한 <부족한 항목: 스크립트 출력 그대로>이(가) 없습니다.
> 1. 필요한 도구를 설치하고 PDF를 만들기 (예상: 설치 수백 MB, 첫 변환 2~3분)
> 2. 설치하지 않고 Markdown 보고서(`<md 경로>`)로 마치기

- **If 2 is chosen**: finalize the `.md` as the report and go to the final report (section 6).
- **If 1 is chosen**: install only what is missing with the commands in the table below, then run the step-1 command again from the `bash $s/scripts/build_pdf.sh` line (with the `s=` and `r=` line), in one Bash call.
  - If an install command fails or lacks permission, stop trying and finalize the `.md` as the report, with the error.
  - If after installation `command -v` still cannot find it (PATH not updated), the script looks in known install paths automatically. If that still fails, tell the user to restart Claude Code in a new terminal.
- If 2 was already chosen in the same session, do not ask again; produce the `.md`.

| Environment | pandoc | xelatex | Korean font |
|------|--------|---------|-----------|
| Windows | `winget install --id JohnMacFarlane.Pandoc --exact --scope user --silent --accept-package-agreements --accept-source-agreements` | `winget install --id MiKTeX.MiKTeX --exact --scope user --silent --accept-package-agreements --accept-source-agreements` then `initexmf --set-config-value="[MPM]AutoInstall=1"` | not needed (bundled fonts) |
| macOS | `brew install pandoc` | `brew install --cask basictex` then `sudo tlmgr install xetexko fvextra titlesec colortbl extsizes newunicodechar pgf` | not needed (bundled fonts) |
| Ubuntu/Debian | `sudo apt-get install -y pandoc` | `sudo apt-get install -y texlive-xetex texlive-lang-korean texlive-latex-extra texlive-pictures` | not needed (bundled fonts) |

- MiKTeX's `AutoInstall=1` makes it download needed LaTeX packages during conversion, so the first conversion takes a while.
- If Claude cannot run a command that needs `sudo`, ask the user to run it themselves with `! <command>`.

---

## 6. Final report

Tell the user only the following, briefly, in Korean.
- path of the generated PDF (if no PDF could be made, the `.md` path and the reason), and `보고서 폴더를 열었습니다.` if `open_folder.sh` printed `폴더 열기:`
- count per severity and titles of severity "상" issues

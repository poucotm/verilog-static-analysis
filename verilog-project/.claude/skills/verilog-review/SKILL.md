---
name: verilog-review
description: Statically analyzes Verilog/SystemVerilog RTL by reading code only (no tools) to find latent problems that are visible only by following relationships between signals and signal flow across cycles. Proves output corruption, hangs/deadlocks, wrong FSM states, lost/duplicated events, reset/initialization-dependent misbehavior, buffer overflow from late backpressure, reordered or miscounted data, arithmetic overflow/truncation, unsafe clock gating, and unoptimized structure (area, latency/throughput such as idle cycles and serialization, and power such as registers missing a load enable) with cycle tables, and reports them with V-001 numbers, 상/중/하 severity, and short symptom-oriented titles. Does not cover lint-level issues or simple missing signals, and never runs simulators, lint, or synthesis tools. Always analyzes the whole design from the session's source folder and top; modules without a definition are black boxes, and modules inside a graybox folder are grayboxes used only for flow analysis. All user-facing responses and output files are in Korean. Always use this skill when the user mentions Verilog code review, bug hunting, latent problems, signal flow, hangs, wrong states, optimization, power, clock gating, CDC, re-analysis, or Korean requests such as 코드 리뷰, 버그 찾기, 잠재 문제, 신호 흐름, 멈춤, 최적화, 전력, 클럭 게이팅, 분석을 시작해줘, 재분석, "다시 봐줘".
---

# Verilog Static Signal-Flow Analysis

## Language

- **Everything the user sees is written in Korean**: every response, the pre-check questions (3.0), the final report (3.6), and the whole result file (section 7).
- Korean text shown in this skill inside backticks, code blocks, quote blocks, or example tables is an **exact literal**. Copy it as is; do not translate it. This includes the result-file headings (`## 분석 개요`, `## 설계 구조`, `## 요약`, `## 상세`, `## 점검 커버리지`, `## 블랙박스 확인 사항`), the overview item names, the `####` item names, severity words (상/중/하), condition numbers (`상-1` …), and fixed phrases such as `(측정 중)`, `측정 불가`, `(사용자 지정)`, `확인함, 문제 없음`, `발견된 이슈 없음`, `보기`.
- The `verilog-report` skill and `session_usage.py` find table rows and headings by these Korean names, so a translated name breaks the PDF and the measurement step.

## 0. Goal

Find, **by reading code only**, problems that pass lint and rarely show up in simulation.
Follow not a single signal but the **relationships between signals** and the **paths that flow across cycles**, to find defects and inefficiencies that appear only when specific conditions coincide.

### Problems to find
| Problem | Examples |
|------|----|
| Output corruption | data corruption, misaligned values, wrong order (reordering across transactions), wrong arithmetic result (overflow, truncation, sign handling), wrong flag, leftover values from the previous transaction mixed into the next, wrong beat count / `tlast` position |
| Hang / deadlock | waiting for an event that never comes, mutual wait, ready/valid deadlock, counter never reaches its target, a gated clock that can never be turned on again |
| Wrong state | unintended transition, undefined encoding, state out of sync with another FSM/counter, no way back |
| Lost / duplicated events | missed pulse, level re-triggers, request handled twice, request without response, CDC loss, buffer overflow because backpressure arrives too late |
| Reset/init-dependent misbehavior | spurious event right after reset, unreset value mixed into control, inconsistency after partial reset |
| Not optimized | latency/throughput loss from idle cycles, serialization, or missing pipelining; duplicated logic/registers; logic with no effect on results; wider-than-needed bit widths; long combinational paths; power wasted by registers, operators, or memories that toggle while their result is unused |

This classification is only a viewpoint for analysis. Do not write a classification code or column in the result file. Instead, **describe the symptom in words in the title and in "발생 가능한 문제".**

**Out of scope** (do not raise as issues)
- Lint level: syntax, style, naming, sensitivity list, mixed blocking/non-blocking, bit-width warnings by themselves (a value that really exceeds its width for a reachable input is in scope: 4.14)
- Simple missing signals: unused signals, unconnected ports, declared-only signals. Raise them only if they combine with other signals into a scenario leading to one of the problems above, or if they waste resources even after synthesis. An unused enable/valid-like signal is a clue that a condition was forgotten where it should have been used (4.9 C "Missing register enable"): follow it before dismissing it.

---

## 1. Principles

- **No tools**: do not run simulators, lint, synthesis, or formal tools. Do not create testbench or assertion files. Only read and search files.
- **Static proof**: evidence is code and cycle tables. A cycle table is the default evidence for every issue, optimization issues included; only an issue with nothing happening over time (duplicated logic, excess width, depth of a combinational path) uses a value or structure table instead (section 6). For area/timing optimization issues, give structural evidence (duplicate locations, value-range calculation, number of operations on the path); for cycle optimization, give a current vs. improved cycle comparison and the added cost; for power, give the width involved and the share of cycles in which the load or toggling is unneeded.
- **Think in relationships**: not "this signal is wrong" but "the relationship that A and B must hold breaks under this condition".
- **Trace back from the symptom**: fix the symptom first, then work backward to the inputs and conditions needed to produce it. Check that those conditions are actually **reachable**.
- **Raise only what you can prove**: if you cannot show a reachable path or structural evidence, do not raise it.
  - If it may not be a problem depending on design intent, say so in one sentence in "문제 설명".
  - If it depends on the spec, a black box, or external input conditions, state in "문제 설명" under which condition it becomes a problem, and also put black-box conditions in "블랙박스 확인 사항".
  - Do not show a separate confidence level.
- **External input assumption**: unless the spec (`docs/`) constrains them, assume top inputs may arrive in any order and timing allowed by the protocol. If the spec constrains them, follow the constraint.
- Do not assume design intent. Read the specs in `docs/` and the code comments first.
  - Files under `docs/example/` are writing examples, so **never read them** (do not open them even if they show up in Glob/Grep results).
  - The `<!-- 작성 안내 … -->` comment in a spec file is a writing guide for people. Do not use it as analysis evidence and do not count it in the constraint/request counts. Everything outside the comment is used as spec.
  - Behavior listed under the spec's "의도된 동작" (intended behavior) is not raised as an issue by itself. Other problems caused by that behavior are raised.
  - If spec items have IDs (constraint `C1`, intended behavior `I1`, analysis request `R1`, etc.), cite the ID in the issue's 문제 설명 / 심각도 근거 and in the user report (e.g., "스펙 C2에 따라 중간 beat의 부분 wkeep은 가정하지 않음").
  - If the spec has "성능 목표" (performance targets), use them as the baseline for optimization (4.9) judgments.
  - If the spec has "전력 목표" (power targets) or says whether the synthesis tool inserts clock gating automatically, use that as the baseline for power (4.9 C) judgments.
  - Never skip the spec's **"분석 요청 사항"** (analysis requests; the same applies if the heading is "요청 사항" or "추가 요청 사항"). Check them (the check order stays as in 3.3). Report each request on one line in the 3.6 user report: the V-number if an issue came out, otherwise "확인함, 문제 없음" with a one-line reason.
- **Read only**: never modify RTL. Show fixes only as diffs in the result file, complete enough to apply as they are (section 7 "Fix proposal").
- **Analysis scope**: analyze only Verilog files under the session's source folder. Modules unreachable from top are not analyzed; only list them as "top 미사용 모듈".
- **The source folder defaults to `source`.** If the user does not name a source folder, use `source` and show it in the 3.0 pre-check as `소스 폴더: source (기본값)`. If `source` does not exist, do not analyze; ask for the source folder.
- If top is not set, do not start; send the session-start guide from CLAUDE.md.

---

## 2. Result File

- Create **exactly one** analysis result file: **`reports/<top>_review_<YYYYMMDD>.md`** (`<top>` is the top module name, the date is the analysis date).
- If a file with the same name exists for the same day, append `_2`, `_3`. Never overwrite an existing file.
- Do not save working notes such as relationship or flow tables as separate files.
- Do not consult previous result files. Analyze everything from the current code every time.
- Follow the format in section 7. The format is designed so that `verilog-report` can turn it into a PDF as is.

---

## 3. Procedure

### 3.0 Pre-check (before analysis, mandatory)
Once top is set (and the source folder, `source` by default), ask the two questions below **separately and in order** **before the actual analysis**. Never put both questions in one message. **Do not start the analysis until the user confirms the composition is correct.** Record the start time (step 0 of 3.1) only after both answers are in: 소요시간 counts only the actual analysis, not the pre-check scan or the time spent waiting for answers.

**(1) Quick composition scan** — do not read logic; only skim module definitions and instances.
1. Glob the `*.v` `*.sv` `*.vh` `*.svh` files under the source folder.
2. Grep for `module <name>` definitions and build a module → file table. Mark modules in files inside a `graybox` folder as grayboxes (section 5.5).
3. In each module, find instance statements (`<module> [#(...)] <instance> (`) and, following from top, collect the modules in use. Keywords (`if`, `assign`, `always`, etc.) and function/task calls are not instances. Read short snippets only for ambiguous lines.
4. Classify:
   - **분석** (analyzed): reachable from top, defined outside graybox
   - **그레이박스** (graybox): reachable from top, defined inside a graybox folder
   - **블랙박스** (black box): instantiated but with no definition in the source folder (vendor/IP vs. 미제공, section 5)
   - **미사용** (unused): defined but unreachable from top (not analyzed)
   - **확인 필요** (needs confirmation): duplicate definitions with the same name, `` `include `` files missing from the source folder, lines where it is unclear whether they are instances
5. **Check reference specs**: list files under `docs/` (exclude `docs/example/` and never open it). Read spec files (`.md` `.txt` `.pdf`, etc.) and count:
   - the number of spec/interface constraint items and analysis request items
   - if a signal or module name in the spec is not in the code (different name, or unclear which port it means), put it under **확인 필요**.
   - If `docs/` is missing or empty, write "참고 스펙: 없음". With no spec, assume every input order/timing the protocol allows (section 1).

Message format (sent in Korean exactly like this; drop rows for categories that do not apply, and drop the 미사용 / 확인 필요 lines if there are none. Always write the 참고 스펙 line):
```
분석 구성 확인 — top: <top>, 소스 폴더: <경로>   ← 기본값이면 "source (기본값)"

| 구분 | 모듈 | 파일 | 인스턴스 위치 |
|------|------|------|------|
| 분석 | rx_top | rx_top.v | (top) |
| 분석 | rx_ctrl | rx_ctrl.v | rx_top.u_ctrl |
| 그레이박스 | win_func | graybox/win_func.v | rx_top.u_win |
| 블랙박스 | fifo_core (미제공) | 정의 없음 | rx_top.u_fifo |

- 분석 n개 모듈 / n개 파일, 그레이박스 n개, 블랙박스 n개
- 미사용 (분석하지 않음): old_ctrl (old_ctrl.v)
- 참고 스펙: docs/analysis-spec.md (제약 4개, 의도된 동작 1개, 분석 요청 2개)   ← 없으면 "없음 (모든 입력 타이밍 가정)"
- 확인 필요: …   (예: 스펙의 `tready`가 s_axis_tready / m_axis_tready 중 어느 것인지 모호)
```
- If a module is instantiated in several places, join the instance locations with `,` (if many, `외 n곳`).
- If there are many modules (more than 30), group analyzed modules per file into one row, but list every graybox, black box, unused, and needs-confirmation item.

**Question (1)** — under the table above, ask only this and wait for the answer. Do not include the PDF question.
> 위 구성이 맞나요? 맞으면 다음으로 넘어갑니다.

**Handling the answer to (1)**
- **Never skip the composition check.** Even if the request already says whether to make a PDF (e.g., "PDF까지 만들어줘"), the composition must be confirmed.
- "맞아", "네", "ㅇㅇ", "OK" mean the composition is correct. Then go to (2). If (2) is not asked (the request already states the report choice), start the analysis right away.
- If the user says the composition is wrong, fix it, show the table again, and get confirmation again.
  - Claude does not move files inside the source folder (CLAUDE.md general principles). If the user moves or adds files and asks to check again, rescan from the start. The same applies when specs in `docs/` are changed or added.
  - If the user says something like "이번 분석에서는 X를 그레이박스로 봐줘", follow it and append `(사용자 지정)` to the 그레이박스 cell of the result file's overview.
- If there are 확인 필요 items, do not analyze until the user decides (e.g., which of the duplicate definitions to use).
- Run the composition check on every re-analysis (files may have changed).

**(2) PDF report choice** — after the user confirms the composition, ask this **in a separate message** and wait for the answer.
> 분석을 마친 뒤 PDF 보고서(`/verilog-report`)까지 한 번에 만들까요?
> 1. 분석 + PDF 보고서
> 2. 분석만 (보고서는 나중에 요청)

**Handling the answer to (2)**
- If the request already states the report choice (e.g., "PDF까지 만들어줘", "분석만 해줘"), do not ask (2); just follow it.
- "1", "네", "ㅇㅇ", "OK", "PDF까지" mean analysis + PDF; "2", "아니요", "분석만" mean analysis only. Start the analysis as soon as you get the answer.
- Remember the choice as a working note for 3.6. On re-analysis in the same session, do not ask again unless the user changes it.

**After confirmation**
- Use the confirmed composition as is in steps 1–2 of 3.1. If you find something during analysis that differs from the confirmed composition (a missed instance, etc.), analyze according to the actual code and state what differed, separately, in the 3.6 user report.

### 3.1 Understand the structure
0. **Record the analysis start time.** Before reading source files, run `date -u +%Y-%m-%dT%H:%M:%SZ` and keep the output as a working note. It is used in 3.6 to compute 분석시간, 소요시간, and 토큰 사용량. Run it in the first response after the user's last answer in 3.0, never during the pre-check.
1. Build the module hierarchy by following instances from top. Start from the composition confirmed in 3.0. (This becomes the `hier` block in section 7 "설계 구조".)
2. Identify black boxes (section 5) and grayboxes (section 5.5). Use the classification confirmed in 3.0.
3. Summarize clock domains and reset structure (sync/async, release order, soft reset/flush).
4. Find every FSM (explicit state registers, and implicit states built from flag/counter combinations).
5. **Understand the block function.** Centered on top, summarize the following. This becomes the 블록 기능 cell of section 7 "분석 개요".
   - top's input/output interfaces (what it receives, what it sends out)
   - main data flow (input → processing → output)
   - roles of the main sub-blocks

### 3.2 Build the relationship model (working notes, not saved)

**(1) Register update table** — for **every** register. Control registers (state, counter, flag, valid) get one row each. Data registers may be grouped into one row per pipeline stage or bus when they share the same update condition, but **none may be left out**.
| Register | Update conditions and priority | Load enable | Signals that decide the value | Reset value | Readers |
- **Load enable**: the condition guarding the assignment, whatever its name. Write `매 클럭` if the register is assigned unconditionally. Every `매 클럭` row must be judged in M13 (4.9 C "Missing register enable"); do not fill the M13 cell before every such row has been judged.
- **Readers**: a register with no reader, especially a delayed enable/valid, is a clue (section 0, 4.9 C).
- Use this table to check whether the conditions updating the same register overlap or leave combinations uncovered.

**(2) Event flow table** — for each control signal (valid, ready, req, ack, start, done, irq, flush, error, etc.)
| Event | Generation condition | Nature (pulse/level/sticky) | Latency | Consumption condition | How it is cleared on consumption |
- Check whether producer and consumer assume the same nature, and whether an event can be generated when the consumer cannot accept it.

**(3) Invariant list** — extract from code and spec the **relationships between signals that must always hold** for the design to be correct.
- Examples: `count == wr_ptr - rd_ptr`; if `out_valid` is 1 then `out_data` belongs to the same transaction; `state==IDLE` implies `busy==0`; `grant` is one-hot; if `FSM_A==WAIT` then `FSM_B` eventually raises `done`
- For each invariant, use the techniques in section 4 to ask "is there an input sequence that breaks it?". A breaking path is an issue candidate.

**(4) Operation list** — for **every** `function`, every `for` loop that builds logic, and every arithmetic or wide operator (`+`, `-`, `*`, shift by a variable, compare of 8 bits or more, variable index / part-select, priority chain of 4 or more `if-else if`)
| Operation | Inputs and width | Serial depth within one cycle | From (register / input port) → to (register / output port) | Where the result is used |
- **Serial depth**: count the operations a value passes through in series between two registers (or port to register). For a loop, depth = iterations × depth of one iteration when each iteration uses the result of the previous one (e.g., a running count that selects the write position). Use the default parameter values and also say how the depth grows with the parameter.
- None may be left out; operations of the same kind in a `generate`/loop may share one row.
- This list is the input to M9 (4.9 B) and M15 (4.14). Do not fill the M9 cell before every row has been judged for timing and compared with the other rows for duplication.

### 3.3 Check checklist (fixed order)
To cover the same scope in the same order every session, follow the order below **exactly**. Do not skip or reorder.

**(1) Module order**
- Go through modules one by one in `hier` block order (depth-first from top, in the order instances appear in the source). Even if a module has several instances, check the module only once.
- Graybox modules get no in-module checks (M1–M15). Black boxes have no definition, so naturally none either. Both are handled only by X4 of the inter-module checks.

**(2) In-module checks** — apply M1 through M15 in order to every module.

| ID | Check | Technique |
|:--:|------|:--:|
| M1 | Reset/init: unreset registers used for control, the first cycles after reset release, reset release order between modules | 4.8 |
| M2 | FSM: transition table, overlapping/missing conditions, default, reachability, recovery | 4.1, 4.2 |
| M3 | Wait points: is the exit event guaranteed to come? | 4.4 |
| M4 | Condition combinations/priority: overlaps and gaps among conditions updating the same register | 4.1 |
| M5 | Counters/pointers: boundaries, skipped compare values, paired counters | 4.6 |
| M6 | Data-control alignment: number of stages data / valid / sideband pass through | 4.5 |
| M7 | Event lifetime within one clock domain: pulse/level nature, loss/duplication | 4.7 |
| M8 | Optimization — cycles (latency/throughput) | 4.9 A |
| M9 | Optimization — area/timing | 4.9 B |
| M10 | Capacity/backpressure margin: is the remaining buffer space always enough for what still arrives before the stop signal takes effect? | 4.10 |
| M11 | Leftover state between transactions: does every transaction (after done, abort, error, flush, soft reset) start from the initial state? | 4.11 |
| M12 | Order/count conservation: output order = input order, output count = input count, one `last` per frame | 4.12 |
| M13 | Optimization — power: registers missing a load enable (not clock-gatable), toggling while the result is unused, activity while idle, memory enables, clock-gating opportunities and gating-friendly coding | 4.9 C |
| M14 | Clock-gating safety: wake-up condition, open/close timing, reset under gating, manual gating structure | 4.13 |
| M15 | Arithmetic value range: overflow of accumulators/sums/products, truncation on width change, signed/unsigned mixing, saturation boundaries | 4.14 |

**(3) Inter-module checks** — after finishing in-module checks for all modules, apply these from top in instance connection order. Each row is one module that has sub-instances (including top).

| ID | Check | Technique |
|:--:|------|:--:|
| X1 | Interface assumptions: does the parent honor the input conditions the child expects, and do both assume the same output latency/nature? Is the same configuration value used with the same value everywhere within one transaction? | 4.3 |
| X2 | Coupled-FSM deadlock: product states of FSM pairs exchanging signals | 4.3 |
| X3 | Clock domain crossings (CDC) | 4.7 |
| X4 | Black box / graybox boundaries | 5, 5.5 |

**Which cell an issue goes in** — each problem has one owning check. Record it only there; the other cells stay `OK`.

| Problem | Owner |
|------|:--:|
| Clock domain crossing of any kind | X3 |
| Values left over after done / abort / flush / soft reset, inside one module | M11 |
| Only one of two modules reset/aborted, the other left mid-transaction | X2 |
| Unreachable FSM state | M2 |
| A wait whose exit event never comes (one side waits) | M3 |
| Two FSMs waiting for each other | X2 |
| A gated clock that is never turned on again | M14 |
| Data, valid, sideband of one item out of step | M6 |
| Buffer runs out of space | M10 |
| Stream data item lost, duplicated, or reordered | M12 |
| Control event (start, done, req, ack, irq) lost or handled twice | M7 |
| Counter/pointer/credit count or full/empty flag update inconsistency, including increment and decrement in the same cycle | M5 |
| Sticky flag set and clear in the same cycle | M7 |
| Any other register with two update conditions true at once | M4 |
| Computed value (sum, product, difference, scaled value) exceeding its width | M15 |
| Logic whose result is never used | M9 |
| Missing load enable, activity in cycles where the result is not used | M13 |
| Configuration value changing midway | X1 |
| Reset release order between modules | M1 of the module that receives the signal |

**(4) Cell results** — after each check, record the result in the coverage table in your working notes. Each cell is one of three values.
- `-` : not applicable (e.g., M2 for a module without an FSM, M3 for a module with no wait point, M10 for a module without a buffer or backpressure, M11/M12 for a module that holds no per-transaction state / passes no stream of items, M13 for a purely combinational module, M14 for a module with no gated clock or clock enable, M15 for a module with no arithmetic, X2 for a module with only one child FSM)
- `OK` : checked, no issue
- `V-00n` : issue number (if a cell yields several issues, list them all like `V-001, V-004`)

Numbers are assigned in 3.5, so during checks use temporary names (e.g., `ctrl-M2-a`) and replace them with numbers after 3.5.
**Do not write the result file until every cell is filled.**

**(5) Questions to ask within each check** — for each check ID, ask the questions for the relevant problem and decide "a path exists / does not exist (with evidence)".

| Problem | Questions |
|------|------|
| Output corruption | Through which register/mux path does each output bit come? Are select and data based on the same cycle? Is any condition that changes the output unintended? |
| Hang / deadlock | At every wait point (wait state, counter wait, ready wait), is the exit event **guaranteed** to come? Could it have already passed before the wait, or be consumed/masked elsewhere? |
| Wrong state | For every state × transition-condition combination, is the next state as intended? What if two conditions are true at once? Does an undefined encoding recover? Can it fall out of sync with a related FSM/counter? |
| Lost/duplicated events | Is every event consumed exactly once each time it is generated? What if it arrives while the consumer is busy? Back to back? Across clock domains? |
| Reset dependence | For the first few cycles after reset release, are all control signals valid? Does a module released from reset earlier send signals to one still in reset? |
| Capacity | After the stop signal (ready low, almost_full) is raised, how many more items still arrive, and is there always room for them? |
| Leftover state | When a transaction ends (normally, by abort, error, flush, or soft reset), which registers keep their value, and does the next transaction read them before overwriting them? After a partial clear, are all related registers consistent? |
| Order/count | Can a later item overtake an earlier one on any path? Does the number of items going out equal the number that came in, with exactly one `last` per frame? |
| Config consistency | Is every use of a configuration value within one transaction based on the same sampled value? What if it changes midway? |
| Power | Which registers are assigned every clock with no enable although their input can change only after an enable/valid? Is there a delayed enable that nothing uses? Which registers, operator inputs, and memory enables change in cycles where their result is not used? What keeps running while the block is idle or disabled? Can one enable stop them? |
| Clock gating | Can the gate enable be produced while the gated clock is off? Is the clock open before the first data and until the last data has left? Are gated registers reset? |
| Arithmetic range | What are the largest and smallest values each computed result can take for reachable inputs, and does the register holding it have enough bits? Which bits are dropped on truncation, and can they be nonzero? Are signed and unsigned values mixed in one expression? |
| Optimization | How many cycles does one transaction take, and every how many cycles can the next input be accepted? Are there cycles that do nothing, or processing done sequentially that could overlap? Is the same value computed or stored twice? Is there logic that does not affect results? Are bit widths wider than the actual value range? Is a long operation path packed into one cycle? |

### 3.4 Proof
- For each functional candidate, build a reachable path as a cycle table from reset or from a normal state (section 6). For an arithmetic-range candidate (M15) that shows within one cycle, concrete input values and the resulting wrong value may replace the cycle table.
- For optimization candidates, also show a cycle table whenever the waste shows over time (idle cycles, loads or toggling in unneeded cycles, a condition that is never true in the cycle it is tested); otherwise write structural evidence as a value or structure table. For cycle candidates, write the current vs. improved cycle comparison and the added cost (4.9 A). For power candidates, write the width involved and the share of cycles in which the load or toggling is unneeded (4.9 C).
- If the path or evidence does not hold, drop the candidate. Do not record why it was dropped. That cell becomes `OK`.
- For each proven issue, decide severity and the condition number (e.g., `상-2`) with section 7 "심각도 판정 절차" (severity procedure).

### 3.5 Numbering and ordering
1. Sort by severity (상 → 중 → 하). Within the same severity, put the most solidly proven first.
2. Number them `V-001`, `V-002`, … (3 digits) in that order.
3. Replace temporary names in the coverage table with numbers. If any cell is still empty, finish that check.

### 3.6 Wrap-up
1. Before writing, reread each issue's prose as a reader who has not seen the code, and rewrite what breaks the section 7 "Writing style" rules. Also check each "수정 제안" against the section 7 "Fix proposal" rules: can the code be fixed from the diff alone? Then write `reports/<top>_review_<YYYYMMDD>.md` (section 7 format). Leave the six overview cells **분석 소스, 분석시간, 사용모델, 노력, 소요시간, 토큰 사용량** as `(측정 중)`.
2. **After the result file is fully written, as the very last tool call**, run the measurement script to fill the six cells. Use the session's source folder and the time recorded in step 0 of 3.1.
   ```bash
   python .claude/skills/verilog-review/scripts/session_usage.py --src <소스 폴더> --since <분석 시작 시각> --fill reports/<top>_review_<YYYYMMDD>.md
   ```
   - The script rewrites the six cells in the result file itself. Claude does not copy values by hand. It is done when the last output line is `채움: …`.
   - **Always run it after writing the result file.** Claude Code writes a response to the log only after that response's tool calls finish. If you run it inside the analyzing response, that response's time and tokens are not yet in the log, so 소요시간 and tokens come out far too low.
   - 분석시간 is the analysis start time converted to this PC's local date/time; 소요시간 is from then until the script runs.
   - The script takes as the analysis start the later of `--since` and the time of the user's last typed message in the session log. So even if the start time was recorded too early, the pre-check and the wait for the user's answers are not counted. It also subtracts tool-approval waits: any tool call whose result came more than 2 seconds after the call is treated as waiting for approval, and that span is removed from 소요시간. Do not ask the user anything between the start and this script; a wait there would be counted.
   - 분석 소스 is the number of `.v` `.sv` `.vh` `.svh` files under the source folder and their total line count (blank lines and comments included). Files inside a graybox folder are excluded from the total and shown separately in parentheses.
   - Tokens are read from the session log (`~/.claude/projects/<project key>/*.jsonl`). Total tokens are the sum of input, output, cache read, and cache creation; most of it is cache read.
   - 사용모델 and 노력 (effort) are also read from the same session log, from responses after the analysis start (e.g., `Opus 5.5`, `medium`). If they changed during analysis, they are listed by usage, most first. Claude never guesses them.
   - If `python` is missing, try `python3` once more. If that also fails, replace the six cells with "측정 불가". Do not stop the analysis because measurement failed.
3. Finish according to the PDF answer from the 3.0 pre-check.
   - **1 (analysis + PDF)**: after the step-2 measurement, continue with the `verilog-report` skill procedure to make the PDF. Do not ask the user again. Report once at the end: count per severity, titles of severity "상" issues, result file and PDF paths (`verilog-report` section 6). If PDF tools are missing, ask as in `verilog-report` 5.1.
   - **2 (analysis only)**: report the count per severity, titles of severity "상" issues, and the result file path, and mention that a PDF report can be made with `verilog-report`.
   - Time and tokens spent on the report are not included in the overview values (measurement already finished in step 2). The measurement script is still **the last tool call of the analysis**; the report comes after it.
   - The user report is in Korean. It also includes the per-request results for the spec's 분석 요청 사항 (section 1) and any differences from the confirmed composition (3.0).

---

## 4. Analysis Techniques

### 4.1 Exhaustive condition combinations (wrong state, output corruption)
- List every condition that updates a register, and check the cases where **two or more are true at once** and where **none is true**.
- `if-else if` chains: is the result correct for input combinations where a later condition is shadowed by an earlier one? Can a later condition be shadowed forever and never served (starvation → hang)?
- `case`: are all state/select values handled? Does `default` go to a safe state? Does it rely on full_case/parallel_case directives?
- If related registers are updated separately in different `always` blocks, is there a condition where only one side updates?
- If one place uses a configuration value captured at start and another uses the live value, they disagree when the value changes midway (see 4.3; record the result in the X1 cell of the parent, or of the module itself if it is top).

### 4.2 FSM transition analysis (wrong state, hang)
- Build a transition table: current state × transition condition → next state. Find overlaps and gaps between conditions in the table.
- Reachability: can every state be reached from the reset state (unreachable states are optimization candidates)? Can every state return to a recovery state (if not, hang/wrong state)?
- Undefined encodings (e.g., only 5 states defined in a 3-bit state, two bits set in one-hot): no `default` handling, or staying put, means no recovery. If there is a real cause that can produce it (CDC, unreset register), it is "중" or higher.
- Check that the datapath (counters, data registers, FIFO pointers) holds the expected values in each state. Look for paths where the state changed but a counter keeps an old value.
- On abort/error/flush transitions, check here only that the FSM itself reaches the right state. The datapath and submodules left as they were while only the FSM returns is checked under M11 (4.11).

### 4.3 Coupled FSMs / inter-module interaction (hang, wrong state)
- For each FSM pair exchanging signals (sender ↔ receiver, master ↔ slave), consider the **product state**. If A can be in a state waiting for B's event while B is in a state waiting for A's event, it deadlocks.
- If only one side is reset/aborted, in which state does the other side remain?
- Does the parent honor, on every path, the input conditions the child assumes (no duplicate start, no request while busy, etc.)?
- **Configuration use-time consistency**: for each configuration value (length, mode, threshold, enable) used by more than one register, FSM, or module, list where each use takes it from — a copy captured at start, or the live value. If the uses differ, or all use the live value across several cycles of one transaction, find what breaks when it changes midway (counter end point vs. FSM length, parent and child disagreeing on mode). If the spec says the value is fixed during a transaction, do not raise it. If the spec is silent, raise it and state the condition "작업 중 설정값이 바뀔 수 있다면" in "문제 설명".

### 4.4 Wait-point analysis (hang)
For each wait point, check:
1. What does it wait for (exit condition)?
2. Who generates that event, and when (event flow table)?
3. Can the event arrive **before entering the wait** and already be gone (pulse arrives first → waits forever)?
4. Can the event be consumed or masked first by another path?
5. Does the event's producer depend on this wait state (circular dependency)?
6. Is there a timeout/abort exit path?

### 4.5 Data-control alignment (output corruption)
- Count, per path, the number of register stages that data, valid, and sideband (last, tag, id, byte enable) of the same transaction pass through. If the count differs on some path depending on bypass/stall/mux conditions, they are misaligned.
- Paths where a mux select changes one cycle earlier or later than the data.
- During stall/backpressure, data, valid, and sideband of the same item do not stop together (one advances while another holds), so they no longer match. Whole items lost or duplicated by a stall are checked under M12 (4.12); buffer overflow under M10 (4.10).
- Paths where only the output valid rises in a cycle where the output register is not updated.

### 4.6 Counter/pointer relationships (output corruption, hang)
- Relationship between a counter's range and its compare value: can the compare target (`==`) be skipped (step not 1, loaded midway)? → never terminates.
- With increment and decrement in the same cycle, or simultaneous read/write, are the counter and flags (full/empty/almost) updated consistently?
- Max + 1, wrap-around; does a compare value exceed the width if parameters change?
- On which path do counter pairs that must correspond (sent count ↔ received count, pointer ↔ count) diverge?

### 4.7 Event lifetime (lost/duplicated events)
- Find pulse producer ↔ level consumer combinations, or the reverse.
- If an event arrives while the consumer is busy, is it buffered, overwritten, or ignored?
- If the same event is consumed in two places, cases where only one side handles it.
- If a sticky flag's clear condition comes in the same cycle as its set condition, which wins?
- Events crossing clock domains (**checked and recorded under X3 only, not M7**): 1-bit pulse passed through a 2-FF (lost going from fast to slow clock), multi-bit value through per-bit 2-FFs (skew), synchronized and unsynchronized related signals used together (reconvergence), the same signal synchronized separately in several places.

### 4.8 Reset/initialization (reset dependence)
- Differences in reset release timing between modules: a module that wakes up first sends signals to a module still in reset.
- Unreset registers used as mux select, FSM input, enable, or output valid (random values in real hardware).
- Edge detectors or previous-value compare registers produce false edges right after reset.
- Soft reset/flush that clears only some of the related registers is checked under M11 (4.11), not here.

### 4.9 Optimization
Find, through signal relationships, structures that are functionally correct but waste resources, timing, power, or **cycles**.
Look at optimization from **three viewpoints**: cycles (A), gates/timing (B), and power (C). Reducing gates (area) is not the only optimization: if a large cycle (latency/throughput) gain is possible at a small area increase, that is an optimization issue too.

#### (A) Cycle viewpoint: latency and throughput
Follow the flow and count how many cycles one transaction takes from input to output, and every how many cycles consecutive inputs can be accepted. Then look for cycles that can be removed.
- **Idle cycles**: states/wait cycles that pass doing nothing (e.g., in IDLE → START → RUN, START does nothing; resting one cycle in DONE at the end)
- **Serialization**: independent work done one after another (e.g., address calculation then memory read in strict order every time, alternating between two channels)
- **No overlap**: the next transaction is accepted only after the previous one fully completes (no pipeline, no back-to-back, extra cycles to restart after done)
- **Handshake loss**: ready is updated one cycle late through a register, halving throughput; valid/ready round trips create a bubble per transaction
- **Not hiding memory/arithmetic latency**: waiting through RAM read latency or multiplier latency without doing other work (pre-read/prefetch possible)
- **Unnecessary stall propagation**: the whole pipeline stops when only some stages need to
- **Counter/loop waste**: an extra cycle spent checking the end condition, an init cycle per loop

Write cycle-viewpoint issues with **both gain and cost**.
- Gain: current vs. improved cycle count (latency per transaction, throughput = one transaction every N cycles). Show it with a cycle table or a comparison like this (Korean labels as shown):
  ```
  구분        | 지연 | 처리율
  ------------+------+-----------
  현재        |  7   | 7사이클/건
  개선 후     |  5   | 1사이클/건
  ```
- Cost: roughly state the added registers, operators, muxes (e.g., "16비트 레지스터 2개, 2:1 mux 1개 추가").
- Raise it if the cycle gain is large even if area grows. Do not raise it if the gain is small and the cost large.
- Check whether throughput already meets the design target (spec, input interface rate). If the spec says input arrives every N cycles, faster throughput than that is no gain. If there is no spec, state the condition "입력이 매 사이클 올 수 있다면".

#### (B) Gate (area) / timing viewpoint
Do not rely on noticing. Go through the **operation list** (3.2 (4)) row by row:
1. **Timing, every row**: take the serial depth of the row and add the operations before and after it on the same register-to-register (or port-to-register) path. Find the deepest path of the module and judge it against 중-6. A loop whose iterations depend on one another (running count, priority search, carry from one iteration to the next) is a chain as long as the loop: with the default parameters, write the depth as a number.
2. **Duplication, every pair of the same kind**: compare the inputs of rows with the same operator. Same inputs, or inputs where one result can be derived from the other (two subtractions of the same pointers selected by a mux, the same sum computed in two branches), is a duplication candidate. Check with a value table that the single operation gives the same result in every case.
3. **Sharing**: rows with the same operator whose results are used only in mutually exclusive cycles.
4. Then check the items below, which are not tied to one operation.

- **Duplication**: the same operation (multiply, add, compare) computed in several places from the same inputs / two registers that always hold the same value / the same signal synchronized or delayed several times
- **Dead logic**: registers/operations whose results never affect outputs or other state / branches that can never be true because of other signal relationships (unreachable FSM states are recorded under M2, not here)
- **Excess width/depth**: counters/registers wider than the actual value range (parameters, compare values) / division or modulo by powers of two implemented as general operations
- **Timing**: long serial operations in one cycle (add/multiply chains, deep `if-else if` priority chains, large comparators) / combinational signals rather than register outputs driven as module outputs, lengthening paths in the parent
- **Resource sharing**: operators never used at the same time (used only in mutually exclusive states) instantiated separately
- **Unneeded reset**: functionally unnecessary resets on datapath registers (resource/placement constraints on FPGAs). Enables are not judged here: a load enable on a datapath register is wanted for clock gating, and a missing one is checked under M13 (4.9 C).
- If a functional problem exists at the same location, raise it as one functional issue and add the optimization to "수정 제안".

#### (C) Power viewpoint: unnecessary activity and clock gating
Follow valid/enable/state signals and find (1) logic that **toggles in cycles where its result is not used**, and (2) registers that **are clocked every cycle although their input can change only in some cycles**. Power is spent both when values toggle and when a register's clock pin is driven: a register with no enable cannot be clock-gated even if its value never changes. So ask two questions for every register: "in which cycles is this value needed?" and "in which cycles can its input change at all?".
- **Missing register enable** (check this first, for every register): for each register assigned unconditionally (outside any `if (en)`; the `매 클럭` rows of the 3.2 register table), trace its input back to the registers/inputs it is computed from and find the cycles in which those can change. If the sources are loaded only under an enable/valid (so the input is stable in all other cycles), the register needs to load only in the cycle after that enable — the enable (or its delayed copy) is the missing clock-gating enable. Raise it even though the value does not toggle: the register reloads the same value and receives the clock every cycle.
  - Typical form: stage 1 is `if (enable) begin ar <= a; br <= b; end`, stage 2 is `c <= ar * br;` with no condition. Stage 2 should be `if (ena) c <= ar * br;` with `ena` = `enable` delayed by one clock.
  - **Clue**: a delayed enable/valid register that is assigned but never used (e.g., `ena <= enable;` with no reader) almost always means the enable of the next stage was forgotten. An unused signal alone is out of scope, but here it is evidence for this issue: cite it in "문제 설명" and use it in "수정 제안".
  - **Judge an enable by structure, not by name.** Any condition that guards a register's assignment (`if (vld)`, `if (state == RUN)`, `if (cnt_done)`, a `case` branch) is an enable regardless of its name, and a register that holds that condition delayed by one clock is a delayed enable regardless of its name (`d1`, `go_r`, …).
  - Also check that the delayed enable itself is reset or otherwise defined when it starts being used.
- **Toggling on invalid data**: datapath/pipeline registers that load every clock with no enable, so they keep toggling while valid is 0. Compare the register's load condition with the valid of the same stage.
- **Operand isolation**: inputs of a multiplier, adder chain, barrel shifter, or wide comparator change every cycle although the result is used only in some states. Compare the cycles in which the operands change with the cycles in which the result is consumed.
- **Activity while idle**: timers, free-running counters, FSMs, LFSRs, or toggles that keep running while the block is idle or disabled (enable = 0, no transaction in progress). Exception: logic that must keep running by function (watchdog, wake-up detection, CDC synchronizer).
- **Memory enables**: RAM chip enable / read enable tied to 1 or asserted every clock although the read value is used only in some states; writes that store an unchanged value every cycle.
- **Block-level gating opportunity**: a sub-block that is not used at all in some mode (bypass, disabled feature, unused channel) still receives changing inputs and has no enable or clock enable to stop it.
- **Gating-friendly coding**: synthesis tools insert a clock-gating cell only for a group of registers sharing one enable written as `if (en) q <= d;`. Find structures that block this:
  - a wide register whose bits have slightly different load conditions that could share one enable
  - holding the value by rewriting it through another path (a mux selecting a stored copy) instead of not assigning
  - the enable buried under a reset/clear branch that fires every transaction, so no cycle is left without a load
  - a register whose width is fixed and 3 bits or less in total for that enable: a gating cell brings no gain, so do not raise it. **If the width is a parameter, never drop it because the default value is small**; judge it as a parameterized datapath and grade it with the severity procedure.

Write power issues with **structural evidence, not power numbers**.
- State the width and the share of unneeded cycles (e.g., "64비트 레지스터 3단이 valid=0인 사이클에도 갱신됨. 처리율이 8사이클/건이라 8사이클 중 7사이클은 불필요한 갱신", "c(BITS비트)는 enable 다음 사이클에만 값이 바뀌는데 매 클럭 대입되어 클럭 게이팅을 넣을 수 없음"). Never write mW or percent-of-power figures.
- State the fix cost (e.g., "enable 조건 1개 추가", "곱셈기 입력에 AND 게이트 32개").
- If the spec says the tool does not insert clock gating, or the target is an FPGA, the gain is smaller: use only 하-5 and say so in "문제 설명". If the spec says nothing, state the condition "합성 도구가 enable에서 클럭 게이팅을 추론한다면" in "문제 설명".
- Do not raise it if the fix changes functional behavior seen at outputs.
- Do not drop it by assuming the block is always busy. Only if the **spec** states an input rate that keeps the enable at 1 in most cycles is it not raised. If the spec is silent, raise it and state the condition "enable이 매 사이클 1이 아니라면" in "문제 설명".
- If a functional problem exists at the same location, raise it as one functional issue and add the power fix to "수정 제안".

### 4.10 Capacity / backpressure margin (lost data, output corruption)
For every buffer (FIFO, skid buffer, line buffer, pipeline with a stall) and every stop signal (ready, almost_full, credit), check only whether the **space (or, on the read side, the data) is enough**. Whether the count and full/empty flags are updated consistently is M5 (4.6); items lost or duplicated without overflow are M12 (4.12).
- Count the **reaction latency**: the number of cycles from the stop condition becoming true until the source really stops (register stages on the stop signal, register stages in the source, items already in flight in the pipeline).
- Compare with the **margin**: remaining space when the stop is raised (depth − threshold). If items arriving during the reaction latency > margin, data is overwritten or dropped. Show the overflow with a cycle table.
- Check the opposite side too: reading on an empty/almost_empty indication that is one cycle old (underflow, stale data read out).
- A registered `ready` that the sender sees one cycle late, with no skid register to hold the extra beat.
- Credit/count-based flow control: whether the credit count itself can go wrong (returned twice, lost) is M5 (4.6). Here check only whether a correct credit count still leaves enough space (initial credits vs. buffer depth, credits returned before the space is really free).
- Check the worst case allowed by the spec (e.g., "받는 쪽은 tready를 최대 16클럭까지 0으로 둘 수 있다"). If the spec is silent, assume the stop can last indefinitely and inputs can arrive every cycle.

### 4.11 Leftover state between transactions (output corruption, wrong state)
The reset state is checked in 4.8; here check the **boundary between one transaction and the next**, including the ends made by soft reset, flush, and abort (M11 owns all partial-clear problems).
- List the registers that carry state within a transaction: accumulators, byte/bit offsets, partial-data (residue) registers, sticky flags, error flags, counters, pointers, toggles, saved sideband.
- For each, at **every** way a transaction can end (normal done, abort, error, flush, early `last`, timeout): is it cleared or reloaded before the next transaction reads it? A register cleared only on the normal path is the typical defect.
- A register cleared at the *start* of the next transaction: is it read in that same cycle, before the clear takes effect?
- Back-to-back: when the last cycle of transaction N and the first cycle of N+1 are the same or adjacent, does the clear of N wipe the first data of N+1, or does the value of N leak into N+1?
- Prove it with a cycle table spanning two transactions: the first leaves the value, the second produces the wrong result.

### 4.12 Order / count conservation (output corruption, lost/duplicated data)
4.5 checks alignment within one transaction; here check the relationship **between items** from input to output.
- **Order**: where paths of different latency merge (bypass vs. processing path, fast path vs. slow path, two parallel lanes, a retry path), can a later item reach the output before an earlier one? Is the merge select derived from the same item order as the split?
- **Count**: for a block that should emit one output per input (or a fixed N:M ratio), is there a condition (stall, flush, simultaneous push/pop, boundary of a width conversion) where an item is emitted twice or not at all?
- **Frame boundary**: exactly one `last` per frame and on the right beat — when the frame length is 1, when the last input beat is partial, when the last beat coincides with a stall, and for the residue beat of a width conversion (missing or extra final beat).
- Sideband that belongs to a frame (id, user, error, length) must come out with the same frame, not with the neighbor frame.
- Prove it with a cycle table listing input items (D0, D1, …) and output items in order.

### 4.13 Clock-gating safety (hang, lost data, reset dependence)
Applies where the code has a gated clock: an instantiated clock-gating cell (ICG), a clock built with logic (`clk & en`), a clock mux, or a clock enable feeding a clock buffer. A plain register enable (`if (en) q <= d;`) is not a gated clock; it is checked in 4.9 C.
For each gated clock, list the gate enable, the registers that produce the enable (and their clock), and the registers that run on the gated clock.
- **Wake-up condition**: the enable must be producible while the gated clock is off. If any register on the path that raises the enable runs on the gated clock itself, the clock can never be turned on again once it is off (hang). Check the same for a chain of gates (A wakes B, B wakes A).
- **Open timing**: the clock must be running at the edge that captures the first data. If the enable is registered and opens one clock late, the first beat/pulse is lost. Show it with a cycle table that includes the gated clock (running / stopped per cycle).
- **Close timing**: the clock must stay open until the last data has left the gated registers and all their outputs have been consumed. Look for a close condition based only on "no input" or on the FSM being idle while the pipeline, FIFO, or an unacknowledged output still holds data (the output never comes out, or `done` is never raised).
- **Signals crossing the gate boundary**: a pulse from an always-on domain into gated registers while the clock is off is lost; a level sampled after wake-up may be stale. Outputs of gated registers frozen at a non-idle value (valid stuck at 1, a request held) are still seen by always-on logic.
- **Reset under gating**: registers with a synchronous reset on a gated clock are not reset if the clock is off during reset. With an asynchronous reset, check the state right after wake-up as in 4.8. Check that the gate enable itself is in a defined state after reset (an unreset enable register leaves the clock in an unknown state).
- **Manual gating structure**: a clock gated by plain logic (`assign gclk = clk & en;`, `clk | ~en`) with no latch lets an enable change during the high phase reach the clock as a glitch. It is safe only when the enable passes through a latch that is transparent while the clock is low (or is registered on the falling edge for an AND gate). Raise it together with the functional consequence (extra or shortened clock pulse on the gated registers), not as a style remark.
- If the gating cell is a black box (no definition in the source folder), its latch behavior and test-enable pin are unknown: handle it under X4 and list the condition it must satisfy in "블랙박스 확인 사항".

### 4.14 Arithmetic value range (output corruption)
A bit-width warning by itself is lint and out of scope. Here follow the **value range**: input range → largest/smallest intermediate value → width of the register that holds it, and find a reachable input for which the value does not fit. Plain counters and pointers are M5 (4.6); computed values are checked here.
- **Range vs. width**: for each computed result (sum, difference, product, scaled/shifted value, average), derive its maximum and minimum from the operand widths, the spec, and the conditions that bound the operands. Compare with the width of the signal it is assigned to.
- **Accumulators**: largest input × largest number of additions before the clear. Find what bounds the number of additions (frame length, a configuration value, a counter limit). If nothing bounds it, or the bound can be larger than the width allows, the sum wraps. (If the cause is a clear missing on some path, it is M11.)
- **Intermediate width**: a carry or upper bits lost inside an expression before a later shift or compare, e.g., `(a + b) >> 1` evaluated at the operand width, a product assigned to a signal narrower than the sum of the operand widths.
- **Truncation**: on assignment to a narrower signal or a part-select, which bits are dropped, and can they be nonzero for a reachable value? Dropping the upper bits of a signed value changes its sign.
- **Signed/unsigned**: one unsigned operand makes the whole expression unsigned; missing sign extension when widening; signed values compared as unsigned; `>>` used where an arithmetic shift is needed.
- **Unsigned subtraction**: `a - b` with `b > a` wrapping to a huge value that is then used as a length, remaining count, or compare value.
- **Saturation/clamp**: is the compare bound correct (off by one, sign of the bound, both directions)? Is saturation applied before the truncation, not after?
- Evidence: concrete input values and the resulting wrong value (e.g., "x=16'hFFFF가 256번 누적되면 합이 24비트를 넘어 상위 비트가 사라짐"). If the range depends on what the spec allows and the spec is silent, state the condition "입력이 전체 비트 범위를 쓸 수 있다면" in "문제 설명".
- If the overflow cannot happen with the current parameters but would with others, grade it 하-1.

---

## 5. Black-Box Modules

### Identification
1. Build the list of `module` definitions from all Verilog files under the source folder.
2. Classify modules that are instantiated but have no definition as black boxes.
3. Record the kind. In both cases the internals are unknown.
   - **벤더/IP** (vendor/IP): looks like an FPGA primitive or IP core (e.g., `BUFG`, `xpm_*`, `altsyncram`, clock generator IP)
   - **미제공** (not provided): any other module without a definition
4. If an `` `include ``d file is not in the source folder, it cannot be handled as a black box. Mark the modules depending on it as not analyzed and give the reason.

### What is known / what is not assumed
- Known: port connections, parameter values passed, bit width / domain / nature of connected signals, specs in `docs/` (state that it is spec-based)
- Unknown without a spec: input→output latency, output clock domain, reset behavior and output values right after reset, handshake rules, whether outputs are pulse or level

### Judgment
- If the conclusion depends on the black box's internal behavior, write in "문제 설명" **the condition the black box must satisfy for no problem to occur**, and put the same condition in "블랙박스 확인 사항".
  Example: "`u_fifo.rd_valid`가 `rd_en` 후 정확히 1클럭에 올라와야 데이터 정렬이 맞음. 2클럭 이상이면 출력 데이터가 어긋남."
- Problems that can be judged from outside the black box are judged normally (e.g., a black-box output used in another domain without synchronization, a black-box output used in a control path right after reset, different parameters between instances of the same black box breaking the parent logic's assumptions).

---

## 5.5 Graybox Modules

Modules defined inside a **`graybox` folder** under the source folder (folder name case-insensitive, at any depth under the source folder) are grayboxes.
They are typically verified IP or another team's modules: **the code is present, but they are not the target of this analysis.**

### Identification
1. When building the module definition list, mark modules defined in files inside a `graybox` folder as grayboxes.
2. Graybox status is decided by **the location of the file holding the module definition**. A submodule instantiated inside a graybox is a graybox if its definition is inside a `graybox` folder, and a normal module if it is outside.
3. A module instantiated by a graybox whose definition is nowhere in the source folder is a black box (section 5).
4. If a module with the same name is defined both inside and outside `graybox`, do not analyze; ask the user which one to use.

### Used for flow analysis
- Read graybox code and use it **as evidence for analyzing other modules' signals**. Unlike black boxes, do not guess its behavior; judge from the code.
  - input→output latency (cycles), output clock domain, reset behavior and output values right after reset
  - handshake rules (valid hold, ready dependency, backpressure handling), whether outputs are pulse or level
  - input conditions the graybox expects (no duplicate start, no request while busy, etc.)
- If a signal flow passes through a graybox, follow the inner path too, and judge relationships between outer modules (e.g., previous module output → graybox → next module input).
- In the relationship model (3.2), include only a summary of the graybox's port behavior, and look at internal registers only as far as the flow requires.

### Its own problems are not analyzed
- **Problems that start and end inside a graybox are not raised as issues.** This covers internal FSM errors, internal counter boundaries, and internal optimization (duplicated operations, excess bit width, etc.). Even if found, do not write them in the result file.
- Do not propose fixes to graybox code.

### Judgment
| Situation | Handling |
|------|------|
| An outer module uses the graybox incorrectly (violates input conditions the graybox expects, assumes different output latency/nature) | **Raise it.** Location and fix go on the outer module side |
| Graybox behavior causes a problem in an outer module (e.g., the graybox outputs a pulse but the outside assumes a level) | **Raise it.** Describe the graybox behavior as a premise; location and fix go on the outer module side |
| Both cause and effect of the problem are inside the graybox | Do not raise |

- When citing graybox behavior as evidence in an issue body, describe only the behavior, like "그레이박스 `u_fft`는 `start` 후 3사이클에 `done`을 낸다".
- Do not put graybox files in the **위치** column of the summary table.

---

## 6. Writing Scenarios

```
cycle | 0 | 1 | 2 | 3 | 4 |
------+---+---+---+---+---+
srst  | 1 | 0 | 0 | 0 | 0 |
init  | 0 | 1 | 0 | 0 | 0 |
state | I | I | N | N | N |   ← INIT 처리
ready | 1 | 1 | 1 | 1 | 1 |   ← 0이 되어야 함
```

- Show from the start state (right after reset, or a stated normal state) up to the cycle where the symptom appears.
- Include only signals related to the symptom. Max 90 characters per line. Keep annotations (← …) short and in Korean.
- When drawing a table inside a code block, count **one Korean character as two ASCII characters wide** to align columns (the report PDF aligns cells on this basis).
- For a hang, explain below the table why the state no longer changes after the last column.
- Below every cycle table, add **one line per key cycle** telling what happens there in plain words, as a bullet list outside the code block (e.g., `- cycle 5: clear가 풀렸는데 wrproc가 아직 1이라 프레임 시작으로 본다`). Two to four lines; a reader must be able to follow the table from these lines alone.
- **Use a cycle table for every issue where something happens over time**, optimization issues included: idle or wasted cycles (current behavior, wasted cycles marked), a register loaded in cycles where it is not needed, a condition that is never true in the cycle where it is tested. For an optimization issue, put the table under "사이클 표" and the gain/cost under "근거".
- Only an issue with **no time axis** (duplicated operation, excess width, depth of a combinational path, unneeded reset) has no cycle table. Give a small table under "근거" instead: example values showing both forms give the same result, or the depth per stage.

Scenarios to try first:
- back-to-back input, maximum throughput
- boundary values (0, 1, MAX-1, MAX, just before wrap)
- simultaneous events in the same cycle (set/clear, start/abort, write/flush, read/write)
- reset, abort, flush, backpressure during processing
- events arriving just before / just after entering a wait
- the first few cycles after reset release
- two transactions in a row, the first ended by abort/error/flush (leftover state)
- the stop signal raised when the buffer is almost full, with inputs still arriving every cycle
- a configuration value changed in the middle of a transaction
- frame length 1, and the last beat coinciding with a stall
- maximum-value inputs on every arithmetic operand, for the longest allowed accumulation

---

## 7. Result File Format (`reports/<top>_review_<YYYYMMDD>.md`)

`.claude/skills/verilog-report/assets/report_template.md` is the complete example. Write the result file with the same structure as that example, except the first-line title is `# <top> 정적 분석 결과`.
**The whole result file is written in Korean.** Headings, table headers, and item names are the exact Korean literals shown below.

````markdown
# <top> 정적 분석 결과

## 분석 개요

| 항목 | 내용 |
|:--:|------------------------------------------|
| TOP | `<top>` |
| 소스 폴더 | `<경로>` |
| 블록 기능 | (2~3문장. 아래 "분석 개요" 규칙) |
| 이슈 | 총 n건 (상 n / 중 n / 하 n) |
| 블랙박스 | n개: `모듈`, `모듈` |
| 그레이박스 | n개: `모듈` (graybox 폴더, 흐름 분석만) |
| 분석 소스 | (측정 중) |
| 참고 스펙 | `docs/analysis-spec.md` |
| 분석시간 | (측정 중) |
| 룰 버전 | v<버전> @ POUCO |
| 사용모델 | (측정 중) |
| 노력 | (측정 중) |
| 소요시간 | (측정 중) |
| 토큰 사용량 | (측정 중) |

## 설계 구조

```hier
rx_top
  u_axis : axis_slave [IF]
  u_ctrl : rx_ctrl [CTRL]
    u_fsm : rx_fsm [CTRL]
  u_lane[0..3] : lane [DP]
  u_lbuf : line_buf [BUF]
  u_fifo : fifo_core [BB]
  u_sync : sync_2ff [CLK]
```

클럭 … · 리셋 … · FSM: …

## 요약

| NO | 심각도 | 내용 | 위치 | 상세 |
|:--:|:--:|:------------------------------------------:|:--:|:--:|
| V-001 | 상 | srst 해제 직후 init 처리 후 ready가 1로 남아 입력 데이터 유실 | `rx_ctrl.v:97` | [보기](#v-001) |

## 상세

### V-001 <제목> {#v-001}

| 심각도 | 관련 신호 |
|:--:|------------------------------------------|
| 상 | `srst`, `init`, `state`, `ready` |

#### 심각도 근거

상-1: srst 해제 뒤 init이라는 정상 입력 순서에서, 초기화 중 들어온 입력 데이터가 유실됨 (조건 번호 + 한 문장)

#### 요약

1~2문장: 블록이 무엇을 하는 중에 → 무엇이 잘못되는지 (밖에서 보이는 것만)

#### 발생 가능한 문제

이 결함 때문에 밖에서 보이는 증상 (출력 데이터 유실, 블록 멈춤, 잘못된 state 진입, 자원 낭비 …)

#### 문제 설명

원래 하려는 동작 → 잘못되는 상황 → 그 상황에서 실제 동작 → 밖에서 보이는 결과 → 문제가 되지 않는 경우 ("Writing style")

#### 신호 흐름

init → state → ready → 출력 ready

#### 발생 조건

한두 문장: 어떤 입력 순서·타이밍에서 생기는지

#### 사이클 표

```
(사이클 표)
```

- cycle 1: (그 사이클에 일어나는 일을 한 줄로)
- cycle 2~3: …

#### 근거

(최적화 이슈만: 이득과 비용, 시간 축이 없으면 값·구조 표)

#### 수정 제안

```diff
(블록의 시작부터 끝까지, 바뀌는 줄 전부)
```

수정 후: (사이클 표의 어느 사이클이 어떤 값으로 바뀌는지)

## 점검 커버리지

| 모듈 | M1 | M2 | M3 | M4 | M5 | M6 | M7 | M8 | M9 | M10 | M11 | M12 | M13 | M14 | M15 |
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| rx_ctrl | [V-001](#v-001) | OK | OK | OK | OK | - | OK | OK | OK | - | OK | - | OK | - | - |
| rx_dp | OK | - | - | OK | OK | OK | OK | OK | [V-004](#v-004) | OK | OK | [V-003](#v-003) | OK | - | OK |

| 모듈 간 | X1 | X2 | X3 | X4 |
|:--:|:--:|:--:|:--:|:--:|
| rx_top | OK | OK | - | [V-002](#v-002) |

## 블랙박스 확인 사항

| 모듈 | 종류 | 인스턴스 | 만족해야 할 조건 | 관련 이슈 |
|:--:|:--:|------|------------------------------|:--:|
| fifo_core | 미제공 | `rx_top.v:88` u_fifo | data_last는 data_valid와 같은 사이클에만 1 | [V-002](#v-002) |
````

### Overview (분석 개요)
- Write the row order, the header (`| 항목 | 내용 |`), and the item names exactly as in the example. During PDF conversion these names are used to merge the first row (TOP·소스 폴더) and the last three rows (분석시간·룰 버전 / 사용모델·노력 / 소요시간·토큰 사용량) into single lines. Use the separator line exactly as in the example too.
- **블록 기능**: 2–3 Korean sentences centered on top. State what it receives, what processing it goes through, what it sends out, and what roles the main sub-blocks play (step 5 of 3.1).
  - Example: `AXI-Stream으로 받은 샘플에 창 함수를 곱하고 누적해 프레임 단위 결과를 낸다. rx_ctrl이 프레임 경계와 ready를 제어하고, rx_dp가 곱셈·누적·포화를 처리한다.`
  - No code locations. Mention grayboxes and black boxes by name only. It is a table cell, so no line breaks.
- **블랙박스 / 그레이박스**: count and module names. If none, "없음".
- **룰 버전**: the rule version used for the analysis (the value in CLAUDE.md's "룰 버전" section) followed by one space and `@ POUCO`. Example: `v0.8.6 @ POUCO`
- **TOP**: item name in uppercase `TOP`; value is the module name as is (case preserved).
- **참고 스펙**: paths of the spec files under `docs/` used for the analysis (those confirmed in 3.0). Join multiple with `, `. **If no spec was used, omit this row.** Never list `docs/example/` files.
- **분석 소스 / 분석시간 / 사용모델 / 노력 / 소요시간 / 토큰 사용량**: write `(측정 중)` in the result file; `session_usage.py --fill` in step 2 of 3.6 replaces them with real values (e.g., `총 12개 파일, 3,450줄`, `2026-10-29 14:10`, `Opus 5.5`, `medium`, `12분 30초`, `총 1.85M (출력 42K)`). If measurement fails, "측정 불가".
- If there is unanalyzed scope or modules unused by top, add `| 미분석 범위 | … |` and `| top 미사용 모듈 | … |` rows at the end of the table.

### Summary table (요약)
- Use only the five columns `NO | 심각도 | 내용 | 위치 | 상세`. There are no classification or confidence columns.
- The **내용** column holds the issue title written by the "Titles" rule below.
- **위치**: one representative location where the problem starts (`file:line`). Two at most, only if really needed.
- Use the separator line exactly as in the example (wide 내용 column, all columns centered). No line breaks inside table cells.

### Titles
- **Short: 30–40 Korean characters, 45 at most.** It must fit on one line in the table.
- Write it as **"under what condition + what symptom"**, ending with a symptom visible from outside: 유실, 멈춤, 교착, 잘못된 state 진입, 가짜 출력, 값 오류, 중복 처리, 리셋 직후 오동작, 처리율 저하, 지연 증가, 자원 낭비, 타이밍 위험 …
  - Cycle optimization example: `done 후 IDLE 경유로 프레임마다 2사이클 버블, 처리율 저하`
  - Good: `srst 해제 직후 init 처리 후 ready가 1로 남아 입력 데이터 유실`
  - Good: `data_valid 없는 data_last로 가짜 결과 출력`
  - Good: `ack가 대기 진입 전에 오면 WAIT_ACK에서 멈춤`
  - Bad: `ready 갱신 조건 오류` (no symptom)
  - Bad: `rx_ctrl.v 84행의 ready 갱신 조건에 state_nxt 비교가 빠져 있어서 …` (too long, explains the cause)
- The detail title (`### V-001 <제목>`) is the same as the summary-table title.

### Details (상세)
- Each item gets a `#### <item name>` heading, with its content as a new paragraph below (items appear spaced apart).
- Item order (Korean item names): 심각도 근거 → 요약 → 발생 가능한 문제 → 문제 설명 → 신호 흐름 → 발생 조건 → 사이클 표 → 근거 → 수정 제안. Drop items that have nothing to say.
  - **사이클 표**: every issue where something happens over time, functional or optimization (section 6). Followed by the per-cycle reading lines.
  - **근거**: optimization issues only. Gain and cost (current vs. improved cycle comparison and added cost for cycles, width and share of unneeded cycles for power), and for an issue with no time axis the value or structure table that replaces the cycle table.
- The table at the top of each detail is `심각도 | 관련 신호`. **관련 신호** lists only 2–5 main signal names directly involved (e.g., `srst`, `init`, `state`, `ready`). If a hierarchy path is needed, keep it short like `u_ctrl.ready`.
- **Code locations (`file:line`) go only in the summary table's 위치 column.** Details contain no locations, only signal names (the fix diff is the exception).
- Signal flow joins signal names with `→`: `init → state → ready → 출력 ready`
- **발생 조건**: one or two sentences giving the input order and timing that trigger it (and the spec/black-box condition it depends on, if any).

### Writing style (요약, 발생 가능한 문제, 문제 설명)
Write for a reader who knows digital design but has **not read this code**. The prose explains; the cycle table and the diff prove.
- **Explain by meaning, not by expression.** No Verilog expressions or operators in prose (`~clear & wrproc`, `sizex > 0 && wrent`, `==`, `<=`). Say what the logic does: "clear가 아닌 동안의 wrproc를 한 클럭 늦춘 값". Expressions appear only in the diff. Stating the value of a signal is not an expression and is fine (`ready가 1인 동안`, `valid=0인 사이클`).
- **One fact per sentence, at most two signal names per sentence.** Split a sentence that lists what several signals do.
- **Give a signal its role the first time it appears in an issue**: `` `wrstt`(프레임 시작 표시) ``. After that the name alone is enough.
- **요약** and **발생 가능한 문제** must read without knowing any internal signal: name only ports and things the reader can see from outside (입력 프레임, 출력 구간, 남은 바이트). 요약 says what the block is doing at that point and what goes wrong.
- **문제 설명** follows this order, one or two sentences each:
  1. what the logic is meant to do
  2. the situation in which it goes wrong
  3. what the logic actually does in that situation
  4. what is seen from outside as a result
  5. when it is not a problem (intended behavior, spec condition), if any
- **No shorthand in prose**: cycle labels such as `L+1`, `N-1`, or stage numbers are used only inside the cycle table and its reading lines. In prose say "마지막 입력 다음 사이클".
- Do not pack a derivation into parentheses. If a reason needs a sentence, give it a sentence.
- Numbers come with what they count: "32단" → "조건부 증가 32단", "512비트" → "mem 64칸 × 8비트 = 512비트".

Example (문제 설명):
- Bad: `alwrproc는 ~clear & wrproc로 만들어져 clear 사이클 다음에 0이 되고, wrstt는 wrproc & ~alwrproc라서 clear가 풀린 첫 사이클에 wrproc가 아직 1이면 프레임 시작으로 판단한다.`
- Good: `이 블록은 wrproc가 0에서 1로 바뀌는 순간을 프레임 시작으로 본다. 이를 위해 한 클럭 전의 wrproc를 alwrproc(이전 사이클의 구간 표시)에 기억해 둔다. 그런데 clear가 오면 이 기억이 0으로 지워진다. clear가 풀렸을 때 wrproc가 아직 1이면, 블록은 구간이 방금 시작된 것으로 착각한다. 그 결과 프레임의 남은 뒷부분이 새 프레임처럼 따로 출력된다. clear를 프레임 사이에서만 쓴다면 문제가 되지 않는다.`

### Fix proposal (수정 제안)
The diff must be **complete enough to apply as it is**. A reader should be able to fix the code from the diff alone.
- **Include every line that changes**: the declaration of each new signal, its reset or initial value, and every place that uses it. Do not show only the key line.
- **Do not cut a block open**: if the diff shows the opening of an `always`, `function`, `case`, `generate`, or `begin`, it also shows its closing line. A long unchanged middle part may be shortened to one line `// ... (변경 없음)`; never drop it silently.
- **Several places → several diff blocks**, in source order. Above each block write one Korean line saying which part it is (e.g., `신호 선언`, `쓰기 쪽 always 블록`, `rdpop 조건`).
- **Copy original lines exactly as in the source** (indentation, names, spacing). Context lines start with a space, removed lines with `-`, added lines with `+`.
- **Show that the fix works**: below the diff, write one or two lines saying which cycle of the cycle table changes and to what value (e.g., `수정 후: cycle 5에서 wrstt가 0으로 남아 두 번째 프레임이 생기지 않는다`). If the change is not obvious from that, add a short "수정 후" cycle table.
- **State side effects**: if the fix adds a cycle of latency, changes the timing of another signal, or needs a matching change elsewhere (a parent module, a delay chain length), say so and include that change in the diff.
- **One fix as a diff**: if there are alternatives, show the recommended one as the diff and mention the others in one line each.
- A fix that only removes lines still shows the surrounding context lines so the place can be found.

### Design structure (설계 구조)
- In the `hier` code block, write the instance hierarchy from top with 2-space indentation. Each line is `instance : module`; only the first line is the top module name.
- Collapse array/generate instances into one line: `u_lane[0..3] : lane`
- **Append exactly one block-kind tag to every instance.** Decide by reading the code, not by the name. Each kind gets a different color in the PDF figure.

  | Tag | Block kind | Criteria |
  |:--:|------|------|
  | `[CTRL]` | Control | FSM, control/scheduling/arbitration, counter/timer-centric, configuration registers |
  | `[BUF]` | Buffer/Memory | FIFO, line buffer, RAM/ROM, register file, delay buffer |
  | `[DP]` | Datapath | arithmetic/logic, filters, accumulation, saturation, data conversion |
  | `[IF]` | Interface | bus/stream interfaces (AXI, APB, etc.), serial I/O, bridges |
  | `[CLK]` | Clock/Reset | clock generation/gating, reset generation/synchronization, CDC synchronizers |
  | `[BB]` | Black box | modules with no definition in the source folder (this tag regardless of kind) |

  - If several natures are mixed, pick the one main job of the module. For a parent block with submodules, use the kind with the largest share among its children.
  - If it is hard to decide, omit the tag (the figure guesses from the name or uses the generic block color).
  - **Grayboxes** (section 5.5) get one more `[GB]` after the block-kind tag: `u_fft : xfft_core [DP] [GB]`. In the figure they are marked with a dashed border and a `GB` label.
- No tag on the top line (first line).
- Do not reduce depth; write as much as you know. During PDF conversion the depth is reduced automatically so the figure stays within half a page, and hidden sub-instance counts appear as `+n`.
- Under the block, write the clock domains, reset structure, and FSM list on one line (in Korean, as in the example).

### Severity procedure (심각도 판정 절차)
Go through the list below **from the top, in order**, and take the grade of the first matching condition. Write that condition number in the detail's "심각도 근거".

**상**
| No. | Condition |
|:--:|------|
| 상-1 | Occurs under a normal input sequence the spec allows, and wrong data or loss goes out to top outputs |
| 상-2 | A hang/deadlock/state that cannot be escaped without reset |
| 상-3 | Missing synchronization, multi-bit CDC, etc. lead from metastability to a functional error |

**중**
| No. | Condition |
|:--:|------|
| 중-1 | Misbehaves only under specific conditions such as boundary values or same-cycle simultaneous events, but those conditions are reachable in normal use |
| 중-2 | Misbehaves only for a few cycles right after reset release |
| 중-3 | A hang that reset does recover from (e.g., escapable via external abort, timeout, or restart) |
| 중-4 | Could become a "상" condition depending on black-box/graybox behavior or spec interpretation (needs confirmation) |
| 중-5 | Cycle optimization that doubles throughput or more, or cuts per-transaction latency by 30% or more, at register/mux-level added cost |
| 중-6 | A path likely to fail timing at the target clock, such as 2+ multiplies or 4+ adds in series within one cycle |
| 중-7 | Power optimization where a wide datapath (32 bits or more in total), a RAM, or a multiplier toggles, or is loaded with no enable, in most of the cycles in which its result is unused or its input cannot change, and one enable can stop it |

**하**
| No. | Condition |
|:--:|------|
| 하-1 | Cannot occur with the current parameters/usage, but an assumption that breaks if parameters or input conditions change |
| 하-2 | Area optimization (duplicated operations/registers, excess bit width, dead logic including branches that can never be true, shareable resources) |
| 하-3 | Cycle optimization below the 중-5 threshold |
| 하-4 | Unreachable FSM state |
| 하-5 | Power optimization below the 중-7 threshold (including a narrower register missing its load enable), or coding that may keep the tool from inferring clock gating |

**Adjustment rules**
- If several conditions match, use the highest grade (highest in the list).
- If the scenario holds but **may be intended design behavior**, lower it one grade (상→중, 중→하, 하 stays). Then append "(의도 확인 필요로 한 단계 낮춤)" to the end of the reason.
- If none of the conditions above match, do not raise it as an issue.
- The 심각도 근거 line is written in Korean: condition number + one sentence. Examples: `상-2: ack가 WAIT_ACK에 들어가기 전에 지나가면 reset 없이는 빠져나오지 못함`, `중-1: 같은 사이클에 flush와 write가 오면 count가 1 어긋남 (의도 확인 필요로 한 단계 낮춤)`

### Coverage (점검 커버리지)
- Copy the 3.3 checklist results as is. Use two tables.
  - In-module: rows = module order from 3.3 (1) (excluding grayboxes and black boxes), columns = M1–M15
  - Inter-module: rows = modules with sub-instances (from top), columns = X1–X4
- Cell values are `-`, `OK`, or an issue link (`[V-001](#v-001)`). No empty cells.
- Write headers and column names exactly as in the example.

### Format rules
- Numbers are `V-` + 3 digits (`V-001`). Anchors are lowercase `{#v-001}`, links are `[보기](#v-001)`.
- Number, severity, and content in the summary table must match number, severity, and title in the details.
- If there are 0 issues, write "발견된 이슈 없음" instead of the summary table, and keep the design structure.

---

## 8. Prohibited

- Running external tools such as simulators, lint, or synthesis / creating testbench or assertion files
- Raising lint-level items or simple missing signals as issues (when no scenario leads to a problem)
- Generalities without a reachable path (scenario) ("CDC 위험이 있다", "리셋이 없어 위험하다", etc.)
- Classification codes, classification columns, or confidence marks
- Code locations (`file:line`) in details (except the fix diff)
- Conclusions drawn only from previous results without checking the current code
- Modifying RTL
- Silently omitting scope that could not be analyzed
- Reordering the 3.3 checklist or skipping checks; writing the result file before all coverage cells are filled
- Deciding severity without a condition number from the severity procedure
- A functional issue without a cycle table (the only exception is an M15 issue shown with concrete values, 3.4); a cycle table without its reading lines
- Verilog expressions or shorthand cycle labels in the prose of 요약 / 발생 가능한 문제 / 문제 설명
- A fix diff that shows only the key line, cuts a block open, or leaves out the declaration of a new signal
- Asserting black-box internal behavior by guessing
- Raising problems that start and end inside a graybox; proposing fixes to graybox code
- Using Verilog files outside the source folder in the analysis
- Creating analysis result files other than `reports/<top>_review_<YYYYMMDD>.md`
- Writing responses or the result file in English (everything the user sees is Korean)

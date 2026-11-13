"""분석 개요 표에 넣을 분석 소스 규모, 분석시간, 사용모델, 노력, 소요시간, 토큰 사용량을 계산한다.

사용법 (분석 세션의 프로젝트 폴더에서, 결과 파일을 다 쓴 뒤 **맨 마지막에** 실행):
    python .claude/skills/verilog-review/scripts/session_usage.py --src rtl/rx --since 2026-10-29T05:10:00Z \
        --fill reports/rx_top_review_20261029.md

출력 (--fill을 주면 결과 파일 "분석 개요" 표의 해당 행 값을 직접 바꾼다):
    분석 소스: 총 12개 파일, 3,450줄 (그레이박스 2개 파일, 800줄 별도)
    분석시간: 2026-10-29 14:10
    사용모델: Opus 5.5
    노력: medium
    소요시간: 12분 30초
    토큰 사용량: 총 1.85M (출력 42K)

- 분석 시작 시각: --since와 "세션 로그에서 사용자가 마지막으로 직접 입력한 메시지의 시각" 중 늦은 쪽.
  사전 확인·PDF 질문에 답하기 전에 --since를 기록했더라도 답을 기다린 시간은 세지 않는다.
  --since가 없거나 잘못됐으면 마지막 사용자 입력 시각을 쓴다.
- 분석시간: 분석 시작 시각을 이 PC의 현지 시각으로 바꾼 날짜·시각.
- 사용모델: --since 이후 응답의 message.model (claude-opus-5-5 -> Opus 5.5).
- 노력: --since 이후 응답의 effort 값 (low / medium / high / xhigh / max).
  둘 다 분석 중 바뀌었거나 subagent가 다른 모델을 썼으면 많이 쓴 순서로 ', '로 잇는다.
- 소요시간: 분석 시작 시각부터 이 스크립트를 실행한 현재 시각까지에서 **도구 승인 대기 시간을 뺀 값**.
  승인 대기는 로그에 따로 기록되지 않아, 도구 호출부터 결과까지 걸린 시간으로 추정한다.
  분석 중 쓰는 도구(Read, Grep, Glob, Write, date)는 실행이 1초 안에 끝나므로,
  호출~결과 간격이 WAIT_MIN초를 넘으면 그 구간 전체를 대기로 보고 뺀다 (겹치는 구간은 한 번만).
  결과가 아직 없는 마지막 호출(이 스크립트 자신)은 호출 시각부터 지금까지를 같은 기준으로 뺀다.
- 왜 맨 마지막에 실행하나: Claude Code는 응답을 그 응답의 도구 실행이 끝난 뒤에 로그에 쓴다.
  분석 도중(같은 응답 안)에 실행하면 진행 중인 응답의 토큰이 아직 로그에 없어 크게 적게 나온다.

- 분석 소스: --src 폴더 아래 *.v *.sv *.vh *.svh 파일 수와 전체 줄 수(빈 줄·주석 포함).
  graybox 폴더(이름 대소문자 무관) 안의 파일은 총계에서 빼고 괄호에 따로 적는다.
- 세션 로그: ~/.claude/projects/<프로젝트 키>/ 에서 가장 최근에 수정된 *.jsonl
  (프로젝트 키 = 현재 폴더 경로의 영숫자 외 문자를 '-'로 바꾼 것)
  같은 이름 폴더의 subagents/*.jsonl 이 있으면 함께 합산한다.
- 한 응답이 여러 줄로 기록되므로 message.id 별로 한 번만 센다.
- 총 토큰 = input + output + cache_read + cache_creation. 대부분은 캐시 읽기다.
- 측정하지 못한 항목은 "측정 불가"로 출력하고 종료 코드 0으로 끝난다 (분석은 계속).
"""
import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

UNAVAILABLE = '측정 불가'
WAIT_MIN = 2.0      # 도구 호출~결과 간격이 이보다 길면 승인 대기로 본다 (초)
VERILOG_EXT = ('.v', '.sv', '.vh', '.svh')


def parse_time(s):
    try:
        t = datetime.fromisoformat(s.strip().replace('Z', '+00:00'))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def count_lines(path):
    with open(path, 'rb') as f:
        data = f.read()
    if not data:
        return 0
    return data.count(b'\n') + (0 if data.endswith(b'\n') else 1)


def source_summary(src):
    if not src or not os.path.isdir(src):
        return UNAVAILABLE
    main_files = main_lines = gb_files = gb_lines = 0
    for root, _, files in os.walk(src):
        rel = os.path.relpath(root, src)
        in_gb = any(part.lower() == 'graybox' for part in rel.replace('\\', '/').split('/'))
        for name in files:
            if not name.lower().endswith(VERILOG_EXT):
                continue
            n = count_lines(os.path.join(root, name))
            if in_gb:
                gb_files += 1
                gb_lines += n
            else:
                main_files += 1
                main_lines += n
    text = f'총 {main_files}개 파일, {main_lines:,}줄'
    if gb_files:
        text += f' (그레이박스 {gb_files}개 파일, {gb_lines:,}줄 별도)'
    return text


def project_dir():
    base = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.join(os.path.expanduser('~'), '.claude')
    key = re.sub(r'[^A-Za-z0-9]', '-', os.getcwd())
    return os.path.join(base, 'projects', key)


def session_files(pdir):
    logs = glob.glob(os.path.join(pdir, '*.jsonl'))
    if not logs:
        return []
    main = max(logs, key=os.path.getmtime)
    subs = glob.glob(os.path.join(main[:-len('.jsonl')], 'subagents', '*.jsonl'))
    return [main] + subs


def last_human_time(pdir):
    """세션 로그에서 사용자가 직접 입력한 마지막 메시지의 시각. 없으면 None.
    도구 결과나 skill 안내처럼 자동으로 들어간 user 줄은 origin.kind가 human이 아니라 제외된다."""
    files = session_files(pdir)
    if not files:
        return None
    last = None
    with open(files[0], encoding='utf-8') as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get('type') != 'user' or d.get('isMeta') or d.get('isSidechain'):
                continue
            if (d.get('origin') or {}).get('kind') != 'human':
                continue
            t = parse_time(d.get('timestamp', ''))
            if t and (last is None or t > last):
                last = t
    return last


def fmt_tokens(n):
    if n >= 1_000_000:
        return f'{n / 1_000_000:.2f}M'
    if n >= 1_000:
        return f'{n / 1_000:.0f}K'
    return str(n)


def fmt_duration(sec):
    sec = int(round(sec))
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f'{h}시간 {m}분 {s}초'
    if m:
        return f'{m}분 {s}초'
    return f'{s}초'


def approval_wait(since, pdir, now):
    """since 이후 도구 승인을 기다린 시간(초). 로그를 읽지 못하면 0."""
    files = session_files(pdir)
    if since is None or not files:
        return 0.0
    start, end = {}, {}         # tool_use id -> 호출 시각 / 결과 시각
    with open(files[0], encoding='utf-8') as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = d.get('message')
            content = msg.get('content') if isinstance(msg, dict) else None
            t = parse_time(d.get('timestamp', ''))
            if t is None or not isinstance(content, list):
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get('type') == 'tool_use' and b.get('id'):
                    start.setdefault(b['id'], t)
                elif b.get('type') == 'tool_result' and b.get('tool_use_id'):
                    end.setdefault(b['tool_use_id'], t)
    spans = []
    for tid, t0 in start.items():
        if t0 >= now:
            continue
        t1 = min(end.get(tid, now), now)    # 결과가 없으면 아직 실행 중인 호출
        t0 = max(t0, since)
        if (t1 - t0).total_seconds() > WAIT_MIN:
            spans.append((t0, t1))
    spans.sort()
    total, cur0, cur1 = 0.0, None, None
    for t0, t1 in spans:                    # 겹치는 구간(병렬 호출)은 합쳐서 한 번만 센다
        if cur1 is None or t0 > cur1:
            if cur1 is not None:
                total += (cur1 - cur0).total_seconds()
            cur0, cur1 = t0, t1
        elif t1 > cur1:
            cur1 = t1
    if cur1 is not None:
        total += (cur1 - cur0).total_seconds()
    return total


def elapsed_until_now(since, wait=0.0, now=None):
    if since is None:
        return UNAVAILABLE
    now = now or datetime.now(timezone.utc)
    sec = (now - since).total_seconds()
    if sec < 0:
        return UNAVAILABLE
    return fmt_duration(max(sec - wait, 0))


def model_name(mid):
    """claude-opus-5-5 -> Opus 5.5. 형식이 다르면 ID 그대로."""
    m = re.fullmatch(r'claude-([a-z]+)-(\d+)-(\d+)(?:-\d{8})?', mid or '')
    if not m:
        return mid
    return f'{m.group(1).capitalize()} {m.group(2)}.{m.group(3)}'


def by_count(counter):
    """많이 쓴 순서로 ', '로 잇는다."""
    return ', '.join(k for k, _ in sorted(counter.items(), key=lambda kv: -kv[1]))


def session_stats(since, pdir):
    """(토큰 사용량, 사용모델, 노력) 문자열. 측정하지 못한 항목은 '측정 불가'."""
    files = session_files(pdir)
    if since is None or not files:
        return UNAVAILABLE, UNAVAILABLE, UNAVAILABLE

    usage = {}          # message.id -> usage. 같은 id는 마지막 줄(최종 값)을 쓴다
    models = {}         # 모델 이름 -> 응답 수
    efforts = {}        # 노력 수준 -> 응답 수
    seen = set()
    for path in files:
        with open(path, encoding='utf-8') as f:
            for line in f:
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if d.get('type') != 'assistant':
                    continue
                t = parse_time(d.get('timestamp', ''))
                if t is None or t < since:
                    continue
                msg = d.get('message', {})
                mid = msg.get('id') or id(d)
                if mid not in seen:             # 응답 하나를 한 번만 센다
                    seen.add(mid)
                    model = msg.get('model')
                    if model and not model.startswith('<'):     # <synthetic> 등 제외
                        name = model_name(model)
                        models[name] = models.get(name, 0) + 1
                    effort = d.get('effort')
                    if isinstance(effort, str) and effort:
                        efforts[effort] = efforts.get(effort, 0) + 1
                u = msg.get('usage')
                if u:
                    usage[mid] = u

    keys = ('input_tokens', 'output_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens')
    if usage:
        total = sum((u.get(k) or 0) for u in usage.values() for k in keys)
        output = sum((u.get('output_tokens') or 0) for u in usage.values())
        tokens = f'총 {fmt_tokens(total)} (출력 {fmt_tokens(output)})'
    else:
        tokens = UNAVAILABLE
    return tokens, by_count(models) or UNAVAILABLE, by_count(efforts) or UNAVAILABLE


def fill_result(path, values):
    """결과 파일 "분석 개요" 표에서 항목 이름이 같은 첫 행의 값을 바꾼다. 바꾼 항목 이름 목록을 돌려준다."""
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    done = []
    for key, val in values:
        pat = re.compile(r'^\|\s*' + re.escape(key) + r'\s*\|.*\|\s*$')
        for i, line in enumerate(lines):
            if pat.match(line):
                lines[i] = f'| {key} | {val} |'
                done.append(key)
                break
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', help='분석 소스 폴더 (세션에서 지정한 소스 폴더)')
    ap.add_argument('--since', help='분석 시작 시각 (ISO 8601, 예: 2026-10-29T05:10:00Z)')
    ap.add_argument('--fill', help='값을 채워 넣을 결과 파일 (reports/<top>_review_<날짜>.md)')
    ap.add_argument('--project-dir', help='세션 로그 폴더를 직접 지정 (기본: 현재 폴더에서 계산)')
    args = ap.parse_args()

    try:
        src = source_summary(args.src)
    except Exception:
        src = UNAVAILABLE
    since = parse_time(args.since) if args.since else None
    pdir = args.project_dir or project_dir()
    try:
        human = last_human_time(pdir)
    except Exception:
        human = None
    if human and human <= datetime.now(timezone.utc) and (since is None or human > since):
        since = human       # 사용자 답을 기다린 시간은 분석 시간에서 뺀다
    started = since.astimezone().strftime('%Y-%m-%d %H:%M') if since else UNAVAILABLE
    now = datetime.now(timezone.utc)
    try:
        wait = approval_wait(since, pdir, now)
    except Exception:
        wait = 0.0
    elapsed = elapsed_until_now(since, wait, now)
    try:
        tokens, models, efforts = session_stats(since, pdir)
    except Exception:
        tokens = models = efforts = UNAVAILABLE

    values = [('분석 소스', src), ('분석시간', started), ('사용모델', models), ('노력', efforts),
              ('소요시간', elapsed), ('토큰 사용량', tokens)]
    for key, val in values:
        print(f'{key}: {val}')
    if wait >= 1:
        print(f'(소요시간에서 도구 승인 대기 {fmt_duration(wait)} 제외)')
    if args.fill:
        try:
            done = fill_result(args.fill, values)
            missing = [k for k, _ in values if k not in done]
            print(f'채움: {args.fill}' + (f' (표에 없는 항목: {", ".join(missing)})' if missing else ''))
        except Exception as e:
            print(f'채우지 못함: {args.fill} ({e})')


if __name__ == '__main__':
    main()
    sys.exit(0)

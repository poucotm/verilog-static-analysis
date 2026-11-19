#!/usr/bin/env python3
"""주석을 뺀 분석용 사본을 만든다 (verilog-review 3.0).

- --src 폴더 아래 *.v *.sv *.vh *.svh 파일을 같은 상대 경로로 --out 폴더에 복사한다.
- // 줄 주석과 /* */ 블록 주석을 지우고 공백 한 칸만 남긴다. 줄바꿈은 그대로 두므로 줄 번호가 원본과 같다.
- 각 줄 끝의 공백을 지운다 (주석만 있던 줄은 빈 줄이 된다). 토큰을 아끼기 위해서다.
- 문자열 "..." 안과 escaped identifier(\\name) 안의 //, /* 는 주석으로 보지 않는다.
- pragma 주석(synopsys, synthesis, pragma, translate_off 등으로 시작)은 남긴다.
- --spec 을 주면 스펙 파일(analysis-spec.md)의 <!-- --> 주석을 지운 사본을 --out 에 만들고,
  "## TOP" 절의 내용(없으면 "없음")을 출력한다.
- --out 은 reports/.nocomment 이거나 그 아래여야 한다. 실행할 때마다 지우고 새로 만든다.
- 원본은 읽기만 한다.
"""
import argparse
import os
import re
import shutil
import sys

EXTS = ('.v', '.sv', '.vh', '.svh')
PRAGMA = re.compile(
    r'\s*(synopsys|synthesis|pragma|cadence|ambit|xilinx|altera|'
    r'translate_off|translate_on|full_case|parallel_case)\b', re.I)


def blank(text):
    """주석 text를 공백 한 칸과 줄바꿈만 남긴다 (토큰 절약, 줄 번호 유지)."""
    return ' ' + ''.join(c for c in text if c in '\r\n')


TRAIL = re.compile(r'[ \t]+(?=\r?\n|\Z)')


def strip(src):
    out = []
    i, n = 0, len(src)
    removed = kept = 0
    while i < n:
        c = src[i]
        if c == '"':                                   # 문자열
            j = i + 1
            while j < n and src[j] != '"' and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
            out.append(src[i:j]); i = j
        elif c == '\\':                                # escaped identifier
            j = i + 1
            while j < n and not src[j].isspace():
                j += 1
            out.append(src[i:j]); i = j
        elif src.startswith('//', i):                  # 줄 주석
            j = src.find('\n', i)
            j = n if j < 0 else j
            if j > i and src[j - 1] == '\r':
                j -= 1
            body = src[i:j]
            if PRAGMA.match(body[2:]):
                out.append(body); kept += 1
            else:
                out.append(blank(body)); removed += 1
            i = j
        elif src.startswith('/*', i):                  # 블록 주석
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            body = src[i:j]
            if PRAGMA.match(body[2:]):
                out.append(body); kept += 1
            else:
                out.append(blank(body)); removed += 1
            i = j
        else:
            j = i + 1
            while j < n and src[j] not in '"\\/':
                j += 1
            out.append(src[i:j]); i = j
    return TRAIL.sub('', ''.join(out)), removed, kept


def read(path):
    raw = open(path, 'rb').read()
    for enc in ('utf-8', 'latin-1'):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            pass


MD_COMMENT = re.compile(r'<!--.*?(-->|\Z)', re.S)
HEADING = re.compile(r'^\s*#{1,6}\s*(.*?)\s*#*\s*$')


def spec_copy(path, out):
    """스펙 파일에서 <!-- --> 주석을 지운 사본을 만들고 Top 절과 내용 유무를 출력한다."""
    if not os.path.isfile(path):
        print(f'스펙: 없음 ({path} 없음)')
        print('스펙 TOP: 없음')
        return
    text, enc = read(path)
    new = MD_COMMENT.sub(lambda m: ''.join(c for c in m.group(0) if c in '\r\n'), text)
    new = TRAIL.sub('', new)
    q = os.path.join(out, os.path.basename(path))
    os.makedirs(out, exist_ok=True)
    with open(q, 'w', encoding=enc, newline='') as f:
        f.write(new)

    top, items, sec = [], 0, None
    for line in new.splitlines():
        h = HEADING.match(line)
        if h and line.lstrip().startswith('#'):
            sec = h.group(1).strip().lower()
            continue
        if not line.strip():
            continue
        if sec == 'top':
            top.append(line.strip())
        else:
            items += 1
    rel = os.path.relpath(q).replace(os.sep, '/')
    if items:
        print(f'스펙: {rel} (주석 밖 내용 {items}줄)')
    else:
        print(f'스펙: {rel} (주석 밖 내용 없음 = 참고 스펙 없음)')
    print('스펙 TOP: ' + (' / '.join(top) if top else '없음'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', help='소스 폴더 (Verilog 사본을 만든다)')
    ap.add_argument('--spec', help='스펙 파일 (보통 analysis-spec.md, 주석을 지운 사본을 만든다)')
    ap.add_argument('--out', default='reports/.nocomment')
    a = ap.parse_args()
    if not a.src and not a.spec:
        sys.exit('오류: --src나 --spec 중 하나는 있어야 합니다')

    out = os.path.abspath(a.out)
    guard = os.path.abspath('reports/.nocomment')
    if not (out == guard or out.startswith(guard + os.sep)):
        sys.exit(f'오류: --out은 reports/.nocomment 아래여야 합니다: {a.out}')
    if a.src:
        src = os.path.abspath(a.src)
        if not os.path.isdir(src):
            sys.exit(f'오류: 소스 폴더가 없습니다: {a.src}')
        if out == src or out.startswith(src + os.sep) or src.startswith(out + os.sep):
            sys.exit('오류: --src와 --out이 겹칩니다')

    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    if a.spec:
        spec_copy(a.spec, out)
    if not a.src:
        return
    files = removed = kept = 0
    for root, dirs, names in os.walk(src):
        dirs.sort()
        for name in sorted(names):
            if not name.lower().endswith(EXTS):
                continue
            p = os.path.join(root, name)
            text, enc = read(p)
            new, r, k = strip(text)
            if new.count('\n') != text.count('\n'):
                sys.exit(f'오류: 줄 수가 달라졌습니다: {p}')
            q = os.path.join(out, os.path.relpath(p, src))
            os.makedirs(os.path.dirname(q), exist_ok=True)
            with open(q, 'w', encoding=enc, newline='') as f:
                f.write(new)
            files += 1; removed += r; kept += k
    print(f'사본: {a.out} (파일 {files}개, 지운 주석 {removed}개, 남긴 pragma {kept}개)')


if __name__ == '__main__':
    main()

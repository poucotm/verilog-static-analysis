#!/usr/bin/env python3
"""보고서 PDF를 글자로 점검한다 (verilog-report 5장 3단계). 토큰을 아끼기 위해 문제만 짧게 출력한다.

사용: python check_pdf.py <보고서 .md> <보고서 .pdf>
- pdftotext -raw 로 PDF 글자를 뽑아 다음을 확인한다.
  1. 쪽수, 글자가 거의 없는 중간 쪽 (빈 페이지, 큰 빈칸)
  2. 깨진 글자 (U+FFFD, 빈 네모)
  3. 요약 표: 이슈 줄마다 NO·심각도·제목·위치·보기가 한 줄에 있는지 (줄바꿈되면 한 줄에 다 나오지 않는다)
  4. 코드 블록(사이클 표, diff 등)의 줄 너비가 본문 폭을 넘는지 (오른쪽 잘림)
     PDF 글자 추출은 쪽 밖으로 나간 글자도 뽑으므로, md 줄의 표시 너비(한글 2칸)로 판단한다.
     본문 폭: 9pt(extarticle)에서 고정폭 139칸, 10pt에서 125칸 (build_pdf.sh와 같은 조건으로 고른다).
  5. md의 "보기" 링크(#v-001 등)마다 같은 이름의 제목 앵커({#v-001})가 있는지
- 출력 마지막 줄: "점검 결과: 문제 없음" 또는 "점검 결과: 문제 n건".
- pdftotext가 없으면 "pdftotext 없음"을 출력하고 종료 코드 2로 끝난다.
- 파일을 읽기만 한다.
"""
import re
import shutil
import subprocess
import sys
import unicodedata

BLANK_MIN = 40          # 공백을 뺀 글자가 이보다 적은 쪽은 빈 페이지로 본다
SKIP_FENCE = ('hier',)  # 설계 구조 그림 블록은 너비 검사에서 뺀다


def code_cols():
    """build_pdf.sh와 같은 조건: extarticle(9pt)을 쓸 수 있으면 139칸, 아니면 10pt 125칸."""
    if shutil.which('miktex'):
        return 139
    k = shutil.which('kpsewhich')
    if k and subprocess.run([k, 'extarticle.cls'], capture_output=True).stdout.strip():
        return 139
    return 125


def width(s):
    return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in s.expandtabs(8))


def squash(s):
    return re.sub(r'\s+', '', s)


def main():
    if len(sys.argv) != 3:
        sys.exit('사용: python check_pdf.py <보고서 .md> <보고서 .pdf>')
    md_path, pdf_path = sys.argv[1], sys.argv[2]
    if not shutil.which('pdftotext'):
        print('pdftotext 없음')
        sys.exit(2)
    raw = subprocess.run(['pdftotext', '-raw', '-enc', 'UTF-8', pdf_path, '-'],
                         capture_output=True).stdout.decode('utf-8', 'replace')
    md = open(md_path, encoding='utf-8').read()
    problems = 0

    # 1. 쪽수와 빈 페이지
    pages = raw.split('\f')
    if pages and not pages[-1].strip():
        pages = pages[:-1]
    print(f'쪽수: {len(pages)}')
    for i, p in enumerate(pages[:-1], 1):   # 마지막 쪽은 짧아도 정상
        n = len(squash(p))
        if n < BLANK_MIN:
            print(f'빈 페이지 의심: {i}쪽 (글자 {n}개)'); problems += 1

    # 2. 깨진 글자
    bad = raw.count('�') + raw.count('□')
    if bad:
        print(f'깨진 글자: {bad}개'); problems += 1

    # 3. 요약 표 (md의 이슈 줄 수와 PDF에서 한 줄로 나온 이슈 줄 수 비교)
    ids = re.findall(r'^\|\s*\[?(V-\d{3})', md, re.M)
    ids = list(dict.fromkeys(ids))
    lines = raw.splitlines()
    try:
        s = lines.index('요약')
        e = next(i for i in range(s + 1, len(lines)) if lines[i] == '상세')
    except (ValueError, StopIteration):
        s, e = 0, -1
        print('요약 표: "요약"/"상세" 제목을 찾지 못함'); problems += 1
    rows = [l for l in lines[s:e] if re.match(r'V-\d{3}\b', l)]
    ok = [l for l in rows if l.rstrip().endswith('보기')]
    if s < e and len(ok) != len(ids):
        problems += 1
        print(f'요약 표: 이슈 {len(ids)}개 중 한 줄로 나온 줄 {len(ok)}개 (제목·위치 줄바꿈 의심)')
        for l in rows:
            if l not in ok:
                print(f'  {l.strip()[:60]}')

    # 4. 코드 블록 줄 너비 (오른쪽 잘림)
    cols = code_cols()
    cut, fence = [], None
    for no, line in enumerate(md.splitlines(), 1):
        m = re.match(r'^\s*```(\S*)', line)
        if m:
            fence = None if fence is not None else m.group(1)
            continue
        if fence is None or fence in SKIP_FENCE:
            continue
        w = width(line.rstrip())
        if w > cols:
            cut.append((no, w))
    if cut:
        problems += 1
        print(f'코드 줄이 본문 폭({cols}칸)을 넘음 (오른쪽 잘림) {len(cut)}줄: '
              + ', '.join(f'md {no}({w}칸)' for no, w in cut[:10]))

    # 5. 보기 링크 대상
    links = set(re.findall(r'\]\(#([\w-]+)\)', md))
    anchors = set(re.findall(r'\{#([\w-]+)\}', md))
    lost = sorted(links - anchors)
    if lost:
        problems += 1
        print('보기 링크 대상 없음: ' + ', '.join(lost))

    print('점검 결과: ' + (f'문제 {problems}건' if problems else '문제 없음'))


if __name__ == '__main__':
    main()

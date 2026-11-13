#!/usr/bin/env bash
# 사용법: build_pdf.sh <보고서.md>
# 필요: pandoc, xelatex, 한글 폰트 (Noto Sans CJK KR / NanumGothic / Malgun Gothic 중 하나)
# 종료 코드: 0 성공, 1 입력 오류, 2 도구 없음, 3 한글 폰트 없음, 그 밖은 pandoc/LaTeX 오류
# Linux, macOS, Windows(Git Bash) 지원
set -euo pipefail

src="${1:?사용법: build_pdf.sh <보고서.md>}"
[ -f "$src" ] || { echo "파일 없음: $src" >&2; exit 1; }
out="${src%.md}.pdf"
dir="$(cd "$(dirname "$0")/.." && pwd)"

# 방금 설치해 PATH에 아직 반영되지 않은 경우를 위해 알려진 설치 경로를 추가
# (Git Bash의 LOCALAPPDATA는 C:\... 형식이라 /c/... 로 바꿔야 PATH에 넣을 수 있다)
lad="${LOCALAPPDATA:-}"
if [ -n "$lad" ] && command -v cygpath >/dev/null 2>&1; then lad="$(cygpath -u "$lad")"; fi
for d in "$lad/Pandoc" "$lad/Programs/MiKTeX/miktex/bin/x64" \
         "/c/Program Files/Pandoc" "/c/Program Files/MiKTeX/miktex/bin/x64" \
         /Library/TeX/texbin /usr/local/bin /opt/homebrew/bin; do
  if [ -d "$d" ]; then PATH="$PATH:$d"; fi
done

missing=()
for t in pandoc xelatex; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "필요한 도구 없음: ${missing[*]}" >&2
  echo "PDF 미생성, Markdown 보고서: $src" >&2
  exit 2
fi

# fc-list가 없는 환경(Windows Git Bash)은 폰트 파일로 확인
font_dirs=(/c/Windows/Fonts "$lad/Microsoft/Windows/Fonts" /usr/share/fonts "$HOME/.local/share/fonts" /Library/Fonts "$HOME/Library/Fonts")

font_file_pattern() {
  case "$1" in
    'Sarasa Gothic K')       echo 'Sarasa*.tt[fc]' ;;
    'Sarasa UI K')           echo 'SarasaUi*.tt[fc]' ;;
    'Spoqa Han Sans Neo')    echo 'SpoqaHanSansNeo-Regular.*' ;;
    'Noto Sans KR')          echo 'NotoSansKR-Regular.*' ;;
    'Malgun Gothic')         echo 'malgun.ttf' ;;
    'NanumGothic')           echo 'NanumGothic.ttf' ;;
    'Roboto Condensed')      echo 'RobotoCondensed-Regular.ttf' ;;
    'Arial Narrow')          echo 'ARIALN.TTF' ;;
    'DejaVu Sans Condensed') echo 'DejaVuSansCondensed.ttf' ;;
    'Ubuntu Condensed')      echo 'UbuntuCondensed-Regular.ttf' ;;
    'NanumGothicCoding')     echo 'NanumGothicCoding*.ttf' ;;
    'D2Coding')              echo 'D2Coding*.tt[fc]' ;;
    'Noto Sans CJK KR')      echo 'NotoSansCJK*.tt[fc]' ;;
    'Noto Sans Mono CJK KR') echo 'NotoSansMonoCJK*.tt[fc]' ;;
    'Consolas')              echo 'consola.ttf' ;;
    'Cascadia Mono')         echo 'CascadiaMono*.ttf' ;;
    'DejaVu Sans Mono')      echo 'DejaVuSansMono.ttf' ;;
    *)                       echo '' ;;
  esac
}

has_font() {
  local name="$1" pat d
  if command -v fc-list >/dev/null 2>&1; then
    fc-list : family 2>/dev/null | grep -qi "$name" && return 0
  fi
  pat="$(font_file_pattern "$name")"
  [ -n "$pat" ] || return 1
  for d in "${font_dirs[@]}"; do
    [ -d "$d" ] || continue
    [ -n "$(find "$d" -maxdepth 3 -iname "$pat" -print -quit 2>/dev/null)" ] && return 0
  done
  return 1
}

pick_font() {
  local f
  for f in "$@"; do
    if has_font "$f"; then echo "$f"; return; fi
  done
  echo ""
}

STRETCH=0.88        # 본문 한글 가로 압축 비율 (좁은 느낌)
MONOSCALE=0.85      # 코드블록 글자 크기 (condensed 본문과 맞춤)

# 한글/영문 폰트 분리 방식
#  xetexko (우선): 한국어 전용. 원본 띄어쓰기를 그대로 지킨다. MiKTeX는 변환 중 자동 설치된다.
#  xeCJK  (대체): xetexko가 없을 때. 영문·한글 사이에 자동 공백이 들어갈 수 있다.
#  없음         : 한글 폰트 하나로 영문까지 쓴다.
komode=none
if kpsewhich xetexko.sty >/dev/null 2>&1 || command -v miktex >/dev/null 2>&1; then
  komode=xetexko
elif kpsewhich xeCJK.sty >/dev/null 2>&1; then
  komode=xecjk
fi

# 번들 글꼴: assets/fonts/에 아래 파일이 모두 있으면 PC에 설치된 글꼴 대신 이 파일을 경로로 직접 쓴다.
# 어느 PC에서나 같은 글꼴로 나오고, 글꼴을 설치할 필요가 없다. (모두 재배포 가능한 OFL/Apache 글꼴)
#   본문 영문 Roboto Condensed / 본문 한글 Pretendard / 코드 D2Coding (한글이 정확히 영문 2칸)
FONTDIR="$dir/assets/fonts"
bundle=0
if [ "$komode" = xetexko ]; then
  bundle=1
  for f in Pretendard-Regular.otf Pretendard-Bold.otf RobotoCondensed-Regular.ttf RobotoCondensed-Bold.ttf \
           D2Coding-Regular.ttf D2Coding-Bold.ttf; do
    [ -f "$FONTDIR/$f" ] || bundle=0
  done
fi

if [ "$bundle" = 1 ]; then
  mainfont="Pretendard"; latinfont="Roboto Condensed"; monofont="D2Coding"; komono="D2Coding"; kostretch=$STRETCH
  MONOSCALE=0.95    # D2Coding은 Consolas보다 글자 폭이 좁아 조금 키운다
else
  [ -d "$FONTDIR" ] && echo "경고: assets/fonts의 번들 글꼴이 빠져 있거나 xetexko가 없어 PC에 설치된 글꼴을 씀" >&2

  # 한글 폰트: narrow 계열을 먼저 찾고, 없으면 일반 한글 폰트를 가로 88%로 압축(FakeStretch)해 쓴다.
  kofont="$(pick_font 'Sarasa Gothic K' 'Sarasa UI K')"
  kostretch=1
  if [ -z "$kofont" ]; then
    kofont="$(pick_font 'Pretendard' 'Spoqa Han Sans Neo' 'Noto Sans KR' 'Noto Sans CJK KR' 'NanumGothic' 'Malgun Gothic' 'Apple SD Gothic Neo')"
    kostretch=$STRETCH
  fi
  if [ -z "$kofont" ]; then
    echo "한글 폰트를 찾지 못함 (Malgun Gothic, NanumGothic, Noto Sans CJK KR 중 하나 필요)" >&2
    echo "PDF 미생성, Markdown 보고서: $src" >&2
    exit 3
  fi
  mainfont="$kofont"

  # 영문: 한글을 따로 지정할 수 있으면 condensed 영문 폰트를 쓴다.
  latinfont=""
  [ "$komode" != none ] && latinfont="$(pick_font 'Roboto Condensed' 'Arial Narrow' 'DejaVu Sans Condensed' 'Ubuntu Condensed')"

  # 코드블록(사이클 표, diff)은 정렬을 위해 반드시 고정폭 폰트를 쓴다.
  # 한글 고정폭 폰트가 있으면 그것을 쓰고, 없으면 영문 고정폭 + 한글만 본문 한글 폰트로 대체한다.
  monofont="$(pick_font 'D2Coding' 'NanumGothicCoding' 'Noto Sans Mono CJK KR')"
  komono="$monofont"
  if [ -z "$monofont" ]; then
    monofont="$(pick_font 'Consolas' 'Cascadia Mono' 'DejaVu Sans Mono' 'Menlo')"
    komono="$mainfont"
    if [ -z "$monofont" ] || [ "$komode" = none ]; then
      echo "경고: 고정폭 폰트 조합을 만들 수 없어 코드블록 정렬이 어긋날 수 있음" >&2
      monofont="$mainfont"
    fi
  fi
fi

# 체크박스를 기호로 치환한 임시 파일 (mktemp --suffix는 환경마다 달라 쓰지 않음)
tmp="$(mktemp "${TMPDIR:-/tmp}/verilog_report.XXXXXX")"
kohdr="$(mktemp "${TMPDIR:-/tmp}/verilog_kofont.XXXXXX")"
trap 'rm -f "$tmp" "$kohdr"' EXIT
# Windows용 pandoc.exe·xelatex에는 C:/... 형식 경로를 넘긴다
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

# xetexko용 한글 폰트 설정. 화살표는 condensed 영문 폰트에 없을 수 있어 수학 기호로 그린다.
if [ "$komode" = xetexko ]; then
  {
    printf '%s\n' '\usepackage{xetexko}'
    if [ "$bundle" = 1 ]; then
      # 번들 글꼴을 파일 경로로 지정 (경로에 공백이 있어도 되도록 중괄호로 감싼다)
      fp="$(native "$FONTDIR")/"
      printf '\\setmainfont{RobotoCondensed}[Path={%s},Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold]\n' "$fp"
      printf '\\setsansfont{RobotoCondensed}[Path={%s},Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold]\n' "$fp"
      printf '\\setmonofont{D2Coding}[Path={%s},Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold,Scale=%s]\n' "$fp" "$MONOSCALE"
      printf '\\setmainhangulfont{Pretendard}[Path={%s},Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,FakeStretch=%s]\n' "$fp" "$kostretch"
      printf '\\setsanshangulfont{Pretendard}[Path={%s},Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,FakeStretch=%s]\n' "$fp" "$kostretch"
      printf '\\setmonohangulfont{D2Coding}[Path={%s},Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold,Scale=%s]\n' "$fp" "$MONOSCALE"
    else
      printf '\\setmainhangulfont{%s}[FakeStretch=%s]\n' "$kofont" "$kostretch"
      printf '\\setsanshangulfont{%s}[FakeStretch=%s]\n' "$kofont" "$kostretch"
      # 코드블록 한글은 영문 고정폭과 같은 크기로. 열 맞춤(한글 2칸)은 code-block.lua가 글자 칸 단위로 처리한다
      printf '\\setmonohangulfont{%s}[Scale=%s]\n' "$komono" "$MONOSCALE"
    fi
    printf '%s\n' '\usepackage{newunicodechar}'
    printf '%s\n' '\newunicodechar{→}{\ensuremath{\rightarrow}}' '\newunicodechar{←}{\ensuremath{\leftarrow}}'
    printf '%s\n' '\newunicodechar{↑}{\ensuremath{\uparrow}}' '\newunicodechar{↓}{\ensuremath{\downarrow}}'
  } > "$kohdr"
fi
sed -e 's/^\([[:space:]]*\)- \[ \] /\1- ☐ /' -e 's/^\([[:space:]]*\)- \[[xX]\] /\1- ☑ /' "$src" > "$tmp"

args=(
  "$(native "$tmp")" -f markdown -o "$(native "$out")"
  --pdf-engine=xelatex
  --include-in-header="$(native "$kohdr")"
  --include-in-header="$(native "$dir/assets/header.tex")"
  --lua-filter="$(native "$dir/assets/issue-head.lua")"   # ### V-001 제목 → [번호 | 제목] 표 (먼저 실행)
  --lua-filter="$(native "$dir/assets/table-grid.lua")"   # 격자 표, 제목 박스, 제목 앞 공간 확보
  --lua-filter="$(native "$dir/assets/die-layout.lua")"   # ```hier 블록 → 설계 구조 그림
  --lua-filter="$(native "$dir/assets/code-block.lua")"   # 코드블록 글자 칸 정렬(한글 2칸), ```diff 색칠
  -V fontfamily=fontspec   # lmodern 패키지가 없는 환경 대응
  -V geometry:margin=12mm
  -V papersize=a4
  -V colorlinks=true
)
# 본문 9pt (extarticle). 없는 환경이면 10pt. MiKTeX는 변환 중 자동 설치된다.
if kpsewhich extarticle.cls >/dev/null 2>&1 || command -v miktex >/dev/null 2>&1; then
  args+=(-V documentclass=extarticle -V fontsize=9pt)
else
  args+=(-V fontsize=10pt)
fi
# 번들 글꼴이면 영문·고정폭 글꼴도 위 헤더에서 경로로 지정했으므로 pandoc 변수로 넘기지 않는다
if [ "$bundle" = 0 ]; then
  args+=(-V monofont="$monofont" -V monofontoptions="Scale=$MONOSCALE")
  if [ -n "$latinfont" ]; then
    args+=(-V mainfont="$latinfont")
  else
    args+=(-V mainfont="$mainfont")
    [ "$kostretch" != 1 ] && args+=(-V mainfontoptions="FakeStretch=$kostretch")
  fi
fi
# pandoc 3.8 이후는 --syntax-highlighting, 이전은 --highlight-style
if pandoc --help 2>/dev/null | grep -q -- '--syntax-highlighting'; then
  args+=(--syntax-highlighting=tango)
else
  args+=(--highlight-style=tango)
fi
# xeCJK(대체 경로): 코드블록 안 한글 글꼴까지 지정
if [ "$komode" = xecjk ]; then
  args+=(-V CJKmainfont="$mainfont" -V CJKmonofont="$komono")
  [ "$kostretch" != 1 ] && args+=(-V CJKoptions="FakeStretch=$kostretch")
fi
src_label="PC 설치 글꼴"; [ "$bundle" = 1 ] && src_label="번들 글꼴(assets/fonts)"
echo "폰트: 한글 $mainfont (가로 ${kostretch}, $komode), 영문 ${latinfont:-$mainfont}, 고정폭 $monofont — $src_label" >&2

pandoc "${args[@]}"
echo "생성: $out"

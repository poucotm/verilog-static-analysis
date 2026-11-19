#!/usr/bin/env bash
# PDF 보고서가 있는 폴더를 열고 그 PDF를 선택해 준다 (verilog-report 5장).
# 사용법: bash .claude/skills/verilog-report/scripts/open_folder.sh reports/pdf/<top>_report_<date>.pdf
# - Windows(Git Bash): 탐색기에서 PDF 선택, macOS: Finder에서 PDF 선택, Linux: 폴더만 연다.
# - 창을 열 수 없는 환경이면 "폴더 열기 생략"을 출력하고 0으로 끝난다 (흐름을 막지 않는다).

pdf="$1"
if [ -z "$pdf" ] || [ ! -f "$pdf" ]; then
  echo "오류: PDF 파일이 없습니다: $pdf" >&2
  exit 1
fi
dir="$(cd "$(dirname "$pdf")" && pwd)"
file="$dir/$(basename "$pdf")"

skip() { echo "폴더 열기 생략: $dir ($1)"; exit 0; }

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v cygpath >/dev/null 2>&1 || skip "cygpath 없음"
    # explorer.exe는 성공해도 종료 코드 1을 돌려준다
    MSYS2_ARG_CONV_EXCL='*' explorer.exe "/select,$(cygpath -w "$file")" >/dev/null 2>&1
    ;;
  Darwin)
    open -R "$file" >/dev/null 2>&1 || skip "open 실패"
    ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null && command -v explorer.exe >/dev/null 2>&1; then
      explorer.exe "/select,$(wslpath -w "$file")" >/dev/null 2>&1   # WSL
    else
      [ -n "$DISPLAY$WAYLAND_DISPLAY" ] || skip "화면 없음"
      command -v xdg-open >/dev/null 2>&1 || skip "xdg-open 없음"
      xdg-open "$dir" >/dev/null 2>&1 &
    fi
    ;;
  *)
    skip "지원하지 않는 OS"
    ;;
esac
echo "폴더 열기: $dir"
exit 0

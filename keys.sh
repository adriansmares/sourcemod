#!/bin/bash
# Which source changes reach the main key, for each way of hashing the -E output.
# Usage: keys.sh CC   (cl, clang-cl or gcc)
set -u
CC=$1
work=$PWD/keys; rm -rf "$work"; mkdir -p "$work"; cd "$work"

pp() {  # pp FLAG FILE: preprocess FILE from the current directory
  case $CC in
    gcc) if [ "$1" = EP ]; then g++ -std=c++20 -E -P "$2"; else g++ -std=c++20 -E "$2"; fi ;;
    *) "$CC" -nologo -std:c++20 -EHsc "-$1" "$2" 2>/dev/null ;;
  esac
}
marker='^#(line)? *[0-9]+'
strip()  { grep -avE "$marker"; }                                       # drop the markers
nopath() { sed -E 's/^#(line)? *([0-9]+) *"[^"]*".*/#line \2/'; }       # keep the numbers, drop the paths

src='#include <source_location>
#include "a.h"
#include "b.h"
const char *file() { return std::source_location::current().file_name(); }
'
# A line that moves from the end of a.h to the start of b.h: same tokens, other file and line.
mk() {  # mk DIR VARIANT
  mkdir -p "$1"
  printf '%s' "$src" > "$1/main.cpp"
  if [ "$2" = moved ]; then
    printf '// a\n' > "$1/a.h"
    printf 'inline int where() { return std::source_location::current().line(); }\n// b\n' > "$1/b.h"
  else
    printf '// a\ninline int where() { return std::source_location::current().line(); }\n' > "$1/a.h"
    printf '// b\n' > "$1/b.h"
  fi
}
mk base base
mk checkout2 base                          # the same tree in another directory
mk moved moved
mk shifted base; { printf '\n'; cat shifted/main.cpp; } > t && mv t shifted/main.cpp   # one more blank line at the top
mk renamed base; mv renamed/main.cpp renamed/other.cpp

key() {  # key DIR FILE MODE: the bytes the main key would hash
  case $3 in
    EP) (cd "$1" && pp EP "$2") ;;
    E) (cd "$1" && pp E "$2") ;;
    strip) (cd "$1" && pp E "$2" | strip) ;;
    nopath) (cd "$1" && pp E "$2" | nopath) ;;
  esac | tr -d '\r' | sha256sum | cut -c1-12
}
printf '%-26s %-14s %-14s %-14s %-14s\n' "change vs base" EP "E (as is)" "E stripped" "E paths only"
for c in "checkout2 main.cpp" "moved main.cpp" "shifted main.cpp" "renamed other.cpp"; do
  set -- $c; row=$1
  for m in EP E strip nopath; do
    if [ "$(key base main.cpp $m)" = "$(key $1 $2 $m)" ]; then r=same; else r=differs; fi
    row="$row|$r"
  done
  echo "$row" | awk -F'|' '{printf "%-26s %-14s %-14s %-14s %-14s\n",$1,$2,$3,$4,$5}'
done
echo
if [ "$(key base main.cpp EP)" = "$(key base main.cpp strip)" ]; then echo "E stripped == EP: yes"; else
  echo "E stripped == EP: no"; diff <(cd base && pp EP main.cpp | tr -d '\r') <(cd base && pp E main.cpp | strip | tr -d '\r') | head -8; fi
echo "blank lines in EP output for main.cpp: $(cd base && pp EP main.cpp | tr -d '\r' | grep -c '^$')"

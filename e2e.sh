#!/bin/bash
# End to end through sccache: does a cached object come back with the wrong source location?
# Usage: e2e.sh SCCACHE
set -u
S=$1
export SCCACHE_DIR=$RUNNER_TEMP/cache SCCACHE_IDLE_TIMEOUT=0
"$S" --stop-server >/dev/null 2>&1; "$S" --start-server >/dev/null
cc() { "$S" cl -nologo -std:c++20 -EHsc -c "$1" "-Fo$2" >/dev/null; }
run() { cl -nologo "$1" "-Fe$2" >/dev/null && "./$2"; }
hits() { "$S" --show-stats --stats-format=json | python -c "import sys,json; s=json.load(sys.stdin)['stats']; print('hits', s['cache_hits']['counts'].get('C/C++',0), 'misses', s['cache_misses']['counts'].get('C/C++',0))"; }
work=$PWD/e2e; rm -rf "$work"; mkdir -p "$work"; cd "$work"

main='#include <source_location>
#include <cstdio>
#include "a.h"
#include "b.h"
int main() { std::printf("file=%s line=%d\n", std::source_location::current().file_name(), where()); }
'
printf '%s' "$main" > a.cpp
printf '// a\ninline int where() { return std::source_location::current().line(); }\n' > a.h
printf '// b\n' > b.h

echo "== 1. a.cpp, then the same source as b.cpp (correct: file=b.cpp)"
cc a.cpp a.obj && run a.obj a.exe; hits
cp a.cpp b.cpp
cc b.cpp b.obj && run b.obj b.exe; hits

echo "== 2. where() moves from a.h line 2 to b.h line 1 (correct: line=1)"
printf '// a\n' > a.h
printf 'inline int where() { return std::source_location::current().line(); }\n// b\n' > b.h
cc a.cpp a2.obj && run a2.obj a2.exe; hits
"$S" --stop-server >/dev/null 2>&1 || true

#!/bin/bash
# Does renaming a file return a stale object? Usage: rename.sh SCCACHE DIRECT(true|false)
set -u
S=$1
export SCCACHE_DIR=$RUNNER_TEMP/cache-$2 SCCACHE_DIRECT=$2 SCCACHE_IDLE_TIMEOUT=0
"$S" --stop-server >/dev/null 2>&1; "$S" --start-server >/dev/null
cc() { "$S" cl -nologo -std:c++20 -EHsc -c "$1" "-Fo$2" >/dev/null; }
run() { cl -nologo "$1" "-Fe$2" >/dev/null && "./$2"; }
hits() { "$S" --show-stats --stats-format=json | python -c "import sys,json; s=json.load(sys.stdin)['stats']; print('  hits', s['cache_hits']['counts'].get('C/C++',0), 'misses', s['cache_misses']['counts'].get('C/C++',0))"; }
work=$PWD/rename-$2; rm -rf "$work"; mkdir -p "$work"; cd "$work"

echo "== source rename: a.cpp, then b.cpp (correct: b.cpp)"
printf '#include <cstdio>\n#include <source_location>\nint main() { std::printf("%%s\\n", std::source_location::current().file_name()); }\n' > a.cpp
cc a.cpp a.obj && run a.obj a.exe; hits
cp a.cpp b.cpp
cc b.cpp b.obj && run b.obj b.exe; hits

echo "== header rename: a.h, then c.h (correct: c.h)"
printf '#include <source_location>\ninline const char *where() { return std::source_location::current().file_name(); }\n' > a.h
printf '#include <cstdio>\n#include "a.h"\nint main() { std::printf("%%s\\n", where()); }\n' > main.cpp
cc main.cpp m1.obj && run m1.obj m1.exe; hits
mv a.h c.h; sed -i 's/a\.h/c.h/' main.cpp
cc main.cpp m2.obj && run m2.obj m2.exe; hits
"$S" --stop-server >/dev/null 2>&1 || true

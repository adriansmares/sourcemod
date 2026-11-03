#!/bin/bash
# Do /d1trimfile or /pathmap change how cl.exe -E spells the paths in its #line markers?
set -u
CC=$1
work=$PWD/trim; rm -rf "$work"; mkdir -p "$work/src" "$work/include"; cd "$work"
printf '#include "foo.h"\n#include <bar.h>\nconst char *f = __FILE__;\n' > src/main.c
printf 'const char *foo = __FILE__;\n' > src/foo.h
printf '#include "bar_impl.h"\n' > include/bar.h
printf 'const char *bar = __FILE__;\n' > include/bar_impl.h
root=$(cygpath -w "$PWD")
markers() { tr -d '\r' | grep -aE '^#(line)? *[0-9]+ "|__FILE__|= "' | grep -av 'Program Files' | sed -E 's/^#(line)? *([0-9]+) /#\1 \2 /' | sort -u; }
run() {  # run LABEL ARGS...
  echo "== $1"; shift
  "$CC" -nologo -E src/main.c -Iinclude "$@" 2>&1 | markers
}
run "plain"
run "/d1trimfile:$root\\" "/d1trimfile:$root\\"
run "/pathmap:$root=." "/pathmap:$root=."
run "/pathmap:$root\\=" "/pathmap:$root\\="
run "/FC" /FC

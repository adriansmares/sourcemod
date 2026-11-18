#!/usr/bin/env bash
# Compiles one source with /sourceDependencies in two directories and shows
# which dependency file each cache hit leaves behind.
set -u
sccache=$1
work="$RUNNER_TEMP/probe"
mkdir -p "$work" && cd "$work" || exit
export SCCACHE_DIR="$work/cache"

"$sccache" --version
for d in a b; do
  mkdir -p "$d"
  printf '#include <stdio.h>\nvoid deps(void) { puts("deps"); }\n' > "$d/deps.c"
  touch -d '1 minute ago' "$d/deps.c"
done

show() {
  if [ -f "$1" ]; then
    jq -c '{Source: .Data.Source, Includes: (.Data.Includes | length), First: .Data.Includes[0]}' "$1" | sed 's/^/    /'
  else
    echo "    no dependency file"
  fi
}

compile() {
  local dir=$1
  shift
  (cd "$dir" && rm -f deps.json deps.obj && "$@" "$sccache" cl -nologo -c deps.c -Fodeps.obj -sourceDependencies deps.json > /dev/null 2>&1
    echo "  $dir: exit $?, object $([ -s deps.obj ] && echo written || echo missing)")
  show "$dir/deps.json"
}

server() {
  "$sccache" --stop-server > /dev/null 2>&1
  SCCACHE_LOG=debug SCCACHE_ERROR_LOG="$work/$1.log" "$sccache" --start-server > /dev/null 2>&1
}

decisions() {
  grep -a -o -E 'Preprocessor cache (hit|miss)|Cache (hit|miss) in|Cannot use preprocessor cache because of.*|preprocess: .*' "$work/$1.log" |
    sed -E 's/(preprocess: ).*"(-EP?)".*/\1\2/' | cut -c1-200 | sed 's/^/    /'
}

stats() {
  "$sccache" --show-stats | grep -E '^(Compile requests  |Cache hits  |Cache misses  )' | sed 's/^/    /'
}

echo "#### preprocessor cache on: a, a, b, b"
server first
compile a env
compile a env
compile b env
compile b env
stats
decisions first

echo "#### objects evicted, preprocessor entries kept: a"
"$sccache" --stop-server > /dev/null 2>&1
find "$SCCACHE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name preprocessor -exec rm -rf {} +
ls "$SCCACHE_DIR"
server second
compile a env
decisions second

echo "#### SCCACHE_DIRECT=false: a, b, b"
server third
compile a env SCCACHE_DIRECT=false
compile b env SCCACHE_DIRECT=false
compile b env SCCACHE_DIRECT=false
stats
decisions third
"$sccache" --stop-server > /dev/null 2>&1

echo "#### what cl.exe itself writes in a and b"
for d in a b; do
  (cd "$d" && cl -nologo -E deps.c 2> /dev/null > "../$d.i"
    cl -nologo -c deps.c -Fodirect.obj -sourceDependencies direct.json > /dev/null 2>&1)
  show "$d/direct.json"
done
grep -a -m 2 '^#line' a.i | sed 's/^/    /'
if cmp -s a.i b.i; then
  echo "    cl -E output is identical in a and b"
else
  echo "    cl -E output differs between a and b:"
  diff a.i b.i | head -n 6 | sed 's/^/      /'
fi
exit 0

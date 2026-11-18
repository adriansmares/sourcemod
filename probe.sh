#!/usr/bin/env bash
# Prints the dependency flags that default MSBuild and CMake builds pass to cl.exe.
set -u
root=$PWD
pattern='[-/](sourceDependencies(:directives)?|scanDependencies|showIncludes)'

flags() {
  local found
  found=$(grep -a -o -i -E "$pattern" "$1" | sort | uniq -c)
  echo "${found:-      none of sourceDependencies, scanDependencies, showIncludes}"
}

cl_lines() {
  grep -a -i -E 'cl\.exe"? .*/c ' "$1" | sed 's/^ */    /' | cut -c1-1600
}

echo "#### versions"
msbuild.exe -nologo -version
echo
cl 2>&1 | head -1
echo "VCToolsVersion=${VCToolsVersion:-} VisualStudioVersion=${VisualStudioVersion:-}"
cmake --version | head -1
echo "ninja $(ninja --version)"

msb() {
  local name=$1
  shift
  local dir="$RUNNER_TEMP/msb-$name"
  mkdir -p "$dir" && cp msbuild/* "$dir/" && cd "$dir" || return
  echo "#### msbuild: $name $*"
  msbuild.exe probe.vcxproj -nologo -m:1 -v:detailed -p:Configuration=Release -p:Platform=x64 "$@" > build.log 2>&1
  echo "  exit: $?"
  echo "  cl command lines:"
  cl_lines build.log
  echo "  dependency flags in the build log:"
  flags build.log
  find . -iname 'CL.command.1.tlog' | while read -r t; do
    echo "  $t:"
    iconv -f UTF-16LE -t UTF-8 "$t" | tr -d '\r' | sed 's/^/    /' | cut -c1-1600
  done
  echo "  json files written:"
  find . -iname '*.json' | sed 's/^/    /'
  cd "$root" || exit
}

msb default
msb cpp20 -p:ProbeStd=stdcpp20
msb cpp20-module -p:ProbeStd=stdcpp20 -p:ProbeModule=true
msb cpplatest -p:ProbeStd=stdcpplatest

echo "#### msbuild: how the targets handle SourceDependencies"
cd "$RUNNER_TEMP/msb-default" || exit
msbuild.exe probe.vcxproj -nologo -pp:pp.xml -p:Configuration=Release -p:Platform=x64 > /dev/null 2>&1
grep -a -n -i -E 'SourceDependenc|ScanSourceForModuleDependencies|scanDependencies' pp.xml | cut -c1-420 | head -120
cd "$root" || exit

cm_ninja() {
  local name=$1 std=$2 module=$3
  local dir="$RUNNER_TEMP/cm-ninja-$name"
  echo "#### cmake + ninja: $name (C++$std, module=$module)"
  cmake -S cmake -B "$dir" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=cl \
    -DPROBE_STD="$std" -DPROBE_MODULE="$module" > "$dir.log" 2>&1
  local status=$?
  echo "  configure exit: $status"
  [ "$status" = 0 ] || tail -n 15 "$dir.log"
  ninja -C "$dir" -t commands > "$dir.cmds" 2>&1
  echo "  commands:"
  sed 's/^/    /' "$dir.cmds" | cut -c1-1200
  echo "  dependency flags:"
  flags "$dir.cmds"
  echo "  deps rules:"
  find "$dir" -name '*.ninja' -exec grep -h -E '^ *deps = ' {} + | sort | uniq -c
}

cm_ninja cpp17 17 OFF
cm_ninja cpp20 20 OFF
cm_ninja cpp20-module 20 ON

cm_vs() {
  local name=$1 std=$2 module=$3
  local dir="$RUNNER_TEMP/cm-vs-$name"
  echo "#### cmake + visual studio generator: $name (C++$std, module=$module)"
  cmake -S cmake -B "$dir" -A x64 -DPROBE_STD="$std" -DPROBE_MODULE="$module" > "$dir.log" 2>&1
  local status=$?
  echo "  configure exit: $status"
  [ "$status" = 0 ] || tail -n 15 "$dir.log"
  grep -a -m1 'Building for' "$dir.log"
  cmake --build "$dir" --config Release -- -m:1 -v:detailed > "$dir.build.log" 2>&1
  echo "  build exit: $?"
  echo "  cl command lines:"
  cl_lines "$dir.build.log"
  echo "  dependency flags in the build log:"
  flags "$dir.build.log"
}

cm_vs cpp17 17 OFF
cm_vs cpp20 20 OFF
cm_vs cpp20-module 20 ON
exit 0

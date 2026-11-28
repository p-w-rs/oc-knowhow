#!/usr/bin/env bash
# Builds and runs all benchmarks, writing one markdown file: ./run.sh <machine-name> [quick]
#   ./run.sh mac-m2max            -> results/mac-m2max.md
#   ./run.sh powerslabs quick     -> a short test run (3 runs, smaller sizes)
# Environment (Linux):
#   SINGLE_CPU   CPU for single-thread benchmarks (default 2)
#   THREAD_CPUS  CPUs for threaded benchmarks, all of one core type (default 0-7)
#   THREADS      thread counts for the false-sharing benchmark (default "2 4 8"; macOS "2 4")
#   ALLOC_THREADS thread count for the allocator thread test (default 4)
# macOS has no pinning: run when the machine is otherwise idle and look at the load line.
set -euo pipefail
cd "$(dirname "$0")"

name="${1:?usage: ./run.sh <machine-name> [quick]}"
mode="${2:-}"
os="$(uname -s)"
if [ "$os" = Darwin ]; then
  jai="${JAI:-$HOME/jai/current/bin/jai-macos}"
  threads="${THREADS:-2 4}"
else
  jai="${JAI:-$HOME/jai/current/bin/jai-linux}"
  threads="${THREADS:-2 4 8}"
fi
alloc_threads="${ALLOC_THREADS:-4}"

mkdir -p results
out="results/$name.md"
[ "$mode" = quick ] && out="results/$name-quick.md"

"$jai" build.jai -quiet

load() { uptime | sed 's/.*load average[s]*: //'; }

{
  echo "# Cache and layout benchmarks: $name"
  echo
  echo "- Date: $(date '+%d %b %Y %H:%M %Z')"
  if [ "$os" = Darwin ]; then
    echo "- CPU: $(sysctl -n machdep.cpu.brand_string); $(sysctl -n hw.perflevel0.physicalcpu) P + $(sysctl -n hw.perflevel1.physicalcpu) E cores"
    echo "- Caches (sysctl): line $(sysctl -n hw.cachelinesize) B; P-core L1d $(( $(sysctl -n hw.perflevel0.l1dcachesize) / 1024 )) KiB, L2 $(( $(sysctl -n hw.perflevel0.l2cachesize) / 1048576 )) MiB per $(sysctl -n hw.perflevel0.cpusperl2) P-cores; E-core L1d $(( $(sysctl -n hw.perflevel1.l1dcachesize) / 1024 )) KiB, L2 $(( $(sysctl -n hw.perflevel1.l2cachesize) / 1048576 )) MiB; page $(sysctl -n hw.pagesize) B"
    echo "- OS: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(( $(sysctl -n hw.memsize) / 1073741824 )) GiB RAM"
    echo "- Pinning: none (macOS has no user-level CPU pinning)"
  else
    echo "- CPU: $(lscpu | sed -n 's/^Model name: *//p'), $(nproc) CPUs"
    c0=/sys/devices/system/cpu/cpu${SINGLE_CPU:-2}/cache
    echo "- Caches (sysfs, CPU ${SINGLE_CPU:-2}): line $(cat $c0/index0/coherency_line_size) B; L1d $(cat $c0/index0/size), L2 $(cat $c0/index2/size), L3 $(cat $c0/index3/size 2>/dev/null || echo none); page $(getconf PAGESIZE) B"
    echo "- OS: $(. /etc/os-release; echo "$PRETTY_NAME"), kernel $(uname -r), $(free -g | awk '/^Mem:/{print $2}') GiB RAM"
    echo "- Pinning: single-thread benchmarks \`taskset -c ${SINGLE_CPU:-2}\`, threaded \`taskset -c ${THREAD_CPUS:-0-7}\` (thread counts: $threads; allocator test: $alloc_threads)"
  fi
  echo "- Jai: $(sed -n 's/^Version: \(beta [0-9.]*\).*/\1/p' "$(dirname "$jai")/../CHANGELOG.txt" | head -1)"
  echo "- Build: build.jai = set_optimization(.VERY_OPTIMIZED) + stack_trace = false (what \`jai -o\` sets)"
  echo "- Method: one warm-up run, then the median (and min) of the timed runs; every kernel feeds a printed checksum"
  echo "- Load average at start: $(load)"
  echo
} > "$out"

quick_arg=""
[ "$mode" = quick ] && quick_arg=quick

run() {   # run single|threaded <program> [args...]   (works with macOS's bash 3.2 too)
  local kind=$1 program=$2; shift 2
  echo "running $program $*" >&2
  {
    if [ "$os" = Darwin ]; then
      "./bin/$program" "$@" $quick_arg
    elif [ "$kind" = single ]; then
      taskset -c "${SINGLE_CPU:-2}" "./bin/$program" "$@" $quick_arg
    else
      taskset -c "${THREAD_CPUS:-0-7}" "./bin/$program" "$@" $quick_arg
    fi
    echo "Load average after $program: $(load)"
    echo
  } >> "$out"
}

run single a_locality
run single b_aos_soa
run single d_alignment
run single e_alloc_speed single
run threaded c_false_sharing $threads
run threaded e_alloc_speed threads "$alloc_threads"
echo "wrote $out" >&2

#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/.."

BENCHES=(
  checksums_bench
  deflate_bench
  formats_bench
  comparison_bench
)

# Allow running a single benchmark: ./bench/run_all.sh checksums_bench
if [ $# -gt 0 ]; then
  BENCHES=("$@")
fi

for bench in "${BENCHES[@]}"; do
  src="bench/${bench}.cr"
  bin="bench/${bench}"

  echo "Building ${bench} (--release)..."
  crystal build --release "$src" -o "$bin"

  echo "Running ${bench}..."
  "./$bin"

  rm -f "$bin"
done

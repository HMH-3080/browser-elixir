#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/wasm"

for file in AtomVM.mjs AtomVM.wasm bundle.avm; do
  test -s "$file" || { echo "Missing $file" >&2; exit 1; }
done

sha256sum -c "$ROOT/scripts/checksums.txt"

grep -q "callMain" AtomVM.mjs || { echo "AtomVM.mjs does not export callMain" >&2; exit 1; }
if grep -qE "PThread|pthread_create|SharedArrayBuffer" AtomVM.mjs; then
  echo "AtomVM.mjs still references pthreads or SharedArrayBuffer" >&2
  exit 1
fi

echo "Runtime checks passed"

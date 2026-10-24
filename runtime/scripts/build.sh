#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/.build}"
FISSIONVM_DIR="${FISSIONVM_DIR:-$BUILD_ROOT/fission}"
MBEDTLS_DIR="${MBEDTLS_DIR:-$BUILD_ROOT/mbedtls}"
BUILD_DIR="${BUILD_DIR:-$FISSIONVM_DIR/src/platforms/emscripten/build-single}"
FISSIONVM_REF="${FISSIONVM_REF:-6c3208c7b3dbc7dacc35a19f8de1fa80b358ac73}"
MBEDTLS_REF="${MBEDTLS_REF:-v3.6.3.1}"
EMSDK_IMAGE="${EMSDK_IMAGE:-emscripten/emsdk:3.1.74}"
BUNDLE_URL="${BUNDLE_URL:-}"

mkdir -p "$BUILD_ROOT" "$ROOT/wasm"

if [ ! -d "$FISSIONVM_DIR/.git" ]; then
  git clone https://github.com/software-mansion-labs/FissionVM.git "$FISSIONVM_DIR"
fi
git -C "$FISSIONVM_DIR" fetch --all --tags
git -C "$FISSIONVM_DIR" checkout --force "$FISSIONVM_REF"

if git -C "$FISSIONVM_DIR" apply --check "$ROOT/patches/fissionvm-no-pthread.patch"; then
  git -C "$FISSIONVM_DIR" apply "$ROOT/patches/fissionvm-no-pthread.patch"
elif ! git -C "$FISSIONVM_DIR" apply --reverse --check "$ROOT/patches/fissionvm-no-pthread.patch"; then
  echo "Patch does not apply to $FISSIONVM_REF" >&2
  exit 1
fi

if [ ! -d "$MBEDTLS_DIR/.git" ]; then
  git clone --branch "$MBEDTLS_REF" --depth 1 https://github.com/Mbed-TLS/mbedtls.git "$MBEDTLS_DIR"
fi

build_native() {
  command -v gperf >/dev/null || { echo "gperf is required" >&2; exit 1; }
  emcmake cmake -S "$FISSIONVM_DIR/src/platforms/emscripten" -B "$BUILD_DIR" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DAVM_EMSCRIPTEN_ENV=web \
    -DAVM_EMSCRIPTEN_NO_PTHREAD=ON \
    -DFETCHCONTENT_SOURCE_DIR_MBEDTLS="$MBEDTLS_DIR"
  cmake --build "$BUILD_DIR" -j"$(nproc)"
}

build_docker() {
  docker run --rm \
    -v "$FISSIONVM_DIR:/fission" \
    -v "$MBEDTLS_DIR:/mbedtls" \
    -v "$ROOT/wasm:/out" \
    -w /fission \
    "$EMSDK_IMAGE" \
    bash -lc '
      set -euo pipefail
      command -v gperf >/dev/null || (apt-get update && apt-get install -y gperf ninja-build)
      emcmake cmake -S src/platforms/emscripten -B src/platforms/emscripten/build-single \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DAVM_EMSCRIPTEN_ENV=web \
        -DAVM_EMSCRIPTEN_NO_PTHREAD=ON \
        -DFETCHCONTENT_SOURCE_DIR_MBEDTLS=/mbedtls
      cmake --build src/platforms/emscripten/build-single -j"$(nproc)"
      cp src/platforms/emscripten/build-single/src/AtomVM.mjs /out/AtomVM.mjs
      cp src/platforms/emscripten/build-single/src/AtomVM.wasm /out/AtomVM.wasm
    '
}

if command -v emcmake >/dev/null 2>&1; then
  build_native
  cp "$BUILD_DIR/src/AtomVM.mjs" "$ROOT/wasm/AtomVM.mjs"
  cp "$BUILD_DIR/src/AtomVM.wasm" "$ROOT/wasm/AtomVM.wasm"
else
  build_docker
fi

if [ -n "$BUNDLE_URL" ]; then
  echo "Downloading bundle from $BUNDLE_URL" >&2
  curl -fL "$BUNDLE_URL" -o "$ROOT/wasm/bundle.avm"
else
  "$ROOT/scripts/build-bundle.sh"
fi
sha256sum "$ROOT/wasm/AtomVM.mjs" "$ROOT/wasm/AtomVM.wasm" "$ROOT/wasm/bundle.avm" \
  | sed "s#$ROOT/wasm/##" > "$ROOT/scripts/checksums.txt"
"$ROOT/scripts/check.sh"
echo "Built runtime in $ROOT/wasm"

#!/usr/bin/env bash
# Builds the AtomVM bytecode bundle (`bundle.avm`) from `runtime/bundle`.
#
# Uses the local Elixir/OTP installation when it is exactly the pair Popcorn
# supports (Elixir 1.17.3 / OTP 26.0.2), otherwise Docker with the pinned image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$ROOT/bundle"
OUT_DIR="$ROOT/wasm"
IMAGE="${BUNDLE_DOCKER_IMAGE:-hexpm/elixir:1.17.3-erlang-26.0.2-debian-bookworm-20261020-slim}"
TAG="browser-elixir-bundle"

mkdir -p "$OUT_DIR"

exact_toolchain() {
  command -v elixir >/dev/null 2>&1 || return 1
  command -v mix >/dev/null 2>&1 || return 1

  local elixir_version otp_version
  elixir_version=$(elixir -e 'IO.puts(System.version())' 2>/dev/null || true)
  otp_version=$(
    elixir -e '
      IO.puts(
        :code.root_dir()
        |> Path.join("releases")
        |> Path.join(System.otp_release())
        |> Path.join("OTP_VERSION")
        |> File.read!()
        |> String.trim()
      )
    ' 2>/dev/null || true
  )

  [[ "$elixir_version" == "1.17.3" && "$otp_version" == "26.0.2" ]]
}

build_local() {
  echo "Cooking bundle with the local Elixir 1.17.3 / OTP 26.0.2 toolchain" >&2
  (
    cd "$BUNDLE_DIR"
    mix local.hex --force >/dev/null
    mix local.rebar --force >/dev/null
    mix deps.get --only prod
    MIX_ENV=prod mix popcorn.cook
  )
  cp "$BUNDLE_DIR/dist/wasm/bundle.avm" "$OUT_DIR/bundle.avm"
}

build_docker() {
  echo "Cooking bundle in Docker ($IMAGE)" >&2
  docker build -f "$ROOT/docker/bundle.Dockerfile" -t "$TAG" "$BUNDLE_DIR"
  docker run --rm -v "$OUT_DIR:/out" "$TAG"
}

if exact_toolchain; then
  build_local
else
  build_docker
fi

test -s "$OUT_DIR/bundle.avm" || { echo "bundle.avm was not produced" >&2; exit 1; }

# Keep the bundle checksum in sync when this script runs on its own.
CHECKSUMS="$ROOT/scripts/checksums.txt"
if [ -f "$CHECKSUMS" ]; then
  digest="$(sha256sum "$OUT_DIR/bundle.avm" | cut -d' ' -f1)"
  tmp="$CHECKSUMS.tmp"
  awk -v digest="$digest" '
    $2 == "bundle.avm" { print digest "  bundle.avm"; found = 1; next }
    { print }
    END { if (!found) print digest "  bundle.avm" }
  ' "$CHECKSUMS" > "$tmp"
  mv "$tmp" "$CHECKSUMS"
fi

sha256sum "$OUT_DIR/bundle.avm" | sed "s#$OUT_DIR/##"
echo "Built bundle in $OUT_DIR/bundle.avm" >&2

# Single-threaded AtomVM runtime

This directory builds the **no-pthread** AtomVM runtime used by the LiveCodes Elixir/Erlang
languages. It is the same runtime published as
[`@hmh-3080/atomvm-wasm`](https://www.npmjs.com/package/@hmh-3080/atomvm-wasm).

The build does not use Emscripten pthreads, so the output does not need `SharedArrayBuffer`,
`Cross-Origin-Opener-Policy`, or `Cross-Origin-Embedder-Policy`. It works in normal
(non-isolated) pages and cross-origin iframes, which keeps popup-based OAuth working.

This is separate from the Popcorn runtime that the demo page loads from the mirror (see
[`../WASM.md`](../WASM.md)). The demo still uses Popcorn's pthread build; this directory owns the
toolchain for the runtime LiveCodes ships.

## Output

`wasm/` is committed so LiveCodes can pin an exact commit:

- `wasm/AtomVM.mjs` — Emscripten JavaScript loader.
- `wasm/AtomVM.wasm` — AtomVM WebAssembly binary.
- `wasm/bundle.avm` — Elixir 1.17.3 / OTP 26.0.2 bytecode bundle carrying the Elixir and Erlang
  compilers.

`scripts/checksums.txt` pins the SHA-256 of all three.

## Build

```bash
npm run build:runtime   # AtomVM + bundle
npm run build:bundle    # bundle only, reusing the existing AtomVM build
npm run check:runtime
```

### AtomVM

The script starts from
[`software-mansion-labs/FissionVM`](https://github.com/software-mansion-labs/FissionVM) at commit
`6c3208c7b3dbc7dacc35a19f8de1fa80b358ac73`, applies
`patches/fissionvm-no-pthread.patch`, and compiles with Emscripten 3.1.74 and mbedTLS 3.6.3.1. It
uses a local `emcmake` when available, otherwise Docker with `emscripten/emsdk:3.1.74`. The Docker
path installs `gperf` and `ninja-build` inside the container.

The patch contains:

- single-threaded main loop and idle handling (`RUN_IDLE`, `single_thread_idle`);
- Emscripten build without `-pthread` / `-sPROXY_TO_PTHREAD`, with `callMain` exported;
- direct dispatch instead of `emscripten_dispatch_to_thread`;
- no-op pthread/signal paths when `AVM_NO_SMP` is set;
- the missing `erlang:md5/1` NIF backed by mbedTLS, required by OTP's compiler.

### Bundle

`bundle/` is Popcorn's `v0.2.2` `examples/eval-in-wasm`, reduced to what the cook step needs: a
`mix.exs` that depends on Popcorn, and the `EvalInWasm` GenServer plus application module that
evaluate Elixir and Erlang inside the VM. `scripts/build-bundle.sh` cooks it with
`mix deps.get --only prod && MIX_ENV=prod mix popcorn.cook` and copies `dist/wasm/bundle.avm` to
`wasm/bundle.avm`.

The Popcorn tag is pinned because the bundle and the worker in LiveCodes are a matched pair.
Upgrading it means re-checking the `Popcorn.Wasm` message protocol against
`src/livecodes/languages/beam-wasm/lang-beam-wasm-worker.raw.js` there.

The cook needs the host Elixir/OTP pair that Popcorn supports. The script uses a local `elixir` and
`mix` when they report exactly 1.17.3 / OTP 26.0.2, and otherwise Docker with
`hexpm/elixir:1.17.3-erlang-26.0.2-debian-bookworm-20261020-slim` (override with
`BUNDLE_DOCKER_IMAGE`). No bundle is downloaded.

#### Why Elixir 1.17.3

Popcorn 0.2.x and 0.3.x read `OTP_VERSION` from the host installation at compile time and raise
unless the pair is OTP 26.0.2 / Elixir 1.17.3. The bundle also carries Popcorn's OTP and Elixir
patches for that pair, so a newer Elixir such as 1.20.4 would need those patches ported. Popcorn has
since moved its supported target to a full-BEAM Wasm runtime, which this single-threaded AtomVM build
does not run. The pair stays pinned until upstream supports another one.

## Checks

```bash
npm run check:runtime
```

This verifies the files and SHA-256 checksums, confirms `callMain` is exported, and rejects output
that still references pthreads or `SharedArrayBuffer`.

## Upgrading

The build inputs are overridable environment variables, so an upgrade does not require editing the
scripts:

| Variable | Default |
| --- | --- |
| `FISSIONVM_REF` | pinned FissionVM commit |
| `MBEDTLS_REF` | `v3.6.3.1` |
| `EMSDK_IMAGE` | `emscripten/emsdk:3.1.74` |
| `BUNDLE_DOCKER_IMAGE` | pinned `hexpm/elixir` cook image |
| `BUNDLE_URL` | unset: cook `bundle/`; set it to reuse an existing bundle |

```bash
FISSIONVM_REF=<new-commit> MBEDTLS_REF=<new-tag> npm run build:runtime
npm run check:runtime
```

Commit `wasm/` and `scripts/checksums.txt`, then pin the new commit in LiveCodes
(`src/livecodes/vendors.ts`) and run the Elixir/Erlang Playwright suites before merging.

The Popcorn tag is pinned in `bundle/mix.exs`; change it together with `BUNDLE_DOCKER_IMAGE`, because
the cook image must match the Elixir/OTP pair that tag supports.

If FissionVM changed the files touched by `patches/fissionvm-no-pthread.patch`, rebase the patch
onto the new commit, rebuild, and confirm the output still has `callMain` and no
`SharedArrayBuffer`/pthread references.

## Benchmark

The runtime measurements and the AtomVM/Popcorn comparison are in
[`../benchmark.md`](../benchmark.md).

## License

AtomVM and FissionVM are Apache-2.0. Elixir and Erlang/OTP are Apache-2.0. Popcorn is MIT. See
[`../LICENSE`](../LICENSE) and the upstream projects for details.

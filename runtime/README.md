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

- `wasm/AtomVM.mjs` — Emscripten JavaScript loader.
- `wasm/AtomVM.wasm` — AtomVM WebAssembly binary.
- `wasm/bundle.avm` — Elixir 1.17.3 / OTP 27 bytecode bundle (Elixir and Erlang), pinned from
  [`live-codes/elixir-browser-eval@6b354da`](https://github.com/live-codes/elixir-browser-eval/tree/6b354dab35fb7454ba2812f935b52b398ca1bec8/wasm).

`wasm/` is generated and is not committed.

## Build

```bash
npm run build:runtime
```

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

## Checks

```bash
npm run check:runtime
```

This verifies the files and SHA-256 checksums, confirms `callMain` is exported, and rejects output
that still references pthreads or `SharedArrayBuffer`.

## Upgrading

The build inputs are overridable environment variables, so an upgrade does not require editing the
script:

| Variable | Default |
| --- | --- |
| `FISSIONVM_REF` | pinned FissionVM commit |
| `MBEDTLS_REF` | `v3.6.3.1` |
| `EMSDK_IMAGE` | `emscripten/emsdk:3.1.74` |
| `BUNDLE_URL` | pinned `live-codes/elixir-browser-eval` bundle |

```bash
FISSIONVM_REF=<new-commit> MBEDTLS_REF=<new-tag> BUNDLE_URL=<new-url> npm run build:runtime
npm run check:runtime
```

Then bump the package version, publish with `npm publish --access public`, and update the package
version in LiveCodes (`src/livecodes/vendors.ts`). Run the LiveCodes Elixir/Erlang Playwright suites
before merging.

If FissionVM changed the files touched by `patches/fissionvm-no-pthread.patch`, rebase the patch
onto the new commit, rebuild, and confirm the output still has `callMain` and no
`SharedArrayBuffer`/pthread references.

## Benchmark

The runtime measurements and the AtomVM/Popcorn comparison are in
[`../benchmark.md`](../benchmark.md).

## License

AtomVM and FissionVM are Apache-2.0. Elixir and Erlang/OTP are Apache-2.0. Popcorn is MIT. See
[`../LICENSE`](../LICENSE) and the upstream projects for details.

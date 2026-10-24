# Browser Elixir

Run **Elixir and Erlang entirely in the browser** — no server, no upload, no install. The compilers
themselves execute in WebAssembly, so a snippet typed into the page is evaluated in that tab.

It is built on **[Popcorn](https://github.com/software-mansion/popcorn)** 0.3, which runs
[AtomVM](https://github.com/atomvm/AtomVM) (a small Erlang VM) compiled to WebAssembly, plus an
`eval-in-wasm` bundle that carries the Elixir **and** Erlang compilers inside the VM. That bundle
is why a playground works at all: without it every snippet would need a build step.

This is the runtime behind adding an `elixir` language to [LiveCodes](https://livecodes.io), in
the same shape as [`browser-haskell`](https://github.com/live-codes/browser-haskell) was for
`haskell-wasm`.

The no-pthread AtomVM build used by LiveCodes lives in [`runtime/`](runtime/README.md), together
with the FissionVM patch, the bundle recipe, build/check scripts, and the [benchmark](benchmark.md).
It runs without `SharedArrayBuffer` or COOP/COEP. The demo page below still loads Popcorn's pthread
runtime from the mirror, so it still requires cross-origin isolation.

## Demo

```bash
npm start          # → http://localhost:8125/   (alias for: node serve.js)
```

Pick **Elixir** or **Erlang**, pick an example (or type your own), and press **Run** — or
`Ctrl`/`Cmd` + `Enter` in the editor. The result pane shows `inspect/1` of the last expression; the
output pane shows `stdout` and `stderr` as the program produces them. `?stdin=Ada%0A42` supplies
standard input in either language, and the footer reports the run's exit code.

A server is required, and it must set two cross-origin isolation headers — see
[Limitations](#limitations). `file://` will not work, and neither will a plain static server.

**The demo page loads its runtime from a CDN.** `bundle.avm`, `AtomVM.wasm` and `AtomVM.mjs` are
fetched from a mirror of
[`live-codes/elixir-browser-eval`](https://github.com/live-codes/elixir-browser-eval), pinned to a
commit. Point it elsewhere with `?baseUrl=`:

```
http://localhost:8125/?baseUrl=https://raw.githubusercontent.com/live-codes/elixir-browser-eval/main/
```

See [WASM.md](WASM.md) for what is mirrored, why ~170 KB of scripts stay in the repo, and the
hashes to verify a mirror against.

## What you get

- **Client-side evaluation.** `Code.eval_string/3` (Elixir) and `:erl_eval` (Erlang) run inside the
  tab; nothing is uploaded.
- **Real compilers, not transpilers.** Modules, pattern matching, pipes, comprehensions, structs
  where supported, `Enum`/`Map`/`String`, `lists`/`maps`, `inspect/1` formatting. Erlang modules
  are compiled with `:compile` and stay loaded for the session.
- **Both languages share one VM**, so switching between them needs no reboot.
- **Processes work.** `spawn`/`send`/`receive` and `GenServer` run on AtomVM (the runtime's own
  eval server is a GenServer).
- **`ETS` and `:crypto` work** — `:crypto.hash(:sha256, "abc")` returns the correct digest.
- **`stdin`, and an exit code.** `IO.gets` and `io:get_line` read the `?stdin=` param, in either
  language; input that runs out returns `:eof` rather than hanging. The footer reports the run's exit
  code — `0` on success, `1` for a runtime error, `124` for a timeout, or whatever
  `System.halt(n)` / `erlang:halt(n)` was given.
- **Self-healing.** A missing NIF or a compile error aborts the VM, so the driver detects the dead
  instance and restarts it rather than leaving the page broken.
- **No build step and no dependencies** — plain ES modules. `npm start` is the whole toolchain.

## Language support

AtomVM implements a **subset** of Elixir/OTP. Measured against this bundle (full evidence with
outputs and timings in [FINDINGS.md](FINDINGS.md)):

| Works | Does not work |
| --- | --- |
| Integers **and floats** (`1.5 + 1.5` → `3.0`, `7 / 2` → `3.5`) | **Regex** — `Regex.match?/2` aborts on a missing NIF |
| `Enum`, `Map`, `String` (Elixir); `lists`, `maps` (Erlang) | **`DateTime`/`os` time** — `os:system_time/0` NIF missing |
| Comprehensions, recursion, `defmodule`, Erlang `-module` + `:compile` | **`Task`** — `erlang:monitor/3` NIF missing |
| `spawn`/`send`/`receive`, `GenServer` | **`Float.round/2`** — dies with no diagnostic at all |
| `:ets`, `:crypto` | **Elixir structs** (`defstruct` + `%S{}` in one eval) — compile error |
| `IO.puts`/`IO.inspect` (Elixir), `io:format` (Erlang) | **Loops forever** — nothing can interrupt it |
| `try`/`rescue` (Elixir), `try`/`catch` (Erlang) | |

Behaviour worth knowing before you trust a snippet:

- **A runtime error is a value, not a restart.** Every run is wrapped, so an uncaught `raise`
  (Elixir) or `1/0` (Erlang) comes back as a message with exit code `1` instead of killing the
  instance. A *compile* error or a missing NIF still cannot be caught — the VM aborts. Erlang parse
  errors were already values: `:erl_scan`/`:erl_parse` failures come back as ordinary
  `{:error, {line, :erl_parse, [text, token]}}`, so a missing final dot is a message, not a crash.
- **Erlang code must end with a dot** and take comma-separated expressions. Code beginning with
  `-module(` is compiled and loaded instead of evaluated, and stays callable in later runs
  (`m:double(21).`), including after switching language.
- **Do not start an Erlang module with a comment.** A `%` comment before the first attribute breaks
  this bundle's form splitter (`syntax error before: '-'`); comments elsewhere are fine.
- **`defmodule` inside the Elixir editor is namespaced as `EvalInWasm.<Name>`.** A call like
  `Fib.of(20)` resolves, but `%Fib{}` struct literal expansion does not.

## Limitations

- **Cross-origin isolation is mandatory.** The page must be served with
  `Cross-Origin-Opener-Policy: same-origin` plus `Cross-Origin-Embedder-Policy`. Verified three ways:
  `require-corp` and `credentialless` both isolate the document and boot; without either,
  `crossOriginIsolated` is `false`, `SharedArrayBuffer` is `undefined`, and `Popcorn.init()` never
  returns. `serve.js` defaults to `require-corp`; `npm run start:credentialless` switches to
  `credentialless`, which is the safer choice if you point `?baseUrl=` at a mirror that does not
  send CORP headers (jsDelivr does). **This remains the main open question for LiveCodes
  embedding**, where the top-level document's headers are not ours to choose. It also cannot be
  worked around at runtime: with the headers absent the VM never becomes ready at all, and
  recovering `SharedArrayBuffer` by hand only moves the failure into the pthread worker — lifting
  the requirement means a different runtime build ([FINDINGS.md](FINDINGS.md) §7).
- **A 15 s timeout still means a dead or wedged instance.** An uncaught error is no longer the usual
  cause, but a missing NIF, a compile error or a program that loops forever still surfaces as the
  timeout, and the runtime is restarted. Lower `EVAL_TIMEOUT_MS` in `public/main.js` to trade
  patience for snappier failure.
- **`stdin` is a mock, and there is no `argv`.** The runtime has no file descriptor 0, so each run
  installs its own IO device and serves `IO.gets` / `io:get_line` from `?stdin=`. There is no
  filesystem, no dependency manager and no compiler driver — this is not a script runner. The device
  lives in a module named `livecodes_io`, which a user module of the same name would replace.
- **8.1 MB of runtime** on first load, from the mirror and cached hard afterwards; the eventual
  LiveCodes entry will need `largeDownload: true`. Only the two patched scripts (~20 KB) are
  committed — see [WASM.md](WASM.md).
- **A hard 16 MiB heap, and it cannot grow.** The build allocates its shared memory with
  `initial === maximum`, so the bundle, the compilers and every module a session defines share
  16 MiB; exceeding it surfaces as `memory access out of bounds` in a pthread worker. Raising it
  from JavaScript fails at instantiation (the ceiling is compiled in), so lifting it needs a rebuilt
  AtomVM — [FINDINGS.md](FINDINGS.md) has the evidence and the workaround.
- **Terse diagnostics**, in AtomVM's own format, sometimes naming internals
  (`function :elixir.eval_external_handler/3 is undefined or private`).

## Layout

```
public/index.html     the harness page (language + example pickers, result, stdout/stderr, timings)
public/main.js        the driver: boots Popcorn, wraps runs (stdin + exit code), recovers a dead VM
public/wasm/          the 2 patched runtime scripts — see WASM.md; everything else is mirrored
runtime/              no-pthread AtomVM + bundle build, committed artifacts, scripts, checksums, docs
benchmark.md          Elixir (Wasm) performance notes and AtomVM/Popcorn comparison
serve.js              static server: COOP/COEP, MIME types, caching, --no-isolation
WASM.md               where the runtime comes from, the mirror pin, and the four deviations
FINDINGS.md           the spike log: what was verified, what breaks, what it means
```

There is no bundler and no `node_modules`.

## Verifying

The demo is verified by *running* it, not by importing it — recorded outputs are in
[FINDINGS.md](FINDINGS.md). Everything below needs no bundler:

| what | command |
| --- | --- |
| serve the page | `npm start` → http://localhost:8125/ |
| check syntax | `npm run check` |
| build the no-pthread runtime | `npm run build:runtime` |
| build the bytecode bundle only | `npm run build:bundle` |
| check the no-pthread runtime | `npm run check:runtime` |
| prove isolation is required | `npm run start:no-isolation`, then reload — boot fails |
| use a different mirror | append `?baseUrl=https://…/` |

## Status

Spike complete. The page boots AtomVM from a mirrored runtime, evaluates Elixir and Erlang, streams
`stdout`/`stderr`, reports `inspect/1` of the result, survives an aborted VM, and is verified end to
end in headless Chrome against the pinned CDN. Elixir runs additionally read `stdin`, report an exit
code and survive a runtime error ([FINDINGS.md](FINDINGS.md) §13).

The no-pthread build in [`runtime/`](runtime/README.md) is the runtime for the LiveCodes Elixir and
Erlang languages. It removes the isolation requirement for the embedded playground. Both
`AtomVM.mjs`/`AtomVM.wasm` and the cooked `bundle.avm` are built from source by `runtime/scripts/`
and committed under `runtime/wasm/` with checksums. The demo page still uses the Popcorn mirror and
its pthread runtime; wiring the no-pthread build into the demo is a separate step.

## License

MIT © Hatem Hosny. Popcorn, AtomVM and the mirrored runtime are Apache-2.0; see
[LICENSE](LICENSE) and [WASM.md](WASM.md) for provenance.

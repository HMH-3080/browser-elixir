# Where the runtime comes from

The **demo page** loads its runtime from a mirror. The only runtime files this repo ships for the
demo are the two scripts it patches — ~20 KB — and they are loaded same-origin because they *are*
the patches. (The no-pthread runtime that LiveCodes ships is built in [`runtime/`](runtime/README.md)
and committed; see [Single-threaded build](#single-threaded-build).)

| file | bytes | served from | patched? |
| --- | --- | --- | --- |
| `popcorn.js` | 14,081 | this repo (`public/wasm/`) | **yes** — bundle path |
| `popcorn_iframe.js` | 6,462 | this repo (`public/wasm/`) | **yes** — worker script + wasm lookup |
| `AtomVM.mjs` | 149,754 | **the mirror** | no |
| `AtomVM.wasm` | 997,332 | **the mirror** | no |
| `bundle.avm` | 7,114,092 | **the mirror** | no |

So the 8.1 MB of runtime and binaries used by the demo page come from a CDN, and nothing large is
committed for it. The single-threaded runtime that LiveCodes ships is separate: it is built and
committed under [`runtime/`](runtime/README.md).

## Default mirror

```
https://cdn.jsdelivr.net/gh/live-codes/elixir-browser-eval@6b354dab35fb7454ba2812f935b52b398ca1bec8/
```

`live-codes/elixir-browser-eval` is a fork of `TORIFUKUKaiou/elixir-browser-eval`, which is
Popcorn's own `examples/eval-in-wasm` built with `mix popcorn.cook` (OTP 26.0.2 / Elixir 1.17.3)
and deployed as static files. The fork's `wasm/` blobs are byte-identical to upstream. Pinned to a
commit rather than a branch, so a mirror cannot shift underneath the scripts.

Verify a mirror before trusting it — these are the bytes the pin resolves to:

| file | sha256 |
| --- | --- |
| `AtomVM.mjs` | `07c3e14aeb0c3ad695195457e99fa1047730a505a874d4be8f8307676a9eedea` |
| `AtomVM.wasm` | `80a10d62b1153fec6cf8eb3991a138f533b1c5e4e51d9c17b62659e827087c7f` |
| `bundle.avm` | `6e25339e38f9d9ee3988b648802f56cf86004e0cec4af997f3ee41d94043f1af` |

## Pointing at another mirror

```
http://localhost:8125/?baseUrl=https://raw.githubusercontent.com/live-codes/elixir-browser-eval/main/
```

`baseUrl` may be absolute or relative to the page (`?baseUrl=./` for a local copy under
`public/wasm/`); a trailing slash is added if missing. The footer shows the URL in use and whether
it came from `?baseUrl`. The bundle path is the single source of truth — the iframe derives
everything else from it — so `Popcorn.init`'s `wasmDir` is no longer meaningful and is not set.

The mirror must carry the pinned version's files: the scripts and the bundle are **version-locked**
(see below), so an older or newer `.avm` will not work. Verified mirrors: jsDelivr (`@<sha>` and
`@main`) and `raw.githubusercontent.com` — the latter serves `AtomVM.wasm` as
`application/octet-stream` rather than `application/wasm`, and Emscripten's fallback to
`ArrayBuffer` instantiation covers it.

## The pthread worker, and why the runtime can now be mirrored

`AtomVM.mjs` is an Emscripten build **with pthreads** — which is why it needs `SharedArrayBuffer`,
and therefore why cross-origin isolation is mandatory. Emscripten spawns those threads as workers:

```js
worker = new Worker(new URL("AtomVM.mjs", import.meta.url), { type: "module", name: "em-pthread" });
```

Workers must be same-origin, so a jsDelivr-hosted `AtomVM.mjs` throws a `SecurityError` the runtime
swallows — the symptom is `Popcorn.init()` hanging until it times out, with no error anywhere.
Measured: same page, same bundle, same headers, only the script origin differing, boot goes from
176 ms to a 30 s timeout.

Emscripten provides `Module.mainScriptUrlOrBlob` for exactly this. Its documented use is a Blob of
the main script, and that is what `popcorn_iframe.js` does here:

```js
const source = await fetch(binaryDir + "AtomVM.mjs").then((resp) => resp.text());
workerScript = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
// …init({ mainScriptUrlOrBlob: workerScript, locateFile: locateBinary })
```

Two details matter:

- **It has to be the module itself, not an `importScripts` shim.** The worker is created with
  `{ type: "module" }` (hardcoded by Emscripten), and `importScripts` does not exist in a module
  worker. The usual `toDataUrl('importScripts("…")')` trick is for *classic* workers only.
- **Blob, not `data:`.** A module worker created from a `data:` URL starts and then aborts with an
  empty reason (`Aborted()`); a Blob URL is same-origin and has a usable base URL, and works.
  Measured both ways — see [FINDINGS.md](FINDINGS.md).

## The four deviations from upstream

All are in the two files vendored into `public/wasm/`, all are commented in place.

1. **`popcorn.js` — bundle path.** Upstream builds the iframe's bundle path as
   `"../" + bundlePath`, which pins the bundle to the hosting origin (an absolute URL becomes
   `../https://…` and resolves to `<origin>/https://…`). Dropping the prefix lets it be absolute.
2. **`popcorn.js` — iframe script origin.** The srcdoc loads `popcorn_iframe.js` from this file's
   own directory instead of `wasmDir`, so the patched copy is the one that runs.
3. **`popcorn_iframe.js` — `mainScriptUrlOrBlob`.** The Blob worker described above.
4. **`popcorn_iframe.js` — `locateFile`.** Upstream resolves `AtomVM.wasm` relative to the script
   directory; the patch resolves it next to the bundle, so it follows the mirror.

This file also reports its own startup failures to the parent's output pane, because an iframe that
dies silently is near-impossible to debug and that cost real time here.

Everything else is upstream and unmodified. When updating the runtime, re-apply all four.

## Single-threaded build

[`runtime/`](runtime/README.md) builds a **no-pthread** AtomVM from FissionVM and cooks
`bundle.avm` from Popcorn `v0.2.2`'s eval server. Neither needs `SharedArrayBuffer` nor COOP/COEP.
This is the runtime LiveCodes ships; the artifacts are committed under `runtime/wasm/` with SHA-256
checksums in `runtime/scripts/checksums.txt`. It is built independently of the Popcorn mirror
described above, and the demo page does not load it yet.

## Rebuilding the demo runtime

To own the whole demo stack — and to lift the 16 MiB heap ceiling described in
[FINDINGS.md](FINDINGS.md) — clone Popcorn at the tag matching `@swmansion/popcorn@0.3.3`, install
the pinned toolchain with `mise install`, then:

```bash
cd examples/eval-in-wasm
mix deps.get
mix popcorn.cook
```

That emits `popcorn.js`, `popcorn_iframe.js`, `AtomVM.mjs`, `AtomVM.wasm` and `bundle.avm` as one
matched set — take all of them, then re-apply the four patches above. This path is separate from
the no-pthread runtime in `runtime/`.

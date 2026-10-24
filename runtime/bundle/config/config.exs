import Config

config :popcorn, out_dir: "dist/wasm"

# The bundle is cooked from the host Elixir/OTP installation. The AtomVM
# runtime is built by `runtime/scripts/build.sh`, so Popcorn's runtime artifact
# downloader is not used here.
config :popcorn, runtime: {:path, "unused", target: :wasm}

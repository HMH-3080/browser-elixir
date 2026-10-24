# Cooks the AtomVM bytecode bundle (`bundle.avm`) from the sources in
# `runtime/bundle` (Popcorn v0.2.2's `examples/eval-in-wasm`).
#
# The bundle must be built with the exact Elixir/OTP pair that Popcorn supports
# (Elixir 1.17.3 / OTP 26.0.2). The image is pinned by tag; passing a different
# image is possible via BUNDLE_DOCKER_IMAGE, but the cook step requires the
# matching host.
FROM hexpm/elixir:1.17.3-erlang-26.0.2-debian-bookworm-20261020-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && mix local.hex --force \
  && mix local.rebar --force

WORKDIR /bundle
COPY . /bundle/

RUN mix deps.get --only prod \
  && MIX_ENV=prod mix popcorn.cook

CMD ["cp", "dist/wasm/bundle.avm", "/out/bundle.avm"]

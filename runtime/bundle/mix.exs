defmodule EvalInWasm.MixProject do
  use Mix.Project

  # Mirrors Popcorn's `examples/eval-in-wasm` at v0.2.2, the version the
  # LiveCodes worker's BEAM-side message protocol was verified against.
  @popcorn_ref "v0.2.2"

  def project do
    [
      app: :eval_in_wasm,
      version: "0.1.0",
      elixir: "~> 1.17.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [], mod: {EvalInWasm.Application, []}]
  end

  defp deps do
    [
      {:popcorn,
       github: "software-mansion/popcorn", tag: @popcorn_ref, sparse: "popcorn/elixir"}
    ]
  end
end

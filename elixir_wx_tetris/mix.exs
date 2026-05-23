defmodule ElixirWxTetris.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_wx_tetris,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: [qa: :test]]
  end

  def application do
    [
      extra_applications: [:logger, :wx],
      mod: {Tetris.Application, []}
    ]
  end

  defp deps do
    []
  end
end

defmodule Elixir3dGallery.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_3d_gallery,
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
      mod: {Elixir3dGallery.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end

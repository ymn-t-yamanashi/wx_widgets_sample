defmodule ElixirWxCameraViewer.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_wx_camera_viewer,
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
      mod: {ElixirWxCameraViewer.Application, []}
    ]
  end

  defp deps do
    [
      {:evision, "~> 0.2.10"}
    ]
  end
end

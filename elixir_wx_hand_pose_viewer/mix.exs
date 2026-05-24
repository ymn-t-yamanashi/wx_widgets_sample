defmodule ElixirWxHandPoseViewer.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_wx_hand_pose_viewer,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def cli do
    [preferred_envs: [qa: :test]]
  end

  def application do
    [
      mod: {ElixirWxHandPoseViewer.Application, []},
      extra_applications: [:logger, :wx]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:evision, "~> 0.2"}
    ]
  end
end

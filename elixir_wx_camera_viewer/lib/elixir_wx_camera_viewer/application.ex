defmodule ElixirWxCameraViewer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        [
          Supervisor.child_spec(
            {ElixirWxCameraViewer.Camera, [device: 0, width: 640, height: 480, fps: 30]},
            restart: :temporary
          ),
          Supervisor.child_spec({ElixirWxCameraViewer.GUI, []}, restart: :temporary)
        ]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: ElixirWxCameraViewer.Supervisor)
  end
end

defmodule ElixirWxHandPoseViewer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        device = parse_device(System.get_env("CAMERA_DEVICE") || "0")

        [
          Supervisor.child_spec(
            {ElixirWxHandPoseViewer.Camera, [device: device, width: 640, height: 480, fps: 30]},
            restart: :temporary
          ),
          Supervisor.child_spec({ElixirWxHandPoseViewer.GUI, []}, restart: :temporary)
        ]
      end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ElixirWxHandPoseViewer.Supervisor
    )
  end

  defp parse_device(text) do
    case Integer.parse(to_string(text)) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end
end

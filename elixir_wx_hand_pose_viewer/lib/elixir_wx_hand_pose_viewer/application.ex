defmodule ElixirWxHandPoseViewer.Application do
  @moduledoc """
  アプリケーションのエントリポイントです。

  `:test` 環境ではGUI/カメラを起動せず、通常環境では
  カメラキャプチャとGUIプロセスを supervision tree に登録します。
  """

  use Application

  @impl true
  @doc """
  アプリケーションの supervision tree を起動します。
  """
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

  # CAMERA_DEVICE の文字列入力を安全にデバイス番号へ変換する。
  defp parse_device(text) do
    case Integer.parse(to_string(text)) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end
end

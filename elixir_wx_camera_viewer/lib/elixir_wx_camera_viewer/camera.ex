defmodule ElixirWxCameraViewer.Camera do
  @moduledoc false

  use GenServer

  @interval_ms 33

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def latest_frame do
    GenServer.call(__MODULE__, :latest_frame)
  catch
    :exit, _ -> {:error, :not_running}
  end

  def toggle_pause do
    GenServer.call(__MODULE__, :toggle_pause)
  catch
    :exit, _ -> {:error, :not_running}
  end

  def save_snapshot(path) do
    GenServer.call(__MODULE__, {:save_snapshot, path})
  catch
    :exit, _ -> {:error, :not_running}
  end

  @impl true
  def init(opts) do
    state = %{capture: nil, frame: nil, error: nil, opts: opts, paused: false}
    Process.send_after(self(), :open_camera, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:latest_frame, _from, state), do: {:reply, frame_reply(state), state}

  def handle_call(:toggle_pause, _from, state) do
    next = %{state | paused: !state.paused}
    {:reply, {:ok, next.paused}, next}
  end

  def handle_call({:save_snapshot, _path}, _from, %{frame: nil} = state),
    do: {:reply, {:error, :no_frame}, state}

  def handle_call(
        {:save_snapshot, path},
        _from,
        %{frame: %{data: data, width: w, height: h}} = state
      ) do
    image = :wxImage.new(w, h, data)
    ok = :wxImage.saveFile(image, to_charlist(path))
    :wxImage.destroy(image)
    {:reply, if(ok, do: :ok, else: {:error, :save_failed}), state}
  end

  @impl true
  def handle_info(:open_camera, state) do
    if Code.ensure_loaded?(Evision.VideoCapture) do
      device = Keyword.fetch!(state.opts, :device)

      case Evision.VideoCapture.videoCapture(device) do
        {:ok, capture} ->
          schedule_grab(capture, state)

        %Evision.VideoCapture{} = capture ->
          schedule_grab(capture, state)

        {:error, reason} ->
          retry_state = %{state | error: "カメラを開けません: #{inspect(reason)}"}
          Process.send_after(self(), :open_camera, 1_000)
          {:noreply, retry_state}
      end
    else
      {:noreply, %{state | error: "Evisionが未導入です。mix deps.get を実行してください。"}}
    end
  end

  def handle_info(:grab_frame, %{capture: nil} = state) do
    Process.send_after(self(), :open_camera, 1_000)
    {:noreply, state}
  end

  def handle_info(:grab_frame, %{paused: true} = state) do
    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, state}
  end

  def handle_info(:grab_frame, state) do
    next_state =
      case Evision.VideoCapture.read(state.capture) do
        {:ok, frame} -> %{state | frame: to_rgb_binary(frame), error: nil}
        {ok, frame} when ok in [true, :ok] -> %{state | frame: to_rgb_binary(frame), error: nil}
        {:error, %Evision.Mat{} = frame} -> %{state | frame: to_rgb_binary(frame), error: nil}
        %Evision.Mat{} = frame -> %{state | frame: to_rgb_binary(frame), error: nil}
        {:error, reason} -> %{state | error: "フレーム取得失敗: #{inspect(reason)}"}
        other -> %{state | error: "フレーム取得失敗: #{inspect(other)}"}
      end

    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, next_state}
  end

  @impl true
  def terminate(_reason, %{capture: capture}) when not is_nil(capture) do
    Evision.VideoCapture.release(capture)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp schedule_grab(capture, state) do
    configure_capture(capture, state.opts)
    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, %{state | capture: capture, error: nil}}
  end

  defp frame_reply(%{frame: nil, error: err}) when is_binary(err), do: {:error, err}
  defp frame_reply(%{frame: nil}), do: {:error, "カメラ初期化中..."}
  defp frame_reply(%{frame: frame}), do: {:ok, frame}

  defp configure_capture(capture, opts) do
    Evision.VideoCapture.set(
      capture,
      Evision.Constant.cv_CAP_PROP_FRAME_WIDTH(),
      opts[:width] || 640
    )

    Evision.VideoCapture.set(
      capture,
      Evision.Constant.cv_CAP_PROP_FRAME_HEIGHT(),
      opts[:height] || 480
    )

    Evision.VideoCapture.set(capture, Evision.Constant.cv_CAP_PROP_FPS(), opts[:fps] || 30)
  end

  defp to_rgb_binary(frame) do
    rgb =
      case Evision.cvtColor(frame, Evision.Constant.cv_COLOR_BGR2RGB()) do
        {:ok, mat} -> mat
        %Evision.Mat{} = mat -> mat
      end

    data = Evision.Mat.to_binary(rgb)
    {h, w, _} = Evision.Mat.shape(rgb)
    %{data: data, width: w, height: h}
  end
end

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

  def toggle_recording do
    GenServer.call(__MODULE__, :toggle_recording)
  catch
    :exit, _ -> {:error, :not_running}
  end

  @impl true
  def init(opts) do
    state = %{
      capture: nil,
      frame: nil,
      error: nil,
      opts: opts,
      paused: false,
      recording: %{active: false, writer: nil, path: nil}
    }

    Process.send_after(self(), :open_camera, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:latest_frame, _from, state), do: {:reply, frame_reply(state), state}

  def handle_call(:toggle_pause, _from, state) do
    next = %{state | paused: !state.paused}
    {:reply, {:ok, next.paused}, next}
  end

  def handle_call(:toggle_recording, _from, %{recording: %{active: true}} = state) do
    {next, _} = stop_recording(state)
    {:reply, {:ok, {:stopped, next.recording.path}}, next}
  end

  def handle_call(:toggle_recording, _from, state) do
    case start_recording(state) do
      {:ok, next, path} -> {:reply, {:ok, {:started, path}}, next}
      {:error, reason} -> {:reply, {:error, reason}, put_error(state, reason)}
    end
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
        {:ok, frame} ->
          frame |> maybe_write_frame(state) |> put_frame(frame)

        {ok, frame} when ok in [true, :ok] ->
          frame |> maybe_write_frame(state) |> put_frame(frame)

        {:error, %Evision.Mat{} = frame} ->
          frame |> maybe_write_frame(state) |> put_frame(frame)

        %Evision.Mat{} = frame ->
          frame |> maybe_write_frame(state) |> put_frame(frame)

        {:error, reason} ->
          %{state | error: "フレーム取得失敗: #{inspect(reason)}"}

        other ->
          %{state | error: "フレーム取得失敗: #{inspect(other)}"}
      end

    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, next_state}
  end

  @impl true
  def terminate(_reason, state) do
    {state, _} = stop_recording(state)

    if not is_nil(state.capture) do
      Evision.VideoCapture.release(state.capture)
    end

    :ok
  end

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

  defp put_frame(state, frame), do: %{state | frame: to_rgb_binary(frame), error: nil}

  defp maybe_write_frame(frame, %{recording: %{active: true, writer: writer}} = state) do
    case writer_write(writer, frame) do
      :ok -> state
      {:error, reason} -> put_error(state, "録画書き込み失敗: #{inspect(reason)}")
    end
  end

  defp maybe_write_frame(_frame, state), do: state

  defp start_recording(%{recording: %{active: true}} = state),
    do: {:ok, state, state.recording.path}

  defp start_recording(state) do
    with true <- Code.ensure_loaded?(Evision.VideoWriter),
         {:ok, frame} <- frame_reply(state),
         {:ok, writer, path} <-
           open_video_writer_with_fallback(frame.width, frame.height, state.opts[:fps] || 30) do
      next = %{state | recording: %{active: true, writer: writer, path: path}, error: nil}
      {:ok, next, path}
    else
      false -> {:error, "Evision.VideoWriter が利用できません"}
      {:error, reason} -> {:error, to_string(reason)}
      other -> {:error, "録画開始失敗: #{inspect(other)}"}
    end
  end

  defp stop_recording(%{recording: %{active: true, writer: writer}} = state) do
    path = state.recording.path
    _ = writer_release(writer)
    {%{state | recording: %{active: false, writer: nil, path: path}}, path}
  end

  defp stop_recording(state), do: {state, nil}

  defp open_video_writer_with_fallback(width, height, fps) do
    attempts = [
      {recording_path("mp4"), [?m, ?p, ?4, ?v]},
      {recording_path("avi"), [?M, ?J, ?P, ?G]}
    ]

    try_open_writer(attempts, width, height, fps)
  end

  defp try_open_writer([], _width, _height, _fps), do: {:error, "対応コーデックで録画開始できません"}

  defp try_open_writer([{path, fourcc_chars} | rest], width, height, fps) do
    case open_video_writer(path, width, height, fps, fourcc_chars) do
      {:ok, writer} -> {:ok, writer, path}
      {:error, _} -> try_open_writer(rest, width, height, fps)
    end
  end

  defp open_video_writer(path, width, height, fps, fourcc_chars) do
    fourcc = apply(Evision.VideoWriter, :fourcc, fourcc_chars)
    writer = apply(Evision.VideoWriter, :videoWriter, [])

    opened? =
      case apply(Evision.VideoWriter, :open, [writer, path, fourcc, fps, {width, height}]) do
        true -> true
        {:ok, true} -> true
        _ -> false
      end

    if opened? and apply(Evision.VideoWriter, :isOpened, [writer]) do
      {:ok, writer}
    else
      _ = writer_release(writer)
      {:error, "VideoWriter open 失敗 (path=#{path}, size=#{width}x#{height}, fps=#{fps})"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp writer_write(writer, frame) do
    case apply(Evision.VideoWriter, :write, [writer, frame]) do
      :ok -> :ok
      true -> :ok
      {:ok, _} -> :ok
      other -> {:error, other}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp writer_release(nil), do: :ok

  defp writer_release(writer) do
    apply(Evision.VideoWriter, :release, [writer])
    :ok
  rescue
    _ -> :ok
  end

  defp recording_path(ext) do
    ts =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()
      |> String.replace(":", "-")

    Path.join(File.cwd!(), "recording_#{ts}.#{ext}")
  end

  defp put_error(state, reason), do: %{state | error: to_string(reason)}

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

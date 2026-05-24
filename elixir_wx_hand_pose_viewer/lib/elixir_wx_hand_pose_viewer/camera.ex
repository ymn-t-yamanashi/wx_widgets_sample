defmodule ElixirWxHandPoseViewer.Camera do
  @moduledoc false

  use GenServer
  require Logger

  @interval_ms 33
  @model_path "priv/models/hand_keypoint.onnx"
  @score_threshold 0.35
  @connections [
    {0, 1},
    {1, 2},
    {2, 3},
    {3, 4},
    {0, 5},
    {5, 6},
    {6, 7},
    {7, 8},
    {0, 9},
    {9, 10},
    {10, 11},
    {11, 12},
    {0, 13},
    {13, 14},
    {14, 15},
    {15, 16},
    {0, 17},
    {17, 18},
    {18, 19},
    {19, 20}
  ]

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

  @impl true
  def init(opts) do
    state = %{
      capture: nil,
      frame: nil,
      error: nil,
      opts: opts,
      paused: false,
      retry_count: 0,
      net: load_model()
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

  @impl true
  def handle_info(:open_camera, state) do
    device = Keyword.fetch!(state.opts, :device)

    case Evision.VideoCapture.videoCapture(device) do
      {:ok, capture} ->
        Logger.info("camera opened device=#{device}")
        schedule_grab(capture, %{state | retry_count: 0})

      %Evision.VideoCapture{} = capture ->
        Logger.info("camera opened device=#{device}")
        schedule_grab(capture, %{state | retry_count: 0})

      {:error, reason} ->
        retry = min(500 * trunc(:math.pow(2, min(state.retry_count, 4))), 8_000)
        Process.send_after(self(), :open_camera, retry)

        {:noreply,
         %{state | error: "カメラを開けません: #{inspect(reason)}", retry_count: state.retry_count + 1}}
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
        {:ok, %Evision.Mat{} = frame} ->
          frame
          |> maybe_predict_and_overlay(state.net)
          |> put_frame(state)

        {ok, %Evision.Mat{} = frame} when ok in [true, :ok, :error] ->
          frame
          |> maybe_predict_and_overlay(state.net)
          |> put_frame(state)

        %Evision.Mat{} = frame ->
          frame
          |> maybe_predict_and_overlay(state.net)
          |> put_frame(state)

        other ->
          %{state | error: "フレーム取得失敗: #{inspect(other)}"}
      end

    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, next_state}
  end

  @impl true
  def terminate(_reason, state) do
    if not is_nil(state.capture), do: Evision.VideoCapture.release(state.capture)
    :ok
  end

  defp load_model do
    path = Path.expand(@model_path, File.cwd!())

    if File.exists?(path) do
      case Evision.DNN.readNet(path) do
        {:ok, net} ->
          Logger.info("onnx model loaded: #{path}")
          net

        net when not is_tuple(net) ->
          Logger.info("onnx model loaded: #{path}")
          net

        err ->
          Logger.warning("onnx model load failed: #{inspect(err)}")
          nil
      end
    else
      Logger.warning("onnx model not found: #{path}")
      nil
    end
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

  defp put_frame(frame, state) do
    %{state | frame: to_rgb_binary(frame), error: nil}
  end

  defp maybe_predict_and_overlay(frame, nil), do: frame

  defp maybe_predict_and_overlay(frame, net) do
    with {:ok, blob} <- make_blob(frame),
         :ok <- set_input(net, blob),
         {:ok, out} <- forward(net),
         points when is_list(points) <- decode_points(out, frame) do
      draw_skeleton(frame, points)
    else
      _ -> frame
    end
  end

  defp make_blob(frame) do
    blob =
      Evision.DNN.blobFromImage(frame,
        scalefactor: 1.0 / 255.0,
        size: {224, 224},
        mean: {0.0, 0.0, 0.0},
        swapRB: true,
        crop: false
      )

    {:ok, blob}
  rescue
    _ -> {:error, :blob}
  end

  defp set_input(net, blob) do
    _ = Evision.DNN.Net.setInput(net, blob)
    :ok
  rescue
    _ -> {:error, :set_input}
  end

  defp forward(net) do
    out = Evision.DNN.Net.forward(net)
    {:ok, out}
  rescue
    _ -> {:error, :forward}
  end

  defp decode_points(out, frame) do
    {h, w, _} = Evision.Mat.shape(frame)
    vals = Nx.to_flat_list(Evision.Mat.to_nx(out))

    if rem(length(vals), 3) == 0 do
      vals
      |> Enum.chunk_every(3)
      |> Enum.take(21)
      |> Enum.map(fn [x, y, score] -> {trunc(x * w), trunc(y * h), score} end)
    else
      []
    end
  rescue
    _ -> []
  end

  defp draw_skeleton(frame, points) do
    green = {0, 255, 0}

    points
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {{x, y, score}, _idx}, acc ->
      if score >= @score_threshold do
        Evision.circle(acc, {x, y}, 3, color: green, thickness: -1)
      else
        acc
      end
    end)
    |> then(fn mat ->
      Enum.reduce(@connections, mat, fn {a, b}, acc ->
        case {Enum.at(points, a), Enum.at(points, b)} do
          {{x1, y1, s1}, {x2, y2, s2}} when s1 >= @score_threshold and s2 >= @score_threshold ->
            Evision.line(acc, {x1, y1}, {x2, y2}, color: green, thickness: 2)

          _ ->
            acc
        end
      end)
    end)
  rescue
    _ -> frame
  end

  defp to_rgb_binary(frame) do
    rgb = Evision.cvtColor(frame, Evision.Constant.cv_COLOR_BGR2RGB())
    data = Evision.Mat.to_binary(rgb)
    {h, w, _} = Evision.Mat.shape(rgb)
    %{width: w, height: h, data: data}
  end
end

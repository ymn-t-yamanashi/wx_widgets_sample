defmodule ElixirWxHandPoseViewer.Camera do
  @moduledoc false
  use GenServer
  require Logger

  @interval_ms 33

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def latest_frame, do: GenServer.call(__MODULE__, :latest_frame)
  def toggle_pause, do: GenServer.call(__MODULE__, :toggle_pause)

  @impl true
  def init(opts) do
    state = %{
      capture: nil,
      frame: nil,
      error: nil,
      opts: opts,
      paused: false,
      tick: 0,
      model: load_model()
    }

    Process.send_after(self(), :open_camera, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:latest_frame, _from, state), do: {:reply, frame_reply(state), state}

  def handle_call(:toggle_pause, _from, state),
    do: {:reply, {:ok, !state.paused}, %{state | paused: !state.paused}}

  @impl true
  def handle_info(:open_camera, state) do
    case Evision.VideoCapture.videoCapture(Keyword.get(state.opts, :device, 0)) do
      {:ok, cap} ->
        schedule_grab(cap, state)

      %Evision.VideoCapture{} = cap ->
        schedule_grab(cap, state)

      err ->
        Process.send_after(self(), :open_camera, 1000)
        {:noreply, %{state | error: "open fail: #{inspect(err)}"}}
    end
  end

  def handle_info(:grab_frame, %{capture: nil} = state),
    do:
      (
        Process.send_after(self(), :open_camera, 1000)
        {:noreply, state}
      )

  def handle_info(:grab_frame, %{paused: true} = state),
    do:
      (
        Process.send_after(self(), :grab_frame, @interval_ms)
        {:noreply, state}
      )

  def handle_info(:grab_frame, state) do
    tick = state.tick + 1

    next =
      case Evision.VideoCapture.read(state.capture) do
        {:ok, %Evision.Mat{} = f} ->
          process_and_store(f, %{state | tick: tick})

        {ok, %Evision.Mat{} = f} when ok in [true, :ok, :error] ->
          process_and_store(f, %{state | tick: tick})

        %Evision.Mat{} = f ->
          process_and_store(f, %{state | tick: tick})

        other ->
          %{state | tick: tick, error: "read fail: #{inspect(other)}"}
      end

    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, next}
  end

  @impl true
  def terminate(_, state) do
    if state.capture, do: Evision.VideoCapture.release(state.capture)
    :ok
  end

  defp load_model do
    case ElixirWxHandPoseViewer.HandInference.load() do
      {:ok, model} -> model
      _ -> nil
    end
  end

  defp schedule_grab(cap, state) do
    Evision.VideoCapture.set(
      cap,
      Evision.Constant.cv_CAP_PROP_FRAME_WIDTH(),
      Keyword.get(state.opts, :width, 640)
    )

    Evision.VideoCapture.set(
      cap,
      Evision.Constant.cv_CAP_PROP_FRAME_HEIGHT(),
      Keyword.get(state.opts, :height, 480)
    )

    Evision.VideoCapture.set(
      cap,
      Evision.Constant.cv_CAP_PROP_FPS(),
      Keyword.get(state.opts, :fps, 30)
    )

    Logger.info("camera opened device=#{Keyword.get(state.opts, :device, 0)}")
    Process.send_after(self(), :grab_frame, @interval_ms)
    {:noreply, %{state | capture: cap, error: nil}}
  end

  defp frame_reply(%{frame: nil, error: err}) when is_binary(err), do: {:error, err}
  defp frame_reply(%{frame: nil}), do: {:error, "カメラ初期化中..."}
  defp frame_reply(%{frame: frame}), do: {:ok, frame}

  defp process_and_store(frame, state) do
    out = process_frame(frame, state)
    put_frame(out, state)
  end

  defp process_frame(frame, %{model: nil}), do: draw_debug_text(frame, "MODEL NOT LOADED")

  defp process_frame(frame, state) do
    {h, w, _} = Evision.Mat.shape(frame)
    s = trunc(min(w, h) * 0.7)
    x = max(div(w - s, 2), 0)
    y = max(div(h - s, 2), 0)
    roi = Evision.Mat.roi(frame, {x, y, s, s})

    case ElixirWxHandPoseViewer.HandInference.infer_debug(state.model, roi) do
      {:ok, points, meta} when is_list(points) and points != [] ->
        if rem(state.tick, 30) == 0,
          do:
            Logger.info(
              "[detect] points=#{length(points)} score=#{inspect(meta[:hand_score])} sample=#{inspect(Enum.take(points, 3))}"
            )

        mapped = Enum.map(points, fn {px, py, sc} -> {x + px, y + py, sc} end)

        frame
        |> draw_skeleton(mapped)
        |> draw_debug_text("ORTEX ON")

      {:error, reason, meta} ->
        if rem(state.tick, 30) == 0,
          do: Logger.info("[detect:miss] reason=#{inspect(reason)} meta=#{inspect(meta)}")

        draw_debug_text(frame, "NO HAND")
    end
  rescue
    _ -> draw_debug_text(frame, "INFER ERROR")
  end

  defp draw_skeleton(frame, points) do
    green = {0, 255, 0}

    Enum.reduce(points, frame, fn {x, y, _s}, acc ->
      Evision.circle(acc, {x, y}, 3, green, thickness: -1)
    end)
  rescue
    _ -> frame
  end

  defp draw_debug_text(frame, text) do
    Evision.putText(
      frame,
      text,
      {20, 40},
      Evision.Constant.cv_FONT_HERSHEY_SIMPLEX(),
      1.0,
      {0, 255, 0},
      thickness: 2
    )
  rescue
    _ -> frame
  end

  defp put_frame(frame, state), do: %{state | frame: to_rgb_binary(frame), error: nil}

  defp to_rgb_binary(frame) do
    rgb = Evision.cvtColor(frame, Evision.Constant.cv_COLOR_BGR2RGB())
    {h, w, _} = Evision.Mat.shape(rgb)
    %{width: w, height: h, data: Evision.Mat.to_binary(rgb)}
  end
end

defmodule ElixirWxHandPoseViewer.Camera do
  @moduledoc """
  カメラキャプチャと手推論を担当する GenServer です。

  - フレーム取得
  - ROI 探索と手キーポイント推論
  - スケルトン描画済みフレームの共有
  """
  use GenServer
  require Logger

  @interval_ms 16
  @infer_every_n_frames 2
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

  @doc """
  カメラサーバーを起動します。
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  最新フレームを取得します。

  戻り値:
  - `{:ok, %{width: integer(), height: integer(), data: binary()}}`
  - `{:error, reason}`
  """
  def latest_frame, do: GenServer.call(__MODULE__, :latest_frame)

  @doc """
  一時停止状態をトグルします。

  戻り値は `{:ok, paused?}` です。
  """
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

  # 手推論モデルをロードし、利用バックエンド情報をログ出力する。
  defp load_model do
    case ElixirWxHandPoseViewer.HandInference.load() do
      {:ok, model} ->
        Logger.info("[hand_inference] backend=#{ElixirWxHandPoseViewer.HandInference.backend()}")
        model

      _ ->
        nil
    end
  end

  # カメラパラメータを設定し、フレーム取得ループを開始する。
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

  # フレーム未取得時のAPI応答形式を統一する。
  defp frame_reply(%{frame: nil, error: err}) when is_binary(err), do: {:error, err}
  defp frame_reply(%{frame: nil}), do: {:error, "カメラ初期化中..."}
  defp frame_reply(%{frame: frame}), do: {:ok, frame}

  # 推論間引きと描画を含む1フレーム処理を行う。
  defp process_and_store(frame, state) do
    out =
      if rem(state.tick, @infer_every_n_frames) == 0 do
        process_frame(frame, state)
      else
        draw_debug_text(frame, "TRACKING")
      end

    put_frame(out, state)
  end

  # モデル未ロード時のプレースホルダー表示。
  defp process_frame(frame, %{model: nil}), do: draw_debug_text(frame, "MODEL NOT LOADED")

  # 複数ROIを探索して手候補を選別し、スケルトン描画を行う。
  defp process_frame(frame, state) do
    rois = hand_rois(frame)

    detections =
      Enum.reduce(rois, [], fn {x, y, s, roi_label}, acc ->
        roi = Evision.Mat.roi(frame, {x, y, s, s})

        case ElixirWxHandPoseViewer.HandInference.infer_debug(state.model, roi) do
          {:ok, points, meta} when is_list(points) and points != [] ->
            if rem(state.tick, 30) == 0 do
              Logger.info(
                "[detect] roi=#{roi_label} points=#{length(points)} score=#{inspect(meta[:hand_score])} sample=#{inspect(Enum.take(points, 3))}"
              )
            end

            mapped = Enum.map(points, fn {px, py, sc} -> {x + px, y + py, sc} end)

            if hand_like?(mapped) do
              [%{points: mapped, score: meta[:hand_score] || 0.0, roi: roi_label} | acc]
            else
              if rem(state.tick, 30) == 0 do
                Logger.info("[detect:reject] roi=#{roi_label} reason=:not_hand_shape")
              end

              acc
            end

          {:error, reason, meta} ->
            if rem(state.tick, 30) == 0 do
              Logger.info(
                "[detect:miss] roi=#{roi_label} reason=#{inspect(reason)} meta=#{inspect(meta)}"
              )
            end

            acc
        end
      end)

    selected =
      detections
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.reduce([], fn det, acc ->
        if overlaps_any?(det, acc), do: acc, else: [det | acc]
      end)
      |> Enum.reverse()
      |> Enum.take(2)

    drawn = Enum.reduce(selected, frame, fn det, acc -> draw_skeleton(acc, det.points) end)
    detected_count = length(selected)

    case detected_count do
      0 -> draw_debug_text(drawn, "NO HAND")
      1 -> draw_debug_text(drawn, "ONE HAND")
      _ -> draw_debug_text(drawn, "TWO HANDS")
    end
  rescue
    _ -> draw_debug_text(frame, "INFER ERROR")
  end

  # 探索用ROIを画面グリッド状に生成する。
  defp hand_rois(frame) do
    {h, w, _} = Evision.Mat.shape(frame)
    s = trunc(min(w, h) * 0.52)
    x_positions = [0.0, 0.32, 0.64]
    y_positions = [0.0, 0.34]

    for y_ratio <- y_positions,
        x_ratio <- x_positions do
      x = min(max(trunc(w * x_ratio), 0), max(w - s, 0))
      y = min(max(trunc(h * y_ratio), 0), max(h - s, 0))
      {x, y, s, "#{x_ratio}_#{y_ratio}"}
    end
  end

  # 候補同士の重なりを見て重複検出を抑制する。
  defp overlaps_any?(det, selected) do
    Enum.any?(selected, fn s -> iou(bbox(det.points), bbox(s.points)) > 0.3 end)
  end

  # キーポイント群の外接矩形を返す。
  defp bbox(points) do
    xs = Enum.map(points, fn {x, _, _} -> x end)
    ys = Enum.map(points, fn {_, y, _} -> y end)
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  # 2つの矩形のIoUを計算する。
  defp iou({ax1, ay1, ax2, ay2}, {bx1, by1, bx2, by2}) do
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    iw = max(ix2 - ix1, 0)
    ih = max(iy2 - iy1, 0)
    inter = iw * ih
    area_a = max(ax2 - ax1, 0) * max(ay2 - ay1, 0)
    area_b = max(bx2 - bx1, 0) * max(by2 - by1, 0)
    denom = area_a + area_b - inter
    if denom <= 0, do: 0.0, else: inter / denom
  end

  # 手らしさ判定の前提として必要点数を確認する。
  defp hand_like?(points) when length(points) < 21, do: false

  # 幾何特徴量で顔などの誤検出を除外する。
  defp hand_like?(points) do
    {x1, y1, x2, y2} = bbox(points)
    w = max(x2 - x1, 1)
    h = max(y2 - y1, 1)
    area = w * h
    ratio = w / h

    wrist = Enum.at(points, 0)
    tips = [4, 8, 12, 16, 20] |> Enum.map(&Enum.at(points, &1))
    dists = Enum.map(tips, &dist(wrist, &1))
    spread = Enum.max(dists) / max(Enum.min(dists), 1.0)
    mean_tip = Enum.sum(dists) / max(length(dists), 1)

    finger_count =
      [4, 8, 12, 16, 20]
      |> Enum.count(fn idx ->
        {tip_x, tip_y, _} = Enum.at(points, idx)
        {wrist_x, wrist_y, _} = wrist

        :math.sqrt((tip_x - wrist_x) * (tip_x - wrist_x) + (tip_y - wrist_y) * (tip_y - wrist_y)) >
          28
      end)

    area > 1800 and area < 130_000 and ratio > 0.45 and ratio < 2.2 and spread > 1.03 and
      mean_tip > 14 and
      finger_count >= 2
  rescue
    _ -> false
  end

  # 2点間のユークリッド距離を返す。
  defp dist({x1, y1, _}, {x2, y2, _}) do
    :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
  end

  # キーポイント同士を線で結び、節点を描画する。
  defp draw_skeleton(frame, points) do
    green = {0, 255, 0}

    with_lines =
      Enum.reduce(@connections, frame, fn {a, b}, acc ->
        case {Enum.at(points, a), Enum.at(points, b)} do
          {{x1, y1, _}, {x2, y2, _}} ->
            Evision.line(acc, {x1, y1}, {x2, y2}, green, thickness: 2)

          _ ->
            acc
        end
      end)

    Enum.reduce(points, with_lines, fn {x, y, _s}, acc ->
      Evision.circle(acc, {x, y}, 3, green, thickness: -1)
    end)
  rescue
    _ -> frame
  end

  # フレーム左上へステータステキストを重畳する。
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

  # 内部MatをGUI描画向けのRGBバイナリへ変換して保持する。
  defp put_frame(frame, state), do: %{state | frame: to_rgb_binary(frame), error: nil}

  # BGRのMatをRGBバイナリ形式へ変換する。
  defp to_rgb_binary(frame) do
    rgb = Evision.cvtColor(frame, Evision.Constant.cv_COLOR_BGR2RGB())
    {h, w, _} = Evision.Mat.shape(rgb)
    %{width: w, height: h, data: Evision.Mat.to_binary(rgb)}
  end
end

defmodule ElixirWxHandPoseViewer.HandInference do
  @moduledoc """
  ONNX モデルのロードと手キーポイント推論を担当します。

  入力画像の前処理、推論実行、座標の後処理までを 1 モジュールで完結させます。
  """
  require Logger

  @model_path "priv/models/hand_keypoint.onnx"
  @input_size 224

  @doc """
  推論モデルをロードします。

  `ENABLE_GPU=1`（または `ENABLE_DNN=1`）時は CUDA を試行し、
  失敗した場合は CPU にフォールバックします。
  """
  def load do
    path = Path.expand(@model_path, File.cwd!())

    cond do
      not File.exists?(path) ->
        {:error, :model_not_found}

      not Code.ensure_loaded?(Ortex) ->
        {:error, :ortex_unavailable}

      true ->
        load_with_provider_fallback(path)
    end
  rescue
    _ -> {:error, :load_failed}
  end

  @doc """
  現在の推論バックエンドを返します。

  戻り値:
  - `:gpu`
  - `:cpu`
  - `:unknown`
  """
  def backend do
    :persistent_term.get({__MODULE__, :backend}, :unknown)
  end

  # GPU要求時はCUDA単独ロードを試し、失敗時はCPUへフォールバックする。
  defp load_with_provider_fallback(path) do
    if gpu_requested?() do
      case try_load(path, [:cuda]) do
        {:ok, model} ->
          :persistent_term.put({__MODULE__, :backend}, :gpu)
          Logger.info("[hand_inference] loaded providers=[:cuda] (GPU active)")
          {:ok, model}

        {:error, reason} ->
          Logger.warning(
            "[hand_inference] cuda probe failed reason=#{inspect(reason)} -> fallback cpu"
          )

          model = Ortex.load(path, [:cpu])
          :persistent_term.put({__MODULE__, :backend}, :cpu)
          {:ok, model}
      end
    else
      model = Ortex.load(path, [:cpu])
      :persistent_term.put({__MODULE__, :backend}, :cpu)
      Logger.info("[hand_inference] loaded providers=[:cpu]")
      {:ok, model}
    end
  end

  # 例外を捕捉してロード失敗理由を呼び出し元へ返せる形にする。
  defp try_load(path, providers) do
    {:ok, Ortex.load(path, providers)}
  rescue
    e -> {:error, e}
  end

  # GPU利用を有効化する環境変数の真偽を判定する。
  defp gpu_requested? do
    gpu_flag = System.get_env("ENABLE_GPU") || System.get_env("ENABLE_DNN") || "0"
    gpu_flag in ["1", "true", "TRUE", "yes", "YES"]
  end

  @doc """
  ROI画像に対して推論を実行し、手キーポイントを返します。
  """
  def infer(model, roi_mat) do
    case infer_debug(model, roi_mat) do
      {:ok, points, _meta} -> {:ok, points}
      {:error, reason, _meta} -> {:error, reason}
    end
  end

  @doc """
  `infer/2` の詳細版です。

  キーポイントに加えて、デバッグ向けメタ情報を返します。
  """
  def infer_debug(model, roi_mat) do
    with {:ok, tensor, width, height} <- preprocess(roi_mat),
         outputs <- Ortex.run(model, tensor),
         {:ok, points, meta} <- postprocess(outputs, width, height) do
      {:ok, points, meta}
    else
      {:error, reason} -> {:error, reason, %{}}
      _ -> {:error, :inference_failed, %{}}
    end
  rescue
    _ -> {:error, :inference_failed, %{}}
  end

  # ROIをモデル入力形式 (1x224x224x3, float32, 0..1) へ変換する。
  defp preprocess(roi_mat) do
    rgb = Evision.cvtColor(roi_mat, Evision.Constant.cv_COLOR_BGR2RGB())
    {h, w, _} = Evision.Mat.shape(rgb)
    resized = Evision.resize(rgb, {@input_size, @input_size})
    bin = Evision.Mat.to_binary(resized)

    tensor =
      bin
      |> Nx.from_binary(:u8)
      |> Nx.reshape({@input_size, @input_size, 3})
      |> Nx.as_type(:f32)
      |> Nx.divide(255.0)
      |> Nx.reshape({1, @input_size, @input_size, 3})

    {:ok, tensor, w, h}
  rescue
    _ -> {:error, :preprocess_failed}
  end

  # モデル出力からランドマークとメタ情報を抽出する。
  defp postprocess({landmarks, hand_score, _handedness, _world}, width, height) do
    score = hand_score |> tensor_first_value() |> normalize_score()
    points = decode_landmarks(landmarks, width, height)

    if points == [],
      do: {:error, :no_points},
      else: {:ok, points, %{hand_score: score, point_count: length(points)}}
  rescue
    _ -> {:error, :postprocess_failed}
  end

  defp postprocess({landmarks}, width, height),
    do: {:ok, decode_landmarks(landmarks, width, height), %{hand_score: nil}}

  defp postprocess(landmarks, width, height),
    do: {:ok, decode_landmarks(landmarks, width, height), %{hand_score: nil}}

  # ランドマーク配列を画面座標へスケールする。
  defp decode_landmarks(landmarks, width, height) do
    landmarks
    |> Nx.to_flat_list()
    |> Enum.chunk_every(3)
    |> Enum.map(fn [x, y, z] ->
      {scale_x(x, width), scale_y(y, height), score_from_z(z)}
    end)
  end

  # スコアがロジットの場合に備えて 0..1 へ正規化する。
  defp normalize_score(v) when v >= 0.0 and v <= 1.0, do: v
  defp normalize_score(v), do: 1.0 / (1.0 + :math.exp(-v))

  # モデル出力値のスケール差異に対応して X 座標へ変換する。
  defp scale_x(x, width) when x >= 0.0 and x <= 1.0, do: clamp(round(x * width), 0, width - 1)
  defp scale_x(x, width), do: clamp(round(x * width / @input_size), 0, width - 1)
  # モデル出力値のスケール差異に対応して Y 座標へ変換する。
  defp scale_y(y, height) when y >= 0.0 and y <= 1.0, do: clamp(round(y * height), 0, height - 1)
  defp scale_y(y, height), do: clamp(round(y * height / @input_size), 0, height - 1)

  # Zを疑似的な信頼度へ変換して描画ロジックに渡す。
  defp score_from_z(z) do
    # Landmark-only model has no per-point confidence, so expose pseudo score.
    1.0 / (1.0 + abs(z))
  end

  # スカラー扱いしたいテンソルから先頭要素を取り出す。
  defp tensor_first_value(tensor) do
    case Nx.to_flat_list(tensor) do
      [v | _] -> v
      _ -> 0.0
    end
  end

  # 値を[min, max]に収める。
  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end

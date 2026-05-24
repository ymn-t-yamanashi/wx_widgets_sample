defmodule ElixirWxHandPoseViewer.HandInference do
  @moduledoc false
  require Logger

  @model_path "priv/models/hand_keypoint.onnx"
  @input_size 224

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

  def backend do
    :persistent_term.get({__MODULE__, :backend}, :unknown)
  end

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

  defp try_load(path, providers) do
    {:ok, Ortex.load(path, providers)}
  rescue
    e -> {:error, e}
  end

  defp gpu_requested? do
    gpu_flag = System.get_env("ENABLE_GPU") || System.get_env("ENABLE_DNN") || "0"
    gpu_flag in ["1", "true", "TRUE", "yes", "YES"]
  end

  def infer(model, roi_mat) do
    case infer_debug(model, roi_mat) do
      {:ok, points, _meta} -> {:ok, points}
      {:error, reason, _meta} -> {:error, reason}
    end
  end

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

  defp decode_landmarks(landmarks, width, height) do
    landmarks
    |> Nx.to_flat_list()
    |> Enum.chunk_every(3)
    |> Enum.map(fn [x, y, z] ->
      {scale_x(x, width), scale_y(y, height), score_from_z(z)}
    end)
  end

  defp normalize_score(v) when v >= 0.0 and v <= 1.0, do: v
  defp normalize_score(v), do: 1.0 / (1.0 + :math.exp(-v))

  defp scale_x(x, width) when x >= 0.0 and x <= 1.0, do: clamp(round(x * width), 0, width - 1)
  defp scale_x(x, width), do: clamp(round(x * width / @input_size), 0, width - 1)
  defp scale_y(y, height) when y >= 0.0 and y <= 1.0, do: clamp(round(y * height), 0, height - 1)
  defp scale_y(y, height), do: clamp(round(y * height / @input_size), 0, height - 1)

  defp score_from_z(z) do
    # Landmark-only model has no per-point confidence, so expose pseudo score.
    1.0 / (1.0 + abs(z))
  end

  defp tensor_first_value(tensor) do
    case Nx.to_flat_list(tensor) do
      [v | _] -> v
      _ -> 0.0
    end
  end

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end

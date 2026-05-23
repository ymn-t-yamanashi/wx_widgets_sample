defmodule ElixirWxCameraViewer.GUI do
  @moduledoc false

  use GenServer
  require Record

  Record.defrecord(:wxKey, Record.extract(:wxKey, from_lib: "wx/include/wx.hrl"))

  @timer_ms 33

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    wx = :wx.new()
    frame = :wxFrame.new(wx, -1, ~c"Elixir wx Camera Viewer", size: {900, 640})
    panel = :wxPanel.new(frame)
    image_box = :wxStaticBitmap.new(panel, -1, :wxBitmap.new(1, 1))

    :wxWindow.connect(panel, :size)
    :wxWindow.connect(panel, :char_hook)
    :wxWindow.connect(frame, :char_hook)
    :wxFrame.connect(frame, :close_window)

    :wxFrame.show(frame)
    :wxWindow.setFocus(panel)

    timer = Process.send_after(self(), :refresh, @timer_ms)

    {:ok,
     Map.merge(state, %{
       wx: wx,
       frame: frame,
       panel: panel,
       image_box: image_box,
       timer: timer,
       paused: false,
       last_frame: nil
     })}
  end

  @impl true
  def handle_info(:refresh, state) do
    state =
      case ElixirWxCameraViewer.Camera.latest_frame() do
        {:ok, frame} -> render_frame(frame, state)
        {:error, reason} -> put_status(state, to_string(reason))
      end

    timer = Process.send_after(self(), :refresh, @timer_ms)
    {:noreply, %{state | timer: timer}}
  end

  def handle_info({:wx, _, _, _, {:wxSize, :size, _w, _h}}, state) do
    if state.last_frame, do: render_frame(state.last_frame, state)
    {:noreply, state}
  end

  def handle_info(wxKey(type: type, keyCode: key_code), state)
      when type in [:char, :char_hook, :key_down] do
    handle_key(key_code, state)
  end

  def handle_info({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    :wxFrame.destroy(state.frame)
    :wx.destroy()
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp handle_key(27, state),
    do: handle_info({:wx, nil, nil, nil, {:wxClose, :close_window}}, state)

  defp handle_key(32, state) do
    case ElixirWxCameraViewer.Camera.toggle_pause() do
      {:ok, paused} ->
        {:noreply, put_status(%{state | paused: paused}, if(paused, do: "一時停止中", else: "再開"))}

      {:error, _} ->
        {:noreply, put_status(state, "カメラ制御エラー")}
    end
  end

  defp handle_key(?s, state), do: save_snapshot(state)
  defp handle_key(?S, state), do: save_snapshot(state)
  defp handle_key(_, state), do: {:noreply, state}

  defp save_snapshot(state) do
    ts =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()
      |> String.replace(":", "-")

    path = Path.join(File.cwd!(), "snapshot_#{ts}.png")

    msg =
      case ElixirWxCameraViewer.Camera.save_snapshot(path) do
        :ok -> "保存: #{path}"
        {:error, :no_frame} -> "保存失敗: フレームなし"
        _ -> "保存失敗"
      end

    {:noreply, put_status(state, msg)}
  end

  defp render_frame(frame, state) do
    bitmap = fit_bitmap(frame, state.panel)
    :wxStaticBitmap.setBitmap(state.image_box, bitmap)
    :wxBitmap.destroy(bitmap)
    %{state | last_frame: frame}
  end

  defp fit_bitmap(%{data: data, width: src_w, height: src_h}, panel) do
    {dst_w, dst_h} = :wxWindow.getClientSize(panel)
    src_ratio = src_w / max(src_h, 1)
    dst_ratio = dst_w / max(dst_h, 1)

    {draw_w, draw_h} =
      if src_ratio > dst_ratio do
        w = max(dst_w, 1)
        {w, trunc(w / src_ratio)}
      else
        h = max(dst_h, 1)
        {trunc(h * src_ratio), h}
      end

    :wxWindow.setSize(panel, 0, 0, max(dst_w, 1), max(dst_h, 1))
    :wxWindow.setSize(stateful_image_box(panel), 0, 0, max(draw_w, 1), max(draw_h, 1))

    image = :wxImage.new(src_w, src_h, data)
    scaled = :wxImage.scale(image, max(draw_w, 1), max(draw_h, 1))
    bitmap = :wxBitmap.new(scaled)
    :wxImage.destroy(scaled)
    :wxImage.destroy(image)
    bitmap
  end

  defp stateful_image_box(panel) do
    [child | _] = :wxWindow.getChildren(panel)
    child
  end

  defp put_status(state, msg) do
    :wxFrame.setTitle(state.frame, to_charlist("Elixir wx Camera Viewer - " <> msg))
    state
  end
end

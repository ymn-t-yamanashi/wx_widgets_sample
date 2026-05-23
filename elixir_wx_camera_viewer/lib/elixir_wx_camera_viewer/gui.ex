defmodule ElixirWxCameraViewer.GUI do
  @moduledoc false

  use GenServer

  @timer_ms 33

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    wx = :wx.new()
    frame = :wxFrame.new(wx, -1, ~c"Elixir wx Camera Viewer", size: {800, 600})
    panel = :wxPanel.new(frame)

    :wxFrame.connect(frame, :close_window)
    :wxFrame.show(frame)

    timer = Process.send_after(self(), :refresh, @timer_ms)
    {:ok, Map.merge(state, %{wx: wx, frame: frame, panel: panel, timer: timer})}
  end

  @impl true
  def handle_info(:refresh, state) do
    draw_latest_frame(state.panel)
    timer = Process.send_after(self(), :refresh, @timer_ms)
    {:noreply, %{state | timer: timer}}
  end

  def handle_info({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    :wxFrame.destroy(state.frame)
    :wx.destroy()
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp draw_latest_frame(panel) do
    dc = :wxClientDC.new(panel)

    case ElixirWxCameraViewer.Camera.latest_frame() do
      {:ok, %{data: data, width: w, height: h}} ->
        image = :wxImage.new(w, h, data)
        bitmap = :wxBitmap.new(image)
        :wxDC.clear(dc)
        :wxDC.drawBitmap(dc, bitmap, {0, 0})
        :wxBitmap.destroy(bitmap)
        :wxImage.destroy(image)

      {:error, reason} ->
        msg = to_charlist(reason)
        :wxDC.clear(dc)
        :wxDC.drawText(dc, msg, {20, 20})
    end

    :wxClientDC.destroy(dc)
  end
end

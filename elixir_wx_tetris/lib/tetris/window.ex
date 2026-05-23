defmodule Tetris.Window do
  use GenServer
  require Record
  alias Tetris.{GameLoop, Input, Renderer}

  Record.defrecord(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecord(:wxKey, Record.extract(:wxKey, from_lib: "wx/include/wx.hrl"))

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_) do
    wx = :wx.new()
    {w, h} = Renderer.viewport_size()
    frame = :wxFrame.new(wx, -1, ~c"Elixir wx Tetris", size: {w, h})
    canvas = :wxGLCanvas.new(frame)
    gl_ctx = :wxGLContext.new(canvas)

    :wxWindow.connect(canvas, :paint)
    :wxWindow.connect(canvas, :size)
    :wxWindow.connect(canvas, :char_hook)
    :wxWindow.connect(frame, :char_hook)
    :wxFrame.connect(frame, :close_window)

    :wxFrame.show(frame)
    :wxWindow.setFocus(canvas)
    timer_ref = Process.send_after(self(), :tick, 16)

    {:ok, %{wx: wx, frame: frame, canvas: canvas, gl_ctx: gl_ctx, timer_ref: timer_ref}}
  end

  def handle_info(:tick, state) do
    :wxWindow.refresh(state.canvas)
    timer_ref = Process.send_after(self(), :tick, 16)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  def handle_info({:wx, _, _, _, {:wxPaint, :paint}}, state) do
    :wxGLCanvas.setCurrent(state.canvas, state.gl_ctx)
    {w, h} = :wxWindow.getClientSize(state.canvas)
    Renderer.draw_gl(GameLoop.state(), w, h)
    :wxGLCanvas.swapBuffers(state.canvas)
    {:noreply, state}
  end

  def handle_info({:wx, _, _, _, {:wxSize, :size, _w, _h}}, state) do
    :wxWindow.refresh(state.canvas)
    {:noreply, state}
  end

  def handle_info(wx(event: wxKey(type: type, keyCode: key_code, uniChar: unicode)), state)
      when type in [:char_hook, :key_down] do
    action = Input.to_action(%{key_code: key_code, unicode_key: unicode})
    GameLoop.action(action)
    {:noreply, state}
  end

  def handle_info({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    :wxFrame.destroy(state.frame)
    :wx.destroy()
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end

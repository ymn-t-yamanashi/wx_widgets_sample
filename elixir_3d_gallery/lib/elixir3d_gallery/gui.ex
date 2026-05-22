defmodule Elixir3dGallery.GUI do
  @moduledoc false

  use GenServer
  require Record

  Record.defrecord(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecord(:wxMouse, Record.extract(:wxMouse, from_lib: "wx/include/wx.hrl"))
  Record.defrecord(:wxKey, Record.extract(:wxKey, from_lib: "wx/include/wx.hrl"))

  @timer_ms 16
  @color_buffer_bit 0x4000
  @depth_buffer_bit 0x0100
  @depth_test 0x0B71
  @cull_face 0x0B44
  @back 0x0405
  @smooth 0x1D01
  @perspective_correction_hint 0x0C50
  @nicest 0x1102
  @projection 0x1701
  @modelview 0x1700
  @lines 0x0001
  @quads 0x0007
  @quad_strip 0x0008
  @triangle_fan 0x0006

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_state) do
    wx = :wx.new()
    frame = :wxFrame.new(wx, -1, ~c"Elixir 3D Gallery", size: {980, 700})
    canvas = :wxGLCanvas.new(frame)
    gl_ctx = :wxGLContext.new(canvas)

    :wxWindow.connect(canvas, :paint)
    :wxWindow.connect(canvas, :size)
    :wxWindow.connect(canvas, :left_down)
    :wxWindow.connect(canvas, :left_up)
    :wxWindow.connect(canvas, :motion)
    :wxWindow.connect(canvas, :mousewheel)
    :wxWindow.connect(canvas, :char)
    :wxWindow.connect(canvas, :char_hook)
    :wxWindow.connect(frame, :char_hook)
    :wxFrame.connect(frame, :close_window)

    timer_ref = Process.send_after(self(), :tick, @timer_ms)
    :wxFrame.show(frame)
    :wxWindow.setFocus(canvas)

    {:ok,
     %{
       wx: wx,
       frame: frame,
       canvas: canvas,
       gl_ctx: gl_ctx,
       timer_ref: timer_ref,
       yaw: 38.0,
       pitch: -32.0,
       zoom: 7.0,
       auto_rotate: true,
       shape: :cube,
       dragging: false,
       last_mouse: {0, 0},
       rot: 0.0,
       gl_inited: false
     }}
  end

  @impl true
  def handle_info({:wx, _, _, _, {:wxPaint, :paint}}, state), do: {:noreply, render(state)}

  def handle_info({:wx, _, _, _, {:wxSize, :size, _w, _h}}, state) do
    :wxWindow.refresh(state.canvas)
    {:noreply, state}
  end

  def handle_info(wx(event: wxMouse(type: :left_down, x: x, y: y)), state) do
    :wxWindow.setFocus(state.canvas)
    {:noreply, %{state | dragging: true, last_mouse: {x, y}}}
  end

  def handle_info(wx(event: wxMouse(type: :left_up)), state),
    do: {:noreply, %{state | dragging: false}}

  def handle_info(wx(event: wxMouse(type: :motion, x: x, y: y)), %{dragging: true} = state) do
    {lx, ly} = state.last_mouse
    dx = x - lx
    dy = y - ly

    {:noreply,
     %{
       state
       | yaw: state.yaw + dx * 0.45,
         pitch: clamp(state.pitch + dy * 0.35, -89.0, 89.0),
         last_mouse: {x, y}
     }}
  end

  def handle_info(wx(event: wxMouse(type: :mousewheel, wheelRotation: wheel)), state) do
    step = if wheel > 0, do: -0.4, else: 0.4
    {:noreply, %{state | zoom: clamp(state.zoom + step, 2.0, 25.0)}}
  end

  def handle_info(wx(event: wxKey(type: type, keyCode: key_code)), state)
      when type in [:char, :char_hook, :key_down] do
    case normalize_hotkey(key_code) do
      nil -> {:noreply, state}
      key -> handle_key_input(key, state)
    end
  end

  def handle_info(:tick, state) do
    next = if state.auto_rotate, do: %{state | rot: state.rot + 0.9}, else: state
    :wxWindow.refresh(state.canvas)
    timer_ref = Process.send_after(self(), :tick, @timer_ms)
    {:noreply, %{next | timer_ref: timer_ref}}
  end

  def handle_info({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    :wxFrame.destroy(state.frame)
    :wx.destroy()
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp handle_key_input(key, state) do
    next =
      case key do
        ?1 -> %{state | shape: :cube}
        ?2 -> %{state | shape: :sphere}
        ?3 -> %{state | shape: :cylinder}
        ?a -> %{state | auto_rotate: !state.auto_rotate}
        ?A -> %{state | auto_rotate: !state.auto_rotate}
        ?r -> %{state | yaw: 38.0, pitch: -32.0, zoom: 7.0, rot: 0.0}
        ?R -> %{state | yaw: 38.0, pitch: -32.0, zoom: 7.0, rot: 0.0}
        _ -> state
      end

    :wxWindow.refresh(state.canvas)
    {:noreply, next}
  end

  defp normalize_hotkey(key_code) when key_code in [?1, ?2, ?3], do: key_code
  defp normalize_hotkey(?a), do: ?a
  defp normalize_hotkey(?A), do: ?A
  defp normalize_hotkey(?r), do: ?r
  defp normalize_hotkey(?R), do: ?R
  defp normalize_hotkey(_), do: nil

  defp render(state) do
    :wxGLCanvas.setCurrent(state.canvas, state.gl_ctx)
    state = maybe_init_gl(state)

    {w, h} = :wxWindow.getClientSize(state.canvas)
    safe_h = max(h, 1)
    aspect = w / safe_h

    :gl.viewport(0, 0, w, safe_h)
    :gl.matrixMode(@projection)
    :gl.loadIdentity()
    perspective(45.0, aspect, 0.1, 200.0)

    :gl.matrixMode(@modelview)
    :gl.loadIdentity()
    :gl.translatef(0.0, 0.0, -state.zoom)
    :gl.rotatef(state.pitch, 1.0, 0.0, 0.0)
    :gl.rotatef(state.yaw, 0.0, 1.0, 0.0)

    :gl.clearColor(0.08, 0.1, 0.16, 1.0)
    :gl.clear(Bitwise.bor(@color_buffer_bit, @depth_buffer_bit))

    draw_grid()

    :gl.pushMatrix()
    :gl.rotatef(state.rot, 0.0, 1.0, 0.0)
    draw_shape(state.shape)
    :gl.popMatrix()

    :wxGLCanvas.swapBuffers(state.canvas)
    state
  end

  defp maybe_init_gl(%{gl_inited: true} = state), do: state

  defp maybe_init_gl(state) do
    :gl.enable(@depth_test)
    :gl.enable(@cull_face)
    :gl.cullFace(@back)
    :gl.shadeModel(@smooth)
    :gl.hint(@perspective_correction_hint, @nicest)
    %{state | gl_inited: true}
  end

  defp perspective(fov_deg, aspect, near, far) do
    top = near * :math.tan(fov_deg * :math.pi() / 360.0)
    bottom = -top
    right = top * aspect
    left = -right
    :gl.frustum(left, right, bottom, top, near, far)
  end

  defp draw_grid do
    :gl.lineWidth(1.0)
    :gl.color3f(0.2, 0.24, 0.32)
    :gl.begin(@lines)

    Enum.each(-10..10, fn i ->
      f = i * 1.0
      :gl.vertex3f(f, -1.5, -10.0)
      :gl.vertex3f(f, -1.5, 10.0)
      :gl.vertex3f(-10.0, -1.5, f)
      :gl.vertex3f(10.0, -1.5, f)
    end)

    :gl.end()
  end

  defp draw_shape(:cube), do: draw_cube()
  defp draw_shape(:sphere), do: draw_sphere(1.3, 18, 18)
  defp draw_shape(:cylinder), do: draw_cylinder(1.0, 2.4, 24)

  defp draw_cube do
    :gl.begin(@quads)
    :gl.color3f(0.88, 0.3, 0.24)
    :gl.vertex3f(-1.2, -1.2, 1.2)
    :gl.vertex3f(1.2, -1.2, 1.2)
    :gl.vertex3f(1.2, 1.2, 1.2)
    :gl.vertex3f(-1.2, 1.2, 1.2)
    :gl.color3f(0.22, 0.65, 0.9)
    :gl.vertex3f(-1.2, -1.2, -1.2)
    :gl.vertex3f(-1.2, 1.2, -1.2)
    :gl.vertex3f(1.2, 1.2, -1.2)
    :gl.vertex3f(1.2, -1.2, -1.2)
    :gl.color3f(0.95, 0.8, 0.24)
    :gl.vertex3f(-1.2, 1.2, -1.2)
    :gl.vertex3f(-1.2, 1.2, 1.2)
    :gl.vertex3f(1.2, 1.2, 1.2)
    :gl.vertex3f(1.2, 1.2, -1.2)
    :gl.color3f(0.28, 0.88, 0.42)
    :gl.vertex3f(-1.2, -1.2, -1.2)
    :gl.vertex3f(1.2, -1.2, -1.2)
    :gl.vertex3f(1.2, -1.2, 1.2)
    :gl.vertex3f(-1.2, -1.2, 1.2)
    :gl.color3f(0.7, 0.34, 0.92)
    :gl.vertex3f(1.2, -1.2, -1.2)
    :gl.vertex3f(1.2, 1.2, -1.2)
    :gl.vertex3f(1.2, 1.2, 1.2)
    :gl.vertex3f(1.2, -1.2, 1.2)
    :gl.color3f(0.35, 0.86, 0.86)
    :gl.vertex3f(-1.2, -1.2, -1.2)
    :gl.vertex3f(-1.2, -1.2, 1.2)
    :gl.vertex3f(-1.2, 1.2, 1.2)
    :gl.vertex3f(-1.2, 1.2, -1.2)
    :gl.end()
  end

  defp draw_sphere(r, stacks, slices) do
    Enum.each(0..(stacks - 1), fn i ->
      lat0 = :math.pi() * (-0.5 + i / stacks)
      z0 = r * :math.sin(lat0)
      zr0 = r * :math.cos(lat0)

      lat1 = :math.pi() * (-0.5 + (i + 1) / stacks)
      z1 = r * :math.sin(lat1)
      zr1 = r * :math.cos(lat1)

      :gl.begin(@quad_strip)
      :gl.color3f(0.24 + i / stacks * 0.6, 0.4, 0.92 - i / stacks * 0.5)

      Enum.each(0..slices, fn j ->
        lng = 2.0 * :math.pi() * j / slices
        x = :math.cos(lng)
        y = :math.sin(lng)
        :gl.vertex3f(x * zr0, y * zr0, z0)
        :gl.vertex3f(x * zr1, y * zr1, z1)
      end)

      :gl.end()
    end)
  end

  defp draw_cylinder(r, h, slices) do
    half = h / 2.0

    :gl.begin(@quad_strip)
    :gl.color3f(0.96, 0.54, 0.2)

    Enum.each(0..slices, fn i ->
      ang = 2.0 * :math.pi() * i / slices
      x = r * :math.cos(ang)
      z = r * :math.sin(ang)
      :gl.vertex3f(x, -half, z)
      :gl.vertex3f(x, half, z)
    end)

    :gl.end()

    :gl.begin(@triangle_fan)
    :gl.color3f(0.88, 0.32, 0.24)
    :gl.vertex3f(0.0, half, 0.0)

    Enum.each(0..slices, fn i ->
      ang = 2.0 * :math.pi() * i / slices
      :gl.vertex3f(r * :math.cos(ang), half, r * :math.sin(ang))
    end)

    :gl.end()

    :gl.begin(@triangle_fan)
    :gl.color3f(0.2, 0.7, 0.86)
    :gl.vertex3f(0.0, -half, 0.0)

    Enum.each(0..slices, fn i ->
      ang = -2.0 * :math.pi() * i / slices
      :gl.vertex3f(r * :math.cos(ang), -half, r * :math.sin(ang))
    end)

    :gl.end()
  end

  defp clamp(v, min_v, max_v), do: max(min_v, min(v, max_v))
end

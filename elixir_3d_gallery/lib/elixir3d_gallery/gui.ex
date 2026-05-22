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
  @triangles 0x0004

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
       vrm_mesh: load_vrm_mesh(),
       vrm_dl: nil,
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
        ?4 -> %{state | shape: :vrm}
        ?a -> %{state | auto_rotate: !state.auto_rotate}
        ?A -> %{state | auto_rotate: !state.auto_rotate}
        ?r -> %{state | yaw: 38.0, pitch: -32.0, zoom: 7.0, rot: 0.0}
        ?R -> %{state | yaw: 38.0, pitch: -32.0, zoom: 7.0, rot: 0.0}
        _ -> state
      end

    :wxWindow.refresh(state.canvas)
    {:noreply, next}
  end

  defp normalize_hotkey(key_code) when key_code in [?1, ?2, ?3, ?4], do: key_code
  defp normalize_hotkey(?a), do: ?a
  defp normalize_hotkey(?A), do: ?A
  defp normalize_hotkey(?r), do: ?r
  defp normalize_hotkey(?R), do: ?R
  defp normalize_hotkey(_), do: nil

  defp render(state) do
    :wxGLCanvas.setCurrent(state.canvas, state.gl_ctx)
    state = maybe_init_gl(state)
    state = maybe_build_vrm_display_list(state)

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
    draw_shape(state.shape, state)
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

  defp draw_shape(:cube, _state), do: draw_cube()
  defp draw_shape(:sphere, _state), do: draw_sphere(1.3, 18, 18)
  defp draw_shape(:cylinder, _state), do: draw_cylinder(1.0, 2.4, 24)
  defp draw_shape(:vrm, %{vrm_mesh: nil}), do: draw_cube()
  defp draw_shape(:vrm, %{vrm_dl: dl}) when is_integer(dl) and dl > 0, do: :gl.callList(dl)
  defp draw_shape(:vrm, %{vrm_mesh: mesh}), do: draw_vrm(mesh)

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

    :gl.begin(@quads)
    :gl.color3f(0.96, 0.54, 0.2)

    Enum.each(0..(slices - 1), fn i ->
      ang0 = 2.0 * :math.pi() * i / slices
      ang1 = 2.0 * :math.pi() * (i + 1) / slices
      x0 = r * :math.cos(ang0)
      z0 = r * :math.sin(ang0)
      x1 = r * :math.cos(ang1)
      z1 = r * :math.sin(ang1)

      :gl.vertex3f(x0, -half, z0)
      :gl.vertex3f(x0, half, z0)
      :gl.vertex3f(x1, half, z1)
      :gl.vertex3f(x1, -half, z1)
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

  defp draw_vrm(%{triangles: triangles}) do
    :gl.begin(@triangles)

    Enum.each(triangles, fn
      {x, y, z, r, g, b} ->
        :gl.color3f(r, g, b)
        :gl.vertex3f(x, y, z)

      {x, y, z} ->
        :gl.color3f(0.92, 0.83, 0.72)
        :gl.vertex3f(x, y, z)
    end)

    :gl.end()
  end

  defp maybe_build_vrm_display_list(%{vrm_dl: dl} = state) when is_integer(dl) and dl > 0, do: state
  defp maybe_build_vrm_display_list(%{vrm_mesh: nil} = state), do: state

  defp maybe_build_vrm_display_list(%{vrm_mesh: mesh} = state) do
    dl = :gl.genLists(1)
    :gl.newList(dl, 0x1300)
    draw_vrm(mesh)
    :gl.endList()
    %{state | vrm_dl: dl}
  end

  defp load_vrm_mesh do
    vrm_path = Path.expand("test.vrm", File.cwd!())

    with {:ok, bytes} <- File.read(vrm_path),
         {:ok, gltf, bin} <- parse_glb(bytes),
         {:ok, mesh} <- extract_scene_mesh(gltf, bin) do
      mesh
    else
      _ -> nil
    end
  end

  defp parse_glb(
         <<"glTF", 2::little-unsigned-32, _len::little-unsigned-32, rest::binary>>
       ) do
    with {json, bin} <- parse_chunks(rest),
         {:ok, gltf} <- Jason.decode(json) do
      {:ok, gltf, bin}
    else
      _ -> {:error, :invalid_glb}
    end
  end

  defp parse_glb(_), do: {:error, :invalid_glb}

  defp parse_chunks(<<json_len::little-unsigned-32, "JSON", json::binary-size(json_len), rest::binary>>) do
    padded = skip_padding(rest)

    case padded do
      <<bin_len::little-unsigned-32, "BIN\0", bin::binary-size(bin_len), _::binary>> -> {json, bin}
      _ -> {json, <<>>}
    end
  end

  defp skip_padding(<<0, tail::binary>>), do: skip_padding(tail)
  defp skip_padding(bin), do: bin

  defp extract_scene_mesh(gltf, bin) do
    scene_index = Map.get(gltf, "scene", 0)
    scenes = Map.get(gltf, "scenes", [])
    nodes = Map.get(gltf, "nodes", [])

    with scene when is_map(scene) <- Enum.at(scenes, scene_index),
         root_nodes when is_list(root_nodes) <- Map.get(scene, "nodes") do
      triangles =
        Enum.flat_map(root_nodes, fn idx ->
          collect_node_triangles(gltf, bin, nodes, idx, {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0})
        end)

      case normalize_triangles(triangles) do
        [] -> {:error, :mesh_not_found}
        normalized -> {:ok, %{triangles: normalized}}
      end
    else
      _ -> {:error, :mesh_not_found}
    end
  end

  defp collect_node_triangles(gltf, bin, nodes, node_idx, parent_t, parent_s) do
    case Enum.at(nodes, node_idx) do
      node when is_map(node) ->
        t = vec_add(parent_t, to_vec3(Map.get(node, "translation"), {0.0, 0.0, 0.0}))
        s = vec_mul(parent_s, to_vec3(Map.get(node, "scale"), {1.0, 1.0, 1.0}))

        own =
          case Map.get(node, "mesh") do
            mesh_idx when is_integer(mesh_idx) -> mesh_triangles(gltf, bin, mesh_idx, t, s)
            _ -> []
          end

        children =
          node
          |> Map.get("children", [])
          |> Enum.flat_map(&collect_node_triangles(gltf, bin, nodes, &1, t, s))

        own ++ children

      _ ->
        []
    end
  end

  defp mesh_triangles(gltf, bin, mesh_idx, t, s) do
    meshes = Map.get(gltf, "meshes", [])

    case Enum.at(meshes, mesh_idx) do
      mesh when is_map(mesh) ->
        mesh
        |> Map.get("primitives", [])
        |> Enum.with_index()
        |> Enum.flat_map(fn {prim, prim_idx} ->
          with attrs when is_map(attrs) <- Map.get(prim, "attributes"),
               pos_acc when is_integer(pos_acc) <- Map.get(attrs, "POSITION"),
               idx_acc when is_integer(idx_acc) <- Map.get(prim, "indices"),
               {:ok, positions} <- read_positions(gltf, bin, pos_acc),
               base_color <- material_base_color(gltf, Map.get(prim, "material"), prim_idx),
               colors <-
                 read_colors(gltf, bin, Map.get(attrs, "COLOR_0"), length(positions), base_color),
               {:ok, indices} <- read_indices(gltf, bin, idx_acc) do
            Enum.map(indices, fn i ->
              {x, y, z} = Enum.at(positions, i, {0.0, 0.0, 0.0})
              {r, g, b} = Enum.at(colors, i, {0.92, 0.83, 0.72})
              {tx, ty, tz} = vec_add(vec_mul({x, y, z}, s), t)
              {tx, ty, tz, r, g, b}
            end)
          else
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  defp normalize_triangles([]), do: []
  defp normalize_triangles(points) do
    {minx, miny, minz, maxx, maxy, maxz} =
      Enum.reduce(points, {1.0e9, 1.0e9, 1.0e9, -1.0e9, -1.0e9, -1.0e9}, fn p,
                                                                           {mnx, mny, mnz, mxx, mxy, mxz} ->
        {x, y, z} = pos3(p)
        {min(mnx, x), min(mny, y), min(mnz, z), max(mxx, x), max(mxy, y), max(mxz, z)}
      end)

    cx = (minx + maxx) / 2.0
    cy = (miny + maxy) / 2.0
    cz = (minz + maxz) / 2.0
    size = max(maxx - minx, max(maxy - miny, maxz - minz))
    scale = if size > 0.0, do: 3.0 / size, else: 1.0
    Enum.map(points, fn p ->
      {x, y, z} = pos3(p)

      case p do
        {_, _, _, r, g, b} -> {(x - cx) * scale, (y - cy) * scale, (z - cz) * scale, r, g, b}
        _ -> {(x - cx) * scale, (y - cy) * scale, (z - cz) * scale}
      end
    end)
  end

  defp pos3({x, y, z}), do: {x, y, z}
  defp pos3({x, y, z, _, _, _}), do: {x, y, z}

  defp to_vec3([x, y, z], _default), do: {x * 1.0, y * 1.0, z * 1.0}
  defp to_vec3(_, default), do: default
  defp vec_add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp vec_mul({ax, ay, az}, {bx, by, bz}), do: {ax * bx, ay * by, az * bz}

  defp read_positions(gltf, bin, accessor_index) do
    with {:ok, %{count: count, comp: 5126, type: "VEC3", data: data}} <-
           read_accessor(gltf, bin, accessor_index) do
      vals = for <<v::little-float-32 <- data>>, do: v
      positions = vals |> Enum.chunk_every(3) |> Enum.take(count) |> Enum.map(&List.to_tuple/1)
      {:ok, positions}
    else
      _ -> {:error, :bad_positions}
    end
  end

  defp read_colors(_gltf, _bin, nil, count, base_color), do: List.duplicate(base_color, count)

  defp read_colors(gltf, bin, accessor_index, count, base_color) do
    case read_accessor(gltf, bin, accessor_index) do
      {:ok, %{comp: 5126, type: "VEC3", data: data}} ->
        vals = for <<v::little-float-32 <- data>>, do: v
        vals |> Enum.chunk_every(3) |> Enum.take(count) |> Enum.map(&List.to_tuple/1)

      {:ok, %{comp: 5126, type: "VEC4", data: data}} ->
        vals = for <<v::little-float-32 <- data>>, do: v

        vals
        |> Enum.chunk_every(4)
        |> Enum.take(count)
        |> Enum.map(fn [r, g, b, _a] -> {r, g, b} end)

      _ ->
        List.duplicate(base_color, count)
    end
  end

  defp material_base_color(gltf, material_index, prim_idx) when is_integer(material_index) do
    materials = Map.get(gltf, "materials", [])

    case Enum.at(materials, material_index) do
      mat when is_map(mat) ->
        pbr = Map.get(mat, "pbrMetallicRoughness", %{})
        has_texture = is_map(Map.get(pbr, "baseColorTexture"))

        # baseColorTexture 未実装のため、テクスチャ依存マテリアルは白化回避色を使う
        if has_texture do
          fallback_primitive_color(prim_idx)
        else
          case Map.get(pbr, "baseColorFactor") do
            [r, g, b, _a] -> {r * 1.0, g * 1.0, b * 1.0}
            [r, g, b] -> {r * 1.0, g * 1.0, b * 1.0}
            _ -> fallback_primitive_color(prim_idx)
          end
        end

      _ ->
        fallback_primitive_color(prim_idx)
    end
  end

  defp material_base_color(_gltf, _, prim_idx), do: fallback_primitive_color(prim_idx)

  defp fallback_primitive_color(i) do
    palette = [
      {0.95, 0.45, 0.40},
      {0.35, 0.75, 0.95},
      {0.95, 0.80, 0.30},
      {0.42, 0.90, 0.55},
      {0.75, 0.55, 0.95},
      {0.35, 0.88, 0.88}
    ]

    Enum.at(palette, rem(i, length(palette)))
  end

  defp read_indices(gltf, bin, accessor_index) do
    with {:ok, %{count: count, comp: comp, data: data}} <- read_accessor(gltf, bin, accessor_index) do
      indices =
        case comp do
          5123 -> for <<v::little-unsigned-16 <- data>>, do: v
          5125 -> for <<v::little-unsigned-32 <- data>>, do: v
          _ -> []
        end

      {:ok, Enum.take(indices, count)}
    else
      _ -> {:error, :bad_indices}
    end
  end

  defp read_accessor(gltf, bin, accessor_index) do
    accessors = Map.get(gltf, "accessors", [])
    views = Map.get(gltf, "bufferViews", [])

    with accessor when is_map(accessor) <- Enum.at(accessors, accessor_index),
         view_index when is_integer(view_index) <- Map.get(accessor, "bufferView"),
         view when is_map(view) <- Enum.at(views, view_index) do
      count = Map.get(accessor, "count", 0)
      comp = Map.get(accessor, "componentType")
      type = Map.get(accessor, "type")
      acc_off = Map.get(accessor, "byteOffset", 0)
      view_off = Map.get(view, "byteOffset", 0)
      byte_len = Map.get(view, "byteLength", 0)
      data = binary_part(bin, view_off + acc_off, byte_len - acc_off)
      {:ok, %{count: count, comp: comp, type: type, data: data}}
    else
      _ -> {:error, :bad_accessor}
    end
  end
end

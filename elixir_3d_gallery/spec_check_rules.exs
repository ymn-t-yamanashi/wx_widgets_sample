%{
  spec_path: "../Elixir_wxWidgets_3Dミニアプリ計画.md",
  files: %{
    gui: "lib/elixir3d_gallery/gui.ex",
    spec: "../Elixir_wxWidgets_3Dミニアプリ計画.md"
  },
  contains: [
    %{name: "specにMVP定義がある", file: :spec, patterns: ["最初のMVP定義"]},
    %{name: "wxGLCanvasを使用", file: :gui, patterns: [":wxGLCanvas.new"]},
    %{name: "wxGLContextを使用", file: :gui, patterns: [":wxGLContext.new"]},
    %{name: "paintイベント接続", file: :gui, patterns: [":wxWindow.connect(canvas, :paint)"]},
    %{name: "timer再描画ループ", file: :gui, patterns: ["Process.send_after(self(), :tick"]},
    %{name: "形状3種", file: :gui, patterns: ["defp draw_shape(:cube", "defp draw_shape(:sphere", "defp draw_shape(:cylinder"]},
    %{name: "キー1/2/3で形状切替", file: :gui, patterns: ["?1 -> %{state | shape: :cube}", "?2 -> %{state | shape: :sphere}", "?3 -> %{state | shape: :cylinder}"]},
    %{name: "Aキーで自動回転トグル", file: :gui, patterns: ["?a -> %{state | auto_rotate: !state.auto_rotate}", "?A -> %{state | auto_rotate: !state.auto_rotate}"]},
    %{name: "マウスドラッグ回転", file: :gui, patterns: ["wxMouse(type: :motion", "yaw: state.yaw + dx", "pitch: clamp(state.pitch + dy"]},
    %{name: "ホイールズーム", file: :gui, patterns: ["wxMouse(type: :mousewheel", "zoom: clamp(state.zoom + step"]}
  ]
}

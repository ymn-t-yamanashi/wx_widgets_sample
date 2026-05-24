# ElixirWxHandPoseViewer Architecture

## シーケンス図

この図は、アプリ起動後に各プロセスがどの順番でやり取りするかを示しています。

- `Application` は `Camera` と `GUI` を起動するだけで、実処理は子プロセスへ委譲します。
- `Camera` は一定間隔でフレーム取得を繰り返し、推論対象フレームでは `HandInference` を呼び出します。
- `GUI` は別タイマーで `Camera.latest_frame/0` を呼び、描画更新を行います。
- キー入力（`Space` / `V` / `ESC`）は `GUI` が受け取り、必要に応じて `Camera` 制御や表示切替を行います。
- 推論失敗時も処理ループは継続し、ステータス表示だけを切り替える設計です。

```mermaid
sequenceDiagram
    participant App as Application
    participant Cam as Camera(GenServer)
    participant Inf as HandInference
    participant Gui as GUI(GenServer)
    participant Wx as wxWidgets

    App->>Cam: start_link(device, width, height, fps)
    App->>Gui: start_link()

    Cam->>Inf: load()
    Inf-->>Cam: {:ok, model} / {:error, reason}
    Cam->>Cam: :open_camera -> :grab_frame loop

    loop every interval
      Cam->>Cam: VideoCapture.read()
      alt inference frame
        Cam->>Inf: infer_debug(model, roi)
        Inf-->>Cam: {:ok, points, meta} / {:error, reason, meta}
        Cam->>Cam: draw_skeleton + draw_debug_text
      else skipped frame
        Cam->>Cam: draw_debug_text("TRACKING")
      end
      Cam->>Cam: keep latest RGB binary frame
    end

    loop every timer tick
      Gui->>Cam: latest_frame()
      Cam-->>Gui: {:ok, frame} / {:error, reason}
      Gui->>Wx: render bitmap
    end

    Gui->>Cam: toggle_pause() (Space key)
    Gui->>Gui: toggle video visibility (V key)
    Gui->>Wx: close window (ESC)
```

## モジュール関係図

この図は、モジュールの責務分離と依存方向を示しています。

- `Application` は依存注入の起点で、`Camera` と `GUI` の supervised 起動を担当します。
- `Camera` は I/O（カメラ取得）と推論呼び出しのハブです。
- `HandInference` は前処理・推論・後処理をまとめた純粋な推論責務を持ちます。
- `GUI` は表示と入力処理に専念し、推論ロジックを直接持ちません。
- 外部依存は `Evision`（画像処理/描画）、`Ortex`/`Nx`（推論）に集約されています。
- `runtime.exs` は `Ortex` の実行機能（例: CUDA feature）を環境変数に応じて切り替える設定点です。

```mermaid
flowchart TD
    A[ElixirWxHandPoseViewer.Application] --> B[ElixirWxHandPoseViewer.Camera]
    A --> C[ElixirWxHandPoseViewer.GUI]

    B --> D[ElixirWxHandPoseViewer.HandInference]
    B --> E[Evision.VideoCapture]
    B --> F[Evision drawing APIs]

    C --> G[:wx / wxWidgets]
    C --> B

    D --> H[Ortex]
    D --> I[Nx]
    D --> F

    J[config/runtime.exs] -. enables cuda feature .-> H
```

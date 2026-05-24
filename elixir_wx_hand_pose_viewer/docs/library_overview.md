# 利用ライブラリ一覧（ElixirWxHandPoseViewer）

このドキュメントは、本プロジェクトで利用している主要ライブラリと役割を整理したものです。

## 直接依存（`mix.exs`）

### `:evision` (`~> 0.2`)
- 目的: OpenCV の Elixir バインディング。
- 公式:
  - https://hex.pm/packages/evision
  - https://github.com/cocoa-xu/evision
- このプロジェクトでの用途:
  - カメラ入力 (`Evision.VideoCapture`)
  - 画像前処理（リサイズ、色変換、ROI切り出し）
  - 描画（線、点、テキスト重畳）

- 主に使用している関数:
  - `Evision.VideoCapture.videoCapture/1`: カメラデバイスを開く。
  - `Evision.VideoCapture.read/1`: 1フレーム取得する。
  - `Evision.VideoCapture.set/3`: 幅・高さ・FPS を設定する。
  - `Evision.VideoCapture.release/1`: カメラリソースを解放する。
  - `Evision.Mat.shape/1`: 行列のサイズ（高さ/幅/チャンネル）を取得する。
  - `Evision.Mat.roi/2`: 画像からROI領域を切り出す。
  - `Evision.Mat.to_binary/1`: Mat をバイナリへ変換する。
  - `Evision.resize/2`: 画像をモデル入力サイズへリサイズする。
  - `Evision.cvtColor/2`: BGR/RGB の色空間を変換する。
  - `Evision.line/5`: 骨格線を描画する。
  - `Evision.circle/5`: キーポイントを描画する。
  - `Evision.putText/7`: ステータステキストを重畳する。

### `:ortex` (`~> 0.1`)
- 目的: ONNX Runtime の Elixir バインディング。
- 公式:
  - https://hex.pm/packages/ortex
  - https://github.com/elixir-nx/ortex
- このプロジェクトでの用途:
  - `hand_keypoint.onnx` のロード
  - ROI画像に対する推論実行
  - GPU(CUDA) / CPU の実行切替

- 主に使用している関数:
  - `Ortex.load/1`: 既定設定でモデルをロードする。
  - `Ortex.load/2`: 実行プロバイダ（`[:cuda]` / `[:cpu]`）を指定してロードする。
  - `Ortex.run/2`: テンソル入力に対して推論を実行する。

## 主要な推移依存（`mix.lock` 由来）

### `:nx`
- 目的: 数値テンソル演算ライブラリ。
- 公式:
  - https://hex.pm/packages/nx
  - https://github.com/elixir-nx/nx
- 用途:
  - 推論前のテンソル化（`u8 -> f32`、reshape、正規化）
  - 推論出力の後処理（flatten、座標復元）

- 主に使用している関数:
  - `Nx.from_binary/2`: 画像バイナリをテンソル化する。
  - `Nx.reshape/2`: テンソル形状をモデル入力/出力向けに整える。
  - `Nx.as_type/2`: `u8` から `f32` へ型変換する。
  - `Nx.divide/2`: 画素値を `0..1` に正規化する。
  - `Nx.to_flat_list/1`: 出力テンソルを平坦化して座標列へ変換する。

### `:rustler`
- 目的: Elixir から Rust NIF を利用するための基盤。
- 公式:
  - https://hex.pm/packages/rustler
  - https://github.com/rusterlium/rustler
- 用途:
  - `ortex` のネイティブ実装（ONNX Runtime呼び出し）を支える。

### `:elixir_make`
- 目的: ネイティブコードのビルド補助。
- 公式:
  - https://hex.pm/packages/elixir_make
  - https://github.com/elixir-lang/elixir_make
- 用途:
  - `evision` / `ortex` のビルド時に利用される。

### `:telemetry`
- 目的: 観測イベントの共通基盤。
- 公式:
  - https://hex.pm/packages/telemetry
  - https://github.com/beam-telemetry/telemetry
- 用途:
  - `nx` 等の内部依存として読み込まれる。

### `:castore`
- 目的: 証明書ストア提供。
- 公式:
  - https://hex.pm/packages/castore
  - https://github.com/elixir-mint/castore
- 用途:
  - 依存ライブラリ内での通信関連処理を補助。

### `:complex`
- 目的: 複素数サポート。
- 公式:
  - https://hex.pm/packages/complex
  - https://github.com/elixir-nx/complex
- 用途:
  - `nx` の依存として利用。

### `:jason`
- 目的: JSONエンコード/デコード。
- 公式:
  - https://hex.pm/packages/jason
  - https://github.com/michalmuskala/jason
- 用途:
  - `rustler` 依存経由で利用。

## 標準アプリケーション

### `:wx`
- 目的: wxWidgets GUI バインディング（Erlang/OTP同梱）。
- 公式:
  - https://www.erlang.org/doc/apps/wx/wx_chapter.html
  - https://www.wxwidgets.org/
- このプロジェクトでの用途:
  - ウィンドウ作成
  - 画像描画
  - キー入力処理

- 主に使用している関数:
  - `:wx.new/0`: wxシステムを初期化する。
  - `:wxFrame.new/4`: メインウィンドウを作成する。
  - `:wxPanel.new/1`: 描画用パネルを作成する。
  - `:wxStaticBitmap.new/3`: 画像表示用ウィジェットを作成する。
  - `:wxWindow.connect/2`, `:wxFrame.connect/2`: イベントハンドラを登録する。
  - `:wxFrame.show/1`: ウィンドウを表示する。
  - `:wxImage.new/3`, `:wxBitmap.new/1`: RGBバッファから描画可能オブジェクトを生成する。
  - `:wxStaticBitmap.setBitmap/2`: 表示画像を更新する。
  - `:wxWindow.setSize/5`: 表示領域サイズを更新する。
  - `:wxFrame.setTitle/2`: ステータスをタイトルへ反映する。
  - `:wxFrame.destroy/1`, `:wx.destroy/0`: 終了時にGUI資源を解放する。

### `:logger`
- 目的: ログ出力。
- 公式:
  - https://www.erlang.org/doc/apps/kernel/logger_chapter.html
- このプロジェクトでの用途:
  - 推論状態、検出結果、エラーの可視化

## 補足
- GPU実行を有効にするには、`Ortex` 設定に加えて CUDA対応 `onnxruntime` 共有ライブラリが必要です。
- 設定は `config/runtime.exs` と環境変数（例: `ENABLE_GPU`, `ORT_LIB_LOCATION`）で制御します。

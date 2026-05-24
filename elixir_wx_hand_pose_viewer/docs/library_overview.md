# 利用ライブラリ一覧（ElixirWxHandPoseViewer）

このドキュメントは、本プロジェクトで利用している主要ライブラリと役割を整理したものです。

## 直接依存（`mix.exs`）

### `:evision` (`~> 0.2`)
- 目的: OpenCV の Elixir バインディング。
- このプロジェクトでの用途:
  - カメラ入力 (`Evision.VideoCapture`)
  - 画像前処理（リサイズ、色変換、ROI切り出し）
  - 描画（線、点、テキスト重畳）

### `:ortex` (`~> 0.1`)
- 目的: ONNX Runtime の Elixir バインディング。
- このプロジェクトでの用途:
  - `hand_keypoint.onnx` のロード
  - ROI画像に対する推論実行
  - GPU(CUDA) / CPU の実行切替

## 主要な推移依存（`mix.lock` 由来）

### `:nx`
- 目的: 数値テンソル演算ライブラリ。
- 用途:
  - 推論前のテンソル化（`u8 -> f32`、reshape、正規化）
  - 推論出力の後処理（flatten、座標復元）

### `:rustler`
- 目的: Elixir から Rust NIF を利用するための基盤。
- 用途:
  - `ortex` のネイティブ実装（ONNX Runtime呼び出し）を支える。

### `:elixir_make`
- 目的: ネイティブコードのビルド補助。
- 用途:
  - `evision` / `ortex` のビルド時に利用される。

### `:telemetry`
- 目的: 観測イベントの共通基盤。
- 用途:
  - `nx` 等の内部依存として読み込まれる。

### `:castore`
- 目的: 証明書ストア提供。
- 用途:
  - 依存ライブラリ内での通信関連処理を補助。

### `:complex`
- 目的: 複素数サポート。
- 用途:
  - `nx` の依存として利用。

### `:jason`
- 目的: JSONエンコード/デコード。
- 用途:
  - `rustler` 依存経由で利用。

## 標準アプリケーション

### `:wx`
- 目的: wxWidgets GUI バインディング（Erlang/OTP同梱）。
- このプロジェクトでの用途:
  - ウィンドウ作成
  - 画像描画
  - キー入力処理

### `:logger`
- 目的: ログ出力。
- このプロジェクトでの用途:
  - 推論状態、検出結果、エラーの可視化

## 補足
- GPU実行を有効にするには、`Ortex` 設定に加えて CUDA対応 `onnxruntime` 共有ライブラリが必要です。
- 設定は `config/runtime.exs` と環境変数（例: `ENABLE_GPU`, `ORT_LIB_LOCATION`）で制御します。

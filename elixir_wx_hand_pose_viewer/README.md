# ElixirWxHandPoseViewer

Elixir + `:wx` + Evision(OpenCV) でカメラ映像に手関節推定結果を重畳表示するアプリです。

## 実行

```bash
mix deps.get
mix qa
CAMERA_DEVICE=0 mix run --no-halt
```

`ESC` またはウィンドウクローズで終了します。

## ONNX モデル

- 配置先: `priv/models/hand_keypoint.onnx`
- 配置先: `priv/models/palm_detection.onnx`
- 入力: `1x224x224x3` (RGB, 0..1)
- 主出力: `1x63` (21 keypoints x xyz)

モデル未配置時は手認識を無効化し、カメラ表示のみ行います。

### モデル取得スクリプト

```bash
chmod +x scripts/download_models.sh
PALM_DETECTION_URL="<palm_detection.onnx のURL>" ./scripts/download_models.sh
```

- `HAND_KEYPOINT_URL` は未指定時にデフォルトURLを使用します。
- `PALM_DETECTION_URL` は必須です（利用元ライセンスに従って指定してください）。

## テスト

```bash
mix qa
```

## GPU 実行

```bash
ENABLE_GPU=1 ORT_LIB_LOCATION=/path/to/libonnxruntime.so CAMERA_DEVICE=0 mix run --no-halt
```

- `ORT_LIB_LOCATION` には CUDA 対応 ONNX Runtime の共有ライブラリを指定してください。
- 起動ログに `loaded providers=[:cuda, :cpu]` が出れば GPU 優先で動作しています。

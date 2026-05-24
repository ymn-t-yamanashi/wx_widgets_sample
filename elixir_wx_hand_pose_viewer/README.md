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
- 入力: `1x3x224x224` (RGB, 0..1)
- 出力: `1x21x3` (`x`, `y`, `score`)
- しきい値: `0.35`

モデル未配置時は手認識を無効化し、カメラ表示のみ行います。

## テスト

```bash
mix qa
```

# ElixirWxCameraViewer

Elixir + wxWidgets (`:wx`) + Evision で USB カメラ映像を表示するサンプルです。

## 前提

- Linux 環境
- `/dev/video*` へアクセス可能
- OpenCV 開発環境（Evision ビルドに必要）

## セットアップ

```bash
mix deps.get
mix compile
```

## 実行

```bash
mix run --no-halt
```

カメラデバイスを切り替える場合:

```bash
CAMERA_DEVICE=1 mix run --no-halt
```

## 操作

- `Space`: 一時停止 / 再開
- `S`: 現在フレームを `snapshot_*.png` として保存
- `R`: 録画開始 / 停止（`recording_*.mp4` を保存）
- `Esc`: 終了

映像はウィンドウサイズに合わせて縦横比を維持したまま自動フィット表示されます。

## 品質確認

```bash
mix qa
```

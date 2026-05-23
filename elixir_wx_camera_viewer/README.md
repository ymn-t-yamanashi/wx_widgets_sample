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

起動するとウィンドウを開き、カメラ映像を表示します。カメラ未接続時や取得失敗時はウィンドウ上にエラーメッセージを表示し、再試行を継続します。

## 品質確認

```bash
mix qa
```

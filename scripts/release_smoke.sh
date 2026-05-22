#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/sum_wx"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[smoke] sum_wx が見つかりません。"
  exit 1
fi

cd "$PROJECT_DIR"

echo "[smoke] format/compile/test を確認します..."
mix qa

if [ -z "${DISPLAY:-}" ]; then
  echo "[smoke] DISPLAY が未設定のため GUI 起動確認をスキップします。"
  echo "[smoke] GUI起動確認は DISPLAY が使える環境で次を実行してください:"
  echo "        timeout 5s mix run --no-halt"
  exit 0
fi

echo "[smoke] GUI起動スモークを実行します（5秒）..."
if timeout 5s mix run --no-halt; then
  echo "[smoke] GUIスモーク完了"
else
  status=$?
  if [ "$status" -eq 124 ]; then
    echo "[smoke] 5秒起動できたため成功（timeout終了）"
    exit 0
  fi
  echo "[smoke] GUIスモーク失敗 (exit: $status)"
  exit "$status"
fi

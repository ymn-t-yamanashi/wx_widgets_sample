#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

git -C "$REPO_ROOT" config core.hooksPath .githooks

echo "Git hooks path を .githooks に設定しました。"
echo "以後、コミット時に pre-commit で mix qa が実行されます。"

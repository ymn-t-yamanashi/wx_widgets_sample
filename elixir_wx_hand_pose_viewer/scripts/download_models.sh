#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${ROOT_DIR}/priv/models"
mkdir -p "${MODEL_DIR}"

# Override these from environment when needed.
# Example:
#   HAND_KEYPOINT_URL="https://example.com/hand_keypoint.onnx" \
#   PALM_DETECTION_URL="https://example.com/palm_detection.onnx" \
#   ./scripts/download_models.sh
HAND_KEYPOINT_URL="${HAND_KEYPOINT_URL:-https://github.com/open-mmlab/mmpose/releases/download/v1.3.0/rtmpose-m_simcc-hand5_pt-aic-coco_210e-256x256-74f2739d_20230228.onnx}"
PALM_DETECTION_URL="${PALM_DETECTION_URL:-}"

download() {
  local url="$1"
  local out="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 10 -o "${out}" "${url}"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "${out}" "${url}"
    return
  fi

  echo "error: curl or wget is required" >&2
  exit 1
}

echo "Downloading hand keypoint model..."
download "${HAND_KEYPOINT_URL}" "${MODEL_DIR}/hand_keypoint.onnx"

if [[ -z "${PALM_DETECTION_URL}" ]]; then
  echo "error: PALM_DETECTION_URL is not set" >&2
  echo "set PALM_DETECTION_URL to a valid ONNX file URL for palm_detection.onnx" >&2
  exit 1
fi

echo "Downloading palm detection model..."
download "${PALM_DETECTION_URL}" "${MODEL_DIR}/palm_detection.onnx"

echo "Done:"
ls -lh "${MODEL_DIR}/hand_keypoint.onnx" "${MODEL_DIR}/palm_detection.onnx"

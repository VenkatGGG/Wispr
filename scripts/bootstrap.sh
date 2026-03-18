#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREW_PREFIX="$(brew --prefix)"
PYTHON_BIN="${BREW_PREFIX}/opt/python@3.11/bin/python3.11"
MODEL_PATH="${ROOT_DIR}/models/ggml-base.en.bin"
MODEL_PATH="${ROOT_DIR}/models/ggml-small.en.bin"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
OLLAMA_BIN="${BREW_PREFIX}/bin/ollama"

brew install python@3.11 portaudio ollama whisper-cpp

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Expected Homebrew Python at ${PYTHON_BIN}" >&2
  exit 1
fi

"${PYTHON_BIN}" -m venv "${ROOT_DIR}/.venv"
"${ROOT_DIR}/.venv/bin/python" -m pip install --upgrade pip
"${ROOT_DIR}/.venv/bin/pip" install -e "${ROOT_DIR}"

mkdir -p "${ROOT_DIR}/models"

if [[ ! -f "${MODEL_PATH}" ]]; then
  curl -L --fail -o "${MODEL_PATH}" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
fi

if ! pgrep -x ollama >/dev/null 2>&1; then
  nohup "${OLLAMA_BIN}" serve >/tmp/wispr-ollama.log 2>&1 &
  sleep 3
fi

if ! "${OLLAMA_BIN}" list | awk 'NR > 1 { print $1 }' | grep -Eq "^${OLLAMA_MODEL}(:latest)?$"; then
  "${OLLAMA_BIN}" pull "${OLLAMA_MODEL}"
fi

echo "Bootstrap complete."
echo "Next:"
echo "  make doctor"
echo "  make run"

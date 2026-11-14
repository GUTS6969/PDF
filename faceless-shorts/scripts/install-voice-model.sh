#!/bin/bash
# Install a free local neural voice without relying on a model CDN.
# Uses the CC0 en_US-joe-medium Piper voice from npm plus the MIT Piper runtime.
# Everything is placed under $FACELESS_HOME; no sudo or account is needed.
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"
NODE_TOOLS="$FH/node-tools"
VOICE_DIR="$FH/models/piper"
MODEL="$VOICE_DIR/en_US-joe-medium.onnx"
CONFIG="$VOICE_DIR/en_US-joe-medium.onnx.json"
PY="${PIPER_PYTHON:-$FH/venv/bin/python}"

[ -x "$PY" ] || { echo "Python environment missing: run setup.sh again." >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required to install the free voice model." >&2; exit 1; }
mkdir -p "$NODE_TOOLS" "$VOICE_DIR"
[ -f "$NODE_TOOLS/package.json" ] || printf '{"private":true}\n' > "$NODE_TOOLS/package.json"

if [ ! -f "$NODE_TOOLS/node_modules/vowel-lab-voices-int8/int8.onnx" ]; then
  echo "Downloading free Piper voice model (~16 MB) ..."
  npm install --prefix "$NODE_TOOLS" --no-audit --no-fund vowel-lab-voices-int8@0.1.0
fi
"$PY" -c 'import piper' >/dev/null 2>&1 || "$PY" -m pip install -q piper-tts==1.8.0
cp "$NODE_TOOLS/node_modules/vowel-lab-voices-int8/int8.onnx" "$MODEL"
cp "$SKILL/scripts/piper-joe-config.json" "$CONFIG"

"$PY" - "$MODEL" <<'PY'
import sys
from piper import PiperVoice
PiperVoice.load(sys.argv[1])
print(f'Free Piper voice model ready: {sys.argv[1]}')
PY

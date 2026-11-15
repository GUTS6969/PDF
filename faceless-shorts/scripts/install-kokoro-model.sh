#!/bin/bash
# Install the free local Kokoro-82M Q8 model from npm-hosted shards.
# Avoids model CDNs and native ONNX Runtime post-install downloads.
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"
PY="${KOKORO_PYTHON:-$FH/venv/bin/python}"
DEST="$FH/models/kokoro-82m-q8"
MODEL="$DEST/onnx/model_quantized.onnx"
VOICES="$DEST/voices.npz"
EXPECTED='fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478'

[ -x "$PY" ] || { echo "Python environment missing: run setup.sh again." >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required to install the free Kokoro model." >&2; exit 1; }

if [ -f "$MODEL" ] && [ -f "$VOICES" ] && [ "$(sha256sum "$MODEL" | awk '{print $1}')" = "$EXPECTED" ]; then
  echo "Kokoro-82M Q8 model ready: $MODEL"
  exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
(
  cd "$TMP"
  npm pack --silent kokoro-q8-shards@1.0.0 > q8.name
  npm pack --silent kokoro-local-runtime@0.1.0 > runtime.name
  mkdir q8 runtime
  tar -xzf "$(cat q8.name)" -C q8
  tar -xzf "$(cat runtime.name)" -C runtime

  STAGE="$DEST/.staging"
  rm -rf "$STAGE"; mkdir -p "$STAGE/onnx" "$STAGE/voices"
  cat q8/package/kokoro-q8.part{0,1,2,3,4,5}.bin > "$STAGE/onnx/model_quantized.onnx"
  ACTUAL="$(sha256sum "$STAGE/onnx/model_quantized.onnx" | awk '{print $1}')"
  [ "$ACTUAL" = "$EXPECTED" ] || { echo "Kokoro model checksum mismatch" >&2; exit 1; }
  cp runtime/package/voices/*.bin "$STAGE/voices/"
  "$PY" - "$STAGE" "$ACTUAL" <<'PY'
import json, sys
from pathlib import Path
import numpy as np
stage, digest = Path(sys.argv[1]), sys.argv[2]
voices = {}
for item in sorted((stage / 'voices').glob('*.bin')):
    data = np.fromfile(item, dtype='<f4')
    if data.size != 510 * 256:
        raise SystemExit(f'Unexpected Kokoro voice tensor: {item}')
    voices[item.stem] = data.reshape(510, 256)
np.savez(stage / 'voices.npz', **voices)
(stage / 'install.json').write_text(json.dumps({
    'model': 'Kokoro-82M v1.0 ONNX Q8',
    'model_path': 'onnx/model_quantized.onnx',
    'sha256': digest,
    'source': 'kokoro-q8-shards@1.0.0',
    'voice_assets': 'kokoro-local-runtime@0.1.0',
    'voice_count': len(voices),
    'license': 'Apache-2.0 model and voice assets',
}, indent=2) + '\n')
PY
  rm -rf "$DEST/onnx" "$DEST/voices" "$DEST/voices.npz" "$DEST/install.json"
  mv "$STAGE/onnx" "$DEST/onnx"; mv "$STAGE/voices" "$DEST/voices"
  mv "$STAGE/voices.npz" "$DEST/voices.npz"; mv "$STAGE/install.json" "$DEST/install.json"
  rmdir "$STAGE"
)

echo "Kokoro-82M Q8 model ready: $MODEL"

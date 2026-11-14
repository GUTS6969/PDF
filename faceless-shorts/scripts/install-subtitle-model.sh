#!/bin/bash
# Install the free local Whisper small (CTranslate2 int8) subtitle model without
# relying on Hugging Face. The model is published as four npm registry shards.
# It is kept outside the repository in $FACELESS_HOME.
set -euo pipefail

FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"
NODE_TOOLS="$FH/node-tools"
MODEL="$FH/models/whisper-small"
PACKAGES=(
  @skillninja/shortmovie-telop-model-p0@1.0.0
  @skillninja/shortmovie-telop-model-p1@1.0.0
  @skillninja/shortmovie-telop-model-p2@1.0.0
  @skillninja/shortmovie-telop-model-p3@1.0.0
)

command -v node >/dev/null || { echo "Node.js is required to install the subtitle model." >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required to install the subtitle model." >&2; exit 1; }
mkdir -p "$NODE_TOOLS" "$MODEL"
[ -f "$NODE_TOOLS/package.json" ] || printf '{"private":true}\n' > "$NODE_TOOLS/package.json"

if [ ! -f "$NODE_TOOLS/node_modules/@skillninja/shortmovie-telop-model-p3/model.bin.part3" ]; then
  echo "Downloading free Whisper small subtitle model shards (~250 MB) ..."
  npm install --prefix "$NODE_TOOLS" --no-audit --no-fund "${PACKAGES[@]}"
fi

P0="$NODE_TOOLS/node_modules/@skillninja/shortmovie-telop-model-p0"
P1="$NODE_TOOLS/node_modules/@skillninja/shortmovie-telop-model-p1"
P2="$NODE_TOOLS/node_modules/@skillninja/shortmovie-telop-model-p2"
P3="$NODE_TOOLS/node_modules/@skillninja/shortmovie-telop-model-p3"
for file in "$P0/model.bin.part0" "$P1/model.bin.part1" "$P2/model.bin.part2" "$P3/model.bin.part3"; do
  [ -f "$file" ] || { echo "Missing model shard: $file" >&2; exit 1; }
done

# The CTranslate2 loader expects a normal model directory, not shard files.
TMP="$MODEL/model.bin.part"
cat "$P0/model.bin.part0" "$P1/model.bin.part1" "$P2/model.bin.part2" "$P3/model.bin.part3" > "$TMP"
EXPECTED="$(tr -d '[:space:]' < "$P0/model.sha256")"
if command -v sha256sum >/dev/null; then ACTUAL="$(sha256sum "$TMP" | awk '{print $1}')"; else ACTUAL="$(shasum -a 256 "$TMP" | awk '{print $1}')"; fi
[ "$ACTUAL" = "$EXPECTED" ] || { rm -f "$TMP"; echo "Whisper model integrity check failed." >&2; exit 1; }
mv "$TMP" "$MODEL/model.bin"
for file in config.json tokenizer.json vocabulary.json preprocessor_config.json; do cp "$P0/$file" "$MODEL/$file"; done

printf 'Whisper small subtitle model ready: %s\n' "$MODEL"

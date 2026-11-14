#!/bin/bash
# Linux fallback for machines that do not already have ffmpeg and Chrome/Chromium.
# Installs only into $FACELESS_HOME (default: ~/.faceless-shorts); it never needs sudo.
# The engine continues to prefer the system ffmpeg and browser when they exist.
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"
NODE_TOOLS="$FH/node-tools"
TOOLS="$FH/tools"
BIN="$TOOLS/bin"

NODE_MAJOR="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1 || true)"
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 22 ]; then
  echo "Node.js 22+ is required to install the portable runtime tools." >&2
  exit 1
fi

mkdir -p "$BIN" "$NODE_TOOLS"
if [ ! -f "$NODE_TOOLS/package.json" ]; then
  printf '{"private":true}\n' > "$NODE_TOOLS/package.json"
fi

# These packages contain prebuilt Linux binaries. They are only a fallback for
# environments without system packages; normal desktop installs use their own tools.
if [ ! -x "$NODE_TOOLS/node_modules/@ffmpeg-installer/linux-x64/ffmpeg" ] || \
   [ ! -d "$NODE_TOOLS/node_modules/@sparticuz/chromium" ]; then
  echo "Installing portable ffmpeg and Chromium into $NODE_TOOLS ..."
  npm install --prefix "$NODE_TOOLS" --no-audit --no-fund \
    @ffmpeg-installer/ffmpeg@1.1.0 @sparticuz/chromium@153.0.0
fi

ln -sfn "$NODE_TOOLS/node_modules/@ffmpeg-installer/linux-x64/ffmpeg" "$BIN/ffmpeg"

# words.py only needs this common ffprobe duration query. The portable ffmpeg
# distribution ships ffmpeg but not a separate ffprobe binary, so provide it.
cat > "$BIN/ffprobe" <<'PY'
#!/usr/bin/env python3
import re
import subprocess
import sys
from pathlib import Path

home = Path(__file__).resolve().parents[2]
ffmpeg = home / 'tools' / 'bin' / 'ffmpeg'
source = sys.argv[-1] if len(sys.argv) > 1 else ''
result = subprocess.run(
    [str(ffmpeg), '-hide_banner', '-i', source],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
match = re.search(r'Duration: (\d+):(\d+):(\d+(?:\.\d+)?)', result.stderr)
if not match:
    sys.exit(1)
hours, minutes, seconds = match.groups()
print(f'{int(hours) * 3600 + int(minutes) * 60 + float(seconds):.6f}')
PY
chmod +x "$BIN/ffprobe"

# @sparticuz/chromium bundles an AL2023-compatible NSS runtime. The launcher
# expands it on first run and execs Chromium so its process is cleanly reaped by
# the capture script.
cat > "$BIN/faceless-chrome" <<'SH'
#!/bin/sh
set -eu
FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"
ROOT="$FH/node-tools/node_modules/@sparticuz/chromium"
[ -d "$ROOT" ] || { echo "Portable Chromium is not installed. Re-run install-runtime-tools.sh." >&2; exit 1; }
RESULT="$(ROOT="$ROOT" node --input-type=module <<'NODE'
const { default: chromium, inflate } = await import(`${process.env.ROOT}/build/index.js`);
const libraries = await inflate(`${process.env.ROOT}/bin/al2023.tar.br`);
const executable = await chromium.executablePath();
console.log(`${libraries}/lib:${executable}`);
NODE
)"
LIBRARY_PATH=${RESULT%:*}
BINARY=${RESULT##*:}
export LD_LIBRARY_PATH="$LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$BINARY" "$@"
SH
chmod +x "$BIN/faceless-chrome"

echo "Portable tools ready: $BIN"
echo "Use system tools when available, or source $SKILL/scripts/env.sh before running projects."

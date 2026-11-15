#!/bin/bash
# One-time setup. Safe to re-run. Prints "All set" when everything works (~350 MB of models, all free).
# Checks Node.js 22+, ffmpeg, Chrome; builds ~/.faceless-shorts/venv; downloads free Kokoro and Whisper models.
# On Linux, missing ffmpeg/Chrome can be installed without sudo through install-runtime-tools.sh.
set -u
ok=1; say() { printf '%-12s %s\n' "$1" "$2"; }
SKILL="$(cd "$(dirname "$0")/.." && pwd)"; FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"; VENV="$FH/venv"
export PATH="$FH/tools/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

NODE_V=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [ -n "$NODE_V" ] && [ "$NODE_V" -ge 22 ]; then
  say node "ok ($(node -v))"
else
  say node "MISSING or too old: need Node.js 22+ (nodejs.org, or: brew install node)"; ok=0
fi

# A portable, user-local fallback makes the engine usable in restricted Linux
# environments without asking for sudo. Desktop installations still use their
# normal system ffmpeg and Chrome/Chromium.
need_runtime=0
command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || need_runtime=1
CH=""; for p in "${CHROME:-}" "$FH/tools/bin/faceless-chrome" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Chromium.app/Contents/MacOS/Chromium" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser /snap/bin/chromium "/c/Program Files/Google/Chrome/Application/chrome.exe"; do [ -n "$p" ] && [ -x "$p" ] && CH="$p" && break; done
[ -n "$CH" ] || need_runtime=1
if [ "$need_runtime" = 1 ] && [ "${NODE_V:-0}" -ge 22 ] && [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
  if bash "$SKILL/scripts/install-runtime-tools.sh"; then
    export PATH="$FH/tools/bin:$PATH"
  else
    say runtime "portable fallback FAILED (install ffmpeg + Chrome/Chromium manually)"; ok=0
  fi
fi

if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null; then say ffmpeg "ok ($(command -v ffmpeg))"; else say ffmpeg "MISSING (install ffmpeg, or re-run setup.sh on Linux)"; ok=0; fi
CH=""; for p in "${CHROME:-}" "$FH/tools/bin/faceless-chrome" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Chromium.app/Contents/MacOS/Chromium" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser /snap/bin/chromium "/c/Program Files/Google/Chrome/Application/chrome.exe"; do [ -n "$p" ] && [ -x "$p" ] && CH="$p" && break; done
if [ -n "$CH" ]; then say chrome "ok ($CH)"; else say chrome "MISSING (install Google Chrome, or re-run setup.sh on Linux)"; ok=0; fi

PYBIN=""; for p in python3.12 python3.11 python3.10 python3 python "py -3"; do $p -c "import sys; assert sys.version_info >= (3, 10)" >/dev/null 2>&1 && PYBIN=$p && break; done
mkdir -p "$FH"
if [ ! -x "$VENV/bin/python" ] && [ ! -x "$VENV/Scripts/python.exe" ]; then
  echo "building the Python env in $VENV (a few minutes)..."
  if command -v uv >/dev/null; then uv venv --python 3.11 "$VENV" >/dev/null 2>&1 || uv venv "$VENV" >/dev/null 2>&1
  elif [ -n "$PYBIN" ]; then $PYBIN -m venv "$VENV"; fi
fi
PY="$VENV/bin/python"; [ -x "$PY" ] || PY="$VENV/Scripts/python.exe"
CHECK="import numpy, scipy, kokoro_onnx, faster_whisper, piper"
PIP="numpy scipy kokoro-onnx faster-whisper piper-tts"
if [ -x "$PY" ]; then
  if ! "$PY" -c "$CHECK" 2>/dev/null; then
    if command -v uv >/dev/null; then uv pip install --python "$PY" -q $PIP >/dev/null 2>&1
    else "$PY" -m pip install -q --upgrade pip >/dev/null 2>&1; "$PY" -m pip install -q $PIP >/dev/null 2>&1; fi
  fi
  if "$PY" -c "$CHECK" 2>/dev/null; then say python-env "ok ($VENV)"; else say python-env "BROKEN: run $PY -m pip install $PIP"; ok=0; fi
  if KOKORO_PYTHON="$PY" bash "$SKILL/scripts/install-kokoro-model.sh" >/dev/null 2>&1 && "$PY" "$SKILL/scripts/voice.py" --download >/dev/null 2>&1; then say voice "ok (local Kokoro-82M Q8)"; else say voice "model download FAILED (check the internet connection, re-run)"; ok=0; fi
  WHISPER="$FH/models/whisper-small"
  if [ ! -f "$WHISPER/model.bin" ]; then bash "$SKILL/scripts/install-subtitle-model.sh" >/dev/null 2>&1 || true; fi
  if FACELESS_WHISPER_MODEL="$WHISPER" "$PY" -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['FACELESS_WHISPER_MODEL'], device='cpu', compute_type='int8')" >/dev/null 2>&1; then say whisper "ok (small, $WHISPER)"; else say whisper "model download FAILED (re-run setup.sh)"; ok=0; fi
else
  say python-env "MISSING: install Python 3.10+ (python.org) or uv (docs.astral.sh/uv)"; ok=0
fi
chmod +x "$SKILL"/scripts/*.sh "$SKILL"/scripts/py 2>/dev/null
[ $ok = 1 ] && echo "All set" || { echo "Fix the MISSING items above, then run setup.sh again."; exit 1; }

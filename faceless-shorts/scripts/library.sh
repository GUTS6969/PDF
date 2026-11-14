#!/bin/sh
# Open a gallery of every MP4 in ~/faceless-shorts/**/renders/.
# Optional: FACELESS_LIBRARY_ROOT=/another/projects bash scripts/library.sh
set -eu
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
exec node "$SKILL/library/server.mjs" "$@"

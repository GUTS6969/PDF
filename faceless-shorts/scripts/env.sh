#!/bin/sh
# Source this file before rendering if the portable fallback tools were installed:
#   . /path/to/faceless-shorts/scripts/env.sh
FH="${FACELESS_HOME:-$HOME/.faceless-shorts}"
export FACELESS_HOME="$FH"
export PATH="$FH/tools/bin:$PATH"
if [ -z "${CHROME:-}" ] && [ -x "$FH/tools/bin/faceless-chrome" ]; then
  export CHROME="$FH/tools/bin/faceless-chrome"
fi

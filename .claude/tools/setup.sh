#!/bin/bash
# One-time setup: create the local venv used by all maintenance tools.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 -m venv "$HERE/venv"
"$HERE/venv/bin/pip" install --quiet --upgrade pip
"$HERE/venv/bin/pip" install --quiet mutagen lingua-language-detector
echo "venv ready at $HERE/venv"
"$HERE/venv/bin/python" -c "import mutagen, lingua; print('mutagen + lingua OK')"

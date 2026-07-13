#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -x ".venv/bin/python" ]; then
  PY=".venv/bin/python"
elif [ -x ".venv/Scripts/python.exe" ]; then
  PY=".venv/Scripts/python.exe"
else
  if command -v python3 >/dev/null 2>&1; then
    python3 -m venv .venv
  elif command -v python >/dev/null 2>&1; then
    python -m venv .venv
  elif command -v py >/dev/null 2>&1; then
    py -3 -m venv .venv
  else
    echo "python interpreter not found" >&2
    exit 127
  fi

  if [ -x ".venv/bin/python" ]; then
    PY=".venv/bin/python"
  else
    PY=".venv/Scripts/python.exe"
  fi
fi

"$PY" -m pip install -e .
"$PY" scripts/compile.py
"$PY" -m pytest -q
"$PY" scripts/check_loc.py

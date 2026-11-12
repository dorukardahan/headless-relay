#!/bin/sh
# Offline regression; Python standard library only, no vendor CLI or network.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/test-fable-target.py"

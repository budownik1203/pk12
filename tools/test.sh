#!/usr/bin/env bash
# Testy bez okna. Użycie: tools/test.sh /sciezka/do/godot
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
"$GODOT" --headless --path game -- --test-zapisu

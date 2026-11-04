#!/bin/sh
# Runs the game, importing new or changed assets first (running with --path alone skips the import, so a new sound
# or sprite wouldn't load). Extra arguments go to Godot; PIZZA_* env vars work as usual.
cd "$(dirname "$0")/.." || exit 1
godot --headless --import --path . >/dev/null 2>&1 || echo "run.sh: asset import failed, running anyway" >&2
exec godot --path . "$@"

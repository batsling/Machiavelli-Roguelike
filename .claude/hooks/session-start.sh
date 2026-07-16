#!/bin/bash
# SessionStart hook for Claude Code on the web: installs headless Godot 4.6
# (for tests/smoke_test.gd) and gdtoolkit (gdparse/gdlint for GDScript
# syntax/lint checks). Idempotent — the container caches installed state, so
# reruns are near-instant.
set -euo pipefail

# Local machines manage their own Godot install; only run on the web.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.6-stable"
GODOT_DIR="$HOME/.local/godot"
GODOT_BIN="$GODOT_DIR/godot"

# gdtoolkit from PyPI works even under restricted network policies
# (package registries bypass the egress proxy).
pip install --quiet gdtoolkit || echo "WARN: could not install gdtoolkit (gdparse/gdlint unavailable)"

if [ ! -x "$GODOT_BIN" ]; then
  mkdir -p "$GODOT_DIR"
  tmp="$(mktemp -d)"
  downloaded=""
  for url in \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    "https://downloads.godotengine.org/godotengine/4.6/Godot_v${GODOT_VERSION}_linux.x86_64.zip"; do
    if curl -fsSL --retry 2 -o "$tmp/godot.zip" "$url" \
        && unzip -o -q "$tmp/godot.zip" -d "$tmp" 2>/dev/null; then
      downloaded="yes"
      break
    fi
  done
  if [ -z "$downloaded" ]; then
    # Soft-fail so the session still starts; the smoke test just won't run.
    echo "WARN: could not download Godot ${GODOT_VERSION}."
    echo "WARN: This environment's network policy must allow one of:"
    echo "WARN:   - github.com release downloads (godotengine/godot)"
    echo "WARN:   - downloads.godotengine.org"
    echo "WARN: Fix it in the environment's network settings at claude.ai/code."
    rm -rf "$tmp"
    exit 0
  fi
  mv "$tmp"/Godot_v"${GODOT_VERSION}"_linux.x86_64 "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  rm -rf "$tmp"
fi

echo "export PATH=\"$GODOT_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# Build the script-class cache once so headless runs work (per README).
"$GODOT_BIN" --headless --path "$CLAUDE_PROJECT_DIR" --import >/dev/null 2>&1 || true
echo "Godot ready: $("$GODOT_BIN" --version 2>/dev/null | head -1)"

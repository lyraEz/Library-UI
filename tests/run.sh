#!/usr/bin/env bash
# Runs the Lyra UI test scenario with the Luau CLI.
# Usage: tests/run.sh [path-to-luau]   (defaults to "luau" on PATH)
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${1:-${LUAU:-luau}}"
WORK="$(mktemp -d)"
OUT="$WORK/lyra-ui-test.lua"
trap 'rm -rf "$WORK"' EXIT
{
    cat tests/mock.lua
    echo 'Mock.Module = (function()'
    cat src/Lyra.lua
    echo 'end)()'
    echo 'local function runShowcase()'
    cat examples/showcase.lua
    echo 'end'
    echo 'local function runMinimal()'
    cat examples/minimal.lua
    echo 'end'
    cat tests/run.lua
} > "$OUT"
"$LUAU" "$OUT"

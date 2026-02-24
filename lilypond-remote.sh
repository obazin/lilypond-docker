#!/usr/bin/env bash
# =============================================================================
# lilypond-remote — run LilyPond on a remote Docker host via SSH
# =============================================================================
#
# Usage:
#   lilypond-remote myscore.ly
#   lilypond-remote --png myscore.ly
#   lilypond-remote --png -dresolution=300 myscore.ly
#
# The .ly file (and all sibling files in its directory) are sent to the
# server. LilyPond runs inside a persistent container. Output files
# (PDF/PNG/MIDI) are pulled back to the local directory. The container
# is stopped after each run but kept for fast restarts.
#
# Configuration (edit below or export before calling):
#   LILYPOND_SERVER   SSH destination (user@host)
#   LILYPOND_CONTAINER  Container name (default: lilypond)
# =============================================================================

set -euo pipefail

: "${LILYPOND_SERVER:=YOUR_SERVER}"
: "${LILYPOND_CONTAINER:=lilypond}"

# ---------------------------------------------------------------------------
# Parse arguments: everything before the last arg = flags, last arg = .ly file
# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  echo "Usage: lilypond-remote [FLAGS...] <file.ly>" >&2
  exit 1
fi

args=("$@")
file="${args[-1]}"
flags=("${args[@]:0:$((${#args[@]} - 1))}")

if [ ! -f "$file" ]; then
  echo "Error: file not found: $file" >&2
  exit 1
fi

dir="$(cd "$(dirname "$file")" && pwd)"
base="$(basename "$file")"
cname="$LILYPOND_CONTAINER"
server="$LILYPOND_SERVER"

# ---------------------------------------------------------------------------
# 1. Ensure the container exists and is running
# ---------------------------------------------------------------------------
ssh "$server" bash -s -- "$cname" <<'REMOTE_SETUP'
  cname="$1"

  if ! docker container inspect "$cname" &>/dev/null; then
    echo "[lilypond] Creating container '$cname'..."
    docker create \
      --name "$cname" \
      --network=none \
      --entrypoint sleep \
      lilypond infinity >/dev/null
  fi

  state="$(docker inspect -f '{{.State.Running}}' "$cname")"
  if [ "$state" != "true" ]; then
    echo "[lilypond] Starting container '$cname'..."
    docker start "$cname" >/dev/null
  fi

  # Clean working directory from previous runs (including dotfiles)
  docker exec "$cname" sh -c 'find /scores -mindepth 1 -delete'
  echo "[lilypond] Output folder cleaned."
REMOTE_SETUP

# ---------------------------------------------------------------------------
# 2. Send source files (entire directory)
# ---------------------------------------------------------------------------
echo "[lilypond] Sending files..."
tar -c -C "$dir" --exclude='*.pdf' --exclude='*.png' --exclude='*.midi' --exclude='*.svg' . |
  ssh "$server" "docker exec -i $cname tar x -C /scores"

# ---------------------------------------------------------------------------
# 3. Run LilyPond
# ---------------------------------------------------------------------------
echo "[lilypond] Compiling ${base}..."
ssh "$server" "docker exec $cname lilypond ${flags[*]+"${flags[*]}"} '$base'"

# ---------------------------------------------------------------------------
# 4. Retrieve output files (pdf, png, midi, svg)
# ---------------------------------------------------------------------------
echo "[lilypond] Retrieving output..."
# /scores was cleaned before the run, so all output files are from this compilation
ssh "$server" "docker exec $cname sh -c '
  cd /scores
  find . \( -name \"*.pdf\" -o -name \"*.png\" -o -name \"*.midi\" -o -name \"*.svg\" \) | tar c -T -
'" | tar x -C "$dir"

# ---------------------------------------------------------------------------
# 5. Stop container (keep it for next run)
# ---------------------------------------------------------------------------
ssh "$server" "docker stop -t 2 $cname >/dev/null"

echo "[lilypond] Done → $(ls "$dir"/"${base%.ly}".{pdf,png,svg,midi} 2>/dev/null | tr '\n' ' ')"

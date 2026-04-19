#!/bin/bash

show_help() {
    cat <<'HELP'
Usage: ./run.sh [COMMAND]

Start the Hermes Gate TUI.

Commands:
      (none)         Start (or connect to existing container)
      rebuild        Force rebuild the Docker image, then start
      update         git pull, then rebuild and start
      stop           Stop and remove the container
      --help, -h     Show this help message and exit

Multiple terminals can run ./run.sh simultaneously — each gets an
independent TUI session inside the same container. The container
auto-stops when the last session exits.
HELP
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

set -e

CONTAINER_NAME="hermes-gate"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_DIR="$PROJECT_DIR/.notify"

# ─── notification watcher (macOS/Linux) ────────────────────────────
_notify_watcher() {
    mkdir -p "$NOTIFY_DIR"
    SOUNDS_DIR="$PROJECT_DIR/sounds"
    while true; do
        for f in "$NOTIFY_DIR"/notify-*.json; do
            [ -f "$f" ] || continue
            msg=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('message',''))" 2>/dev/null || echo "")
            title=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('title','Hermes Gate'))" 2>/dev/null || echo "Hermes Gate")
            sound=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('sound',''))" 2>/dev/null || echo "")
            sound_file=""
            [ -n "$sound" ] && [ -f "$SOUNDS_DIR/$sound" ] && sound_file="$SOUNDS_DIR/$sound"
            if [ "$(uname)" = "Darwin" ]; then
                osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
                [ -n "$sound_file" ] && afplay "$sound_file" 2>/dev/null &
            elif command -v notify-send >/dev/null 2>&1; then
                notify-send "$title" "$msg" 2>/dev/null || true
                [ -n "$sound_file" ] && { command -v paplay >/dev/null 2>&1 && paplay "$sound_file" 2>/dev/null || aplay "$sound_file" 2>/dev/null; } &
            fi
            rm -f "$f"
        done
        sleep 2
    done
}

_cleanup_watcher() {
    if [ -n "${_WATCHER_PID:-}" ]; then
        disown "$_WATCHER_PID" 2>/dev/null
        kill "$_WATCHER_PID" 2>/dev/null
    fi
    _auto_stop
}

# ─── auto-stop if no other sessions ───────────────────────────────
_auto_stop() {
    REMAINING=$(docker exec "${CONTAINER_NAME}" pgrep -c python 2>/dev/null || true)
    if [ "${REMAINING:-0}" -eq 0 ] 2>/dev/null; then
        echo "No active sessions, stopping container..."
        docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    fi
}

# ─── stop subcommand ──────────────────────────────────────────────
if [ "$1" = "stop" ]; then
    echo "Stopping ${CONTAINER_NAME}..."
    docker compose down 2>/dev/null || docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Stopped."
    exit 0
fi

# ─── rebuild / update ─────────────────────────────────────────────
FORCE_REBUILD=false
if [ "$1" = "rebuild" ]; then
    FORCE_REBUILD=true
elif [ "$1" = "update" ]; then
    echo "Pulling latest changes..."
    git pull
    FORCE_REBUILD=true
fi

if [ "$FORCE_REBUILD" = true ]; then
    echo "Force rebuilding..."
    docker compose down --rmi local 2>/dev/null || true
    docker compose up -d --build
    echo "Build complete, launching TUI..."
    mkdir -p "$NOTIFY_DIR"
    _notify_watcher &
    _WATCHER_PID=$!
    trap _cleanup_watcher EXIT
    docker exec -it "${CONTAINER_NAME}" python -m hermes_gate || true
    exit 0
fi

# ─── ensure container is running ──────────────────────────────────
RUNNING=$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || echo "false")

if [ "$RUNNING" != "true" ]; then
    EXISTS=$(docker inspect -f '{{.Id}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

    if [ -n "$EXISTS" ]; then
        echo "Container exists (stopped), starting..."
        docker start "${CONTAINER_NAME}"
    else
        HAS_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "hermes" || true)
        if [ -n "$HAS_IMAGE" ]; then
            echo "Image found, starting container..."
            docker compose up -d
        else
            echo "No image found, building for the first time..."
            docker compose up -d --build
        fi
    fi
    echo "Container started, launching TUI..."
fi

# ─── launch TUI ───────────────────────────────────────────────────
mkdir -p "$NOTIFY_DIR"
_notify_watcher &
_WATCHER_PID=$!
trap _cleanup_watcher EXIT
docker exec -it "${CONTAINER_NAME}" python -m hermes_gate || true

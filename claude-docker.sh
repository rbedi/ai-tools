#!/bin/bash
set -euo pipefail

# Claude Code Docker Runner
# Usage:
#   ./claude-docker.sh                              # Interactive session in current dir
#   ./claude-docker.sh /path/to/project             # Interactive session in specified dir
#   ./claude-docker.sh --bio /path/to/project       # Use bio image (with conda env)
#   ./claude-docker.sh --budget 5 . -p "fix tests"  # Cap spend at $5
#   ./claude-docker.sh --no-firewall .              # Skip network firewall

IMAGE_NAME="claude-code-sandbox"
CONTAINER_PREFIX="claude-sandbox"

# --- Parse arguments ---
PROJECT_DIR=""
CLAUDE_ARGS=()
ENABLE_FIREWALL=true
USE_BIO=false
MAX_BUDGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bio)
            USE_BIO=true
            shift
            ;;
        --no-firewall)
            ENABLE_FIREWALL=false
            shift
            ;;
        --budget)
            MAX_BUDGET="$2"
            shift 2
            ;;
        *)
            if [[ -z "$PROJECT_DIR" && -d "$1" ]]; then
                PROJECT_DIR="$1"
            else
                CLAUDE_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

if $USE_BIO; then
    IMAGE_NAME="claude-code-sandbox-bio"
    CONTAINER_PREFIX="claude-sandbox-bio"
fi

# Default to current directory
if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(pwd)"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"  # Resolve to absolute path
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# --- Check for API key ---
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "Error: ANTHROPIC_API_KEY environment variable is not set."
    echo ""
    echo "Set it with:"
    echo "  export ANTHROPIC_API_KEY='sk-ant-...'"
    exit 1
fi

# --- Build image if needed ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$SCRIPT_DIR/.devcontainer"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    if $USE_BIO; then
        echo "Building Claude Code + Bio Docker image (this will take a while the first time)..."
        docker build -t "$IMAGE_NAME" -f "$DEVCONTAINER_DIR/Dockerfile.bio" "$DEVCONTAINER_DIR"
    else
        echo "Building Claude Code Docker image (first time only)..."
        docker build -t "$IMAGE_NAME" -f "$DEVCONTAINER_DIR/Dockerfile" "$DEVCONTAINER_DIR"
    fi
    echo ""
fi

# --- Build claude flags ---
CLAUDE_FLAGS="--dangerously-skip-permissions"
if [[ -n "$MAX_BUDGET" ]]; then
    CLAUDE_FLAGS="$CLAUDE_FLAGS --max-budget-usd $MAX_BUDGET"
fi

# --- Run container ---
CONTAINER_NAME="${CONTAINER_PREFIX}-$(date +%s)"

echo "Starting Claude Code sandbox..."
echo "  Image: $IMAGE_NAME"
echo "  Project: $PROJECT_DIR -> /workspace"
echo "  Firewall: $ENABLE_FIREWALL"
if [[ -n "$MAX_BUDGET" ]]; then
    echo "  Budget: \$$MAX_BUDGET"
fi
echo ""

DOCKER_ARGS=(
    --rm
    -it
    --name "$CONTAINER_NAME"
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
    -e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
    -e "NODE_OPTIONS=--max-old-space-size=4096"
    -v "$PROJECT_DIR:/workspace"
    -v "claude-code-config:/home/node/.claude"
    "$IMAGE_NAME"
)

if [[ ${#CLAUDE_ARGS[@]} -gt 0 ]]; then
    # Non-interactive: run with args and exit
    if $ENABLE_FIREWALL; then
        docker run "${DOCKER_ARGS[@]}" \
            bash -c "sudo /usr/local/bin/init-firewall.sh && claude $CLAUDE_FLAGS ${CLAUDE_ARGS[*]}"
    else
        docker run "${DOCKER_ARGS[@]}" \
            bash -c "claude $CLAUDE_FLAGS ${CLAUDE_ARGS[*]}"
    fi
else
    # Interactive: drop into shell with claude available
    if $ENABLE_FIREWALL; then
        docker run "${DOCKER_ARGS[@]}" \
            bash -c "sudo /usr/local/bin/init-firewall.sh && echo \"Claude Code sandbox ready. Run: claude $CLAUDE_FLAGS\" && exec bash"
    else
        docker run "${DOCKER_ARGS[@]}" \
            bash -c "echo \"Claude Code sandbox ready (no firewall). Run: claude $CLAUDE_FLAGS\" && exec bash"
    fi
fi

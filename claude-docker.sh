#!/bin/bash
set -euo pipefail

# Claude Code Docker Runner
# Usage:
#   ./claude-docker.sh                          # Interactive session in current dir (base image)
#   ./claude-docker.sh /path/to/project         # Interactive session in specified dir
#   ./claude-docker.sh --bio /path/to/project   # Use bio image (with conda env)
#   ./claude-docker.sh . -p "fix all tests"     # Pass args to claude (non-interactive)
#   ./claude-docker.sh --no-firewall .          # Skip network firewall

IMAGE_NAME="claude-code-sandbox"
CONTAINER_PREFIX="claude-sandbox"

# --- Parse arguments ---
PROJECT_DIR=""
CLAUDE_ARGS=()
ENABLE_FIREWALL=true
USE_BIO=false
FORCE_REBUILD=false

for arg in "$@"; do
    if [[ "$arg" == "--bio" ]]; then
        USE_BIO=true
    elif [[ "$arg" == "--rebuild" ]]; then
        FORCE_REBUILD=true
    elif [[ "$arg" == "--no-firewall" ]]; then
        ENABLE_FIREWALL=false
    elif [[ -z "$PROJECT_DIR" && -d "$arg" ]]; then
        PROJECT_DIR="$arg"
    else
        CLAUDE_ARGS+=("$arg")
    fi
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

if $FORCE_REBUILD || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    if $USE_BIO; then
        echo "Building Claude Code + Bio Docker image (this will take a while the first time)..."
        docker build -t "$IMAGE_NAME" --build-arg HOST_UID="$(id -u)" -f "$DEVCONTAINER_DIR/Dockerfile.bio" "$DEVCONTAINER_DIR"
    else
        echo "Building Claude Code Docker image (first time only)..."
        docker build -t "$IMAGE_NAME" -f "$DEVCONTAINER_DIR/Dockerfile" "$DEVCONTAINER_DIR"
    fi
    echo ""
fi

# --- Run container ---
CONTAINER_NAME="${CONTAINER_PREFIX}-$(date +%s)"

echo "Starting Claude Code sandbox..."
echo "  Image: $IMAGE_NAME"
echo "  Project: $PROJECT_DIR -> /workspace"
echo "  Firewall: $ENABLE_FIREWALL"
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
            bash -c "sudo /usr/local/bin/init-firewall.sh && claude --dangerously-skip-permissions ${CLAUDE_ARGS[*]}"
    else
        docker run "${DOCKER_ARGS[@]}" \
            bash -c "claude --dangerously-skip-permissions ${CLAUDE_ARGS[*]}"
    fi
else
    # Interactive: drop into shell with claude available
    if $ENABLE_FIREWALL; then
        docker run "${DOCKER_ARGS[@]}" \
            bash -c 'sudo /usr/local/bin/init-firewall.sh && echo "Claude Code sandbox ready. Run: claude --dangerously-skip-permissions" && exec bash'
    else
        docker run "${DOCKER_ARGS[@]}" \
            bash -c 'echo "Claude Code sandbox ready (no firewall). Run: claude --dangerously-skip-permissions" && exec bash'
    fi
fi

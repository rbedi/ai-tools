# Claude Code Docker Sandbox

Run Claude Code with `--dangerously-skip-permissions` inside a Docker container so it can't touch your real filesystem.

## Quick Start

```bash
export ANTHROPIC_API_KEY='sk-ant-...'

# Interactive session
./claude-docker.sh ~/my-project

# One-shot prompt
./claude-docker.sh ~/my-project -p "refactor the auth module"
```

Inside the container, your project is mounted at `/workspace`. Claude can read/write freely there but has no access to anything else on your machine.

## Bio Image (conda env)

A second image (`claude-code-sandbox-bio`) includes the full `bio` conda environment with Python 3.11, numpy, pandas, torch, scipy, scikit-learn, transformers, biopython, rdkit, and ~150 other bio/ML packages.

```bash
# Interactive session with bio env
./claude-docker.sh --bio ~/my-project

# One-shot with bio env
./claude-docker.sh --bio ~/my-project -p "analyze the protein sequences"
```

The conda `bio` env is auto-activated on container start. A few packages from the original env aren't available on linux/arm64:
- `prody` — fails to build (C extension issue)
- `fast-tsp` — no arm64 wheel
- All `pyobjc-*` packages — macOS only

To add these or other packages, edit `.devcontainer/bio-requirements.txt` and rebuild.

## Options

```bash
# Skip the network firewall (see "Network Access" below)
./claude-docker.sh ~/my-project --no-firewall

# Use bio image without firewall
./claude-docker.sh --bio --no-firewall ~/my-project

# Pass any claude args after the directory
./claude-docker.sh ~/my-project -p "fix all tests" --model sonnet
```

## Network Access & Firewall

By default, `init-firewall.sh` runs at container start and sets up iptables rules that **only** allow traffic to:

- `api.anthropic.com` (Claude API)
- `registry.npmjs.org` (npm)
- GitHub IP ranges
- `sentry.io`, `statsig.anthropic.com` (telemetry)

Everything else is blocked. Pass `--no-firewall` to disable this.

### Should you use the firewall?

The firewall protects against **prompt injection from untrusted repos** — malicious content hidden in code/docs that tricks Claude into exfiltrating data over the network. The two things at risk are:

1. **Your `ANTHROPIC_API_KEY`** — could be sent to an attacker's server
2. **Your project source code** — could be exfiltrated

What's **not** at risk regardless (container isolation handles this):
- Your home directory, SSH keys, cloud credentials, browser cookies
- Other processes on your machine
- Any files outside the mounted directories

**TL;DR:** If you're working on non-sensitive code and use a rotatable/spend-limited API key, `--no-firewall` is fine. Use the firewall when working with untrusted repos or sensitive source code.

## Mounting Additional Directories

The convenience script mounts your project directory to `/workspace`. To mount additional directories, use `docker run` directly:

```bash
docker run --rm -it \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e NODE_OPTIONS="--max-old-space-size=4096" \
  -v ~/my-project:/workspace \
  -v ~/shared-libs:/mnt/shared-libs \
  -v ~/data:/mnt/data:ro \
  claude-code-sandbox \
  bash -c 'sudo /usr/local/bin/init-firewall.sh && claude --dangerously-skip-permissions'
```

The pattern is `-v /host/path:/container/path`. Add `:ro` for read-only. You can add as many `-v` flags as you need.

If you don't need the firewall, drop the `--cap-add` flags and the `init-firewall.sh` call:

```bash
docker run --rm -it \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -v ~/my-project:/workspace \
  -v ~/shared-libs:/mnt/shared-libs \
  claude-code-sandbox \
  bash -c 'claude --dangerously-skip-permissions'
```

## VS Code DevContainer

Open this folder in VS Code, then `Cmd+Shift+P` → **Dev Containers: Reopen in Container**. The `.devcontainer/devcontainer.json` configures everything automatically including the firewall.

## Rebuilding the Image

The images are built automatically on first run. To rebuild (e.g. after a new Claude Code release or package changes):

```bash
# Base image
docker build -t claude-code-sandbox -f .devcontainer/Dockerfile .devcontainer/

# Bio image
docker build -t claude-code-sandbox-bio -f .devcontainer/Dockerfile.bio .devcontainer/
```

Or delete and let the script rebuild:

```bash
docker rmi claude-code-sandbox
docker rmi claude-code-sandbox-bio
```

## What's in the Containers

**Base image** (`claude-code-sandbox`):
- Node.js 20
- Claude Code (latest)
- git, gh (GitHub CLI), jq, vim, nano, fzf
- iptables/ipset (for the firewall)
- Runs as non-root `node` user

**Bio image** (`claude-code-sandbox-bio`) — everything above, plus:
- Conda (miniforge) with `bio` env auto-activated
- Python 3.11 with numpy, pandas, scipy, scikit-learn, matplotlib, seaborn
- PyTorch 2.x (CPU), TensorFlow 2.15, transformers, huggingface-hub
- Biopython, RDKit, pyhmmer, hmmer, anndata, pydeseq2, fair-esm
- PDF/doc tools: docling, pymupdf, pdfplumber, tesseract
- And ~150 more packages (see `bio-requirements.txt`)

## File Layout

```
.devcontainer/
  Dockerfile              # Base image
  Dockerfile.bio          # Bio image (extends base with conda env)
  devcontainer.json       # VS Code DevContainer config
  init-firewall.sh        # Network firewall script
  bio-environment.yml     # Conda packages for bio env
  bio-requirements.txt    # Pip packages for bio env
claude-docker.sh          # Convenience runner script
```

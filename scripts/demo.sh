#!/usr/bin/env bash
#
# demo.sh — drives the README demo so it can be captured as an asciinema cast / GIF.
#
# This is the highest-ROI marketing asset for mcp-box: it shows, in ~15 seconds,
# a process inside the sandbox *failing* to escape — the entire value proposition
# in one shot.
#
# What it demonstrates: the container hardening (read-only root, no network,
# dropped caps) applies to ANY process in the box, so we run plain commands via
# `-- bash -c '...'` to prove the boundary holds. (The real product runs an MCP
# server over stdio inside this same box; the isolation shown here is what wraps
# it.)
#
# Record it:
#   asciinema rec -c "scripts/demo.sh" mcp-box-demo.cast
#   agg mcp-box-demo.cast docs/demo.gif        # asciinema/agg -> GIF
#
# Then embed docs/demo.gif at the top of README.md.
#
# Requirements: mcp-box on PATH (or ./mcp-box), Docker running, and the `shell`
# image already present. Pre-warm it before recording so the cast is tight:
#   mcp-box build shell      (Nix)   or   mcp-box run shell -- true   (pulls from GHCR)

set -u

# Resolve the CLI: prefer ./mcp-box, fall back to PATH.
MCP_BOX="./mcp-box"
command -v "$MCP_BOX" >/dev/null 2>&1 || MCP_BOX="mcp-box"

# Fixed, clean workspace path so the recording shows a tidy directory (not a
# random mktemp path under $TMPDIR, which is noisy inside a nix-shell).
WORKDIR="/tmp/mcp-box-demo"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

# Small helper: print a prompt + command, pause briefly, then run it.
step() {
  printf '\n\033[1;32m$ \033[0m%s\n' "$*"
  sleep 1
  "$@"
}

clear
printf '\033[1;36m# mcp-box — your AI agent runs its tools in a locked box.\033[0m\n'
sleep 1

printf '\n\033[1;36m# A writable workspace IS allowed (you chose it):\033[0m\n'
step "$MCP_BOX" run shell --workspace "$WORKDIR" -- \
  bash -c 'echo hello > /workspace/ok.txt && cat /workspace/ok.txt'

printf '\n\033[1;36m# Escaping the box is NOT — the root FS is read-only:\033[0m\n'
step "$MCP_BOX" run shell --workspace "$WORKDIR" -- \
  bash -c 'touch /etc/naughty'

printf '\n\033[1;36m# And it has no network, so it cannot send your data anywhere:\033[0m\n'
step "$MCP_BOX" run shell --workspace "$WORKDIR" -- \
  bash -c 'curl -sS -m 5 https://example.com'

printf '\n\033[1;32m# Your host, configs, and keys never came into reach.\033[0m\n'
sleep 1

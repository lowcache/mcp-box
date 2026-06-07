#!/usr/bin/env bash
#
# demo.sh — drives the README demo so it can be captured as an asciinema cast / GIF.
#
# This is the highest-ROI marketing asset for mcp-box: it shows, in ~15 seconds,
# a sandboxed tool *failing* to escape — the entire value proposition in one shot.
#
# Record it:
#   asciinema rec -c "scripts/demo.sh" mcp-box-demo.cast
#   agg mcp-box-demo.cast docs/demo.gif        # asciinema/agg -> GIF
#
# Then embed docs/demo.gif at the top of README.md.
#
# Requirements: mcp-box on PATH (or ./mcp-box), Docker running. On first run the
# shell image is built (Nix) or pulled (GHCR); pre-warm it before recording so the
# cast is tight:  mcp-box build shell   (or: mcp-box run shell -- --help)

set -u

# Resolve the CLI: prefer ./mcp-box, fall back to PATH.
MCP_BOX="./mcp-box"
command -v "$MCP_BOX" >/dev/null 2>&1 || MCP_BOX="mcp-box"

WORKDIR="$(mktemp -d)"
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
  --tool run_command "echo hello > /workspace/ok.txt && cat /workspace/ok.txt"

printf '\n\033[1;36m# Escaping the box is NOT — the root FS is read-only:\033[0m\n'
step "$MCP_BOX" run shell --workspace "$WORKDIR" -- \
  --tool run_command "touch /etc/naughty"

printf '\n\033[1;36m# And there is no network to phone home over:\033[0m\n'
step "$MCP_BOX" run shell --workspace "$WORKDIR" -- \
  --tool run_command "curl -sS -m 5 https://example.com"

printf '\n\033[1;32m# Your host, configs, and keys never came into reach.\033[0m\n'
sleep 1

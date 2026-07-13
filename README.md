# mcp-box

[![CI](https://github.com/lowcache/mcp-box/actions/workflows/ci.yml/badge.svg)](https://github.com/lowcache/mcp-box/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Go](https://img.shields.io/badge/Go-1.22%2B-00ADD8.svg)](src/go/go.mod)

![mcp-box sandbox demo](docs/demo.gif)

**Your AI agent's tools run with your permissions.** When an MCP server can call `run_command` or write files, 
a buggy prompt or a malicious instruction can reach your home directory, your SSH keys, and your cloud credentials. 
`mcp-box` puts every MCP server inside a locked-down Docker sandbox with a read-only root filesystem, explicit writable mounts, 
dropped Linux capabilities, and per-profile network policy. Only the folders you mount are writable; the rest of your host stays out of reach.

> ### mcp-box is the boringly reliable way to run MCP servers safely: inspectable, reproducible, and default-deny by design.

**mcp-box** is a single, portable **Go** binary that launches turnkey, immutable, strictly-isolated
container sandboxes for Model Context Protocol (MCP) servers. Nix is used for deterministic image builds 
when present, but it is **entirely optional**. Without Nix, `mcp-box` pulls the same pinned OCI image definitions
from GHCR and runs them under the same Docker isolation model. Docker is the only hard requirement.

> ### Same server, same hardening, same sandbox boundary — only the image source changes.


## Security Audit Checks

You can audit the sandbox boundary directly by overriding the container command with -- bash -c '...'. 
These checks prove the boundary itself, not just the MCP server running inside it. 
The hardening (read-only root, no network, dropped capabilities, host UID mapping) applies to *any* process in the box:

1. **Read-only filesystem** — writes outside `/workspace` are rejected:
   ```bash
   ./mcp-box run shell -- bash -c 'touch /etc/naughty'
   # => touch: cannot touch '/etc/naughty': Read-only file system   (exit 1)
   ```
2. **Network isolation** — with the default `--network none`, DNS/egress fail:
   ```bash
   ./mcp-box run shell -- bash -c 'curl -I https://google.com'
   # => curl: (6) Could not resolve host: google.com               (exit 6)
   ```
3. **No privilege escalation** — `sudo` is not even present in the image:
   ```bash
   ./mcp-box run shell -- bash -c 'sudo -l'
   # => bash: line 1: sudo: command not found                       (exit 127)
   ```
4. **Host UID/GID mapping** — the process is *you*, not root:
   ```bash
   ./mcp-box run shell -- bash -c 'id'
   # => uid=<your uid> gid=<your gid> ...   (files in /workspace are owned by you)
   ```

---

## Key Features

1. **Strict Sandboxing**:
   - **Immutable Root (`--read-only`)**: The entire root filesystem is mounted read-only.
   - **Transient State (`--tmpfs`)**: Writable spaces (`/tmp` and `/run`) exist solely in RAM and disappear once the container stops.
   - **Zero Capabilities (`--cap-drop=ALL`)**: The running processes have no special Linux kernel capabilities.
   - **No Privilege Escalation (`no-new-privileges:true`)**: Prevents elevation to root inside the sandbox.
   - **Per-Profile Network Policy**:
      - Most sandboxes default to `--network none`.
      - Networked profiles are explicit and opt-in, so a server only gets egress when its job genuinely requires it.
      - The `fetch` profile is the exception by design: it uses a controlled network mode for web access, while still keeping the container boundary intact.
   - **Scoped Workspaces**: Only specifically mounted host directories (`--workspace`) are visible to the server at `/workspace`.
2. **Correct File Ownership**:
   - Containers run mapped to your host UID/GID (`-u $(id -u):$(id -g)`), ensuring that files written to mounted workspaces are owned by you (not `root`) and don't trigger host-side permission errors.
3. **Painless Integration**:
   - Built-in configuration generator (`mcp-box config <server>`) prints out paste-ready JSON snippets to plug directly into `claude_desktop_config.json` or OpenClaw configurations.
4. **Zero-Dependency Nix Autonomy**:
   - If Nix is installed, running a sandbox automatically triggers a local rebuild and load of the OCI image.
   - If Nix is absent, `mcp-box` automatically detects this and falls back to pulling pre-built, identical, and secure OCI images directly from the GitHub Container Registry (`ghcr.io/lowcache`), making Nix entirely optional for the end-user.

---

## CLI Surface

`mcp-box` is designed to be inspectable, scriptable, and auditable.

- `mcp-box run <server>` — launch a sandboxed MCP server
- `mcp-box stop <id>` — stop a running sandbox
- `mcp-box ps` — list active sandboxes
- `mcp-box inspect <id>` — show the full sandbox spec and policy
- `mcp-box logs <id>` — read audit logs
- `mcp-box logs --follow` — stream live events
- `mcp-box config <server>` — print paste-ready client config
- `mcp-box build <server>` — rebuild or refresh an OCI image

---

## Quickstart

```bash
# 1. Get the binary (Docker is the only dependency)
curl -sSL https://github.com/lowcache/mcp-box/releases/latest/download/mcp-box-linux-amd64 -o mcp-box
chmod +x mcp-box && mv mcp-box ~/.local/bin/

# 2. Prove the sandbox holds — this write MUST fail
mcp-box run shell --workspace /tmp/demo -- bash -c 'touch /etc/naughty'
# => touch: cannot touch '/etc/naughty': Read-only file system

# 3. Wire it into your AI client (paste the output into claude_desktop_config.json)
mcp-box config sqlite
```

---

## Pre-Packaged Sandboxes

| Server Name | Language | Included Utilities | Network Mode | Primary Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **`sqlite`** | Python | `sqlite3` CLI, `fastmcp` SDK | `none` | High-performance, isolated database querying. |
| **`shell`** | Python | `bash`, `ripgrep`, `fd`, `git`, `curl`, `jq`, `sqlite`, `tar` | `none` | Safe, sandboxed script running and file operations. |
| **`filesystem`** | Node.js | `ripgrep`, `fd`, `git` | `none` | Scoped filesystem read/write and code searching. |
| **`fetch`** | Node.js | `curl` | `bridge` | Safe, isolated web fetching and scraping. |

---

## Policy, Compose, and Auditability

`mcp-box` is not just a runner — it is a trust layer for MCP execution.

Planned core platform features:
- **Policy profiles** for common trust levels: `readonly`, `dev`, `trusted`, `internet-off`, `internet-on`
- **Compose-style specs** for multi-server setups
- **Append-only audit logs** for sandbox lifecycle and denied actions
- **`ps` / `inspect` / `logs`** so every sandbox can be checked after launch
- **Pinned image digests** for reproducible, reviewable execution

---

## Dependencies

Depending on your installation path, `mcp-box` has distinct dependency requirements:

*   **Runtime Boundary (All Users)**:
    - **Docker Engine** (Must be active and running locally on the host system).
*   **Local Image Building (Source Flow with Nix)**:
    - **Nix** (with experimental `flakes` and `nix-command` enabled).
*   **CLI Compilation (Source Flow with Go)**:
    - **Go** compiler v1.22 or higher (only required if building the executable from source without using Nix).
*   **Zero-Dependency Fallback Flow**:
    - **None**. The pre-compiled CLI binary runs standalone and automatically pulls the pre-built, multi-arch OCI images straight from GHCR into your local Docker daemon.

---

## Architecture

```mermaid
graph TD
    subgraph Host [Host Environment]
        Agent[AI Agent / Claude Desktop] <-->|stdio piping| CLI[mcp-box CLI]
        CLI -->|Checks for Nix| NixDetect{Nix Installed?}
        
        NixDetect -->|Yes: Source Flow| NixBuild[nix build .#server]
        NixBuild -->|Stream tarball| DockerLoad[docker load]
        
        NixDetect -->|No: Registry Flow| DockerPull[docker pull ghcr.io]
        DockerPull -->|Tag locally| DockerLoad
        
        DockerLoad -->|Loads image| Docker[Docker Engine]
    end
    
    subgraph Sandbox [Docker Sandbox]
        Server[MCP Server]
        Tools[Isolated Tools: git, rg, sqlite3, curl]
        Workspace[Mounted Workspace: /workspace]
    end
    
    Docker -->|spawns with strict isolation| Sandbox
    CLI <-->|stdio piping| Server
```

---

## Installation

Depending on your host environment, you can install and run `mcp-box` with three different avenues:

### Option A: Pre-built Go Binary (No Nix / Docker-only)
For systems that only have Docker installed:
1. **Download the compiled CLI binary** (pick the asset matching your OS/arch — `linux`/`darwin`, `amd64`/`arm64`):
   ```bash
   curl -sSL https://github.com/lowcache/mcp-box/releases/latest/download/mcp-box-linux-amd64 -o mcp-box
   chmod +x mcp-box
   ```
2. **Move to PATH** (Optional):
   ```bash
   mv mcp-box ~/.local/bin/  # Or another folder in your PATH
   ```
*On first execution, `mcp-box` will automatically detect the absence of Nix and pull the pre-built OCI images from `ghcr.io/lowcache` into your local Docker daemon.*

### Option B: From Source via Nix Flake (Nix/NixOS)
For systems running Nix/NixOS:
*   **Run directly without installing**:
    ```bash
    nix run github:lowcache/mcp-box -- list
    ```
*   **Install to your user profile**:
    ```bash
    nix profile install github:lowcache/mcp-box
    ```
*   **Declarative Installation (NixOS / Home Manager)**:
    Add the flake input and package to your configuration:
    ```nix
    # flake.nix inputs:
    inputs.mcp-box.url = "github:lowcache/mcp-box";
    
    # In systemPackages or home.packages:
    inputs.mcp-box.packages.${pkgs.system}.default
    ```
*On first execution, `mcp-box` will build the Go binary and OCI images purely from source and load them directly into your local Docker daemon.*

### Option C: Compile from Source (Go Compiler)
If you want to compile the CLI binary manually without Nix:
1. **Clone the repository**:
   ```bash
   git clone https://github.com/lowcache/mcp-box.git
   cd mcp-box
   ```
2. **Compile the binary** (the Go module lives in `src/go`):
   ```bash
   cd src/go
   go build -o ../../mcp-box .
   ```
*You can now run `./mcp-box` directly, which will pull OCI layers from the registry or build locally using Nix based on your host environment.*

---

## Usage Guide

### 1. Show Help & Supported Servers
```bash
./mcp-box help
./mcp-box list
```

### 2. Run a Sandbox Interactively
You can launch any server interactively to test its behavior and tools:
```bash
./mcp-box run sqlite --workspace /tmp/sandbox-db -- --db /workspace/test.db
```

### 3. Build/Force-Update an OCI Image
If you want to manually rebuild or force-update a Nix-built image:
```bash
./mcp-box build sqlite
```

### 4. Integration with AI Clients

`mcp-box config <server>` prints a ready-to-paste `mcpServers` JSON block (with an
absolute path to the binary). The same block works for both Claude Desktop and
Claude Code.

```bash
./mcp-box config sqlite
```

#### Claude Code (CLI)

Claude Code does **not** use `claude_desktop_config.json`. Add the server with one
command — note the nested `--` (the first separates `claude`'s flags from the
subprocess; the second is consumed by `mcp-box` to forward server args):

```bash
# user scope (available in every project); drop -s user for the current project only
claude mcp add -s user mcp-box-sqlite -- \
  mcp-box run sqlite --workspace /abs/path/to/workspace -- --db /workspace/db.sqlite
```

Or, to commit a shareable config to your repo, drop the `mcp-box config` JSON block
straight into a project-root **`.mcp.json`** — it uses the exact `{"mcpServers": …}`
shape that `config` emits.

Verify with `claude mcp list`.

#### Claude Desktop

Paste the `config` block into `claude_desktop_config.json`. Its location is
OS-specific:

| OS | Path |
| :--- | :--- |
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| Linux | `~/.config/Claude/claude_desktop_config.json` |

---


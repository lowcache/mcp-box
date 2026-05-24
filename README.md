# mcp-box

**mcp-box** is a highly portable, compiled **Go** executable that provides turnkey, immutable, and highly-isolated Linux container environments optimized specifically for Model Context Protocol (MCP) servers. By coupling **Nix**'s deterministic building engine with **Docker**'s isolation policies, `mcp-box` completely sandboxes AI agent tool execution, keeping your host system, configurations, and private keys entirely safe from unauthorized access, accidental changes, or malicious exploits.

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
    - **None**. The pre-compiled CLI binary runs standalone and automatically pulls identical, signed OCI layers straight from GHCR into your local Docker daemon.

---

## Key Features

1. **Strict Sandboxing**:
   - **Immutable Root (`--read-only`)**: The entire root filesystem is mounted read-only.
   - **Transient State (`--tmpfs`)**: Writable spaces (`/tmp` and `/run`) exist solely in RAM and disappear once the container stops.
   - **Zero Capabilities (`--cap-drop=ALL`)**: The running processes have no special Linux kernel capabilities.
   - **No Privilege Escalation (`no-new-privileges:true`)**: Prevents elevation to root inside the sandbox.
   - **Strict Network Policies (`--network none`)**: Servers like `sqlite`, `shell`, and `filesystem` have absolutely zero internet access by default.
   - **Scoped Workspaces**: Only specifically mounted host directories (`--workspace`) are visible to the server at `/workspace`.
2. **Correct File Ownership**:
   - Containers run mapped to your host UID/GID (`-u $(id -u):$(id -g)`), ensuring that files written to mounted workspaces are owned by you (not `root`) and don't trigger host-side permission errors.
3. **Painless Integration**:
   - Built-in configuration generator (`mcp-box config <server>`) prints out paste-ready JSON snippets to plug directly into `claude_desktop_config.json` or OpenClaw configurations.
4. **Zero-Dependency Nix Autonomy**:
   - If Nix is installed, running a sandbox automatically triggers a local rebuild and load of the OCI image.
   - If Nix is absent, `mcp-box` automatically detects this and falls back to pulling pre-built, identical, and secure OCI images directly from the GitHub Container Registry (`ghcr.io/lowcache`), making Nix entirely optional for the end-user.

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

## Pre-Packaged Sandboxes

| Server Name | Language | Included Utilities | Network Mode | Primary Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **`sqlite`** | Python | `sqlite3` CLI, `fastmcp` SDK | `none` | High-performance, isolated database querying. |
| **`shell`** | Python | `bash`, `ripgrep`, `fd`, `git`, `curl`, `jq`, `sqlite`, `tar` | `none` | Safe, sandboxed script running and file operations. |
| **`filesystem`** | Node.js | `ripgrep`, `fd`, `git` | `none` | Scoped filesystem read/write and code searching. |
| **`fetch`** | Node.js | `curl` | `bridge` | Safe, isolated web fetching and scraping. |

---

## Installation

Depending on your host environment, you can install and run `mcp-box` with three different avenues:

### Option A: Pre-built Go Binary (No Nix / Docker-only)
For systems that only have Docker installed:
1. **Download the compiled CLI binary**:
   ```bash
   curl -sSL https://github.com/lowcache/mcp-box/releases/latest/download/mcp-box -o mcp-box
   chmod +x mcp-box
   ```
2. **Move to PATH** (Optional):
   ```bash
   mv mcp-box ~/.local/bin/  # Or another folder in your PATH
   ```
*On first execution, `mcp-box` will automatically detect the absence of Nix and pull the secure pre-built OCI images from `ghcr.io/lowcache` into your local Docker daemon.*

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
2. **Compile the binary**:
   ```bash
   go build -o mcp-box
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
To hook `mcp-box` into an AI client like Claude Desktop, generate the JSON config snippet:
```bash
./mcp-box config sqlite
```
Copy the printed snippet and add it to your configuration file (typically `~/.config/Claude/claude_desktop_config.json`).

---

## Security Audit Checks

To verify that your sandbox is indeed perfectly secure and isolated:

1. **Check Read-Only Filesystem**:
   ```bash
   ./mcp-box run shell --workspace /tmp/test-space -- --tool run_command "touch /etc/naughty"
   # Output should fail: "touch: cannot touch '/etc/naughty': Read-only file system"
   ```
2. **Check Network Isolation**:
   ```bash
   ./mcp-box run shell --workspace /tmp/test-space -- --tool run_command "curl -I https://google.com"
   # Output should fail due to network resolution issues.
   ```
3. **Check Privilege Escalation Block**:
   ```bash
   ./mcp-box run shell --workspace /tmp/test-space -- --tool run_command "sudo -l"
   # Output should fail: "sudo: command not found" or "sudo: must be setuid root"
   ```

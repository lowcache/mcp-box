#!/usr/bin/env bash
set -euo pipefail

# Find the absolute path to this CLI script
CLI_PATH=$(realpath "$0")
PROJECT_DIR=$(dirname "$CLI_PATH")

usage() {
    cat <<EOF
mcp-box: Turnkey immutable and isolated Linux sandboxes for MCP servers.

Usage:
  $(basename "$0") <command> [arguments]

Commands:
  build <server>                  Build the Nix OCI image and load it into Docker.
  run <server> [options] -- [arg] Run the sandboxed MCP server with strict isolation.
  list                            List pre-configured MCP servers.
  config <server> [options]       Generate a Claude Desktop/OpenClaw configuration JSON.
  help                            Show this help menu.

Run Options:
  -w, --workspace <path>          Host directory to mount at /workspace (Default: none)
  -n, --network <none|bridge>     Network access mode (Default: none, except fetch defaults to bridge)
  -e, --env KEY=VALUE             Pass custom environment variable (Can be used multiple times)

Example:
  $(basename "$0") run sqlite --workspace /tmp/test-db -- --db /workspace/test.db
EOF
}

# Supported servers
SERVERS=("sqlite" "shell" "filesystem" "fetch")

is_supported_server() {
    local target="$1"
    for s in "${SERVERS[@]}"; do
        if [ "$s" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

# Verify docker is available
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker daemon is not running or accessible." >&2
        exit 1
    fi
}

cmd_build() {
    local server="${1:-}"
    if [ -z "$server" ]; then
        echo "Error: Please specify which MCP server to build." >&2
        echo "Available: ${SERVERS[*]}" >&2
        exit 1
    fi

    if ! is_supported_server "$server"; then
        echo "Error: Unknown MCP server: '$server'." >&2
        echo "Available: ${SERVERS[*]}" >&2
        exit 1
    fi

    echo "Building OCI image for '$server' via Nix and loading into Docker..."
    # We navigate to the project directory to build using the local flake
    (
        cd "$PROJECT_DIR"
        local script_path
        script_path=$(nix build .#"$server" --no-link --print-out-paths --extra-experimental-features "nix-command flakes")
        "$script_path" | docker load
    )
    echo "Successfully loaded mcp-box-${server}:latest into Docker."
}

cmd_run() {
    local server="${1:-}"
    if [ -z "$server" ]; then
        echo "Error: Please specify which MCP server to run." >&2
        exit 1
    fi

    if ! is_supported_server "$server"; then
        echo "Error: Unknown MCP server: '$server'." >&2
        exit 1
    fi

    check_docker

    # Auto-load OCI image if not already present
    if ! docker image inspect "mcp-box-${server}:latest" >/dev/null 2>&1; then
        if command -v nix >/dev/null 2>&1; then
            echo "Image 'mcp-box-${server}:latest' not found. Nix detected: Auto-building locally..." >&2
            cmd_build "$server"
        else
            local registry="ghcr.io/lowcache"
            echo "Image 'mcp-box-${server}:latest' not found. Nix not detected: Pulling from registry ${registry}..." >&2
            if ! docker pull "${registry}/mcp-box-${server}:latest"; then
                echo "Error: Failed to pull image from ${registry}/mcp-box-${server}:latest." >&2
                exit 1
            fi
            docker tag "${registry}/mcp-box-${server}:latest" "mcp-box-${server}:latest"
            docker rmi "${registry}/mcp-box-${server}:latest" >/dev/null 2>&1 || true
            echo "Successfully loaded registry image." >&2
        fi
    fi

    # Parse arguments
    shift 1
    local workspace=""
    local network=""
    local envs=()
    local server_args=()

    # Set default network security profiles
    if [ "$server" = "fetch" ]; then
        network="bridge" # Fetch server needs network access
    else
        network="none"   # Max isolation by default for others
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -w|--workspace)
                workspace=$(realpath "$2")
                shift 2
                ;;
            -n|--network)
                network="$2"
                shift 2
                ;;
            -e|--env)
                envs+=("-e" "$2")
                shift 2
                ;;
            --)
                shift 1
                server_args=("$@")
                break
                ;;
            *)
                echo "Error: Unknown run option: '$1'" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Prepare mount options
    local mounts=()
    if [ -n "$workspace" ]; then
        if [ ! -d "$workspace" ]; then
            mkdir -p "$workspace"
        fi
        mounts+=("--mount" "type=bind,source=${workspace},target=/workspace")
    fi

    # Execute sandbox with high isolation parameters
    # - --read-only: Root filesystem is completely read-only.
    # - --tmpfs: Writable transient RAM spaces for standard operations.
    # - --cap-drop=ALL: Drops all privileges.
    # - --security-opt=no-new-privileges:true: Prevents escalation.
    # - -u: Maps host UID/GID for correct host file ownership.
    exec docker run --rm -i \
        --init \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=64m \
        --tmpfs /run:rw,noexec,nosuid,size=16m \
        --cap-drop=ALL \
        --security-opt=no-new-privileges:true \
        --user "$(id -u):$(id -g)" \
        --network "$network" \
        "${mounts[@]}" \
        "${envs[@]}" \
        "mcp-box-${server}:latest" \
        "${server_args[@]}"
}

cmd_list() {
    echo "Available sandboxed MCP servers:"
    echo "  - sqlite      (Python FastMCP, SQLite DB tool execution)"
    echo "  - shell       (Python FastMCP, sandboxed secure terminal command environment)"
    echo "  - filesystem  (NodeJS Official, scoped file/directory management)"
    echo "  - fetch       (NodeJS Official, isolated safe web crawler/fetcher)"
}

cmd_config() {
    local server="${1:-}"
    if [ -z "$server" ]; then
        echo "Error: Please specify which MCP server to configure." >&2
        exit 1
    fi

    if ! is_supported_server "$server"; then
        echo "Error: Unknown MCP server: '$server'." >&2
        exit 1
    fi

    local workspace="/absolute/path/to/your/workspace"
    local extra_args=""

    # Suggest configuration arguments based on the server type
    if [ "$server" = "sqlite" ]; then
        extra_args=', "--", "--db", "/workspace/db.sqlite"'
    elif [ "$server" = "filesystem" ]; then
        extra_args=', "--", "/workspace"'
    fi

    cat <<EOF
Add the following snippet to your 'claude_desktop_config.json' or equivalent AI client configuration:

{
  "mcpServers": {
    "mcp-box-${server}": {
      "command": "${CLI_PATH}",
      "args": [
        "run",
        "${server}",
        "--workspace",
        "${workspace}"${extra_args}
      ]
    }
  }
}
EOF
}

# Main routing
if [ $# -lt 1 ]; then
    usage
    exit 1
fi

COMMAND="$1"
case "$COMMAND" in
    build)
        shift
        cmd_build "$@"
        ;;
    run)
        shift
        cmd_run "$@"
        ;;
    list)
        cmd_list
        ;;
    config)
        shift
        cmd_config "$@"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'" >&2
        usage
        exit 1
        ;;
esac

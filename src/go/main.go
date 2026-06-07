package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

var supportedServers = []string{"sqlite", "shell", "filesystem", "fetch"}

func usage() {
	fmt.Printf(`mcp-box: Turnkey immutable and isolated Linux sandboxes for MCP servers.

Usage:
  %s <command> [arguments]

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
  %s run sqlite --workspace /tmp/test-db -- --db /workspace/test.db
`, filepath.Base(os.Args[0]), filepath.Base(os.Args[0]))
}

func isSupportedServer(server string) bool {
	for _, s := range supportedServers {
		if s == server {
			return true
		}
	}
	return false
}

func checkDocker() error {
	cmd := exec.Command("docker", "info")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Docker daemon is not running or accessible")
	}
	return nil
}

func cmdBuild(server string) error {
	if !isSupportedServer(server) {
		return fmt.Errorf("unknown MCP server: '%s'. Available: %s", server, strings.Join(supportedServers, ", "))
	}

	executablePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get CLI path: %w", err)
	}
	projectDir := filepath.Dir(executablePath)

	fmt.Fprintf(os.Stderr, "Building OCI image for '%s' via Nix and loading into Docker...\n", server)

	// Nix build step to evaluate the stream script
	buildCmd := exec.Command("nix", "build", ".#"+server, "--no-link", "--print-out-paths", "--extra-experimental-features", "nix-command flakes")
	buildCmd.Dir = projectDir
	out, err := buildCmd.Output()
	if err != nil {
		return fmt.Errorf("nix build failed: %w", err)
	}

	scriptPath := strings.TrimSpace(string(out))

	// Execute stream script and pipe to docker load
	runScriptCmd := exec.Command(scriptPath)
	dockerLoadCmd := exec.Command("docker", "load")

	pipe, err := runScriptCmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to open stdout pipe: %w", err)
	}
	dockerLoadCmd.Stdin = pipe
	dockerLoadCmd.Stdout = os.Stdout
	dockerLoadCmd.Stderr = os.Stderr

	if err := runScriptCmd.Start(); err != nil {
		return fmt.Errorf("failed to start stream script: %w", err)
	}
	if err := dockerLoadCmd.Start(); err != nil {
		return fmt.Errorf("failed to start docker load: %w", err)
	}

	if err := runScriptCmd.Wait(); err != nil {
		return fmt.Errorf("stream script failed: %w", err)
	}
	if err := dockerLoadCmd.Wait(); err != nil {
		return fmt.Errorf("docker load failed: %w", err)
	}

	fmt.Fprintf(os.Stderr, "Successfully loaded mcp-box-%s:latest into Docker.\n", server)
	return nil
}

// runConfig holds the parsed result of the `run` subcommand's options.
type runConfig struct {
	workspace  string
	network    string
	envs       []string
	serverArgs []string
}

// defaultNetwork returns the default network mode for a given server.
// Every server is network-isolated by default except `fetch`, whose entire
// purpose is web access.
func defaultNetwork(server string) string {
	if server == "fetch" {
		return "bridge"
	}
	return "none"
}

// parseRunArgs parses the option list passed after `run <server>`. It is kept
// free of side effects (no filesystem/docker access) so it can be unit tested.
// The workspace path is returned verbatim; absolute-path resolution and
// directory creation happen at execution time in cmdRun.
func parseRunArgs(server string, runArgs []string) (runConfig, error) {
	cfg := runConfig{network: defaultNetwork(server)}

	for i := 0; i < len(runArgs); i++ {
		arg := runArgs[i]
		switch arg {
		case "-w", "--workspace":
			if i+1 >= len(runArgs) {
				return runConfig{}, fmt.Errorf("error: workspace requires an argument")
			}
			cfg.workspace = runArgs[i+1]
			i++
		case "-n", "--network":
			if i+1 >= len(runArgs) {
				return runConfig{}, fmt.Errorf("error: network requires an argument")
			}
			cfg.network = runArgs[i+1]
			i++
		case "-e", "--env":
			if i+1 >= len(runArgs) {
				return runConfig{}, fmt.Errorf("error: env requires an argument")
			}
			cfg.envs = append(cfg.envs, runArgs[i+1])
			i++
		case "--":
			cfg.serverArgs = runArgs[i+1:]
			return cfg, nil
		default:
			return runConfig{}, fmt.Errorf("error: unknown run option: %s", arg)
		}
	}

	return cfg, nil
}

func cmdRun(server string, runArgs []string) error {
	if !isSupportedServer(server) {
		return fmt.Errorf("unknown MCP server: '%s'", server)
	}

	if err := checkDocker(); err != nil {
		return err
	}

	imageName := fmt.Sprintf("mcp-box-%s:latest", server)

	// Check if OCI image exists locally
	inspectCmd := exec.Command("docker", "image", "inspect", imageName)
	if err := inspectCmd.Run(); err != nil {
		// command -v is a shell builtin, so we check using standard lookpath
		_, nixErr := exec.LookPath("nix")

		if nixErr == nil {
			fmt.Fprintf(os.Stderr, "Image '%s' not found. Nix detected: Auto-building locally...\n", imageName)
			if err := cmdBuild(server); err != nil {
				return err
			}
		} else {
			registry := "ghcr.io/lowcache"
			registryImage := fmt.Sprintf("%s/%s", registry, imageName)
			fmt.Fprintf(os.Stderr, "Image '%s' not found. Nix not detected: Pulling from registry %s...\n", imageName, registry)

			pullCmd := exec.Command("docker", "pull", registryImage)
			pullCmd.Stdout = os.Stdout
			pullCmd.Stderr = os.Stderr
			if err := pullCmd.Run(); err != nil {
				return fmt.Errorf("failed to pull image from %s", registryImage)
			}

			tagCmd := exec.Command("docker", "tag", registryImage, imageName)
			if err := tagCmd.Run(); err != nil {
				return fmt.Errorf("failed to tag registry image locally")
			}

			// Clean up original registry tag to keep system neat
			cleanupCmd := exec.Command("docker", "rmi", registryImage)
			_ = cleanupCmd.Run()

			fmt.Fprintf(os.Stderr, "Successfully loaded registry image.\n")
		}
	}

	// Parse arguments manually to guarantee double-dash (--) argument piping
	cfg, err := parseRunArgs(server, runArgs)
	if err != nil {
		return err
	}

	// Build Docker execution arguments
	dockerArgs := []string{
		"run", "--rm", "-i",
		"--init",
		"--read-only",
		"--tmpfs", "/tmp:rw,noexec,nosuid,size=64m",
		"--tmpfs", "/run:rw,noexec,nosuid,size=16m",
		"--cap-drop=ALL",
		"--security-opt", "no-new-privileges:true",
		"--user", fmt.Sprintf("%d:%d", os.Getuid(), os.Getgid()),
		"--network", cfg.network,
	}

	if cfg.workspace != "" {
		absPath, err := filepath.Abs(cfg.workspace)
		if err != nil {
			return fmt.Errorf("failed to resolve workspace path: %w", err)
		}
		if err := os.MkdirAll(absPath, 0755); err != nil {
			return fmt.Errorf("failed to create workspace directory: %w", err)
		}
		dockerArgs = append(dockerArgs, "--mount", fmt.Sprintf("type=bind,source=%s,target=/workspace", absPath))
	}

	for _, env := range cfg.envs {
		dockerArgs = append(dockerArgs, "-e", env)
	}

	dockerArgs = append(dockerArgs, imageName)
	dockerArgs = append(dockerArgs, cfg.serverArgs...)

	// Execute Docker sandbox and directly forward all standard input/output streams
	cmd := exec.Command("docker", dockerArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}

func cmdList() {
	fmt.Println("Available sandboxed MCP servers:")
	fmt.Println("  - sqlite      (Python FastMCP, SQLite DB tool execution)")
	fmt.Println("  - shell       (Python FastMCP, sandboxed secure terminal command environment)")
	fmt.Println("  - filesystem  (NodeJS Official, scoped file/directory management)")
	fmt.Println("  - fetch       (NodeJS Official, isolated safe web crawler/fetcher)")
}

func cmdConfig(server string) error {
	if !isSupportedServer(server) {
		return fmt.Errorf("unknown MCP server: '%s'", server)
	}

	executablePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get absolute executable path: %w", err)
	}

	workspaceSuggestion := "/absolute/path/to/your/workspace"
	args := []string{"run", server, "--workspace", workspaceSuggestion}

	// Extra suggestions based on server types
	if server == "sqlite" {
		args = append(args, "--", "--db", "/workspace/db.sqlite")
	} else if server == "filesystem" {
		args = append(args, "--", "/workspace")
	}

	type mcpServerConfig struct {
		Command string   `json:"command"`
		Args    []string `json:"args"`
	}

	type clientConfig struct {
		McpServers map[string]mcpServerConfig `json:"mcpServers"`
	}

	cfg := clientConfig{
		McpServers: map[string]mcpServerConfig{
			"mcp-box-" + server: {
				Command: executablePath,
				Args:    args,
			},
		},
	}

	bytes, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}

	fmt.Println("Add the following snippet to your 'claude_desktop_config.json' or equivalent AI client configuration:")
	fmt.Println()
	fmt.Println(string(bytes))
	return nil
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "build":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "Error: Please specify which MCP server to build.")
			os.Exit(1)
		}
		if err := cmdBuild(os.Args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "run":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "Error: Please specify which MCP server to run.")
			os.Exit(1)
		}
		if err := cmdRun(os.Args[2], os.Args[3:]); err != nil {
			// Forward correct exit code from docker process if possible
			if exitErr, ok := err.(*exec.ExitError); ok {
				os.Exit(exitErr.ExitCode())
			}
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "list":
		cmdList()
	case "config":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "Error: Please specify which MCP server to configure.")
			os.Exit(1)
		}
		if err := cmdConfig(os.Args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "Error: Unknown command '%s'\n", command)
		usage()
		os.Exit(1)
	}
}

package main

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestIsSupportedServer(t *testing.T) {
	for _, s := range supportedServers {
		if !isSupportedServer(s) {
			t.Errorf("isSupportedServer(%q) = false, want true", s)
		}
	}
	for _, s := range []string{"", "postgres", "Shell", "sqlite ", "unknown"} {
		if isSupportedServer(s) {
			t.Errorf("isSupportedServer(%q) = true, want false", s)
		}
	}
}

func TestDefaultNetwork(t *testing.T) {
	if got := defaultNetwork("fetch"); got != "bridge" {
		t.Errorf("defaultNetwork(fetch) = %q, want bridge", got)
	}
	for _, s := range []string{"sqlite", "shell", "filesystem"} {
		if got := defaultNetwork(s); got != "none" {
			t.Errorf("defaultNetwork(%q) = %q, want none", s, got)
		}
	}
}

func TestParseRunArgs(t *testing.T) {
	tests := []struct {
		name    string
		server  string
		args    []string
		want    runConfig
		wantErr bool
	}{
		{
			name:   "defaults: isolated server gets no network",
			server: "sqlite",
			args:   nil,
			want:   runConfig{network: "none"},
		},
		{
			name:   "fetch defaults to bridge network",
			server: "fetch",
			args:   nil,
			want:   runConfig{network: "bridge"},
		},
		{
			name:   "workspace long flag",
			server: "sqlite",
			args:   []string{"--workspace", "/tmp/db"},
			want:   runConfig{workspace: "/tmp/db", network: "none"},
		},
		{
			name:   "workspace short flag",
			server: "sqlite",
			args:   []string{"-w", "/tmp/db"},
			want:   runConfig{workspace: "/tmp/db", network: "none"},
		},
		{
			name:   "explicit network overrides default",
			server: "fetch",
			args:   []string{"--network", "none"},
			want:   runConfig{network: "none"},
		},
		{
			name:   "multiple env vars accumulate",
			server: "shell",
			args:   []string{"-e", "FOO=1", "--env", "BAR=2"},
			want:   runConfig{network: "none", envs: []string{"FOO=1", "BAR=2"}},
		},
		{
			name:   "double-dash forwards remaining args verbatim",
			server: "sqlite",
			args:   []string{"-w", "/tmp/db", "--", "--db", "/workspace/test.db"},
			want:   runConfig{workspace: "/tmp/db", network: "none", serverArgs: []string{"--db", "/workspace/test.db"}},
		},
		{
			name:   "flags after double-dash are not interpreted as options",
			server: "shell",
			args:   []string{"--", "--network", "bridge", "-w", "x"},
			want:   runConfig{network: "none", serverArgs: []string{"--network", "bridge", "-w", "x"}},
		},
		{
			name:    "unknown option errors",
			server:  "sqlite",
			args:    []string{"--bogus"},
			wantErr: true,
		},
		{
			name:    "workspace without value errors",
			server:  "sqlite",
			args:    []string{"--workspace"},
			wantErr: true,
		},
		{
			name:    "network without value errors",
			server:  "sqlite",
			args:    []string{"-n"},
			wantErr: true,
		},
		{
			name:    "env without value errors",
			server:  "sqlite",
			args:    []string{"-e"},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseRunArgs(tt.server, tt.args)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("parseRunArgs(%q, %v) = %+v, want error", tt.server, tt.args, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseRunArgs(%q, %v) unexpected error: %v", tt.server, tt.args, err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseRunArgs(%q, %v) = %+v, want %+v", tt.server, tt.args, got, tt.want)
			}
		})
	}
}

// TestConfigJSONShape verifies the structure cmdConfig emits stays compatible
// with what Claude Desktop / OpenClaw expect: a top-level "mcpServers" map
// keyed by "mcp-box-<server>" with "command" and "args".
func TestConfigJSONShape(t *testing.T) {
	type mcpServerConfig struct {
		Command string   `json:"command"`
		Args    []string `json:"args"`
	}
	type clientConfig struct {
		McpServers map[string]mcpServerConfig `json:"mcpServers"`
	}

	cfg := clientConfig{
		McpServers: map[string]mcpServerConfig{
			"mcp-box-sqlite": {
				Command: "/usr/local/bin/mcp-box",
				Args:    []string{"run", "sqlite", "--workspace", "/ws"},
			},
		},
	}

	out, err := json.Marshal(cfg)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}

	var round map[string]map[string]struct {
		Command string   `json:"command"`
		Args    []string `json:"args"`
	}
	if err := json.Unmarshal(out, &round); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}

	srv, ok := round["mcpServers"]["mcp-box-sqlite"]
	if !ok {
		t.Fatalf("expected key mcpServers.mcp-box-sqlite in %s", out)
	}
	if srv.Command == "" {
		t.Errorf("command must not be empty: %s", out)
	}
	if len(srv.Args) == 0 || srv.Args[0] != "run" {
		t.Errorf("args must start with \"run\": %s", out)
	}
}

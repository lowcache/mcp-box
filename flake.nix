{
  description = "mcp-box: Turnkey immutable Linux container sandboxes for MCP servers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Helper package to wrap the SQLite MCP script
        sqlite-server-pkg = pkgs.stdenv.mkDerivation {
          name = "mcp-server-sqlite-pkg";
          src = ./src/sqlite;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/app
            cp server.py $out/app/server.py
          '';
        };

        # Helper package to wrap the Shell MCP script
        shell-server-pkg = pkgs.stdenv.mkDerivation {
          name = "mcp-server-shell-pkg";
          src = ./src/shell;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/app
            cp server.py $out/app/server.py
          '';
        };

        # Define OCI Streamed Layered Images
        images = {
          sqlite = pkgs.dockerTools.streamLayeredImage {
            name = "mcp-box-sqlite";
            tag = "latest";
            contents = [
              (pkgs.python3.withPackages (ps: [ ps.fastmcp ]))
              pkgs.sqlite
              pkgs.bash
              pkgs.coreutils
              sqlite-server-pkg
            ];
            config = {
              Cmd = [ "python3" "/app/server.py" ];
              Env = [
                "PATH=${pkgs.lib.makeBinPath [
                  (pkgs.python3.withPackages (ps: [ ps.fastmcp ]))
                  pkgs.sqlite
                  pkgs.bash
                  pkgs.coreutils
                ]}"
                "SQLITE_DB_PATH=/workspace/db.sqlite"
              ];
              WorkingDir = "/workspace";
            };
          };

          shell = pkgs.dockerTools.streamLayeredImage {
            name = "mcp-box-shell";
            tag = "latest";
            contents = [
              (pkgs.python3.withPackages (ps: [ ps.fastmcp ]))
              pkgs.bashInteractive
              pkgs.coreutils
              pkgs.ripgrep
              pkgs.fd
              pkgs.git
              pkgs.curl
              pkgs.jq
              pkgs.sqlite
              pkgs.gnutar
              pkgs.gzip
              pkgs.cacert
              shell-server-pkg
            ];
            config = {
              Cmd = [ "python3" "/app/server.py" ];
              Env = [
                "PATH=${pkgs.lib.makeBinPath [
                  (pkgs.python3.withPackages (ps: [ ps.fastmcp ]))
                  pkgs.bashInteractive
                  pkgs.coreutils
                  pkgs.ripgrep
                  pkgs.fd
                  pkgs.git
                  pkgs.curl
                  pkgs.jq
                  pkgs.sqlite
                  pkgs.gnutar
                  pkgs.gzip
                ]}"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              WorkingDir = "/workspace";
            };
          };

          filesystem = pkgs.dockerTools.streamLayeredImage {
            name = "mcp-box-filesystem";
            tag = "latest";
            contents = [
              pkgs.mcp-server-filesystem
              pkgs.ripgrep
              pkgs.fd
              pkgs.git
              pkgs.bash
              pkgs.coreutils
            ];
            config = {
              Cmd = [ "mcp-server-filesystem" "/workspace" ];
              Env = [
                "PATH=${pkgs.lib.makeBinPath [
                  pkgs.mcp-server-filesystem
                  pkgs.ripgrep
                  pkgs.fd
                  pkgs.git
                  pkgs.bash
                  pkgs.coreutils
                ]}"
              ];
              WorkingDir = "/workspace";
            };
          };

          fetch = pkgs.dockerTools.streamLayeredImage {
            name = "mcp-box-fetch";
            tag = "latest";
            contents = [
              pkgs.mcp-server-fetch
              pkgs.bash
              pkgs.coreutils
              pkgs.curl
              pkgs.cacert
            ];
            config = {
              Cmd = [ "mcp-server-fetch" ];
              Env = [
                "PATH=${pkgs.lib.makeBinPath [
                  pkgs.mcp-server-fetch
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.curl
                ]}"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              WorkingDir = "/workspace";
            };
          };
        };

        # CLI Wrapper Script Package
        mcp-box-cli = pkgs.writeShellApplication {
          name = "mcp-box";
          runtimeInputs = [ pkgs.bash pkgs.docker pkgs.git ];
          text = builtins.readFile ./mcp-box;
        };

      in
      {
        inherit images;
        packages = {
          default = mcp-box-cli;
          mcp-box = mcp-box-cli;
        } // images;
      }
    );
}

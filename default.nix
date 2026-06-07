# A traditional Nix fallback for non-flake or legacy nix-build invocations.
{ pkgs ? import <nixpkgs> {} }:

pkgs.writeShellApplication {
  name = "mcp-box";
  runtimeInputs = [ pkgs.bash pkgs.docker pkgs.git ];
  text = builtins.readFile ./mcp-box;
}

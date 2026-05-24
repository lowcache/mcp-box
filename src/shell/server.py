from mcp.server.fastmcp import FastMCP
import subprocess
import os

mcp = FastMCP("shell-sandbox")

@mcp.tool()
def run_command(command: str) -> str:
    """Execute a bash shell command inside the isolated container sandbox and return stdout/stderr."""
    # Ensure commands run inside the mounted workspace directory if it exists, or /tmp
    cwd = "/workspace" if os.path.exists("/workspace") else "/tmp"
    
    try:
        res = subprocess.run(
            ["/bin/bash", "-c", command],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=cwd
        )
        out = ""
        if res.stdout:
            out += f"STDOUT:\n{res.stdout}\n"
        if res.stderr:
            out += f"STDERR:\n{res.stderr}\n"
        if not res.stdout and not res.stderr:
            out += "Command produced no output.\n"
        out += f"Exit Code: {res.returncode}"
        return out
    except subprocess.TimeoutExpired:
        return "Error: Command execution timed out after 60 seconds."
    except Exception as e:
        return f"Error executing command: {e}"

if __name__ == "__main__":
    mcp.run()

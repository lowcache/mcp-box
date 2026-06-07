import sys
import sqlite3
import os
from mcp.server.fastmcp import FastMCP

DB_PATH = os.getenv("SQLITE_DB_PATH", "/workspace/db.sqlite")

mcp = FastMCP("sqlite-sandbox")

def get_connection():
    db_dir = os.path.dirname(DB_PATH)
    if db_dir and not os.path.exists(db_dir):
        try:
            os.makedirs(db_dir, exist_ok=True)
        except Exception:
            pass
    return sqlite3.connect(DB_PATH)

@mcp.tool()
def read_query(sql: str) -> str:
    """Execute a read-only SELECT query on the SQLite database and return results as formatted text."""
    sql_stripped = sql.strip().upper()
    if not sql_stripped.startswith("SELECT") and not sql_stripped.startswith("WITH") and not sql_stripped.startswith("PRAGMA"):
        return "Error: read_query only allows SELECT, WITH, or PRAGMA statements. Use write_query for modifications."
    
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql)
            columns = [col[0] for col in cursor.description] if cursor.description else []
            rows = cursor.fetchall()
            if not rows:
                return "Query executed successfully. 0 rows returned."
            
            # Format as a simple readable table
            header = " | ".join(columns)
            sep = "-+-".join(["-" * len(c) for c in columns])
            body = "\n".join(" | ".join(str(val) for val in row) for row in rows)
            return f"{header}\n{sep}\n{body}"
    except Exception as e:
        return f"Error executing read query: {e}"

@mcp.tool()
def write_query(sql: str) -> str:
    """Execute a modifying query (INSERT, UPDATE, DELETE, CREATE, DROP) on the SQLite database."""
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql)
            conn.commit()
            changes = conn.total_changes
            return f"Query executed successfully. Total changes: {changes} rows modified."
    except Exception as e:
        return f"Error executing write query: {e}"

@mcp.tool()
def list_tables() -> str:
    """List all tables available in the database schema."""
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
            tables = [row[0] for row in cursor.fetchall()]
            if not tables:
                return "No tables found in the database."
            return "Tables:\n" + "\n".join(f"- {t}" for t in tables)
    except Exception as e:
        return f"Error listing tables: {e}"

@mcp.tool()
def describe_table(table_name: str) -> str:
    """Describe the schema (columns, types, nullability, defaults) for a specific table."""
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"PRAGMA table_info({table_name});")
            rows = cursor.fetchall()
            if not rows:
                return f"Table '{table_name}' does not exist or has no columns."
            header = "Column | Type | NotNull | Default | PK"
            sep = "-------+------+---------+---------+---"
            body = []
            for row in rows:
                body.append(f"{row[1]} | {row[2]} | {'Yes' if row[3] else 'No'} | {row[4] or 'NULL'} | {'Yes' if row[5] else 'No'}")
            return f"Schema for table '{table_name}':\n\n{header}\n{sep}\n" + "\n".join(body)
    except Exception as e:
        return f"Error describing table: {e}"

if __name__ == "__main__":
    mcp.run()

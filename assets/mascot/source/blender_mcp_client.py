"""Send a Python script to the running Blender MCP extension (localhost only)."""
import json
import socket
import sys
from pathlib import Path

def execute(code):
    with socket.create_connection(("127.0.0.1", 9876), timeout=15) as connection:
        connection.settimeout(180)
        connection.sendall(json.dumps({"type": "execute", "code": code, "strict_json": True}).encode() + b"\0")
        response = bytearray()
        while b"\0" not in response:
            chunk = connection.recv(65536)
            if not chunk:
                raise RuntimeError("Blender closed the connection before responding")
            response.extend(chunk)
    result = json.loads(response.split(b"\0", 1)[0])
    print(json.dumps(result, indent=2))
    if result.get("status") == "error":
        raise SystemExit(1)
    return result

if __name__ == "__main__":
    if len(sys.argv) > 1:
        script = Path(sys.argv[1]).resolve()
        execute('__file__ = ' + repr(str(script)) + '\n' + script.read_text(encoding='utf-8'))
    else:
        execute(sys.stdin.read())

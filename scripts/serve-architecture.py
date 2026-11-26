#!/usr/bin/env python3
"""Serve docs/architecture on the LAN: scripts/serve-architecture.py [port] (default 8765)."""
import functools
import http.server
import socket
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "docs" / "architecture"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


def lan_ip() -> str:
    # Picks the outbound interface; a UDP connect sends no packets.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(ROOT))
with http.server.ThreadingHTTPServer(("0.0.0.0", PORT), handler) as httpd:
    print(f"Serving {ROOT} on http://{lan_ip()}:{PORT}/ (Ctrl-C to stop)", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass

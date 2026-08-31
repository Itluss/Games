"""Sert web/ en local avec les en-têtes COOP/COEP requises par Godot,
sans mise en cache.

Usage : python outils/serve_web.py [port] [dossier]
Défauts : port 8060, dossier "web".
"""

import functools
import http.server
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
directory = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


handler = functools.partial(Handler, directory=directory)
with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
    print(f"Serving {directory} on http://127.0.0.1:{port}", flush=True)
    httpd.serve_forever()

#!/usr/bin/env python3
"""Serve the repo for the WebGL harness and accept its uploads.

  python3 tests/build_harness.py [--save-gallery]
  python3 tests/serve.py [port]          then open http://127.0.0.1:8765/build/harness.html

POST /results          -> build/webgl-results.json
POST /save?path=gallery/NAME.png   (body: PNG data URL) -> writes the gallery image
"""

from __future__ import annotations

import base64
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, fmt, *args):
        if "POST" in (args[0] if args else ""):
            sys.stderr.write("%s\n" % (fmt % args))

    def do_POST(self):
        url = urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if url.path == "/results":
            target = ROOT / "build" / "webgl-results.json"
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(body)
        elif url.path == "/save":
            rel = parse_qs(url.query).get("path", [""])[0]
            target = (ROOT / rel).resolve()
            if not (target.parent == (ROOT / "gallery").resolve() and target.suffix == ".png"):
                self.send_error(400, "only gallery/*.png")
                return
            payload = body.decode("ascii").split(",", 1)[-1]
            target.write_bytes(base64.b64decode(payload))
        else:
            self.send_error(404)
            return
        self.send_response(204)
        self.end_headers()


def serve(port: int = 8765) -> ThreadingHTTPServer:
    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"serving {ROOT} at http://127.0.0.1:{port}/build/harness.html")
    serve(port).serve_forever()

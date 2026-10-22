#!/usr/bin/env python3
"""Small test web app. /work burns CPU, /health is cheap."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/work":
            data = b"x"
            for _ in range(20000):
                data = hashlib.sha256(data).digest()
            body = data.hex().encode()
        else:
            body = b"ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
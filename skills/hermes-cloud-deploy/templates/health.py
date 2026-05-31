#!/usr/bin/env python3
"""Minimal HTTP health check server for Railway platform.

Railway requires an HTTP 200 response from a health check endpoint
before routing traffic to a new deployment.
Place this at docker/health.py in your repo.

Default port: 8080 (Railway ignores PORT for volume-mounted services
when healthcheckPath is "/" — the health.py listens on 8080 separately
from the main app ports).
"""
import os
import http.server
import socketserver


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass  # Suppress request logs to keep Railway logs clean


if __name__ == "__main__":
    PORT = int(os.environ.get("HEALTH_PORT", "8080"))
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        httpd.serve_forever()

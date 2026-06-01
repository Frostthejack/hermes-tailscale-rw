#!/usr/bin/env python3
"""Minimal HTTP health check server. Uses $PORT if set, otherwise 8080."""
import http.server
import socketserver
import os

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, *args):
        pass

port = int(os.environ.get("PORT", 8080))
with socketserver.TCPServer(("0.0.0.0", port), Handler) as httpd:
    print(f"Health check listening on port {port}")
    httpd.serve_forever()

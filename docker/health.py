#!/usr/bin/env python3
"""Minimal HTTP health check server on port 8080."""
import http.server
import socketserver

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, *args):
        pass

with socketserver.TCPServer(("0.0.0.0", 8080), Handler) as httpd:
    httpd.serve_forever()

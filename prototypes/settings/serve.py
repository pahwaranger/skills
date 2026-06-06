#!/usr/bin/env python3
# THROWAWAY — tiny static server for the Steve Settings prototype.
# Serves this directory. Port from $PORT (preview) or 8755.
import os, http.server, socketserver

os.chdir(os.path.dirname(os.path.abspath(__file__)))
PORT = int(os.environ.get("PORT", "8755"))

Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"serving Steve Settings prototype on :{PORT}")
    httpd.serve_forever()

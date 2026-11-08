#!/usr/bin/env python3
"""Serve windows/web/ the way the .scr host does (fonts/ from Resources/Fonts), for any browser.

    python3 -I windows/tools/serve.py [port]      # default 8766
    open "http://127.0.0.1:8766/index.html?style=chorus&flipIn=3"
"""

import functools
import http.server
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
WEB = ROOT / "windows" / "web"
FONTS = ROOT / "Resources" / "Fonts"


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if clean.startswith("/fonts/"):
            name = pathlib.PurePosixPath(clean).name
            return str(FONTS / name)
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
    handler = functools.partial(Handler, directory=str(WEB))
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print(f"Serving {WEB} on http://127.0.0.1:{port}/index.html")
        httpd.serve_forever()

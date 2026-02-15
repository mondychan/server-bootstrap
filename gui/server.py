#!/usr/bin/env python3
import argparse
import json
import pathlib
import subprocess
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAIN_SH = ROOT / "main.sh"
STATIC_DIR = ROOT / "gui" / "static"


def run_main(args):
    cmd = ["bash", str(MAIN_SH), *args]
    proc = subprocess.run(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout


class Handler(BaseHTTPRequestHandler):
    server_version = "ServerBootstrapGUI/0.2"

    def _send_json(self, payload, code=HTTPStatus.OK):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path):
        data = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ["/", "/index.html"]:
            self._send_file(STATIC_DIR / "index.html")
            return

        if self.path == "/api/health":
            self._send_json({"ok": True})
            return

        if self.path == "/api/modules":
            rc, out = run_main(["--list-json"])
            if rc != 0:
                self._send_json({"ok": False, "error": out, "exit_code": rc}, HTTPStatus.BAD_REQUEST)
                return
            self._send_json({"ok": True, "modules": json.loads(out)})
            return

        if self.path == "/api/profiles":
            rc, out = run_main(["--list-profiles-json"])
            if rc != 0:
                self._send_json({"ok": False, "error": out, "exit_code": rc}, HTTPStatus.BAD_REQUEST)
                return
            self._send_json({"ok": True, "profiles": json.loads(out)})
            return

        self._send_json({"ok": False, "error": "Not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self):
        if self.path != "/api/run":
            self._send_json({"ok": False, "error": "Not found"}, HTTPStatus.NOT_FOUND)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length <= 0:
            self._send_json({"ok": False, "error": "Empty body"}, HTTPStatus.BAD_REQUEST)
            return

        body = self.rfile.read(content_length)
        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json({"ok": False, "error": "Invalid JSON"}, HTTPStatus.BAD_REQUEST)
            return

        action = payload.get("action", "plan")
        if action not in {"plan", "apply", "verify"}:
            self._send_json({"ok": False, "error": "Invalid action"}, HTTPStatus.BAD_REQUEST)
            return

        modules = payload.get("modules", [])
        if not isinstance(modules, list):
            self._send_json({"ok": False, "error": "modules must be a list"}, HTTPStatus.BAD_REQUEST)
            return

        profile = payload.get("profile", "")
        if profile is None:
            profile = ""

        cmd_args = [f"--{action}", "--no-interactive"]
        if profile:
            cmd_args.extend(["--profile", profile])
        if modules:
            cmd_args.extend(["--modules", ",".join(modules)])

        rc, out = run_main(cmd_args)
        self._send_json(
            {
                "ok": rc == 0,
                "exit_code": rc,
                "command": " ".join(["./main.sh", *cmd_args]),
                "output": out,
            }
        )


def main():
    parser = argparse.ArgumentParser(description="Local web GUI for server-bootstrap")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8089)
    args = parser.parse_args()

    if not MAIN_SH.exists():
        raise SystemExit(f"main.sh not found at {MAIN_SH}")

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Server Bootstrap GUI: http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

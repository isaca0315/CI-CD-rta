"""hookcat: sustituto local de webhook.site.

Guarda las ultimas peticiones y las muestra en http://localhost:8888
GET  /__requests  -> JSON con lo capturado
GET  /__clear     -> borra el historial
Cualquier otro path/metodo -> se registra y responde 200
"""
import html
import json
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8888
MAX = 300
REQS = []
LOCK = threading.Lock()
COUNTER = [0]


class Handler(BaseHTTPRequestHandler):
    server_version = "hookcat/1.0"

    def log_message(self, fmt, *args):
        print("[hookcat] " + fmt % args, flush=True)

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        raw = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _capture(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        with LOCK:
            COUNTER[0] += 1
            item = {
                "id": COUNTER[0],
                "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "method": self.command,
                "path": self.path,
                "headers": dict(self.headers),
                "body": body[:20000],
            }
            REQS.insert(0, item)
            del REQS[MAX:]
        print(f"[hookcat] {item['method']} {item['path']} -> {body[:300]}", flush=True)
        self._send(200, json.dumps({"ok": True, "id": item["id"]}), "application/json")

    def do_GET(self):
        if self.path.startswith("/__requests"):
            with LOCK:
                return self._send(200, json.dumps(REQS, indent=2), "application/json")
        if self.path.startswith("/__clear"):
            with LOCK:
                REQS.clear()
            return self._send(200, "cleared")
        if self.path == "/":
            return self._send(200, self._index())
        return self._capture()

    def do_POST(self):
        return self._capture()

    do_PUT = do_POST
    do_PATCH = do_POST
    do_DELETE = do_POST

    def _index(self):
        with LOCK:
            items = list(REQS)
        rows = []
        for i in items:
            rows.append(
                "<tr><td>{id}</td><td>{time}</td><td>{method}</td><td><code>{path}</code></td>"
                "<td><pre>{body}</pre></td></tr>".format(
                    id=i["id"],
                    time=html.escape(i["time"]),
                    method=html.escape(i["method"]),
                    path=html.escape(i["path"]),
                    body=html.escape(i["body"]) or "<em>(vacio)</em>",
                )
            )
        return (
            "<html><head><title>hookcat</title><style>"
            "body{font-family:monospace;margin:20px;background:#111;color:#ddd}"
            "table{border-collapse:collapse;width:100%}td,th{border:1px solid #333;padding:6px;vertical-align:top}"
            "pre{margin:0;white-space:pre-wrap;max-width:70ch;color:#7ee787}"
            "code{color:#79c0ff}a{color:#ffa657}"
            "</style></head><body><h1>hookcat</h1>"
            f"<p>{len(items)} peticiones | <a href='/__requests'>JSON</a> | <a href='/__clear'>limpiar</a></p>"
            "<table><tr><th>#</th><th>hora (UTC)</th><th>metodo</th><th>path</th><th>body</th></tr>"
            + "".join(rows)
            + "</table></body></html>"
        )


if __name__ == "__main__":
    print(f"[hookcat] listening on 0.0.0.0:{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

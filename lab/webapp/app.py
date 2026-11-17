"""App victima del lab.

- /update?host=...  ejecuta ping con shell=True  -> command injection intencionada
- /flag.txt         no se sirve; el flag esta en /flag.txt del contenedor
- IMDS falso        169.254.169.254 (lo levanta entrypoint.sh en este mismo netns)
"""
import subprocess

from flask import Flask, request

app = Flask(__name__)

FLAG = open("/flag.txt").read().strip() if __import__("os").path.exists("/flag.txt") else "no-flag"

PAGE = """<!doctype html>
<html><head><title>NetOps Console</title>
<style>
body{{font-family:system-ui;margin:3rem;max-width:52rem}}
input{{padding:.4rem;width:22rem}} pre{{background:#111;color:#7ee787;padding:1rem;overflow:auto}}
</style></head><body>
<h1>NetOps Console</h1>
<p>Comprueba conectividad contra un host.</p>
<form action="/update" method="get">
  <input name="host" value="127.0.0.1" placeholder="host o IP">
  <button>Ping</button>
</form>
<p><a href="/health">health</a></p>
</body></html>"""


@app.get("/")
def index():
    return PAGE


@app.get("/update")
def update():
    host = request.args.get("host", "127.0.0.1")
    # VULNERABLE A PROPOSITO: shell=True con entrada del usuario
    out = subprocess.run(
        f"ping -c 1 -W 1 {host}",
        shell=True,
        capture_output=True,
        text=True,
    )
    body = out.stdout + out.stderr
    return f"<html><body><h3>Resultado</h3><pre>{body}</pre><a href='/'>volver</a></body></html>"


@app.get("/health")
def health():
    return {"ok": True}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)

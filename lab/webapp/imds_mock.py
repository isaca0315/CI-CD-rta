"""IMDS falso, solo visible dentro del netns del contenedor webapp.

Reproduce los endpoints de metadata de AWS, GCP y Azure para que el RCE del
lab pueda exfiltrar credenciales sin tocar ninguna nube real.
"""
import base64
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def b64url(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


AWS_CREDS = {
    "Code": "Success",
    "LastUpdated": "2026-01-01T00:00:00Z",
    "Type": "AWS-HMAC",
    "AccessKeyId": "ASIAFAKELABACCESS",
    "SecretAccessKey": "fake-secret-key-for-moto",
    "Token": "fake-session-token",
    "Expiration": "2030-01-01T00:00:00Z",
}

AZURE_TOKEN = ".".join(
    [
        b64url({"alg": "none", "typ": "JWT"}),
        b64url(
            {
                "aud": "https://management.azure.com/",
                "tid": "11111111-1111-1111-1111-111111111111",
                "oid": "22222222-2222-2222-2222-222222222222",
                "sub": "lab-managed-identity",
                "appid": "33333333-3333-3333-3333-333333333333",
                "exp": 1900000000,
                "flag": "FLAG{cloud_identity_token}",
            }
        ),
        "",
    ]
)

GCP_TOKEN = {
    "access_token": "ya29.FAKE-GCP-TOKEN-FOR-LOCAL-LAB",
    "expires_in": 3599,
    "token_type": "Bearer",
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[imds] " + fmt % args, flush=True)

    def _json(self, obj):
        raw = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        p = self.path
        if p.startswith("/latest/meta-data/iam/security-credentials/"):
            role = p.rsplit("/", 1)[-1]
            if role:
                return self._json(AWS_CREDS)
            return self._json("lab-role")
        if p.startswith("/computeMetadata/v1/instance/service-accounts"):
            return self._json(GCP_TOKEN)
        if p.startswith("/azure/token"):
            return self._json(
                {"access_token": AZURE_TOKEN, "expires_on": "1900000000", "resource": "https://management.azure.com/"}
            )
        self.send_response(404)
        self.end_headers()


if __name__ == "__main__":
    print("[imds] listening on 169.254.169.254:80", flush=True)
    ThreadingHTTPServer(("169.254.169.254", 80), Handler).serve_forever()

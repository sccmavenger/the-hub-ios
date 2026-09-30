#!/usr/bin/env python3
"""App Store Connect API client.

Talks to Apple's REST API directly using an App Store Connect API key, so
metadata can be read and written without a browser and without 2FA prompts.
Fastlane would be the usual tool, but Homebrew installs aren't available in
this environment; this needs only PyJWT + cryptography (installed with
pip --user).

Credentials — put these in .secrets/ (gitignored), next to the repo root:
  .secrets/asc-key.p8        the private key downloaded from App Store Connect
  .secrets/asc-key-id        the Key ID   (e.g. 2X9R4HXF34)
  .secrets/asc-issuer-id     the Issuer ID (a UUID, shown above the key list)

Generate the key at: App Store Connect → Users and Access → Integrations →
App Store Connect API → + . Role "App Manager" is enough for metadata; use
"Admin" if you also want to manage users. The .p8 downloads exactly once.

Usage:
  scripts/asc.py apps                       list your apps
  scripts/asc.py versions <appId>           list versions for an app
  scripts/asc.py get <path>                 raw GET (path after /v1/)
  scripts/asc.py patch <path> <json>        raw PATCH
  scripts/asc.py post <path> <json>         raw POST
"""
import json
import sys
import time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

import jwt

ROOT = Path(__file__).resolve().parent.parent
SECRETS = ROOT / ".secrets"
BASE = "https://api.appstoreconnect.apple.com/v1"


def _read(name: str) -> str:
    f = SECRETS / name
    if not f.exists():
        sys.exit(
            f"Missing {f}.\n"
            "See the docstring in scripts/asc.py for how to create an "
            "App Store Connect API key."
        )
    return f.read_text().strip()


def token() -> str:
    """ES256 JWT, 20 min expiry (Apple's maximum)."""
    key_id, issuer_id = _read("asc-key-id"), _read("asc-issuer-id")
    private_key = (SECRETS / "asc-key.p8").read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(method: str, path: str, body=None):
    url = path if path.startswith("http") else f"{BASE}/{path.lstrip('/')}"
    data = json.dumps(body).encode() if body is not None else None
    req = Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {"status": r.status}
    except HTTPError as e:
        detail = e.read().decode()
        try:
            detail = json.dumps(json.loads(detail), indent=2)
        except Exception:
            pass
        sys.exit(f"HTTP {e.code} {method} {url}\n{detail}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]

    if cmd == "apps":
        for a in call("GET", "apps?limit=200").get("data", []):
            at = a["attributes"]
            print(f'{a["id"]}  {at.get("bundleId"):45s} {at.get("name")}')
    elif cmd == "versions":
        app_id = sys.argv[2]
        for v in call("GET", f"apps/{app_id}/appStoreVersions?limit=50").get("data", []):
            at = v["attributes"]
            print(f'{v["id"]}  {at.get("versionString"):10s} {at.get("appStoreState")}  {at.get("platform")}')
    elif cmd == "get":
        print(json.dumps(call("GET", sys.argv[2]), indent=2))
    elif cmd in ("patch", "post"):
        print(json.dumps(call(cmd.upper(), sys.argv[2], json.loads(sys.argv[3])), indent=2))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

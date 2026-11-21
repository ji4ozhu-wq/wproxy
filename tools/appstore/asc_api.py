"""Minimal App Store Connect API client (ES256 JWT via openssl, stdlib HTTP)."""
import base64
import json
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ISSUER = "e44a5e2f-0499-4cce-b422-01bafe9a37d3"
KEY_ID = "KRDS76CZMJ"
KEY_PATH = "/Users/zhang/.appstoreconnect/private_keys/AuthKey_KRDS76CZMJ.p8"
BASE = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    assert der[0] == 0x30
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    def read_int(pos):
        assert der[pos] == 0x02
        ln = der[pos + 1]
        val = der[pos + 2:pos + 2 + ln]
        return pos + 2 + ln, int.from_bytes(val, "big")
    pos, r = read_int(idx)
    pos, s = read_int(pos)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def token() -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def request(method, path, body=None, raw=False):
    url = path if path.startswith("http") else BASE + path
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read()
            return response.status, (payload if raw else json.loads(payload or b"{}"))
    except urllib.error.HTTPError as error:
        payload = error.read()
        try:
            parsed = json.loads(payload)
        except Exception:
            parsed = payload.decode(errors="replace")
        return error.code, parsed


if __name__ == "__main__":
    status, apps = request("GET", "/apps?filter[bundleId]=com.juejin.ios.wuji")
    print("apps", status)
    print(json.dumps(apps, indent=2)[:2000])

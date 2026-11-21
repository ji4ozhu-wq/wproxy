#!/usr/bin/env python3
"""Generate / edit images via gpt-image-2 for the Wuji project.

Reads credentials from Public/docs/image-gen-env.txt at runtime; never hardcode keys.
Usage:
  python3 gen_image.py --prompt "..." --out out.png [--size 1024x1792] [--quality low|medium|high] [--n 1]
  python3 gen_image.py --prompt "..." --out out.png --edit a.png [--edit b.png]
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # app_src/<name>/tools -> workspace root
CONFIG = ROOT / "Public" / "docs" / "image-gen-env.txt"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")


def read_config():
    cfg = {}
    for line in CONFIG.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
    for key in ("base_url", "api_key", "image-model"):
        if not cfg.get(key):
            sys.exit(f"missing {key} in {CONFIG}")
    return cfg


def request(url, headers, data=None, method="POST", timeout=600):
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()[:2000].decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {e.code} {e.reason}: {body}")


def generate(cfg, prompt, out, size, quality, n=1):
    url = cfg["base_url"].rstrip("/") + "/images/generations"
    payload = {"model": cfg["image-model"], "prompt": prompt, "size": size, "quality": quality, "n": n}
    headers = {
        "Authorization": "Bearer " + cfg["api_key"],
        "Content-Type": "application/json",
        "User-Agent": UA,
        "Accept": "application/json",
    }
    body = json.dumps(payload).encode()
    last_err = None
    for attempt in range(3):
        try:
            raw = request(url, headers, body)
            return save_images(raw, out, n)
        except RuntimeError as e:
            last_err = e
            print(f"  attempt {attempt + 1} failed: {e}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise last_err


def edit(cfg, prompt, out, images, size, quality, n=1):
    url = cfg["base_url"].rstrip("/") + "/images/edits"
    fields = {
        "model": cfg["image-model"],
        "prompt": prompt,
        "size": size,
        "quality": quality,
        "n": str(n),
    }
    parts, boundary = [], "----WujiBoundary" + base64.urlsafe_b64encode(os.urandom(9)).decode()
    for k, v in fields.items():
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    for p in images:
        p = Path(p)
        alias = k = "image" if len(images) == 1 else "image[]"
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{alias}\"; filename=\"{p.name}\"\r\n"
            f"Content-Type: image/png\r\n\r\n".encode() + p.read_bytes() + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    headers = {
        "Authorization": "Bearer " + cfg["api_key"],
        "Content-Type": "multipart/form-data; boundary=" + boundary,
        "User-Agent": UA,
        "Accept": "application/json",
    }
    last_err = None
    for attempt in range(3):
        try:
            raw = request(url, headers, body)
            return save_images(raw, out, n)
        except RuntimeError as e:
            last_err = e
            print(f"  attempt {attempt + 1} failed: {e}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise last_err


def save_images(raw, out, n):
    try:
        data = json.loads(raw.decode("utf-8", "replace"))
    except Exception:
        raise RuntimeError("response is not JSON: " + raw[:500].decode("utf-8", "replace"))
    items = data.get("data") or []
    if not items:
        raise RuntimeError("empty data: " + json.dumps(data)[:800])
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    saved = []
    for i, item in enumerate(items[:n]):
        suffix = out.suffix or ".png"
        fp = out if i == 0 else out.with_name(out.stem + f"-{i + 1}" + suffix)
        if item.get("b64_json"):
            fp.write_bytes(base64.b64decode(item["b64_json"]))
        elif item.get("url"):
            fp.write_bytes(request(item["url"], {"User-Agent": UA}, method="GET"))
        else:
            raise RuntimeError("item has neither b64_json nor url")
        saved.append(str(fp))
        print(saved[-1])
    return saved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", default="1024x1792")
    ap.add_argument("--quality", default="medium")
    ap.add_argument("--n", type=int, default=1)
    ap.add_argument("--edit", action="append", default=[])
    args = ap.parse_args()
    cfg = read_config()
    if args.edit:
        edit(cfg, args.prompt, args.out, args.edit, args.size, args.quality, args.n)
    else:
        generate(cfg, args.prompt, args.out, args.size, args.quality, args.n)


if __name__ == "__main__":
    main()

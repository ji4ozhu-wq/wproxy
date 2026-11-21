#!/usr/bin/env python3
"""Prepares the GeoIP assets bundled with Wuji from the v2fly/geoip release data.

Why this script exists
----------------------
Country-based routing in Wuji no longer expands every CIDR into the Xray routing
configuration (that would be ~26 MB of JSON for the full DB-IP-derived dataset).
Instead the app ships the raw v2ray `geoip.dat` (gzipped) and asks Xray to match
`ext:<asset>.dat:<cc>` rule targets at runtime, so Xray only loads the countries
the user actually selected. This script downloads the upstream database, verifies
it and produces the two small files that go into `Wuji/Resources/`:

  * geoip.dat.gz          the complete v2ray GeoIPList protobuf, gzip-compressed
                          (~23.8 MB → ~4.4 MB) so the app bundle stays compact;
                          the app decompresses it into the App Group container on
                          first launch.
  * geoip_countries.json  list metadata: for every published list entry its
                          `country_code` and CIDR count (~6 KB), used by the
                          country picker and by the integrity check below.

Data source
-----------
https://github.com/v2fly/geoip, branch `release`, rebuilt monthly. The release
branch publishes `geoip.dat` (v2ray GeoIPList protobuf), `geoip.dat.sha256sum`
and the same data as `text/<cc>.txt` (offline fallback).

Geolocation provenance (verified against the repo's build.yml + config.json):
the release build converts the free **DB-IP Lite country** MMDB
(https://db-ip.com, CC BY 4.0) plus the `private` and `test` lists into the v2ray
format. The v2fly/geoip compilation is CC BY-SA 4.0. Older descriptions of the
repository mentioned MaxMind GeoLite2; the current pipeline does not use it, so
the attribution in docs/licenses-geoip.md and the About screen must credit DB-IP.

Protobuf format decoded below (v2ray GeoIPList)
-----------------------------------------------
    message GeoIPList { repeated GeoIP entry = 1; }
    message GeoIP {
      string country_code = 1;   // "CN", "PRIVATE", "TEST", "ZZ"
      repeated CIDR cidr = 2;
    }
    message CIDR {
      bytes ip = 1;              // 4 bytes IPv4 / 16 bytes IPv6, network order
      uint32 prefix = 2;         // 0...32 / 0...128
    }

Every field is `varint tag = (field_number << 3) | wire_type`, where wire type
0 = varint and 2 = length-delimited. The metadata scan below therefore does not
need to decode CIDRs: it skips field 2 payloads by their length and only counts
them, which keeps this script fast.

Usage
-----
  python3 tools/prepare_geoip_assets.py                  # download, verify, generate
  python3 tools/prepare_geoip_assets.py --from-dir DIR   # offline: DIR/geoip.dat
                                                         # (or DIR/text/<cc>.txt)
  python3 tools/prepare_geoip_assets.py --check          # validate checked-in assets

Proxy: downloads use curl, which honours the standard HTTPS_PROXY / ALL_PROXY
environment variables (e.g. export HTTPS_PROXY=socks5h://host:port on the dev
machine). The proxy is never written into the generated assets.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES_DEFAULT = ROOT / "Wuji" / "Resources"
DATASET_NAME = "geoip.dat.gz"
METADATA_NAME = "geoip_countries.json"

# v2fly/geoip release branch. jsDelivr first: it is reachable from more networks
# than raw.githubusercontent.com and serves the same git content for the tag.
DAT_URLS = (
    "https://cdn.jsdelivr.net/gh/v2fly/geoip@release/geoip.dat",
    "https://raw.githubusercontent.com/v2fly/geoip/release/geoip.dat",
)
SHA256SUFFIX = ".sha256sum"

SOURCE_TEXT = (
    "v2fly/geoip release branch (https://github.com/v2fly/geoip), rebuilt monthly; "
    "geolocation data by DB-IP Lite (https://db-ip.com)"
)
LICENSE_TEXT = (
    "CC BY-SA 4.0 (v2fly/geoip compilation); underlying DB-IP Lite data CC BY 4.0"
)

# Lists that are not ISO 3166-1 countries: `test` is a synthetic prefix used by
# probe-resistance tests, `private` is RFC1918/ULA (the app adds it when LAN
# bypass is on) and `zz` is v2fly's "unknown" bucket. They stay in the metadata
# (and in geoip.dat) but are not offered in the country picker.
NON_COUNTRY_LISTS = frozenset({"TEST", "PRIVATE", "ZZ"})
COUNTRY_CODE_RE = re.compile(r"^[A-Z]{2}$")
REQUIRED_CODES = ("CN", "JP", "US", "DE", "GB", "SG", "HK", "TW", "KR")
MIN_COUNTRIES = 240
MAX_DATASET_BYTES = 6 * 1024 * 1024    # gzipped geoip.dat budget
MAX_METADATA_BYTES = 64 * 1024        # metadata is a few KB


# --------------------------------------------------------------------------- #
# Networking
# --------------------------------------------------------------------------- #
def http_get(url: str, timeout: int = 180) -> bytes:
    """GET a URL.

    curl is preferred because it supports SOCKS proxies through the standard proxy
    environment variables (the dev machine reaches GitHub only through a socks5h
    proxy). urllib is the fallback when curl is unavailable.
    """
    curl = shutil.which("curl")
    if curl:
        proc = subprocess.run(
            [curl, "-fsSL", "--retry", "3", "--connect-timeout", "20", "--max-time", str(timeout), url],
            capture_output=True,
        )
        if proc.returncode == 0:
            return proc.stdout
        raise RuntimeError(f"curl failed for {url}: {proc.stderr.decode('utf-8', 'replace').strip()}")
    request = urllib.request.Request(url, headers={"User-Agent": "wuji-prepare-geoip-assets/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - fixed https URLs
        return response.read()


def parse_sha256sum(raw: bytes) -> str:
    """Extracts the checksum from a `sha256sum` file (`<hex>  geoip.dat`)."""
    tokens = raw.decode("utf-8", "replace").strip().split()
    if not tokens or not re.fullmatch(r"[0-9a-fA-F]{64}", tokens[0]):
        raise ValueError("malformed sha256sum file")
    return tokens[0].lower()


def download_dataset() -> tuple[bytes, str, str]:
    """Downloads geoip.dat + checksum from the first mirror that verifies."""
    errors: list[str] = []
    for url in DAT_URLS:
        checksum_url = url + SHA256SUFFIX
        try:
            payload = http_get(url, timeout=600)
        except Exception as error:  # noqa: BLE001 - try the next mirror
            errors.append(f"{url}: {error}")
            continue
        digest = hashlib.sha256(payload).hexdigest()
        try:
            expected = parse_sha256sum(http_get(checksum_url, timeout=120))
        except Exception as error:  # noqa: BLE001 - checksum unavailable: try next mirror
            errors.append(f"{checksum_url}: {error}")
            continue
        if digest != expected:
            errors.append(f"{url}: checksum mismatch (got {digest}, expected {expected})")
            continue
        return payload, digest, url
    raise SystemExit("could not download a verified geoip.dat:\n  - " + "\n  - ".join(errors))


# --------------------------------------------------------------------------- #
# Protobuf helpers (encoding is only needed for the offline text fallback)
# --------------------------------------------------------------------------- #
class ProtoError(ValueError):
    """Raised when the payload is not a decodable v2ray GeoIPList."""


def encode_varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def encode_length_delimited(field: int, payload: bytes) -> bytes:
    return encode_varint((field << 3) | 2) + encode_varint(len(payload)) + payload


def encode_varint_field(field: int, value: int) -> bytes:
    return encode_varint(field << 3) + encode_varint(value)


def read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    result = 0
    shift = 0
    size = len(buf)
    while True:
        if pos >= size:
            raise ProtoError("unexpected end of buffer while reading varint")
        byte = buf[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, pos
        shift += 7
        if shift > 63:
            raise ProtoError("varint longer than 10 bytes")


def skip_field(buf: bytes, pos: int, wire_type: int) -> int:
    if wire_type == 0:
        _, pos = read_varint(buf, pos)
        return pos
    if wire_type == 2:
        length, pos = read_varint(buf, pos)
        if length > len(buf) - pos:
            raise ProtoError("length-delimited field overruns the buffer")
        return pos + length
    if wire_type == 5:
        if len(buf) - pos < 4:
            raise ProtoError("fixed32 field is truncated")
        return pos + 4
    if wire_type == 1:
        if len(buf) - pos < 8:
            raise ProtoError("fixed64 field is truncated")
        return pos + 8
    raise ProtoError(f"unsupported wire type {wire_type}")


def scan_metadata(dat: bytes) -> dict[str, int]:
    """Returns {country_code: cidr_count} without decoding individual CIDRs.

    Top level: field 1 is a GeoIP entry (length-delimited). Inside an entry,
    field 1 is the country code and each field 2 is one CIDR — counting those
    field numbers is enough for the metadata.
    """
    counts: dict[str, int] = {}
    pos = 0
    entries = 0
    while pos < len(dat):
        tag, pos = read_varint(dat, pos)
        field, wire_type = tag >> 3, tag & 0x07
        if field != 1 or wire_type != 2:
            pos = skip_field(dat, pos, wire_type)
            continue
        length, pos = read_varint(dat, pos)
        end = pos + length
        if length > len(dat) - pos:
            raise ProtoError("GeoIP entry overruns the buffer")
        code: str | None = None
        cidr_count = 0
        entry_pos = pos
        while entry_pos < end:
            entry_tag, entry_pos = read_varint(dat, entry_pos)
            entry_field, entry_wire = entry_tag >> 3, entry_tag & 0x07
            if entry_field == 1 and entry_wire == 2:
                code_length, entry_pos = read_varint(dat, entry_pos)
                entry_code = dat[entry_pos:entry_pos + code_length].decode("utf-8", "replace")
                entry_pos += code_length
                if entry_pos > end:
                    raise ProtoError("GeoIP entry code overruns the entry")
                code = entry_code.strip().upper()
            elif entry_field == 2 and entry_wire == 2:
                cidr_count += 1
                entry_pos = skip_field(dat, entry_pos, entry_wire)
            else:
                entry_pos = skip_field(dat, entry_pos, entry_wire)
        if code is None:
            raise ProtoError("GeoIP entry has no country code")
        counts[code] = counts.get(code, 0) + cidr_count
        entries += 1
        pos = end
    if entries == 0:
        raise ProtoError("geoip.dat contains no entries")
    return counts


def encode_dat_from_text(text_root: Path) -> bytes:
    """Builds a GeoIPList protobuf from `text/<cc>.txt` files (offline fallback)."""
    files = sorted(text_root.glob("*.txt"))
    if not files:
        raise SystemExit(f"{text_root}: no text/*.txt files found")
    output = bytearray()
    for path in files:
        code = path.stem.upper()
        entry = bytearray(encode_length_delimited(1, code.encode("utf-8")))
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            address, _, prefix_text = line.partition("/")
            prefix = int(prefix_text) if prefix_text else (32 if ":" not in address else 128)
            ip = _parse_ip(address)
            cidr = encode_length_delimited(1, ip) + encode_varint_field(2, prefix)
            entry += encode_length_delimited(2, cidr)
        output += encode_length_delimited(1, bytes(entry))
    return bytes(output)


def _parse_ip(address: str) -> bytes:
    if ":" in address:
        import ipaddress
        return ipaddress.IPv6Address(address).packed
    import ipaddress
    return ipaddress.IPv4Address(address).packed


# --------------------------------------------------------------------------- #
# Build / write assets
# --------------------------------------------------------------------------- #
def build_metadata(dat: bytes, sha256: str, generated: str) -> dict:
    counts = scan_metadata(dat)
    country_codes = sorted(code for code in counts if COUNTRY_CODE_RE.fullmatch(code)
                           and code not in NON_COUNTRY_LISTS)
    for pseudo in NON_COUNTRY_LISTS:
        if pseudo not in counts:
            raise SystemExit(f"geoip.dat is missing the {pseudo} list")
    countries = {code: counts[code] for code in country_codes}
    for pseudo in sorted(NON_COUNTRY_LISTS):
        countries[pseudo] = counts[pseudo]
    return {
        "version": 1,
        "source": SOURCE_TEXT,
        "license": LICENSE_TEXT,
        "dataVersion": sha256[:12],
        "sha256": sha256,
        "generated": generated,
        "countryCount": len(country_codes),
        "entryCount": len(counts),
        "countries": countries,
    }


def write_assets(dat: bytes, metadata: dict, resources: Path) -> tuple[int, int]:
    resources.mkdir(parents=True, exist_ok=True)
    compressed = gzip.compress(dat, 9, mtime=0)  # deterministic bytes
    dataset_path = resources / DATASET_NAME
    dataset_path.write_bytes(compressed)
    metadata_path = resources / METADATA_NAME
    metadata_path.write_bytes(
        json.dumps(metadata, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    return len(compressed), metadata_path.stat().st_size


def validate_assets(resources: Path) -> tuple[dict, bytes]:
    """Checks the checked-in assets against the contract the app relies on."""
    dataset_path = resources / DATASET_NAME
    metadata_path = resources / METADATA_NAME
    if not dataset_path.is_file() or not metadata_path.is_file():
        raise SystemExit(f"missing assets: {dataset_path} / {metadata_path}")
    problems: list[str] = []

    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    compressed = dataset_path.read_bytes()
    if compressed[:2] != b"\x1f\x8b":
        raise SystemExit(f"{dataset_path} is not gzip")
    try:
        dat = gzip.decompress(compressed)
    except OSError as error:
        raise SystemExit(f"{dataset_path} is not a valid gzip file: {error}") from error

    digest = hashlib.sha256(dat).hexdigest()
    if metadata.get("sha256") != digest:
        problems.append("metadata sha256 does not match the decompressed geoip.dat")
    if metadata.get("dataVersion") != digest[:12]:
        problems.append("metadata dataVersion is not the sha256 prefix")
    if len(compressed) > MAX_DATASET_BYTES:
        problems.append(f"{dataset_path} is {len(compressed)} bytes (budget {MAX_DATASET_BYTES})")
    if metadata_path.stat().st_size > MAX_METADATA_BYTES:
        problems.append(f"{metadata_path} is unexpectedly large")

    countries = metadata.get("countries", {})
    real = {code: count for code, count in countries.items()
            if COUNTRY_CODE_RE.fullmatch(code) and code not in NON_COUNTRY_LISTS}
    if len(real) < MIN_COUNTRIES:
        problems.append(f"only {len(real)} countries in metadata (need >= {MIN_COUNTRIES})")
    for code in REQUIRED_CODES:
        if real.get(code, 0) <= 0:
            problems.append(f"required country {code} is missing or empty")
    for pseudo in NON_COUNTRY_LISTS:
        if countries.get(pseudo, 0) <= 0:
            problems.append(f"required list {pseudo} is missing or empty")

    scanned = scan_metadata(dat)
    expected = dict(countries)
    if scanned != expected:
        problems.append("metadata country counts do not match the re-scanned geoip.dat")

    if problems:
        raise SystemExit("GeoIP asset validation failed:\n  - " + "\n  - ".join(problems))
    return metadata, dat


def summarize(metadata: dict, dataset_bytes: int, metadata_bytes: int, resources: Path) -> None:
    countries = metadata["countries"]
    real = [code for code in countries if COUNTRY_CODE_RE.fullmatch(code) and code not in NON_COUNTRY_LISTS]
    print(f"wrote {resources / DATASET_NAME} ({dataset_bytes / 1024 / 1024:.2f} MB gz)")
    print(f"wrote {resources / METADATA_NAME} ({metadata_bytes} bytes)")
    print(f"  entries: {len(countries)}  countries: {len(real)}  "
          f"CIDRs: {sum(countries.values())}")
    print(f"  sha256: {metadata['sha256']}  dataVersion: {metadata['dataVersion']}  "
          f"generated: {metadata['generated']}")
    for code in REQUIRED_CODES:
        print(f"  {code}: {countries.get(code, 0)} CIDRs")
    print(f"  PRIVATE: {countries.get('PRIVATE', 0)} CIDRs")


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #
def load_dataset(args: argparse.Namespace) -> tuple[bytes, str, str]:
    if args.from_dir:
        directory: Path = args.from_dir
        dat_path = directory / "geoip.dat"
        if dat_path.is_file():
            dat = dat_path.read_bytes()
            digest = hashlib.sha256(dat).hexdigest()
            checksum_path = directory / "geoip.dat.sha256sum"
            if checksum_path.is_file():
                expected = parse_sha256sum(checksum_path.read_bytes())
                if expected != digest:
                    raise SystemExit(f"{checksum_path}: checksum does not match {dat_path}")
            print(f"reading {dat_path} ({len(dat)} bytes)")
            return dat, digest, str(dat_path)
        text_root = directory / "text" if (directory / "text").is_dir() else directory
        print(f"building a GeoIPList from {text_root} (offline text fallback)")
        dat = encode_dat_from_text(text_root)
        return dat, hashlib.sha256(dat).hexdigest(), f"text directory {text_root}"
    dat, digest, url = download_dataset()
    print(f"downloaded {url} ({len(dat)} bytes, sha256 {digest})")
    return dat, digest, url


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare Wuji's bundled GeoIP assets from v2fly/geoip")
    parser.add_argument("--resources-dir", type=Path, default=RESOURCES_DEFAULT,
                        help="output directory (default Wuji/Resources)")
    parser.add_argument("--from-dir", type=Path,
                        help="offline directory containing geoip.dat (optionally geoip.dat.sha256sum) "
                             "or a text/<cc>.txt tree")
    parser.add_argument("--check", action="store_true", help="validate the checked-in assets only")
    parser.add_argument("--generated", default=_dt.date.today().isoformat(),
                        help="provenance date override")
    args = parser.parse_args()

    if os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy") \
            or os.environ.get("ALL_PROXY") or os.environ.get("all_proxy"):
        print("using proxy from environment for downloads")

    if args.check:
        metadata, _ = validate_assets(args.resources_dir)
        summarize(metadata,
                  (args.resources_dir / DATASET_NAME).stat().st_size,
                  (args.resources_dir / METADATA_NAME).stat().st_size,
                  args.resources_dir)
        print("validation passed")
        return

    dat, digest, provenance = load_dataset(args)
    metadata = build_metadata(dat, digest, args.generated)
    dataset_bytes, metadata_bytes = write_assets(dat, metadata, args.resources_dir)
    print(f"source: {provenance}")
    summarize(metadata, dataset_bytes, metadata_bytes, args.resources_dir)


if __name__ == "__main__":
    main()

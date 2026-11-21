#!/usr/bin/env python3
"""Extracts selected entries from a v2ray geoip.dat (GeoIPList protobuf).

Usage: extract_geoip_asset.py <geoip.dat|geoip.dat.gz> <out.dat> <code> [code...]

Writes a GeoIPList containing only the requested list codes, copying each entry's
original protobuf bytes verbatim (same technique the app's GeoIPAssetManager uses).
"""
import gzip
import sys

WIRE_VARINT, WIRE_64BIT, WIRE_LEN, WIRE_32BIT = 0, 1, 2, 5


def read_varint(data, i):
    shift = 0
    value = 0
    while True:
        if i >= len(data):
            raise ValueError("truncated varint")
        byte = data[i]
        i += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, i
        shift += 7


def read_len_field(data, i):
    length, i = read_varint(data, i)
    start = i
    end = i + length
    if end > len(data):
        raise ValueError("truncated length-delimited field")
    return start, end


def iter_entries(data):
    i = 0
    while i < len(data):
        tag, i = read_varint(data, i)
        field, wire = tag >> 3, tag & 0x7
        if field == 1 and wire == WIRE_LEN:  # GeoIPList.entry
            start, end = read_len_field(data, i)
            yield start, end
            i = end
        elif wire == WIRE_VARINT:
            _, i = read_varint(data, i)
        elif wire == WIRE_LEN:
            _, end = read_len_field(data, i)
            i = end
        elif wire == WIRE_64BIT:
            i += 8
        elif wire == WIRE_32BIT:
            i += 4
        else:
            raise ValueError(f"unsupported wire type {wire}")


def entry_code(data, start, end):
    i = start
    while i < end:
        tag, i = read_varint(data, i)
        field, wire = tag >> 3, tag & 0x7
        if field == 1 and wire == WIRE_LEN:
            s, e = read_len_field(data, i)
            return data[s:e].decode("utf-8", "replace")
        if wire == WIRE_VARINT:
            _, i = read_varint(data, i)
        elif wire == WIRE_LEN:
            _, i = read_len_field(data, i)
        elif wire == WIRE_64BIT:
            i += 8
        elif wire == WIRE_32BIT:
            i += 4
        else:
            raise ValueError(f"unsupported wire type {wire} in entry")
    return ""


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    source, output = sys.argv[1], sys.argv[2]
    wanted = {code.lower() for code in sys.argv[3:]}

    raw = open(source, "rb").read()
    data = gzip.decompress(raw) if source.endswith(".gz") else raw

    entries = []
    found = set()
    for start, end in iter_entries(data):
        code = entry_code(data, start, end)
        if code.lower() in wanted:
            payload = data[start:end]
            entries.append(payload)
            found.add(code.lower())

    missing = wanted - found
    if missing:
        raise SystemExit(f"missing list codes in source: {sorted(missing)}")

    body = bytearray()
    for payload in entries:
        body += bytes([0x0A])  # field 1, wire 2
        length = len(payload)
        while True:  # varint length
            chunk = length & 0x7F
            length >>= 7
            body += bytes([chunk | (0x80 if length else 0)])
            if not length:
                break
        body += payload
    with open(output, "wb") as handle:
        handle.write(body)
    print(f"wrote {output} ({len(body)} bytes, {len(entries)} entries: {sorted(found)})")


if __name__ == "__main__":
    sys.exit(main())

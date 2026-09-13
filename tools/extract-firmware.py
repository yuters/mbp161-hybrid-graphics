#!/usr/bin/env python3
"""Extract the verified Falcon payload locally; never installs firmware.

Usage: extract-firmware.py SystemKernelExtensions.kc navi14_smc.bin OUTPUT
The second input is the decompressed, hash-identified Linux container. Its
power table is preserved to keep Linux's existing table-selection behavior.
Unknown Apple payloads or Linux templates are rejected rather than guessed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

PAYLOAD_SHA = 'db06582c2dc1a3bf625e910b9f4ebae9ff4b880737407f6bca6a4d0b8bc45281'
TEMPLATE_SHA = 'ffffaa9068ff481b653dc129abb13b7723a3d3d480b81685e90d0bf84751ea7a'
SIZE = 0x40200
VERSION = 0x04350b03


def sha(b):
    return hashlib.sha256(b).hexdigest()


def package(collection, template):
    if collection[:4] != bytes.fromhex('cffaedfe'):
        raise ValueError('Expected an uncompressed 64-bit little-endian Mach-O collection')
    if sha(template) != TEMPLATE_SHA:
        raise ValueError('Unknown Linux firmware template; audit its container/table first')
    matches = []
    pos = 0
    while True:
        pos = collection.find(b'$PS1', pos)
        if pos < 0:
            break
        start = pos - 16
        if start >= 0 and sha(collection[start:start + SIZE]) == PAYLOAD_SHA:
            matches.append(start)
        pos += 4
    if not matches:
        raise ValueError('Verified Apple Falcon 53.11.3 payload not found')
    payload = collection[matches[0]:matches[0] + SIZE]
    if struct.unpack_from('>I', payload, 0x60)[0] != VERSION:
        raise ValueError('Signed payload version differs')
    result = bytearray(template)
    offset = struct.unpack_from('<I', result, 24)[0]
    if struct.unpack_from('<I', result, 20)[0] != SIZE:
        raise ValueError('Template payload size differs')
    result[offset:offset + SIZE] = payload
    struct.pack_into('<I', result, 16, VERSION)
    struct.pack_into('<I', result, 28, zlib.crc32(payload))
    return bytes(result), matches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('collection', type=Path)
    parser.add_argument('template', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    collection, template = args.collection.read_bytes(), args.template.read_bytes()
    result, matches = package(collection, template)
    with args.output.open('xb') as f:
        f.write(result)
    report = dict(collection_sha256=sha(collection), template_sha256=sha(template),
                  payload_sha256=PAYLOAD_SHA, matching_offsets=[hex(x) for x in matches],
                  firmware_sha256=sha(result), version=hex(VERSION),
                  payload_size=SIZE, crc32=hex(zlib.crc32(result[256:256 + SIZE])),
                  linux_soft_pptable_preserved=True)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Wrap a Nano 20K .fs stream for the SD core loader (never writes hardware)."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

HEADER_BYTES = 512
SLOT_ADDRESS = SLOT_BYTES = 0x100000


def read_fs(path):
    data = bytearray()
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('//'):
            continue
        if len(line) % 8 or not re.fullmatch('[01]+', line):
            raise ValueError(f'Invalid .fs data on line {number}')
        data.extend(int(line, 2).to_bytes(len(line)//8, 'big'))
    return bytes(data)


def package(payload, core_id, title, base=False, autostart=False):
    if not 128 <= len(payload) <= SLOT_BYTES:
        raise ValueError('Core must fit the 1 MiB slot')
    if payload[:32] != bytes([255])*22 + bytes.fromhex('a5c3060000000000081b'):
        raise ValueError('Expected an uncompressed GW2A-18C bitstream')
    address, next_address = (0, SLOT_ADDRESS) if base else (SLOT_ADDRESS, 0)
    if payload[52:60] != bytes.fromhex('d200ffff') + struct.pack('>I', next_address):
        raise ValueError(f'Pack the core with --multiboot_address {next_address:#x}')
    if not re.fullmatch('[a-z0-9_-]{1,31}', core_id):
        raise ValueError('ID must contain 1–31 lowercase letters, digits, - or _')
    if not 1 <= len(title) <= 63 or any(not 32 <= ord(c) <= 126 for c in title):
        raise ValueError('Title must contain 1–63 printable ASCII characters')
    header = bytearray(HEADER_BYTES)
    struct.pack_into('>8s6I', header, 0, b'N20KCORE', 2 if autostart else 1, 0x20180001,
                     len(payload), zlib.crc32(payload), next_address, address)
    header[32:32+len(core_id)] = core_id.encode('ascii')
    header[64:64+len(title)] = title.encode('ascii')
    if autostart:struct.pack_into('>I', header, 128, 1)
    struct.pack_into('>I', header, 508, zlib.crc32(header[:508]))
    return bytes(header) + payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bitstream', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--id', required=True)
    parser.add_argument('--title', required=True)
    parser.add_argument('--base', action='store_true', help='Mega Drive boot core at flash address 0')
    parser.add_argument('--autostart', action='store_true', help='Core firmware supports persistent menu-return requests')
    args = parser.parse_args()
    payload = read_fs(args.bitstream)
    result = package(payload, args.id, args.title, args.base, args.autostart)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(result)
    report = dict(core_id=args.id, title=args.title, bytes=len(result),
                  sha256=hashlib.sha256(result).hexdigest(),
                  payload_sha256=hashlib.sha256(payload).hexdigest(),
                  flash_address=0 if args.base else SLOT_ADDRESS,
                  next_address=SLOT_ADDRESS if args.base else 0)
    args.output.with_suffix('.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

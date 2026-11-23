#!/usr/bin/env python3
import argparse
import hashlib
import os
import struct
import sys


def refuse(msg):
    print(f"[make_patch] refused: {msg}")
    sys.exit(1)


def read_manifest(patch_dir):
    with open(os.path.join(patch_dir, "manifest")) as f:
        return dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)


def read_changes(path):
    with open(path) as f:
        for line in f:
            offset, old, new, label = line.rstrip("\n").split("\t")
            yield int(offset, 16), int(old, 16), int(new, 16), label


def main():
    ap = argparse.ArgumentParser(description="rebuild the patched executable from the change table")
    ap.add_argument("--patch-dir", default=os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "patches", "megaton-1.4.9-linux"))
    ap.add_argument("original")
    ap.add_argument("out")
    args = ap.parse_args()
    manifest = read_manifest(args.patch_dir)
    with open(args.original, "rb") as f:
        data = bytearray(f.read())
    if hashlib.sha256(data).hexdigest() != manifest["ORIGINAL_SHA256"]:
        refuse(f"unknown original {args.original}")
    count = 0
    for offset, old, new, label in read_changes(os.path.join(args.patch_dir, manifest["CHANGES"])):
        have = struct.unpack_from("<I", data, offset)[0]
        if have != old:
            refuse(f"offset {offset:#010x} {label} holds {have:#010x}, expected {old:#010x}")
        struct.pack_into("<I", data, offset, new)
        count += 1
    got = hashlib.sha256(data).hexdigest()
    if got != manifest["PATCHED_SHA256"]:
        refuse(f"result sha256 {got} does not match {manifest['PATCHED_SHA256']}")
    with open(args.out, "wb") as f:
        f.write(data)
    os.chmod(args.out, os.stat(args.original).st_mode & 0o7777)
    print(f"[make_patch] ok changes={count} sha256={got}")


if __name__ == "__main__":
    main()

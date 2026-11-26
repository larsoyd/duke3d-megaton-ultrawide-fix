#!/usr/bin/env python3
import os
import re
import struct
import sys
import time

BASE = 0x400000
OLD = {"radarang2": (0x005EE0D8, 5120), "bakumost": (0x0071E9C0, 5120), "bakdmost": (0x00710B48, 5120),
       "uwall": (0x0063CA30, 5120), "dwall": (0x00723E68, 5120), "swplc": (0x005F34F8, 10240),
       "lplc": (0x007038B8, 10240), "swall": (0x005F8930, 10240), "lwall": (0x005F6100, 10256),
       "umost": (0x01EE5C40, 5120), "dplc": (0x01C92B20, 5120), "dmost": (0x01E8C020, 5120),
       "startumost": (0x01E99780, 5120), "uplc": (0x01E84B80, 5120), "startdmost": (0x01ED5040, 5120)}
SCALARS = {"windowx1": 0x01DD2624, "windowy1": 0x01C93F2C, "windowx2": 0x01C911E0, "windowy2": 0x01C93F50,
           "xdimen": 0x005B0564, "ydimen": 0x01CCFD5C, "xdim": 0x01E8E744, "ydim": 0x01D67DC4}
NEIGHBOURS = {"sdl_window": 0x01EE7040, "globalposz": 0x01C93F20, "halfxdimen": 0x01ED6440,
              "visibility": 0x01ED6444, "validmodecnt": 0x01E8E420}
PUSH_CLOUD = 0x005341D0
MAXX = 8192
PATTERN = 0xA5


def log(msg):
    print("[integrity] " + msg, flush=True)


def find_game(marker):
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() != "duke3d.exe":
                    continue
            with open(f"/proc/{pid}/environ", "rb") as f:
                if marker.encode() in f.read():
                    return int(pid)
        except OSError:
            continue
    return None


def image_base(pid):
    with open(f"/proc/{pid}/maps") as f:
        starts = [int(line.split("-")[0], 16) for line in f if line.rstrip().endswith("duke3d.exe")]
    return min(starts) if starts else None


def new_bases(changes):
    bases = {}
    with open(changes) as f:
        for line in f:
            _, _, new, label = line.split()
            m = re.match(r"(\w+)\+(-?\d+)$", label)
            if m:
                bases[m.group(1)] = int(new, 16) - int(m.group(2))
    return bases


def regions(changes):
    out = [(n + ".old", a, s) for n, (a, s) in OLD.items()]
    for n, base in new_bases(changes).items():
        size = (OLD[n][1] // 2560) * MAXX + (16 if n == "lwall" else 0)
        out.append((n + ".guard", base + size, 64))
    return out


class Mem:
    def __init__(self, pid, delta):
        self.f = open(f"/proc/{pid}/mem", "r+b", buffering=0)
        self.delta = delta

    def read(self, va, size):
        self.f.seek(va + self.delta)
        return self.f.read(size)

    def write(self, va, data):
        self.f.seek(va + self.delta)
        self.f.write(data)

    def word(self, va):
        return struct.unpack("<i", self.read(va, 4))[0]


def guards(mem, mode, changes):
    bad = 0
    for name, addr, size in regions(changes):
        if mode == "fill":
            mem.write(addr, bytes([PATTERN]) * size)
            continue
        changed = sum(1 for b in mem.read(addr, size) if b != PATTERN)
        if changed:
            bad += 1
            log(f"guard=fail region={name} addr={addr:#x} changed_bytes={changed}")
    log(f"guard={mode} regions={len(regions(changes))} bad={bad}")


def view(mem):
    s = {k: mem.word(a) for k, a in SCALARS.items()}
    n = {k: mem.word(a) for k, a in NEIGHBOURS.items()}
    ok = (s["xdimen"] == s["windowx2"] - s["windowx1"] + 1 and s["ydimen"] == s["windowy2"] - s["windowy1"] + 1
          and s["ydimen"] > 0)
    log("view " + " ".join(f"{k}={v}" for k, v in s.items()) + f" ok={ok}")
    log("neighbours " + " ".join(f"{k}={v:#x}" for k, v in n.items()))


def main():
    mode, marker = sys.argv[1], sys.argv[2]
    pid = None
    for _ in range(int(os.environ.get("PROBE_WAIT", "1")) * 10):
        pid = find_game(marker)
        if pid:
            break
        time.sleep(0.1)
    if not pid:
        log("refused: game process not found")
        return 1
    base = image_base(pid)
    if base is None:
        log(f"refused: no duke3d.exe mapping in pid={pid}")
        return 1
    if mode == "pid":
        log(f"pid={pid} base={base:#x}")
        return 0
    mem = Mem(pid, base - BASE)
    if mode in ("fill", "check"):
        guards(mem, mode, os.environ["PROBE_CHANGES"])
    elif mode == "view":
        view(mem)
    elif mode == "nocloud":
        mem.write(PUSH_CLOUD, b"\xc3")
        log(f"cloud upload disabled at {PUSH_CLOUD:#x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

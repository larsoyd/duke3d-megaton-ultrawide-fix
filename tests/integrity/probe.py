import json
import os
import re

import gdb

OLD = {"radarang2": (0x083A76A0, 5120), "bakumost": (0x08481560, 5120), "bakdmost": (0x08482960, 5120),
       "uwall": (0x08483D60, 5120), "dwall": (0x08485160, 5120), "swplc": (0x08486560, 10240),
       "lplc": (0x08488D60, 10240), "swall": (0x0848B560, 10240), "lwall": (0x0848DD60, 10256),
       "umost": (0x093C28E0, 5120), "dplc": (0x0950C220, 5120), "dmost": (0x0950D620, 5120),
       "startumost": (0x09511F20, 5120), "uplc": (0x09564D80, 5120), "startdmost": (0x095DD140, 5120)}
SCALARS = {"windowx1": 0x0947EC88, "windowy1": 0x0947EC80, "windowx2": 0x093C9D04, "windowy2": 0x09531174,
           "xdimen": 0x08355A48, "ydimen": 0x093C3CE4, "xdim": 0x09511F00, "ydim": 0x0959C638}
NEIGHBOURS = {"parallaxyscale": 0x093C3CE0, "globalxpanning": 0x095DE540, "totalclocklock": 0x0950EA20,
              "globalzd": 0x09513320}
DRAWROOMS = 0x081261D8
MAXX = 8192
PATTERN = 0xA5


def new_bases(changes):
    bases = {}
    with open(changes) as f:
        for line in f:
            _, old, new, label = line.split()
            m = re.match(r"(\w+)\+(\d+)$", label)
            if m:
                bases[m.group(1)] = int(new, 16) - int(m.group(2))
    return bases


def regions(changes):
    out = [(n + ".old", a, s) for n, (a, s) in OLD.items()]
    for n, base in new_bases(changes).items():
        size = (OLD[n][1] // 2560) * MAXX + (16 if n == "lwall" else 0)
        out.append((n + ".guard", base + size, 64))
    return out


def word(addr):
    return int(gdb.parse_and_eval("*(int*)%#x" % addr))


def guards(mode, changes):
    inf = gdb.selected_inferior()
    bad = 0
    for name, addr, size in regions(changes):
        if mode == "fill":
            inf.write_memory(addr, bytes([PATTERN]) * size)
            continue
        changed = sum(1 for b in bytes(inf.read_memory(addr, size)) if b != PATTERN)
        if changed:
            bad += 1
            print(f"[integrity] guard=fail region={name} addr={addr:#x} changed_bytes={changed}")
    print(f"[integrity] guard={mode} regions={len(regions(changes))} bad={bad}")


def view():
    gdb.execute("break *%#x" % DRAWROOMS, to_string=True)
    gdb.execute("continue", to_string=True)
    s = {k: word(a) for k, a in SCALARS.items()}
    n = {k: word(a) for k, a in NEIGHBOURS.items()}
    gdb.execute("delete", to_string=True)
    ok = s["xdimen"] == s["windowx2"] - s["windowx1"] + 1 and s["ydimen"] == s["windowy2"] - s["windowy1"] + 1
    print("[integrity] view " + " ".join(f"{k}={v}" for k, v in s.items()) + f" ok={ok and s['ydimen'] > 0}")
    print("[integrity] neighbours " + json.dumps({k: hex(v) for k, v in n.items()}))


mode = os.environ["PROBE_MODE"]
if mode in ("fill", "check"):
    guards(mode, os.environ["PROBE_CHANGES"])
elif mode == "view":
    view()

#!/usr/bin/env python3
# lp.py - minimal Android logical-partition (liblp) helper for chopin.
#
# If the phone runs Android, the Debian rootfs lives on its own userdata
# partition, but the touch/WiFi/... firmware files are still inside the
# "vendor" logical partition which lives inside the physical "super" partition.
# This helper reads the liblp metadata out of /dev/sdc61 (or whatever the super
# partition is) so it can be loop-mounted read-only.
#
# usage:
#   lp.py list <super-dev>
#   lp.py map  <super-dev> [partition]
#
# "map" prints "<byte-offset> <byte-size>" of the partition's first extent
# (vendor is a single extent on chopin), ready for:
#   losetup -f --show -r --offset O --sizelimit S /dev/sdc61
import struct
import sys

SECTOR = 512
GEOM_MAGIC = 0x616c4467
HDR_MAGIC = 0x414c5030

def geometry(dev):
    with open(dev, "rb") as f:
        f.seek(4096)
        g = f.read(4096)
    magic, = struct.unpack_from("<I", g, 0)
    if magic != GEOM_MAGIC:
        raise SystemExit("bad geometry magic 0x%08x" % magic)
    mms, msc, lbs = struct.unpack_from("<III", g, 40)
    return dict(mms=mms, msc=msc, lbs=lbs)

def metadata(dev, geom, slot=0, backup=False):
    mms = geom["mms"]
    base = 4096 + 2 * 4096 + mms * (slot + (geom["msc"] if backup else 0))
    with open(dev, "rb") as f:
        f.seek(base)
        data = f.read(mms)
    if len(data) < 128:
        raise SystemExit("short metadata")
    magic, major, minor, header_size = struct.unpack_from("<IHHI", data, 0)
    if magic != HDR_MAGIC:
        raise SystemExit("bad header magic 0x%08x at %d" % (magic, base))
    desc = {}
    for i, name in enumerate(["partitions", "extents", "groups", "block_devices"]):
        off, n, es = struct.unpack_from("<III", data, 80 + 12 * i)
        desc[name] = (off, n, es)
    ts = header_size
    parts = []
    off, n, es = desc["partitions"]
    for i in range(n):
        e = data[ts + off + i * es: ts + off + (i + 1) * es]
        name = e[0:36].split(b"\x00")[0].decode("ascii", "replace")
        attrs, first, num, group = struct.unpack_from("<IIII", e, 36)
        parts.append(dict(name=name, attrs=attrs, first=first, num=num, group=group))
    exts = []
    off, n, es = desc["extents"]
    for i in range(n):
        e = data[ts + off + i * es: ts + off + (i + 1) * es]
        num, ttype, tdata = struct.unpack_from("<QIQ", e, 0)
        src, = struct.unpack_from("<I", e, 20)
        exts.append(dict(num=num, type=ttype, data=tdata, src=src))
    bdevs = []
    off, n, es = desc["block_devices"]
    for i in range(n):
        e = data[ts + off + i * es: ts + off + (i + 1) * es]
        fls, al, alo, size = struct.unpack_from("<QIIQ", e, 0)
        nm = e[24:60].split(b"\x00")[0].decode("ascii", "replace")
        bdevs.append(dict(first=fls, size=size, name=nm))
    return dict(parts=parts, exts=exts, bdevs=bdevs)

def show(dev):
    g = geometry(dev)
    print("geometry: metadata_max_size=%d slots=%d logical_block=%d" % (g["mms"], g["msc"], g["lbs"]))
    m = metadata(dev, g, 0)
    for p in m["parts"]:
        sectors = sum(m["exts"][p["first"] + k]["num"] for k in range(p["num"]))
        print("  %-16s %10.1f MiB  extents=%d attrs=0x%x" % (p["name"], sectors * SECTOR / 1048576.0, p["num"], p["attrs"]))

def map_part(dev, name):
    g = geometry(dev)
    m = metadata(dev, g, 0)
    cands = [name + "_a", name] if not name.endswith("_a") else [name]
    for p in m["parts"]:
        if p["name"] in cands:
            if p["num"] != 1:
                raise SystemExit("partition %s has %d extents, only single-extent partitions are supported" % (p["name"], p["num"]))
            e = m["exts"][p["first"]]
            print("%d %d" % (e["data"] * SECTOR, e["num"] * SECTOR))
            return
    raise SystemExit("partition %s not found" % name)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: lp.py list <dev> | lp.py map <dev> [partition]")
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "list":
        show(sys.argv[2])
    elif cmd == "map":
        map_part(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "vendor")
    else:
        raise SystemExit("unknown command " + cmd)

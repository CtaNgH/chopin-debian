#!/usr/bin/env python3
"""把 ext4 镜像转成 Android sparse 镜像（4K 块，跳过全零块）。"""
import struct, sys

BLK = 4096
CHUNK_RAW = 0xCAC1
CHUNK_DONT_CARE = 0xCAC3

def main(src, dst):
    with open(src, 'rb') as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(0)
        total_blks = (size + BLK - 1) // BLK
        chunks = []
        pending_raw = []
        pending_zero = 0
        while True:
            blk = f.read(BLK)
            if not blk:
                break
            if len(blk) < BLK:
                blk = blk + b'\0' * (BLK - len(blk))
            if blk == b'\0' * BLK:
                if pending_raw:
                    chunks.append((CHUNK_RAW, pending_raw)); pending_raw = []
                pending_zero += 1
            else:
                if pending_zero:
                    chunks.append((CHUNK_DONT_CARE, pending_zero)); pending_zero = 0
                pending_raw.append(blk)
        if pending_raw:
            chunks.append((CHUNK_RAW, pending_raw))
        if pending_zero:
            chunks.append((CHUNK_DONT_CARE, pending_zero))

    with open(dst, 'wb') as o:
        o.write(struct.pack('<IHHHHIIII', 0xED26FF3A, 1, 0, 28, 12, BLK,
                            total_blks, len(chunks), 0))
        for kind, payload in chunks:
            if kind == CHUNK_DONT_CARE:
                o.write(struct.pack('<HHII', kind, 0, payload, 12))
            else:
                n = len(payload)
                o.write(struct.pack('<HHII', kind, 0, n, 12 + n * BLK))
                for b in payload:
                    o.write(b)
    print(f"{dst}: {total_blks} blocks, {len(chunks)} chunks")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

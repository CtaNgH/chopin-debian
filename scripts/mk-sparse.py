#!/usr/bin/env python3
"""把 ext4 镜像转成 Android sparse 镜像（4K 块，零块用 FILL 而不是 DONT_CARE）。

注意：DONT_CARE 的含义是"目标上这块内容无所谓，跳过不写"。如果把镜像里的
全零块标成 DONT_CARE，而目标分区上还留着旧数据（社区用户刷机时就是这种
情况），这些块就会保留旧数据 —— 文件系统元数据说它们属于某个文件，读出来
却是旧内容，表现为随机的文件损坏（python3 段错误就是这么来的）。

所以零块必须用 CHUNK_TYPE_FILL（0xCAC2，填 4 字节 0）让 bootloader 真的写零。
FILL 块的头部只有 16 字节，和 DONT_CARE 一样省空间。
"""
import struct, sys

BLK = 4096
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
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
                    chunks.append((CHUNK_FILL, pending_zero)); pending_zero = 0
                pending_raw.append(blk)
        if pending_raw:
            chunks.append((CHUNK_RAW, pending_raw))
        if pending_zero:
            chunks.append((CHUNK_FILL, pending_zero))

    with open(dst, 'wb') as o:
        o.write(struct.pack('<IHHHHIIII', 0xED26FF3A, 1, 0, 28, 12, BLK,
                            total_blks, len(chunks), 0))
        for kind, payload in chunks:
            if kind == CHUNK_FILL:
                o.write(struct.pack('<HHII', kind, 0, payload, 16))
                o.write(b'\0\0\0\0')
            elif kind == CHUNK_DONT_CARE:
                o.write(struct.pack('<HHII', kind, 0, payload, 12))
            else:
                n = len(payload)
                o.write(struct.pack('<HHII', kind, 0, n, 12 + n * BLK))
                for b in payload:
                    o.write(b)
    print(f"{dst}: {total_blks} blocks, {len(chunks)} chunks")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

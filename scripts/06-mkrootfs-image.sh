#!/usr/bin/env bash
# rootfs 目录 -> ext4 镜像 -> Android sparse 镜像（32 位 fastboot 可刷）。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root

[ -d "$ROOTFS/etc" ] || die "先运行 00-05"
IMG="$OUT_DIR/$ROOTFS_IMG_NAME"
SPARSE="$OUT_DIR/$ROOTFS_SPARSE_NAME"
rm -f "$IMG" "$SPARSE"

log "清理 apt 缓存与索引（可减掉约 600 MB）"
rm -f "$ROOTFS"/var/cache/apt/archives/*.deb
rm -rf "$ROOTFS"/var/lib/apt/lists/*
rm -rf "$ROOTFS"/var/cache/apt/*.bin

log "创建 ext4：$IMG（$ROOTFS_SIZE_MB MB）"
truncate -s "$ROOTFS_SIZE_MB"M "$IMG"
mkfs.ext4 -q -F -L "$ROOTFS_LABEL" -d "$ROOTFS" "$IMG"
e2fsck -fy "$IMG" >/dev/null || true
resize2fs -M "$IMG"
e2fsck -fy "$IMG" >/dev/null || true

log "转 Android sparse"
python3 "$DEBIAN_DIR/scripts/mk-sparse.py" "$IMG" "$SPARSE"
ls -lh "$IMG" "$SPARSE"

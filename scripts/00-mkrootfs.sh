#!/usr/bin/env bash
# 创建 Debian 13.7 (trixie) arm64 minbase 根文件系统。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root
mkdir -p "$BUILD_DIR" "$OUT_DIR"

if [ -e "$ROOTFS/etc/debian_version" ]; then
    log "rootfs 已存在，跳过：$ROOTFS"
    exit 0
fi
rm -rf "$ROOTFS"

PKGS="$(grep -v '^#' "$CONFIG_DIR/packages.base" | grep -v '^$' | paste -sd, -)"
log "mmdebstrap $DEBIAN_SUITE arm64 -> $ROOTFS"
mmdebstrap --arch=arm64 --variant=minbase \
    --keyring="$CONFIG_DIR/debian-archive-keyring.gpg" \
    --components=main,contrib,non-free-firmware \
    --include="$PKGS" \
    "$DEBIAN_SUITE" "$ROOTFS" "$DEBIAN_MIRROR"

write_sources
chroot_mount
trap chroot_umount EXIT
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
in_chroot apt-get update
log "base rootfs 完成：$ROOTFS"

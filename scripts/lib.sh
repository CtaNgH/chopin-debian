#!/usr/bin/env bash
# 公共函数：路径、版本、chroot 挂载。所有脚本通过 source 使用。
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
DEBIAN_DIR="$PROJECT/debian"
CONFIG_DIR="$DEBIAN_DIR/config"
BUILD_DIR="$DEBIAN_DIR/build"
OUT_DIR="$DEBIAN_DIR/out"
ROOTFS="$BUILD_DIR/rootfs"
KERNEL_DIR="$PROJECT/linux"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

load_env() {
    set -a
    . "$CONFIG_DIR/versions.env"
    set +a
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "需要 root 运行"
}

chroot_mount() {
    mkdir -p "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" "$ROOTFS/dev/pts"
    mountpoint -q "$ROOTFS/proc" || mount -t proc proc "$ROOTFS/proc"
    mountpoint -q "$ROOTFS/sys" || mount -t sysfs sysfs "$ROOTFS/sys"
    mountpoint -q "$ROOTFS/dev" || mount --bind /dev "$ROOTFS/dev"
    mountpoint -q "$ROOTFS/dev/pts" || mount --bind /dev/pts "$ROOTFS/dev/pts"
}

chroot_umount() {
    mountpoint -q "$ROOTFS/dev/pts" && umount "$ROOTFS/dev/pts" || true
    mountpoint -q "$ROOTFS/dev" && umount "$ROOTFS/dev" || true
    mountpoint -q "$ROOTFS/sys" && umount "$ROOTFS/sys" || true
    mountpoint -q "$ROOTFS/proc" && umount "$ROOTFS/proc" || true
}

in_chroot() { chroot "$ROOTFS" "$@"; }

write_sources() {
    sed -e "s|@MIRROR@|$DEBIAN_MIRROR|g" -e "s|@SECURITY@|$DEBIAN_SECURITY|g" \
        "$CONFIG_DIR/sources.list.in" > "$ROOTFS/etc/apt/sources.list"
    rm -f "$ROOTFS"/etc/apt/sources.list.d/*.list "$ROOTFS"/etc/apt/sources.list.d/*.sources
    install -Dm644 "$CONFIG_DIR/debian-archive-keyring.gpg" \
        "$ROOTFS/usr/share/keyrings/debian-archive-keyring.gpg"
}

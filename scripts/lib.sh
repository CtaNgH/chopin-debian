#!/usr/bin/env bash
# 公共函数：路径、版本、chroot 挂载。所有脚本通过 source 使用。
set -euo pipefail

# 本仓库根目录（chopin-debian/）
DEBIAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 顶层工作区（chopin-linux/）；单独 clone debian 时也成立，只是默认找不到 kernel/
PROJECT="$(dirname "$DEBIAN_DIR")"
CONFIG_DIR="$DEBIAN_DIR/config"
BUILD_DIR="${BUILD_DIR:-$DEBIAN_DIR/build}"
OUT_DIR="${OUT_DIR:-$DEBIAN_DIR/out}"
ROOTFS="$BUILD_DIR/rootfs"

# 内核仓库：默认与本仓库同级的 kernel/（顶层布局）。
# 单独使用本仓库时：KERNEL_REPO=/path/to/chopin-kernel make build
KERNEL_REPO="${KERNEL_REPO:-$PROJECT/kernel}"
KERNEL_DIR="${KERNEL_DIR:-$KERNEL_REPO/linux}"
KERNEL_OUT="${KERNEL_OUT:-$KERNEL_REPO/out}"
MKBOOTIMG="${MKBOOTIMG:-$KERNEL_REPO/scripts/mkbootimg.py}"

# 原厂镜像：不随仓库分发，放进顶层 stock/ 或用环境变量指定
STOCK_DIR="${STOCK_DIR:-$PROJECT/stock}"
STOCK_BOOT="${STOCK_BOOT:-$STOCK_DIR/boot_a.img}"
STOCK_DTBO="${STOCK_DTBO:-$STOCK_DIR/dtbo_a.img}"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

load_env() {
    set -a
    # shellcheck source=../config/versions.env
    . "$CONFIG_DIR/versions.env"
    set +a
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "需要 root 运行：sudo make build（或 sudo ./scripts/build-all.sh）"
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

# 仅当单元存在时 enable，便于 --skip-gnome 的精简构建也能通过。
enable_unit() {
    local unit="$1"
    if in_chroot systemctl list-unit-files "$unit.service" 2>/dev/null | grep -q "^$unit.service"; then
        in_chroot systemctl enable "$unit"
    else
        log "跳过不存在的单元：$unit.service"
    fi
}

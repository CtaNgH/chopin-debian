#!/usr/bin/env bash
# 在 rootfs 内安装 GNOME 48（gnome-core 组合）。可重复执行。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root
[ -d "$ROOTFS" ] || die "先运行 00-mkrootfs.sh"

chroot_mount
trap chroot_umount EXIT
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
in_chroot apt-get update

PKGS="$(grep -v '^#' "$CONFIG_DIR/packages.gnome" | grep -v '^$' | paste -sd' ' -)"
log "安装 GNOME 组件（下载约 1.5-2 GB，qemu-user 下较慢）"
in_chroot env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PKGS

FULL="$(printenv INSTALL_FULL_TASK 2>/dev/null || true)"
if [ "$FULL" = "1" ]; then
    log "追加 task-gnome-desktop（完整桌面应用集）"
    in_chroot env DEBIAN_FRONTEND=noninteractive apt-get install -y task-gnome-desktop
fi

log "桌面组件安装完成"

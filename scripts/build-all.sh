#!/usr/bin/env bash
# 一键构建 Debian 13 + GNOME rootfs 与 boot.img。
# 用法：debian/scripts/build-all.sh [--skip-gnome] [--skip-mesa]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root

SKIP_GNOME=0
SKIP_MESA=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-gnome) SKIP_GNOME=1 ;;
        --skip-mesa) SKIP_MESA=1 ;;
        *) die "未知参数：$1" ;;
    esac
    shift
done

"$DEBIAN_DIR/scripts/00-mkrootfs.sh"
if [ "$SKIP_GNOME" = "1" ]; then
    log "跳过 GNOME 安装"
else
    "$DEBIAN_DIR/scripts/01-install-desktop.sh"
fi
"$DEBIAN_DIR/scripts/02-configure-rootfs.sh"
"$DEBIAN_DIR/scripts/03-install-kernel.sh"
if [ "$SKIP_MESA" = "1" ]; then
    log "跳过 Mesa G77"
else
    "$DEBIAN_DIR/scripts/04-build-mesa.sh"
fi
"$DEBIAN_DIR/scripts/05-mkinitramfs.sh"
"$DEBIAN_DIR/scripts/06-mkrootfs-image.sh"
"$DEBIAN_DIR/scripts/07-mkbootimg.sh"

log "完成。产物在 $OUT_DIR"

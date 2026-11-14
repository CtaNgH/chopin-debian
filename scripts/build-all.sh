#!/usr/bin/env bash
# 一键构建 Debian 13 + GNOME rootfs、initramfs、rootfs 镜像与 boot.img。
#
# 用法：
#   sudo ./scripts/build-all.sh [--skip-gnome] [--skip-mesa] [--rebuild]
#
#   --skip-gnome  只做 minbase + 基础配置（仍会尝试安装内核模块）
#   --skip-mesa   跳过 G77 libgallium（默认就跳过，见 04 脚本）
#   --rebuild     删除已有 rootfs 后从零构建
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
require_root

SKIP_GNOME=0
SKIP_MESA=0
REBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-gnome) SKIP_GNOME=1 ;;
        --skip-mesa)  SKIP_MESA=1 ;;
        --rebuild)    REBUILD=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
    shift
done
if [ "$REBUILD" = "1" ]; then
    export REBUILD_ROOTFS=1
fi

[ -d "$KERNEL_DIR" ] || die "找不到内核工作树：$KERNEL_DIR
先运行：make -C ../kernel bootstrap && make -C ../kernel build"
[ -f "$KERNEL_DIR/arch/arm64/boot/Image.gz" ] || die "内核尚未构建：先运行 make -C ../kernel build"

log "Debian $DEBIAN_RELEASE ($DEBIAN_SUITE) / 内核 $KERNEL_DIR"
log "rootfs: $ROOTFS"
log "产物:   $OUT_DIR"

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

log "生成校验和"
( cd "$OUT_DIR" && sha256sum ./*.img ./*.cpio.gz > SHA256SUMS 2>/dev/null || true )
log "完成。产物在 $OUT_DIR"
ls -lh "$OUT_DIR"/*.img "$OUT_DIR"/*.cpio.gz 2>/dev/null || true

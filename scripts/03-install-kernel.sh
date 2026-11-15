#!/usr/bin/env bash
# 把内核模块与 Image/dtb 装进 rootfs。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root
[ -d "$ROOTFS" ] || die "先运行 00-02"

REL="$(cat "$KERNEL_DIR/include/config/kernel.release")"
SRC="$PROJECT/out/modules/lib/modules/$REL"
[ -d "$SRC" ] || die "找不到模块目录 $SRC；先运行 scripts/build.sh"
[ -f "$KERNEL_DIR/arch/arm64/boot/Image.gz" ] || die "先运行 scripts/build.sh"

log "内核 release：$REL"
mkdir -p "$ROOTFS/lib/modules"
rm -rf "$ROOTFS/lib/modules"
mkdir -p "$ROOTFS/lib/modules"
cp -a "$SRC" "$ROOTFS/lib/modules/"
depmod -b "$ROOTFS" "$REL"

install -Dm644 "$KERNEL_DIR/arch/arm64/boot/Image" "$ROOTFS/boot/vmlinuz-$REL"
install -Dm644 "$KERNEL_DIR/arch/arm64/boot/Image.gz" "$ROOTFS/boot/vmlinuz-$REL.gz"
install -Dm644 "$KERNEL_DIR/arch/arm64/boot/dts/mediatek/mt6893-xiaomi-chopin.dtb" \
    "$ROOTFS/boot/mt6893-xiaomi-chopin.dtb"

[ -f "$ROOTFS/lib/modules/$REL/kernel/drivers/gpu/drm/panfrost/panfrost.ko" ] || \
    die "panfrost.ko 不在模块目录，检查 CONFIG_DRM_PANFROST"

log "模块与内核已安装：$REL"

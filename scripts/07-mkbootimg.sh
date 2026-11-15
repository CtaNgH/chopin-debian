#!/usr/bin/env bash
# 打包 boot.img：原厂镜像为模板，替换 kernel + initramfs，保留原厂 dtb 段。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root

[ -f "$OUT_DIR/initramfs.cpio.gz" ] || die "先运行 05-mkinitramfs.sh"
[ -f "$KERNEL_DIR/arch/arm64/boot/Image.gz" ] || die "先运行 scripts/build.sh"

STOCK="$STOCK_BOOT"
if [ -z "$STOCK" ]; then
    STOCK="$PROJECT/chopin/images/boot_a.img"
fi
[ -f "$STOCK" ] || die "找不到原厂 boot 镜像：$STOCK（改 versions.env 的 STOCK_BOOT）"

OUT="$OUT_DIR/boot-chopin-debian.img"
python3 "$PROJECT/scripts/mkbootimg.py" \
    --stock "$STOCK" \
    --kernel "$KERNEL_DIR/arch/arm64/boot/Image.gz" \
    --ramdisk "$OUT_DIR/initramfs.cpio.gz" \
    -o "$OUT"
ls -lh "$OUT"

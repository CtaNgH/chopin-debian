#!/usr/bin/env bash
# 打包 boot.img：原厂镜像为模板，替换 kernel + initramfs，保留原厂 dtb 段。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
require_root

[ -f "$OUT_DIR/initramfs.cpio.gz" ] || die "先运行 05-mkinitramfs.sh"
[ -f "$KERNEL_DIR/arch/arm64/boot/Image.gz" ] || die "先运行 make -C ../kernel build"
[ -f "$MKBOOTIMG" ] || die "找不到 mkbootimg.py：$MKBOOTIMG"

STOCK="$STOCK_BOOT"
if [ -z "$STOCK" ] || [ ! -f "$STOCK" ]; then
    die "找不到原厂 boot 镜像：$STOCK
把自备份的 boot_a.img 放到顶层 stock/，或：STOCK_BOOT=/path/to/boot_a.img make bootimg"
fi

OUT="$OUT_DIR/$BOOT_IMG_NAME"
python3 "$MKBOOTIMG" \
    --stock "$STOCK" \
    --kernel "$KERNEL_DIR/arch/arm64/boot/Image.gz" \
    --ramdisk "$OUT_DIR/initramfs.cpio.gz" \
    -o "$OUT"
ls -lh "$OUT"

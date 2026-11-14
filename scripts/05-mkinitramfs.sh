#!/usr/bin/env bash
# 生成 busybox initramfs（init + gadget）。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root

[ -d "$ROOTFS" ] || die "先运行 00-04"
[ -x "$ROOTFS/bin/busybox" ] || die "rootfs 缺少 busybox-static"
command -v cpio >/dev/null 2>&1 || die "缺少 cpio（apt install cpio）"

STAGE="$BUILD_DIR/initramfs"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/tmp" "$STAGE/run" "$STAGE/newroot"

cp "$ROOTFS/bin/busybox" "$STAGE/bin/busybox"
chmod 755 "$STAGE/bin/busybox"
cp "$DEBIAN_DIR/initramfs/init" "$STAGE/init"
chmod 755 "$STAGE/init"
cp "$DEBIAN_DIR/initramfs/chopin-gadget.sh" "$STAGE/bin/chopin-gadget.sh"
chmod 755 "$STAGE/bin/chopin-gadget.sh"

( cd "$STAGE" && find . -print0 | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9 ) \
    > "$OUT_DIR/initramfs.cpio.gz"

ls -lh "$OUT_DIR/initramfs.cpio.gz"

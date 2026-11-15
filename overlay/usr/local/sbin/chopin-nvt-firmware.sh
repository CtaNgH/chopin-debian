#!/bin/sh
# chopin-nvt-firmware.sh - install the Novatek NT36672C touch firmware.
#
# The touch controller on chopin is a host-download part: it has no usable
# firmware after a cold boot, and the stock vendor kernel always pushes
# novatek_nt36672c_k10a_fwNN.bin into it at boot (that is why the driver asks
# request_firmware() for it).  Mainline's linux-firmware has no such file, so
# without it the chip stays silent: the driver probes fine, the input device is
# registered, but the IRQ line never asserts and the touchscreen never reports.
#
# The very same blobs are shipped in the device's own vendor logical partition
# (inside the physical "super" partition), so extract them from there.  The
# rootfs is on userdata; the super partition is untouched by the Debian port.
#
# Idempotent: exits immediately when the firmware is already installed.
set -u

FW_DIR=/lib/firmware
FW_FILE=$FW_DIR/novatek_nt36672c_k10a_fw01.bin
LP_TOOL=/usr/local/lib/chopin/lp.py
MNT=/run/chopin-vendor
PY=/usr/bin/python3

log() {
    echo "chopin-nvt-firmware: $*"
    logger -t chopin-nvt-firmware "$*" 2>/dev/null || true
}

if [ -f "$FW_FILE" ]; then
    log "firmware already installed"
    exit 0
fi

SUPER=
if [ -e /dev/disk/by-partlabel/super ]; then
    SUPER=$(readlink -f /dev/disk/by-partlabel/super)
fi
if [ -z "$SUPER" ]; then
    for d in /sys/class/block/sd*; do
        [ -r "$d/uevent" ] || continue
        if grep -q '^PARTNAME=super$' "$d/uevent" 2>/dev/null; then
            SUPER=/dev/$(basename "$d")
            break
        fi
    done
fi
if [ -z "$SUPER" ]; then
    log "no super partition found, skipping"
    exit 0
fi
if [ ! -x "$PY" ] || [ ! -f "$LP_TOOL" ]; then
    log "python3 or $LP_TOOL missing, skipping"
    exit 0
fi

MAP=$("$PY" "$LP_TOOL" map "$SUPER" vendor 2>/dev/null) || MAP=
if [ -z "$MAP" ]; then
    log "cannot map vendor logical partition on $SUPER"
    exit 0
fi
OFFSET=$(echo "$MAP" | awk '{print $1}')
SIZE=$(echo "$MAP" | awk '{print $2}')
log "vendor partition on $SUPER: offset=$OFFSET size=$SIZE"

LOOP=$(losetup -f --show -r --offset "$OFFSET" --sizelimit "$SIZE" "$SUPER" 2>/dev/null) || {
    log "losetup failed"
    exit 0
}
mkdir -p "$MNT"
if ! mount -t ext4 -o ro "$LOOP" "$MNT" 2>/dev/null; then
    log "mount of $LOOP failed"
    losetup -d "$LOOP"
    exit 0
fi

COPIED=0
for f in "$MNT"/firmware/novatek_nt36672c_k10a_*.bin; do
    [ -f "$f" ] || continue
    if cp -f "$f" "$FW_DIR/"; then
        COPIED=$((COPIED + 1))
    fi
done

umount "$MNT"
losetup -d "$LOOP"

if [ "$COPIED" -eq 0 ]; then
    log "no Novatek touch firmware found in the vendor image"
    exit 0
fi
log "installed $COPIED firmware file(s) into $FW_DIR"

# If the touch driver probed before the firmware existed, reload it so the
# download happens now instead of on the next boot.
if [ -e /sys/bus/spi/drivers/NVT-ts-spi/spi0.0 ]; then
    log "rebinding NVT-ts-spi so the chip gets its firmware"
    echo spi0.0 > /sys/bus/spi/drivers/NVT-ts-spi/unbind 2>/dev/null || true
    sleep 1
    echo spi0.0 > /sys/bus/spi/drivers/NVT-ts-spi/bind 2>/dev/null || true
fi
exit 0

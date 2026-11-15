#!/bin/sh
# chopin-wifi-firmware.sh - install the MediaTek WLAN firmware and NVRAM.
#
# The WLAN block (conninfra / soc3_0, "WIFI-GEN4") is a built-in driver that
# needs three kinds of blobs which mainline's linux-firmware does not ship:
#
#   1. the runtime firmware      WIFI_RAM_CODE_soc3_0_1a_1.bin
#   2. the MCU/patch headers     soc3_0_ram_*.bin   (wmmcu header is requested
#                                 first and its absence aborts the power-on)
#   3. the per-unit NVRAM blob   mediatek/mt6893/WIFI, which carries the
#                                 factory calibration for THIS unit
#
# (1) and (2) live in the vendor logical partition inside "super"; (3) lives on
# the nvdata partition at /APCFG/APRDEB/WIFI.  The driver retries the NVRAM load
# for a few seconds after boot, so install early: the unit runs before sysinit.
#
# Idempotent: exits immediately when everything is already installed.
set -u

FW_DIR=/lib/firmware
NVRAM=$FW_DIR/mediatek/mt6893/WIFI
RAMCODE=$FW_DIR/WIFI_RAM_CODE_soc3_0_1a_1.bin
LP_TOOL=/usr/local/lib/chopin/lp.py
MNT=/run/chopin-vendor
PY=/usr/bin/python3

log() {
    echo "chopin-wifi-firmware: $*"
    logger -t chopin-wifi-firmware "$*" 2>/dev/null || true
}

if [ -f "$NVRAM" ] && [ -f "$RAMCODE" ]; then
    log "firmware already installed"
    exit 0
fi

# ---- NVRAM from the nvdata partition -------------------------------------
# Same udev-timing problem as the super partition below: at Before=sysinit the
# /dev/disk/by-partlabel links do not exist yet on a freshly flashed system.
# Wait for the link, or take the raw node (nvdata is partition 6 on chopin).
if [ ! -f "$NVRAM" ]; then
    NVD=""
    i=0
    while [ "$i" -lt 20 ]; do
        if [ -e /dev/disk/by-partlabel/nvdata ]; then
            NVD=$(readlink -f /dev/disk/by-partlabel/nvdata)
            break
        fi
        [ -b /dev/sdc6 ] && { NVD=/dev/sdc6; break; }
        sleep 0.5
        i=$((i + 1))
    done
fi
if [ ! -f "$NVRAM" ] && [ -n "${NVD:-}" ]; then
    mkdir -p /run/chopin-nvdata
    if mount -t ext4 -o ro "$NVD" /run/chopin-nvdata 2>/dev/null; then
        if [ -f /run/chopin-nvdata/APCFG/APRDEB/WIFI ]; then
            mkdir -p "$(dirname "$NVRAM")"
            cp -f /run/chopin-nvdata/APCFG/APRDEB/WIFI "$NVRAM" && \
                log "installed NVRAM from $NVD"
        fi
        umount /run/chopin-nvdata
    else
        log "cannot mount $NVD"
    fi
fi

# ---- firmware from the vendor logical partition --------------------------
if [ ! -f "$RAMCODE" ]; then
    # The service runs Before=sysinit.target, i.e. before udev has created
    # /dev/disk/by-partlabel — on a freshly flashed image that lookup returns
    # nothing and the firmware would never be installed.  Wait briefly for the
    # udev link, and fall back to the raw device node of this board (super is
    # partition 61 on chopin, same as the initramfs fallback for userdata).
    SUPER=
    i=0
    while [ "$i" -lt 20 ]; do
        if [ -e /dev/disk/by-partlabel/super ]; then
            SUPER=$(readlink -f /dev/disk/by-partlabel/super)
            break
        fi
        [ -b /dev/sdc61 ] && { SUPER=/dev/sdc61; break; }
        sleep 0.5
        i=$((i + 1))
    done
    if [ -n "$SUPER" ] && [ -x "$PY" ] && [ -f "$LP_TOOL" ]; then
        MAP=$("$PY" "$LP_TOOL" map "$SUPER" vendor 2>/dev/null) || MAP=
        if [ -n "$MAP" ]; then
            OFFSET=$(echo "$MAP" | awk '{print $1}')
            SIZE=$(echo "$MAP" | awk '{print $2}')
            mkdir -p "$MNT"
            LOOP=$(losetup -f --show -r --offset "$OFFSET" --sizelimit "$SIZE" "$SUPER" 2>/dev/null) || LOOP=
            if [ -n "$LOOP" ] && mount -t ext4 -o ro "$LOOP" "$MNT" 2>/dev/null; then
                COPIED=0
                for f in "$MNT"/firmware/WIFI_RAM_CODE_soc3_0_1a_1.bin \
                         "$MNT"/firmware/soc3_0_*.bin; do
                    [ -f "$f" ] || continue
                    cp -f "$f" "$FW_DIR/" && COPIED=$((COPIED + 1))
                done
                [ -f "$MNT/firmware/wifi.cfg" ] && cp -f "$MNT/firmware/wifi.cfg" "$FW_DIR/"
                umount "$MNT"
                [ -n "$LOOP" ] && losetup -d "$LOOP"
                log "installed $COPIED WLAN firmware file(s) from $SUPER"
            else
                log "cannot mount vendor partition on $SUPER"
                [ -n "$LOOP" ] && losetup -d "$LOOP"
            fi
        fi
    else
        log "no super partition or lp.py, skipping firmware"
    fi
fi

if [ -f "$NVRAM" ] && [ -f "$RAMCODE" ]; then
    log "WLAN firmware ready"
else
    log "WLAN firmware incomplete (nvram=$([ -f "$NVRAM" ] && echo yes || echo no) ramcode=$([ -f "$RAMCODE" ] && echo yes || echo no))"
fi
exit 0

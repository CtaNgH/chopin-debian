#!/bin/sh
# chopin: raise the Mali-G77 core clock.
#
# The GPU comes up at whatever LK programmed (350 MHz = mfgpll 349999848).  The
# panfrost port has a safe re-lock path exposed as
# /sys/devices/platform/13000000.mali/core_clk_rate: it parks mfg_sel on clk26m,
# re-locks mfgpll, then switches back - re-locking the PLL while the GPU is still
# clocked from it wedges the AXI bus (measured, twice).
#
# 650 MHz is the best measured point on this board (+11.5 % glmark2).  750 MHz is
# *slower* and a warning sign: the GPU rail voltage is set by the bootloader
# (MT6315 7_vbuck1, no SPMI driver in Linux), so anything above 650 runs closer
# to undervolt.  Keep it at 650.
#
# Override: echo 450000000 > /etc/chopin-gpu-freq
# Disable:  rm /etc/chopin-gpu-freq
set -u
FILE=/etc/chopin-gpu-freq
KNOB=/sys/devices/platform/13000000.mali/core_clk_rate

[ -s "$FILE" ] || exit 0
[ -w "$KNOB" ] || exit 0

hz=$(cat "$FILE" 2>/dev/null)
case "$hz" in
'' | *[!0-9]*)
    echo "chopin-gpu-freq: $FILE must contain a plain frequency in Hz" >&2
    exit 1
    ;;
esac

cur=$(cat "$KNOB")
[ "$cur" = "$hz" ] && exit 0

echo "$hz" > "$KNOB" || exit 1
echo "chopin-gpu-freq: $cur -> $(cat "$KNOB") Hz"

#!/bin/sh
# chopin: pin the A78 cluster at a higher OPP.
#
# The bootloader leaves armpll_bl at 729 MHz (the lowest vendor OPP) and there
# is no cpufreq driver for MT6893, so the big cluster would stay there forever.
# chopin-cpuclk exposes the PLLs; this script pins them.
#
# Re-locking a PLL while a core runs from it wedges the MCUSYS bus, so the whole
# cluster goes offline first and comes back afterwards.  The CPU rail voltage is
# on the MT6315 (SPMI, not ported), i.e. untouchable - 1.5 GHz is what boots this
# board stably; do not raise it blindly.
set -u
FILE=/etc/chopin-cpu-freq
SYS=/sys/devices/platform/chopin-cpuclk
BIG="4 5 6 7"

[ -s "$FILE" ] || exit 0
hz=$(cat "$FILE" 2>/dev/null)
case "$hz" in
'' | *[!0-9]*) echo "chopin-cpu-freq: $FILE must hold a plain frequency in Hz" >&2; exit 1 ;;
esac

modprobe chopin_cpuclk 2>/dev/null || true

i=0
while [ ! -e "$SYS/bl_freq" ]; do
    i=$((i + 1))
    [ "$i" -gt 40 ] && { echo "chopin-cpu-freq: $SYS never appeared" >&2; exit 0; }
    sleep 0.5
done

cur=$(cat "$SYS/bl_freq")
# The PLL cannot hit the requested value exactly (1.5 GHz reads back as
# 1499998780), so treat anything within 1 kHz as "already there".
if [ "$cur" -ge $((hz - 1000)) ] 2>/dev/null && [ "$cur" -le $((hz + 1000)) ] 2>/dev/null; then
    echo "chopin-cpu-freq: already at $cur Hz"
    exit 0
fi

for c in $BIG; do
    echo 0 > "/sys/devices/system/cpu/cpu$c/online" 2>/dev/null || true
done

if ! echo "$hz" > "$SYS/bl_freq"; then
    echo "chopin-cpu-freq: refused ($hz); cluster stays at $cur" >&2
fi

for c in $BIG; do
    echo 1 > "/sys/devices/system/cpu/cpu$c/online" 2>/dev/null || true
done

now=$(cat "$SYS/bl_freq")
echo "chopin-cpu-freq: armpll_bl $cur -> $now Hz (online: $(cat /sys/devices/system/cpu/online))"

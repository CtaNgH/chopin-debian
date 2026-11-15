#!/bin/sh
# chopin: restart charging after the MT6360 latches end-of-charge.
#
# With a 900 mA input the battery only sees ~300 mA, so the 100 mA IEOC
# threshold is reached long before the pack is full (4.46 V design, we stop at
# ~4.35 V, gauge says 89 %).  Worse, the driver never re-arms charging on its
# own: status stays "Full" until the cable is replugged, which is exactly the
# "charges to 85-89 % and stops" report.
#
# Cycling the input current limit clears the latched Full state (verified on
# hardware: 0 -> 1500000 turned "Full" back into "Charging" with +311 mA).
set -u
CHG=$(ls -d /sys/class/power_supply/mt6360-chg* 2>/dev/null | head -1)
BAT=$(ls -d /sys/class/power_supply/bq27z561* 2>/dev/null | head -1)
[ -n "$CHG" ] || exit 0
[ -n "$BAT" ] || exit 0

online=$(cat "$CHG/online" 2>/dev/null || echo 0)
[ "$online" = "1" ] || exit 0

status=$(cat "$CHG/status" 2>/dev/null)
cap=$(cat "$BAT/capacity" 2>/dev/null)
[ -n "$cap" ] || cap=100

# Only when the charger says full but the gauge says it is not.
[ "$status" = "Full" ] || exit 0
[ "$cap" -ge 99 ] && exit 0

limit=900000
[ -s /etc/chopin-charge-limit ] && limit=$(cat /etc/chopin-charge-limit)
[ -n "$limit" ] || limit=900000

echo 0 > "$CHG/input_current_limit" 2>/dev/null || exit 0
sleep 3
echo "$limit" > "$CHG/input_current_limit" 2>/dev/null || true
sleep 2
echo "chopin-charge-recharge: cap=$cap status now $(cat "$CHG/status" 2>/dev/null)"

#!/bin/sh
# chopin: raise the MT6360 input current limit.
#
# Why: the charger comes up as a plain SDP port with input_current_limit=500 mA.
# The phone itself draws 400-450 mA, so only ~50-90 mA reaches the battery and
# the pack never gets past ~85% - it looks like charging is broken.  The
# reference port measured 900 mA input / ~500 mA into the battery on the same
# hardware (chopin-support docs/CHARGING.md).
#
# The port must be able to source it: 900 mA is what the reference port
# validated on a PC USB port.  Override with
#   echo 2000000 > /etc/chopin-charge-limit   (on a dedicated charger)
set -u
LIMIT_FILE=/etc/chopin-charge-limit
CHG=$(ls -d /sys/class/power_supply/mt6360-chg* 2>/dev/null | head -1)
[ -n "$CHG" ] || exit 0

online=$(cat "$CHG/online" 2>/dev/null)
[ "$online" = "1" ] || exit 0

limit=900000
if [ -s "$LIMIT_FILE" ]; then
    limit=$(cat "$LIMIT_FILE" 2>/dev/null)
    [ -n "$limit" ] || limit=900000
fi

# Never ask for more than the hardware allows.
max=$(cat "$CHG/input_current_limit_max" 2>/dev/null)
[ -n "$max" ] || max=$limit
[ "$limit" -le "$max" ] 2>/dev/null || limit=$max

echo "$limit" > "$CHG/input_current_limit" 2>/dev/null || true
# Cap the battery current above what the input can deliver: on a 900 mA port
# this never becomes the limiting factor, on a charger it does.
echo 1500000 > "$CHG/constant_charge_current" 2>/dev/null || true

# The pack's design maximum is 4.46 V; the driver's reset value charges to
# 4.35 V, which the gauge reports as ~89 %.  Use 4.4 V - the vendor's profile
# for this cell - and keep headroom to the design limit.
echo 4400000 > "$CHG/constant_charge_voltage" 2>/dev/null || true

# Lower the end-of-charge current.  With the SDP default the charger sees only
# ~85 mA flowing into the pack, decides the battery is full and terminates at
# ~85 % (that is the "full but only 85 %" symptom).  100 mA is below what the
# 900 mA input can sustain, so termination now really means "full".
echo 100000 > "$CHG/charge_term_current" 2>/dev/null || true

echo "chopin-charge-tune: input=$limit uA charge=1500000 uA (online=$online)"

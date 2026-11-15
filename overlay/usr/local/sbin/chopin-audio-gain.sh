#!/bin/sh
# chopin: set the CS35L41 speaker gain.
#
# Why: the amplifier exposes "Analog PCM Volume" (0..20 = +0.5..+20.5 dB) and
# "Digital PCM Volume" (raw 1..913 = -102..+12 dB, 817 = 0 dB).  Nothing in the
# kernel or userspace sets the analog stage, so it stays at the reset value
# (+0.5 dB) and the speaker is much quieter than the hardware allows.
#
# PipeWire runs with api.alsa.soft-mixer=true for this card (see
# 51-chopin-soft-mixer.conf), so the system slider attenuates in software and
# the hardware gain stays what we set here.
#
# Override: echo 14 > /etc/chopin-audio-gain   (dB = value + 0.5)
set -u
CARD=0
GAIN_FILE=/etc/chopin-audio-gain
DIGITAL=817   # 0 dB; 913 would be +12 dB

gain=20
if [ -s "$GAIN_FILE" ]; then
    gain=$(cat "$GAIN_FILE" 2>/dev/null)
    [ -n "$gain" ] || gain=20
fi

# The card appears a few seconds into boot; give up after 30 s.
i=0
while [ ! -f "/proc/asound/card$CARD/id" ]; do
    i=$((i + 1))
    [ "$i" -gt 30 ] && exit 0
    sleep 1
done

for ctl in "Left Analog PCM Volume" "Right Analog PCM Volume"; do
    amixer -c "$CARD" cset "name='$ctl'" "$gain" >/dev/null 2>&1 || true
done
for ctl in "Left Digital PCM Volume" "Right Digital PCM Volume"; do
    amixer -c "$CARD" cset "name='$ctl'" "$DIGITAL" >/dev/null 2>&1 || true
done

db=$(awk "BEGIN{printf \"%.1f\", $gain + 0.5}")
echo "chopin-audio-gain: analog=$gain (+$db dB), digital=$DIGITAL (0 dB)"

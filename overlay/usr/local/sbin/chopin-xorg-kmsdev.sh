#!/bin/sh
# Point Xorg at the MediaTek display DRM card (chopin / MT6893).
#
# The KMS device is mediatek-drm while the Mali-G77 (panfrost) is render-only;
# Mesa's kmsro pairs the two, so X has to run on the display card.  Xorg
# matches Option "kmsdev" against the /dev node it enumerated itself, so the
# value must be the real path: with a by-path symlink X does not recognise the
# device, adds it a second time as a GPU screen and dies with "Cannot run in
# framebuffer mode".  Card numbers depend on probe order (panfrost probes at
# ~2.8 s, mediatek-drm defers to ~16 s waiting for its components), so the
# snippet is generated at boot instead of hard-coded.
set -eu

src=/dev/dri/by-path/platform-mediatek-drm.7.auto-card
conf=/etc/X11/xorg.conf.d/10-chopin-gpu.conf

# --wait N: give the display controller up to N seconds to appear
if [ "${1:-}" = "--wait" ]; then
    i=0
    while [ ! -e "$src" ] && [ "$i" -lt "${2:-30}" ]; do
        sleep 1
        i=$((i + 1))
    done
fi
[ -e "$src" ] || exit 0

card=$(readlink -f "$src")
body="Section \"Device\"
    Identifier \"MTK-DSI\"
    Driver     \"modesetting\"
    Option     \"kmsdev\" \"$card\"
EndSection"

# leave the file alone when it is already right (no needless rewrites)
if [ -f "$conf" ] && [ "$(cat "$conf")" = "$body" ]; then
    exit 0
fi
mkdir -p "${conf%/*}"
printf '%s\n' "$body" > "$conf.tmp"
chmod 644 "$conf.tmp"
mv "$conf.tmp" "$conf"

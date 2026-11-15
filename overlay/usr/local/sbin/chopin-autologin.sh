#!/bin/sh
# chopin: toggle GDM automatic login.
#
# The image ships with AutomaticLoginEnable=true so the phone boots straight
# into the desktop (there is no keyboard on the device).  Turn it off to get a
# normal login screen.
set -eu
CONF=/etc/gdm3/daemon.conf

action=status
[ $# -ge 1 ] && action=$1

case "$action" in
on|off)
    value=true
    [ "$action" = off ] && value=false
    sed -i "s/^AutomaticLoginEnable=.*/AutomaticLoginEnable=$value/" "$CONF"
    grep -q '^AutomaticLoginEnable=' "$CONF" || sed -i "/^\[daemon\]/a AutomaticLoginEnable=$value" "$CONF"
    echo "autologin: $action (restarting gdm)"
    systemctl restart gdm 2>/dev/null || true
    ;;
status)
    grep -E '^AutomaticLogin' "$CONF" || true
    ;;
*)
    echo "usage: chopin-autologin on|off|status" >&2
    exit 2
    ;;
esac

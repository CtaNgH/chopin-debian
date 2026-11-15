#!/bin/sh
# chopin bring-up diagnostics：关键状态写 /dev/kmsg，随 ramoops 跨重启保留。
K=/dev/kmsg
log() { echo "<6>CHOPIN-DIAG $*" > "$K" 2>/dev/null; }

snap() {
    log "=== t=$1s ==="
    log "udc-list: $(ls /sys/class/udc 2>/dev/null | tr '\n' ' ')"
    for u in /sys/class/udc/*; do
        [ -d "$u" ] || continue
        log "udc $(basename "$u"): state=$(cat "$u/state" 2>/dev/null) cur=$(cat "$u/current_speed" 2>/dev/null) max=$(cat "$u/maximum_speed" 2>/dev/null)"
    done
    log "gadget-configfs: $(ls /sys/kernel/config/usb_gadget 2>/dev/null | tr '\n' ' ')"
    log "ttyGS: $(ls /dev/ttyGS* 2>/dev/null | tr '\n' ' ')"
    log "net: $(ip -br link 2>/dev/null | tr '\n' '|')"
    log "drm: $(ls /sys/class/drm 2>/dev/null | tr '\n' ' ')"
    log "gpu: $(cat /sys/class/devfreq/*/cur_freq 2>/dev/null | tr '\n' ' ')"
    log "usb-dmesg: $(dmesg 2>/dev/null | grep -iE 'mtu3|udc|gadget|panfrost|mediatek-drm' | tail -n 20 | tr '\n' '|')"
}

log "diag start kernel=$(uname -r)"
sleep 5;  snap 5
sleep 10; snap 15
sleep 15; snap 30
log "failed-units: $(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null | tr '\n' '|')"
log "gdm: $(systemctl is-active gdm3 2>/dev/null) session: $(loginctl list-sessions --no-legend 2>/dev/null | tr '\n' '|')"
log "diag done"

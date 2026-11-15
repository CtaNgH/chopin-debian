#!/bin/sh
# chopin: configfs USB gadget（CDC-ACM 串口 + 可选网络：NCM 优先，RNDIS 备用）。
CONF=/sys/kernel/config
G=$CONF/usb_gadget/g1

log() {
    echo "<3>CHOPIN-GADGET: $*" > /dev/kmsg 2>/dev/null
    echo "chopin-gadget: $*" > /dev/tty0 2>/dev/null
}

want_net() {
    if [ "$CHOPIN_GADGET_NET" = "1" ]; then return 0; fi
    [ -f /etc/chopin-gadget-net ] && return 0
    # 旧名字，保留兼容
    [ -f /etc/chopin-gadget-rndis ] && return 0
    return 1
}

has_net() {
    ls "$G/functions" 2>/dev/null | grep -qE '^(ncm|rndis)\.usb0$'
}

# configfs 的属性文件不能 unlink，rm -rf 删不干净：必须按顺序 rm 软链 + rmdir。
teardown() {
    echo "" > "$G/UDC" 2>/dev/null
    sleep 1
    for l in "$G"/configs/c.1/*; do
        [ -L "$l" ] && rm -f "$l"
    done
    for f in acm.usb0 ncm.usb0 rndis.usb0 ecm.usb0; do
        [ -d "$G/functions/$f" ] && rmdir "$G/functions/$f" 2>/dev/null
    done
    rmdir "$G/configs/c.1/strings/0x409" "$G/configs/c.1/strings" "$G/configs/c.1" 2>/dev/null
    rmdir "$G/strings/0x409" "$G/strings" 2>/dev/null
    rmdir "$G/functions" 2>/dev/null
    rmdir "$G" 2>/dev/null
    log "teardown left: $(ls "$CONF/usb_gadget" 2>/dev/null | tr '\n' ' ')"
}

mount -t configfs configfs "$CONF" 2>/dev/null
# 注意：sysfs/configfs 属性文件的 stat 大小恒为 4096，[ -s "$G/UDC" ] 恒真，
# 会把"未绑定"误判成"已绑定"。必须读内容判断。这是 23:28 镜像 USB 不枚举的根因。
is_bound() {
    [ -n "$(cat "$G/UDC" 2>/dev/null)" ]
}

if is_bound; then
    if want_net && ! has_net; then
        log "bound gadget has no network function, rebuilding"
        teardown
    else
        log "gadget already bound to $(cat "$G/UDC"), skip"
        exit 0
    fi
fi
mkdir -p "$G" || { log "cannot create $G"; exit 1; }
echo 0x1d6b > "$G/idVendor"
echo 0x0104 > "$G/idProduct"
echo 0x0200 > "$G/bcdUSB"
mkdir -p "$G/strings/0x409"
echo chopin > "$G/strings/0x409/serialnumber"
echo Xiaomi > "$G/strings/0x409/manufacturer"
echo chopin-mainline > "$G/strings/0x409/product"
mkdir -p "$G/configs/c.1/strings/0x409"
echo "ACM serial" > "$G/configs/c.1/strings/0x409/configuration"

mkdir -p "$G/functions/acm.usb0"
ln -s "$G/functions/acm.usb0" "$G/configs/c.1/" 2>/dev/null

if want_net; then
    # Windows 11 自带 CDC-NCM 驱动（usbncm.inf 匹配 USB Class_02&SubClass_0d&Prot_00），
    # 比 RNDIS 新、不需要 MS OS 描述符；NCM 不可用时退回 RNDIS。
    if mkdir -p "$G/functions/ncm.usb0" 2>/dev/null; then
        echo 02:00:00:00:00:02 > "$G/functions/ncm.usb0/dev_addr" 2>/dev/null
        ln -s "$G/functions/ncm.usb0" "$G/configs/c.1/" 2>/dev/null
        log "ncm requested"
    elif mkdir -p "$G/functions/rndis.usb0" 2>/dev/null; then
        echo 02:00:00:00:00:02 > "$G/functions/rndis.usb0/dev_addr" 2>/dev/null
        ln -s "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
        log "ncm unavailable, rndis requested"
    else
        log "no network function available"
    fi
fi

WAIT=120
if [ -n "$CHOPIN_UDC_WAIT" ]; then WAIT=$CHOPIN_UDC_WAIT; fi
i=0
UDC=""
while [ $i -lt "$WAIT" ]; do
    UDC="$(ls /sys/class/udc 2>/dev/null | head -1)"
    if [ -n "$UDC" ] && ! is_bound; then
        log "bind attempt $i on $UDC funcs=$(ls "$G/functions" 2>/dev/null)"
        if echo "$UDC" > "$G/UDC" 2>/tmp/chopin-bind.err; then
            log "bound $UDC"
            break
        fi
        log "bind failed: $(cat /tmp/chopin-bind.err 2>/dev/null)"
    fi
    is_bound && break
    sleep 2
    i=$((i+2))
done
[ -n "$UDC" ] || { log "no UDC after $WAIT s"; exit 1; }

log "udc=$UDC state=$(cat /sys/class/udc/$UDC/state 2>/dev/null) ttyGS=$(ls /dev/ttyGS* 2>/dev/null | tr '\n' ' ')"

if command -v ip >/dev/null 2>&1; then
    for n in usb0 usb1; do
        [ -d "/sys/class/net/$n" ] || continue
        ip link set "$n" up 2>/dev/null
        ip addr add 192.168.42.2/24 dev "$n" 2>/dev/null
        if command -v dnsmasq >/dev/null 2>&1; then
            [ -f "/tmp/chopin-dnsmasq-$n.pid" ] && kill "$(cat "/tmp/chopin-dnsmasq-$n.pid")" 2>/dev/null
            dnsmasq --interface="$n" --dhcp-range=192.168.42.100,192.168.42.110,12h \
                --port=0 --dhcp-option=3 --dhcp-option=6 --pid-file=/tmp/chopin-dnsmasq-$n.pid 2>/dev/null
            log "dnsmasq started on $n"
        fi
    done
fi
exit 0

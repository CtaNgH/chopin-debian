#!/usr/bin/env bash
# 配置 Debian rootfs：用户、网络、服务、overlay、Mesa pin。可重复执行。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
require_root
[ -d "$ROOTFS" ] || die "先运行 00-mkrootfs.sh"

chroot_mount
trap chroot_umount EXIT
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

write_sources

echo "$CHOPIN_HOSTNAME" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<'CHOPIN_EOF'
127.0.0.1 localhost
127.0.1.1 chopin
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
CHOPIN_EOF

cat > "$ROOTFS/etc/fstab" <<'CHOPIN_EOF'
LABEL=chopinroot / ext4 defaults,noatime 0 1
tmpfs /tmp tmpfs defaults,nosuid,nodev,size=1G 0 0
CHOPIN_EOF

ln -sf /usr/share/zoneinfo/"$CHOPIN_TIMEZONE" "$ROOTFS/etc/localtime"
echo "$CHOPIN_TIMEZONE" > "$ROOTFS/etc/timezone"
echo "en_US.UTF-8 UTF-8" > "$ROOTFS/etc/locale.gen"
echo "zh_CN.UTF-8 UTF-8" >> "$ROOTFS/etc/locale.gen"
in_chroot locale-gen
in_chroot update-locale LANG=en_US.UTF-8

if ! in_chroot id "$CHOPIN_USER" >/dev/null 2>&1; then
    # minbase 可能缺少这些附加组；先补齐，保证 --skip-gnome 也能构建
    for g in sudo audio video render input plugdev netdev; do
        grep -q "^$g:" "$ROOTFS/etc/group" || in_chroot groupadd -r "$g"
    done
    in_chroot useradd -m -s /bin/bash -G sudo,audio,video,render,input,plugdev,netdev "$CHOPIN_USER"
fi
echo "$CHOPIN_USER:$CHOPIN_PASSWORD" | in_chroot chpasswd
echo "root:$CHOPIN_PASSWORD" | in_chroot chpasswd

cp -a "$DEBIAN_DIR/overlay/." "$ROOTFS/"
install -Dm755 "$DEBIAN_DIR/initramfs/chopin-gadget.sh" "$ROOTFS/usr/local/sbin/chopin-gadget.sh"
chmod 755 "$ROOTFS/usr/local/sbin/chopin-diag.sh" "$ROOTFS/usr/local/sbin/chopin-growroot.sh"

mkdir -p "$ROOTFS/etc/apt/preferences.d"
cat > "$ROOTFS/etc/apt/preferences.d/chopin-mesa.pin" <<CHOPIN_EOF
Package: libgl1-mesa-dri
Pin: version $MESA_VERSION
Pin-Priority: 1001
CHOPIN_EOF

if [ -x "$ROOTFS/usr/bin/dconf" ]; then
    in_chroot dconf update
fi

for unit in gdm3 NetworkManager ssh chopin-gadget chopin-diag chopin-growroot \
            chopin-nvt-firmware chopin-xorg-kmsdev; do
    enable_unit "$unit"
done
in_chroot systemctl enable serial-getty@ttyGS0.service || log "跳过 serial-getty@ttyGS0"
in_chroot systemctl set-default graphical.target
ln -sf /dev/null "$ROOTFS/etc/systemd/system/systemd-pstore.service"

# 镜像不携带构建机的 resolv.conf 与 SSH host key
rm -f "$ROOTFS/etc/resolv.conf"
rm -f "$ROOTFS"/etc/ssh/ssh_host_*

# chopin 内核当前没有 zram 模块（CONFIG_ZRAM 未开）：
# mask zramswap，避免每次启动 systemd 进入 degraded。
ln -sf /dev/null "$ROOTFS/etc/systemd/system/zramswap.service"

log "rootfs 配置完成"

#!/bin/sh
# 首次启动把 rootfs 扩到 userdata 分区大小（107 GB）。
FLAG=/var/lib/chopin/grown
[ -e "$FLAG" ] && exit 0
DEV="$(findmnt -n -o SOURCE / 2>/dev/null)"
[ -n "$DEV" ] || exit 0
resize2fs "$DEV" || exit 1
mkdir -p /var/lib/chopin
touch "$FLAG"

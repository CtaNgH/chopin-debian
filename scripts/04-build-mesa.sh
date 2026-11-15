#!/usr/bin/env bash
# 交叉编译 Mali-G77 版 libgallium（Debian 13 的 Mesa 25.0.7-2+deb13u1）。
#
# 做法：Debian 官方 orig.tar.xz + 参考项目的 G77 补丁 + 参考项目的 chopin/build.sh。
# 不走 git clone：GitHub 在当前网络下只有 ~10 KB/s，而 Debian 镜像 ~3 MB/s。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env
require_root

# GPU 用户态已打通（2026-11-15）：内核 panfrost + Mesa kmsro 让 Xorg(glamor)/GLX/EGL
# 都跑在 Mali-G77 上，所以默认安装 G77 版 libgallium。注意这份构建只有 panfrost
# （-Dllvm=disabled，没有 swrast），系统里不再有 llvmpipe 兜底；需要软件渲染时用
# MESA_INSTALL_G77=0 make build。
if [ "${MESA_INSTALL_G77:-1}" != "1" ]; then
    log "跳过 G77 libgallium 替换（MESA_INSTALL_G77=0），保留 Debian 原版 Mesa（llvmpipe）"
    exit 0
fi

MESA_DIR="$DEBIAN_DIR/third_party/mesa"
TARBALL="$BUILD_DIR/mesa_$MESA_SOURCE_VERSION.orig.tar.xz"
VENV="$BUILD_DIR/mesa-venv"
OUTM="$OUT_DIR/mesa"
WORK="$BUILD_DIR/mesa-work"

command -v meson >/dev/null 2>&1 || die "缺少 meson（apt install meson）"
command -v ninja >/dev/null 2>&1 || die "缺少 ninja（apt install ninja-build）"
command -v patch >/dev/null 2>&1 || die "缺少 patch（apt install patch）"
command -v aarch64-linux-gnu-g++-14 >/dev/null 2>&1 || \
    die "缺少 aarch64-linux-gnu-g++-14；apt install g++-14-aarch64-linux-gnu libstdc++-14-dev-arm64-cross"

mkdir -p "$BUILD_DIR" "$OUTM" "$WORK"

if [ ! -f "$TARBALL" ]; then
    log "下载 Mesa 源码：$MESA_TARBALL_URL"
    curl -fL --retry 3 -o "$TARBALL" "$MESA_TARBALL_URL"
fi
echo "$MESA_TARBALL_SHA256  $TARBALL" | sha256sum -c - || die "Mesa 源码 sha256 不匹配"

rm -rf "$MESA_DIR"
mkdir -p "$MESA_DIR"
tar -xJf "$TARBALL" -C "$MESA_DIR" --strip-components=1
echo "$MESA_VERSION" > "$MESA_DIR/VERSION"

mkdir -p "$MESA_DIR/chopin"
cp "$CONFIG_DIR/mesa-build.sh" "$MESA_DIR/chopin/build.sh"
chmod 755 "$MESA_DIR/chopin/build.sh"
( cd "$MESA_DIR" && patch -p1 --batch --forward < "$CONFIG_DIR/0001-panfrost-add-mali-g77.patch" )
grep -q '0x9080' "$MESA_DIR/src/panfrost/lib/pan_props.c" || die "G77 补丁没有生效"

VER="$(cat "$MESA_DIR/VERSION")"
INST="$(in_chroot dpkg-query -W libgl1-mesa-dri | awk '{print $2}')"
[ "$VER" = "$INST" ] || die "mesa VERSION=$VER 与 rootfs 的 libgl1-mesa-dri=$INST 不一致"
[ "$VER" = "$MESA_VERSION" ] || log "警告：VERSION=$VER，versions.env=$MESA_VERSION"

# Mesa 25 需要 meson >= 1.4；Ubuntu 24.04 自带的 1.3 太旧
if [ ! -x "$VENV/bin/meson" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q meson mako packaging pyyaml
fi
export PATH="$VENV/bin:$PATH"
export WORK

# 7 GB 内存下 16 路 C++ 编译容易 OOM
sed -i 's/-j"$(nproc)"/-j8/' "$MESA_DIR/chopin/build.sh"

log "交叉编译 mesa $VER（panfrost，Mali-G77）"
"$MESA_DIR/chopin/build.sh" "$OUTM"

SO="$OUTM/libgallium-$VER.so"
[ -f "$SO" ] || die "构建产物不存在：$SO"
DST="$ROOTFS/usr/lib/aarch64-linux-gnu/libgallium-$VER.so"
[ -f "$DST" ] || die "rootfs 缺少 $DST；先安装 gnome-core"
[ -f "$DST.debian" ] || cp -a "$DST" "$DST.debian"
install -m644 "$SO" "$DST"
sha256sum "$SO" > "$OUTM/SHA256SUMS"
log "已替换 rootfs 的 libgallium：$DST"

# chopin-debian

chopin（Redmi Note 10 Pro 5G / POCO X3 GT，MT6891Z/CZA）的 **Debian 13.7 (trixie) + GNOME 48**
用户空间工程：从 Debian 镜像构建 arm64 rootfs，装入主线内核模块，生成 initramfs、ext4/sparse
镜像和可刷写的 boot.img。

本仓库只保留**构建配方**（版本锁、软件包清单、overlay、initramfs、脚本、文档），
rootfs/镜像/Mesa 源码树等大文件全部在 `.gitignore` 里，可随时重建。

| 项 | 状态 |
| --- | --- |
| rootfs | Debian 13.7 arm64，GNOME 48.7 + gdm3，1067 包（2026-11-15 验证） |
| 内核模块 / initramfs | 可用；release 从内核工作树动态读取 |
| Mesa | 默认交叉编译 **Mali-G77 (panfrost)** 版 libgallium；`MESA_INSTALL_G77=0` 回退 Debian 原版（llvmpipe） |
| 桌面 | GNOME 48.7 走 **Wayland**（mutter + EGL/GBM + kmsro + panfrost）；X11 下 mutter 不出帧 |
| 触摸 | NVT36672C 固件自愈服务 + 驱动时序修复；Y 轴镜像问题已修复并在实机验证 |
| USB 网络 | configfs gadget：CDC-ACM 串口 + **CDC-NCM** 网卡（usb0 = 192.168.42.2/24 + dnsmasq）；Windows 11 自带 usbncm 驱动，SSH 免密可用 |
| WiFi | WLAN-GEN4 内置驱动 + vendor 固件 + nvdata 里的 NVRAM；wlan0 连 5 GHz，apt 实测 1.8 MB/s |
| 音频 | MT6893/MT6359/CS35L41 声卡（card 0 mt6893_mt6359），扬声器播放正常；PipeWire + WirePlumber，软件音量 |
| 时间 | RTC 没有电池，systemd-timesyncd 启动后校准（否则 TLS/apt 全挂） |
| 镜像 | ext4 + Android sparse + `boot-chopin-debian.img` |
| 实机 | Debian 13.7 + GNOME 48.7（Wayland，1080×2400@120，缩放 2.5）；触摸、串口、USB 网络/SSH、WiFi、扬声器正常 |
| 许可 | MIT（脚本/overlay）；Debian 软件包保留各自许可 |

> 构建手册是本文；当前状态与阻塞见 [docs/PLAN.md](docs/PLAN.md)；
> 实机现场记录见 [docs/BRINGUP.md](docs/BRINGUP.md)；完整 v1 方案见 [docs/debian.md](docs/debian.md)。
> 内核部分在独立仓库 [chopin-kernel](../kernel)。

---

## 1. 目录

```
chopin-debian/
├── config/
│   ├── versions.env        # 唯一版本来源（Debian/Mesa/镜像/用户）
│   ├── packages.base       # minbase 之外的基础包
│   ├── packages.gnome      # GNOME 桌面包
│   ├── sources.list.in     # apt 源模板
│   ├── mesa-build.sh       # 参考项目的 Mesa 交叉编译脚本
│   ├── 0001-panfrost-add-mali-g77.patch
│   └── debian-archive-keyring.gpg
├── scripts/
│   ├── lib.sh              # 路径/版本/chroot 公共函数
│   ├── 00-mkrootfs.sh      # mmdebstrap minbase
│   ├── 01-install-desktop.sh
│   ├── 02-configure-rootfs.sh
│   ├── 03-install-kernel.sh
│   ├── 04-build-mesa.sh    # 默认跳过 G77 替换
│   ├── 05-mkinitramfs.sh
│   ├── 06-mkrootfs-image.sh
│   ├── 07-mkbootimg.sh
│   ├── build-all.sh
│   ├── mk-sparse.py
│   └── flash.ps1           # Windows 侧刷机示例
├── initramfs/
│   ├── init                # busybox PID1
│   ├── chopin-gadget.sh    # configfs USB gadget
│   └── experiments/        # 历史 debug/rescue 变体
├── overlay/                # 直接覆盖进 rootfs 的文件
├── docs/
├── build/                  # rootfs 与缓存（忽略）
├── out/                    # 镜像产物（忽略）
└── third_party/            # Mesa 源码（忽略）
```

## 2. 构建主机

WSL2 Ubuntu 24.04 / 16 核 / 8 GB 内存 / 20 GB 磁盘：

```bash
sudo apt-get install -y mmdebstrap qemu-user-static binfmt-support debootstrap \
  cpio gzip xz-utils zstd rsync e2fsprogs mtools \
  meson ninja-build pkg-config dpkg-dev python3-venv git \
  gcc-aarch64-linux-gnu g++-14-aarch64-linux-gnu libstdc++-14-dev-arm64-cross
```

需要 `/proc/sys/fs/binfmt_misc/qemu-aarch64` 已注册（`update-binfmts --enable qemu-aarch64`）。
`04-build-mesa.sh` 需要 meson >= 1.4 与 g++-14 交叉编译器；默认不启用。

## 3. 快速开始

先构建内核（见 [chopin-kernel](../kernel)）：

```bash
cd chopin-linux/kernel
make bootstrap
make build
```

再构建用户空间。所有脚本需要 root（mmdebstrap/chroot/mount）：

```bash
cd chopin-linux/debian
sudo make build
```

等价的分步方式：

```bash
sudo ./scripts/00-mkrootfs.sh
sudo ./scripts/01-install-desktop.sh
sudo ./scripts/02-configure-rootfs.sh
sudo ./scripts/03-install-kernel.sh
sudo ./scripts/04-build-mesa.sh
sudo ./scripts/05-mkinitramfs.sh
sudo ./scripts/06-mkrootfs-image.sh
sudo ./scripts/07-mkbootimg.sh
```

可选参数：

| 参数 | 作用 |
| --- | --- |
| `--skip-gnome` | 只做 minbase + 基础配置（调试构建链用） |
| `--skip-mesa` | 跳过 G77 `libgallium`（默认行为） |
| `--rebuild` | 删除已有 rootfs 后从零构建 |

产物：

| 文件 | 说明 |
| --- | --- |
| `out/chopin-rootfs.img` | ext4（resize2fs -M 后的最小尺寸） |
| `out/chopin-rootfs.sparse.img` | Android sparse，32 位 fastboot 可刷 |
| `out/initramfs.cpio.gz` | busybox initramfs |
| `out/boot-chopin-debian.img` | 内核 + initramfs 的 boot.img |
| `out/SHA256SUMS` | 以上产物的校验和 |

## 4. 原厂镜像与刷机

仓库**不包含**原厂 boot/dtbo（版权与体积原因）。请自行备份并放到顶层：

```
chopin-linux/stock/
├── boot_a.img
├── dtbo_a.img
└── ...
```

`07-mkbootimg.sh` 默认读取 `stock/boot_a.img`，也可以用 `STOCK_BOOT=/path/boot_a.img` 覆盖。

刷机（Windows）：

```powershell
cd D:\chopin-linux
.\scripts\windows\flash-debian.ps1
```

注意：

- `userdata` 会被整段覆盖，Android 数据不可恢复；
- 32 位 fastboot 无法刷 >2 GB 的 raw 镜像，必须用 sparse；
- 设备是 A/B：中断后可能切到 `_b`，用 `fastboot --set-active=a` 恢复。

## 5. 版本锁

`config/versions.env` 是唯一版本来源，所有变量都可用环境变量覆盖：

- `DEBIAN_SUITE=trixie`，`DEBIAN_RELEASE=13.7`；
- `MESA_VERSION=25.0.7-2+deb13u1` —— 必须等于 rootfs 里 `libgl1-mesa-dri` 的版本，
  否则 `libEGL_mesa` 的符号版本对不上；
- `MESA_TARBALL_URL/SHA256` —— Debian 官方 orig tarball，本地缓存并校验；
- 内核 release **不写死**：`03-install-kernel.sh` 从
  `../kernel/linux/include/config/kernel.release` 读取；
- 用户/密码默认 `chopin/chopin`，可用 `CHOPIN_USER` / `CHOPIN_PASSWORD` 覆盖。

## 6. 可重复构建

```bash
sudo make clean          # 删除 build/ out/ third_party/
sudo make build          # 从 Debian 镜像重新构建
```

- `00-mkrootfs.sh` 看到 `build/rootfs/etc/debian_version` 会跳过；`--rebuild` 强制重建；
- `02` / `03` / `05` / `06` / `07` 都是幂等的，可单独重复执行；
- Mesa 源码在 `third_party/mesa`，可用 `MESA_INSTALL_G77=1` 重新交叉编译；
- 依赖只来自 Debian 镜像与固定版本的 Mesa tarball，不依赖 GitHub 实时状态。

## 7. 故障排查

| 现象 | 先看 | 处理 |
| --- | --- | --- |
| 卡 logo，无输出 | 串口、pstore | 换回原厂 boot；确认 initramfs 已打包 |
| initramfs 找不到 rootfs | 启动打印的 label/设备 | 确认 userdata 已刷 sparse；`blkid` 看 LABEL |
| 进 multi-user 但无图形 | `journalctl -u gdm3` | 先 `modetest` / `eglinfo` / `kmscube` 分层定位 |
| eglinfo 显示 llvmpipe | `libgallium` 版本 | `dpkg -W libgl1-mesa-dri`；默认就是 llvmpipe |
| gdm 反复重启 | gdm 日志 EGL/GBM | 当前用 X11；`WaylandEnable=false` 已写入 overlay |
| USB 无串口 | `/sys/class/udc`、`dmesg` | 看 `chopin-gadget` 日志；确认 UDC 已 bind |
| 无 WiFi | `ip link`、`dmesg` | 缺 NVRAM；先用 RNDIS/SSH |

## 8. 已知限制

- 显示栈是 vendor `mediatek_v2`，GBM/Wayland 尚未打通，当前 X11 + llvmpipe；
- panfrost 时钟/复位未修，无 `renderD128`；
- 触摸 NVT IRQ 不触发；
- WiFi/BT 缺 NVRAM；音频/相机未验证；
- 充电/电量依赖 MT6360，i2c5 问题未修。

## 9. 许可

脚本、overlay、文档以 **MIT** 发布（见 `LICENSE`）；通过 apt 安装的 Debian 软件包、
Mesa 源码及厂商固件保留其原始许可，再分发前请自行确认。

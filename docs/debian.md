# chopin Debian 13 + GNOME 实施方案（v2，适配三仓库布局）

> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC，MT6891Z/CZA，Dimensity 1100）
> 内核：Linux 7.3.4 + 25 个补丁（见 [chopin-kernel](../../kernel)）
> 目标：Debian 13.7 trixie + GNOME 48.7 + Mesa 25.0.7-2+deb13u1
> 更新：2026-11-15

> 本文是当前有效方案。2026-11-14 的 v1 全文（含更多推演、时间表、风险表）已归档在顶层
> [docs/archive/docs-debian-2026-11-15.md](../../docs/archive/docs-debian-2026-11-15.md)。

---

## 1. 目标与验收

在 chopin 上得到一个可日常使用的 Debian + GNOME：

- 从 LK 正常引导，不依赖 Android 用户空间；
- 1080×2400 DSI 屏点亮，GNOME 会话可登录、可交互；
- 触摸、电源/音量键、USB 串口控制台可用；
- 系统可重复构建（一条命令出 rootfs 镜像 + boot.img）；
- 内核与用户空间的版本、模块、Mesa 版本可追溯。

| 里程碑 | 内容 | 当前状态 |
| --- | --- | --- |
| M0 构建链 | rootfs 可 chroot、可装包 | ✅ 完成 |
| M1 首启 | 内核 → initramfs → ext4 → systemd，串口可登录 | ✅ 完成（2026-11-15） |
| M2 图形 | KMS + EGL + GPU | 🔶 KMS ✅、llvmpipe ✅、panfrost ❌ |
| M3 桌面 | GDM + GNOME 会话，可交互 | 🔶 X11 桌面 ✅、触摸 ❌ |
| M4 日常 | 网络、WiFi、电源、音频 | ⬜ 未开始 |

## 2. 启动与图形数据流

```
LK (boot_a)
  └─ boot.img = Image.gz + busybox initramfs
       └─ initramfs/init
            ├─ 挂 pstore，打印上次启动 ramoops 摘要
            ├─ configfs 建 USB gadget（CDC-ACM，可选 RNDIS）
            ├─ 等 UFS，按 LABEL=chopinroot 挂 /dev/sdc75
            └─ switch_root → systemd (Debian 13.7)

systemd
  ├─ gdm3 → Xorg → gnome-shell (X11 + llvmpipe)
  ├─ NetworkManager → usb0 (RNDIS) / wlan0 (待固件)
  ├─ chopin-gadget.service（每次启动重建 gadget，幂等）
  ├─ chopin-diag.service（USB/DRM/GPU 状态写 /dev/kmsg）
  └─ chopin-growroot.service（首次启动把 ext4 扩到分区大小）
```

运行时设备树由内核内嵌的 `chopin-board.dtb` 覆盖，boot.img 的 dtb 段只影响 LK 阶段；
cmdline 由 `CONFIG_CMDLINE_FORCE` 强制。详见 [kernel/docs/kernel.md](../../kernel/docs/kernel.md)。

## 3. 关键决策

| # | 决策 | 备选 | 理由 |
| --- | --- | --- | --- |
| D1 | Debian 13.7 trixie | Debian 12 + backports | Mesa 25.0.7 与参考 mesa 树一致；GNOME 48.7；5 年支持 |
| D2 | 保留 LK + boot.img | Mu-Silicium UEFI | LK 路径已实测；UEFI 引入 ESP/显示初始化等新变量 |
| D3 | ext4 写到 userdata（LABEL=chopinroot） | 新建分区；SD 卡 | userdata 107 GB 可用；不动其他分区 |
| D4 | vendor mediatek_v2 + panfrost | 主线 mtk-drm；纯 fbdev | vendor 栈已出图；mainline 无 MT6893 支持 |
| D5 | 替换单个 libgallium | 重编 Mesa .deb | 文件名/符号版本约束明确，风险最小 |
| D6 | 自建 busybox initramfs | initramfs-tools/dracut | 需要 pstore 摘要、gadget、按 label 挂 rootfs |
| D7 | 先 gnome-core，后 task-gnome-desktop | 一次装完整 task | 首启只验证会话，失败时易定位 |
| D8 | 固件后置 | 首启即追 WiFi | 首启不依赖网络；串口/RNDIS 足够调试 |

显示退路顺序：mutter Wayland + GBM + panfrost → X11 + llvmpipe（当前）→ GNOME Flashback
→ Weston/cage 验证 KMS。只有最后一步也失败，才需要动内核显示栈。

## 4. 仓库布局

三个独立 Git 仓库，由顶层 `chopin-linux` 用 submodule 固定版本：

| 目录 | 仓库 | 内容 |
| --- | --- | --- |
| `kernel/` | chopin-kernel | 25 个补丁、defconfig、build/bootimg 脚本、内核文档 |
| `debian/` | chopin-debian | 本仓库：rootfs/桌面/initramfs/镜像 |
| 顶层 | chopin-linux | README、docs、Makefile、Windows 辅助脚本、submodule 锁 |

```
chopin-linux/
├── kernel/          # submodule
├── debian/          # submodule
├── stock/           # 原厂镜像（忽略，不随仓库分发）
├── out/             # 汇总产物（忽略）
├── docs/
└── scripts/
```

## 5. 构建流程

| 脚本 | 作用 | 关键点 |
| --- | --- | --- |
| 00-mkrootfs.sh | mmdebstrap minbase | Debian 13 keyring；arm64 + qemu binfmt |
| 01-install-desktop.sh | chroot 内 apt 安装桌面 | gnome-core + gdm3 + 字体/工具 |
| 02-configure-rootfs.sh | 用户/网络/服务/overlay/dconf | 幂等；仅 enable 存在的单元 |
| 03-install-kernel.sh | 模块 + Image + dtb | release 从内核工作树读取 |
| 04-build-mesa.sh | 交叉编译 G77 libgallium | 默认跳过；`MESA_INSTALL_G77=1` 启用 |
| 05-mkinitramfs.sh | busybox cpio.gz | 从 rootfs 取 busybox，init 在仓库 |
| 06-mkrootfs-image.sh | ext4 + sparse | mkfs.ext4 -d，e2fsck，mk-sparse |
| 07-mkbootimg.sh | boot.img | 不传 --dtb，保留原厂 dtb 段 |

完整命令：

```bash
cd chopin-linux/kernel && make bootstrap && make build
cd ../debian && sudo make build
```

## 6. 测试矩阵

| 层 | 命令 | 期望 | 失败处置 |
| --- | --- | --- | --- |
| 构建 | `qemu-aarch64-static chroot rootfs /bin/true` | 返回 0 | 检查 binfmt/动态库 |
| 首启 | 串口/tty0 | 出现 login | 看 initramfs 打印、ramoops |
| systemd | `systemctl is-system-running` | running/degraded | `journalctl -xb` |
| 显示 | `modetest -M mediatek -c` | DSI-1 1080×2400 | 检查 mediatek_v2 绑定 |
| EGL | `eglinfo -B` | llvmpipe（当前） | 检查 libgallium 版本 |
| GPU | `kmscube` | 稳定 10 分钟 | 锁频/看 dmesg（panfrost 未通） |
| 桌面 | `loginctl session-status` | X11 会话 | 切 Wayland/Flashback |
| 触摸 | `evtest` | ABS_MT 事件 | 查 NVT IRQ/固件 |
| USB | `cat /sys/class/udc/*/state` | configured | 看 gadget 日志 |
| 网络 | `ip -br a` | usb0 有地址 | 开 RNDIS/查 DHCP |

## 7. 风险

| # | 风险 | 影响 | 缓解 |
| --- | --- | --- | --- |
| R1 | Wayland/GBM 不可用 | 只能 X11 | X11 已可用；评估 mainline mtk-drm |
| R2 | panfrost 修不好 | 无 GPU 加速 | llvmpipe 退路已可用 |
| R3 | 触摸不工作 | 无法交互 | 修固件/中断；USB 键鼠兜底 |
| R4 | 无网络 | 无法在线装包 | 串口/RNDIS 传输；离线 .deb |
| R5 | MT6360 充电不工作 | 电池耗尽 | 保持 USB 供电；优先修 i2c5 |
| R6 | 32 位 fastboot 限制 | 刷机失败 | 使用 2.9 GB sparse 镜像 |

## 8. 参考

- 内核参考：<https://github.com/MT6891-Mainline/linux>（`7.3.3-mt6893-xiaomi-chopin`）
- Mesa 参考：<https://github.com/MT6891-Mainline/mesa>
- UEFI 备选：<https://github.com/MT6891-Mainline/Mu-Silicium>
- Debian 13：<https://www.debian.org/releases/trixie/>
- 构建命令： [../README.md](../README.md)
- 当前状态： [PLAN.md](PLAN.md)

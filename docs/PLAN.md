# chopin Debian 当前执行计划

> 更新时间：2026-11-15
> 内核：Linux 7.3.4 + 20 个补丁；用户空间：Debian 13.7 + GNOME 48.7
> 构建：[../README.md](../README.md)；方案：[debian.md](debian.md)；现场记录：[BRINGUP.md](BRINGUP.md)

## 0. 一句话

M0（构建链）、M1（实机首启 + 串口控制台）完成；M2 图形到"能进桌面"（X11 + llvmpipe，
1080×2400，GNOME 48）；**GPU（panfrost）与触摸仍是内核侧阻塞项**。

## 1. 实机已验证

| 项 | 状态 | 证据 |
| --- | --- | --- |
| 内核/引导 | ✅ | `uname -a` = 7.3.4-g…；LK 正常引导 |
| rootfs | ✅ | `/dev/sdc75` ≈106 GB ext4，`/etc/debian_version`=13.7 |
| systemd | ✅ | `systemctl is-system-running` = running |
| USB gadget | ✅ | `g1/UDC`=11201000.usb，`state`=configured，`/dev/ttyGS0` 可登录 |
| 串口控制台 | ✅ | Windows COM11 @115200 8N1 |
| 显示 | ✅ | DRM `card0-DSI-1` connected；1080×2400 |
| 桌面 | ✅ | gdm + Xorg + gnome-shell 48.7，自动登录 chopin |
| 渲染 | ⚠️ | EGL llvmpipe；无 GPU |
| GPU panfrost | ❌ | probe -110：reset timeout、bus_clock=0、无 renderD128 |
| 触摸 | ❌ | NVT probe 成功、IRQ33 注册，但中断计数 0 |
| 网络 | ❌ | 仅 lo；RNDIS 未启用，WiFi 无 NVRAM |
| SSH | ✅（本机） | host key 首次启动生成 |

## 2. 已修复并固化

1. **USB gadget 不枚举**：`[ -s "$G/UDC" ]` 对 configfs 属性恒真 → 改为读内容。
   修复后 initramfs 绑定成功，systemd 服务看到已绑定会 skip。
   见 [../../kernel/docs/kernel.md](../../kernel/docs/kernel.md) 5.7。
2. **GDM TRAP**：GNOME 48 的 Debian 包只有 wayland-sessions，没有 xsessions；
   补 `/usr/share/xsessions/gnome.desktop` + `WaylandEnable=false` 后 X11 桌面可用。
3. **EGL 全平台失败**：G77 libgallium 只有 panfrost、无 swrast；恢复 Debian 原版后 llvmpipe 可用。
   `04` 默认跳过替换，等 GPU 修好再开。
4. **ssh.service 失败**：单元第一条 ExecStartPre 是 `sshd -t`，无 host key 时先失败；
   drop-in 清空后按 `ssh-keygen -A` → `sshd -t` 重排。
5. **zramswap 失败**：内核没编 zram；构建时 mask。
6. **构建树与实机不一致**：gdm mask、default.target 等已写回 overlay/脚本。

## 3. 当前阻塞

### 3.1 触摸（最高优先，决定"可交互"）

- probe 正常：chip id、input 设备、IRQ 33 都成功；
- `/proc/interrupts` IRQ 33 恒 0；`evtest` / `libinput debug-events` 无事件；
- `/sys/kernel/debug/gpio`：`gpio-19 (NVT-int) in lo IRQ ACTIVE LOW`；
- DT：`novatek,irq-gpio = <&pio 0x13 0x2001>`，驱动 `int_trigger_type=1`。

排查顺序：

1. 触发类型/极性：EDGE vs LEVEL、ACTIVE LOW 是否符合芯片实际 INT 行为；
2. EINT19 pinctrl 复用是否被占用、是否输入上拉；
3. 固件：从 `/vendor/firmware` / nvdata 提取 `novatek_nt36672c_k10a_fw01.bin`；
4. 通过 `/proc/NVTSPI` 或临时 print 确认芯片是否在扫描并拉低 INT。

验收：`evtest /dev/input/event2` 有 ABS_MT 事件，GNOME 点击/滑动生效。

### 3.2 GPU / panfrost

- 首次 probe mtcmos -517（audio-controller 未 probe）；重载后仍 reset timeout、
  `bus_clock rate = 0`、`chopin: no core_clk_rate knob` → probe -110；
- 结论：电源域已就绪，阻塞在 GPU 时钟/复位。

方向：对齐 mt6893 clk 驱动的 mfg/bus clock id；确认复位前 mfg 电源域已上电；
修好后用 `-Dgallium-drivers=panfrost,swrast` 重建 libgallium（保留 llvmpipe 兜底）。

验收：`/dev/dri/renderD128` 出现；`eglinfo -B` 显示 Mali-G77；`kmscube` 稳定。

### 3.3 网络 / 电源 / 音频

1. RNDIS：`touch /etc/chopin-gadget-rndis` → 重启 gadget → Windows 192.168.42.100/设备 .2；
2. WiFi：从 nvdata 提取 `mediatek/mt6893/WIFI` + BT 固件，恢复 pre-cal 等待；
3. 充电/电量：修 i2c5 上 MT6360（subpmic_pmic/ldo、tcpc），接 upower；在此之前保持 USB 供电；
4. 音频：ASoC + UCM + pipewire（当前 pipewire-pulse 有 dbus 错误）。

## 4. 下一步（按顺序）

1. ⏭ 触摸：提取 NVT 固件 / 调 DT 触发类型 → 重建内核 → 只刷 boot → evtest 验证；
2. ⏭ GPU：修 panfrost 时钟/电源 → renderD128 → eglinfo/kmscube；
3. ⏭ Mesa 全量 libgallium（panfrost+swrast）→ 尝试 Wayland；
4. ⏭ RNDIS/SSH 网络 → WiFi NVRAM → MT6360 充电 → 音频；
5. ⏭ 桌面打磨、稳定性、文档与上游化。

## 5. 复现命令（新布局）

```bash
# 内核
cd /root/chopin-linux/kernel
make bootstrap
make build

# 用户空间
cd /root/chopin-linux/debian
sudo make build            # 完整构建
sudo make build ARGS='--rebuild'   # 强制重建 rootfs
```

刷机：`D:\chopin-linux\scripts\windows\flash-debian.ps1`（先备份原厂 boot/dtbo）。

## 6. 文件索引

- 构建手册：[../README.md](../README.md)
- 方案：[debian.md](debian.md)
- 现场记录：[BRINGUP.md](BRINGUP.md)
- 历史构建手册：[README-2026-11-14.md](README-2026-11-14.md)
- initramfs 实验变体：[../initramfs/experiments/](../initramfs/experiments/)

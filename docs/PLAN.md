# chopin Debian 13 (Trixie) + GNOME 适配方案 v2（基于实机状态）

> 更新时间：2026-11-15 04:30
> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，MT6891Z/CZA）
> 说明：现场记录，`<workdir>` 代表当时的私有工作目录；公开仓库布局见 [../README.md](../README.md)。
> 内核：Linux 7.3.4 + 18 补丁（分支 chopin，release 7.3.4-g5775fb2ac0a1-dirty，`boot-chopin-p0.img`）
> 用户空间：Debian 13.7 (trixie) + GNOME 48.7 + Mesa 25.0.7-2+deb13u1
> 本文是**当前状态下的执行方案**；构建细节见 [../README.md](../README.md)，内核细节见
> [../../kernel/docs/kernel.md](../../kernel/docs/kernel.md)，现场记录见 [BRINGUP.md](BRINGUP.md)。

---

## 0. 一句话

**M0（构建链）、M1（实机首启 + 串口控制台）、触摸（NVT 固件自愈）、GPU 用户态
（Mali-G77 + kmsro + Wayland，1080×2400@120，桌面正常）已完成并实机验证。
当前最高优先级只剩 P0：偶发 SError panic（内核/内存布局），桌面负载下仍会重启。
触摸坐标有小偏差（P1-d，待量化）。**

---

## 1. 实机已验证状态（2026-11-15 00:30）

| 项 | 状态 | 证据 |
| --- | --- | --- |
| 内核/引导 | ✅ 正常 | `uname -a` = 7.3.4-ga9777a8559e0-dirty #10，LK 正常引导 |
| rootfs | ✅ | `/dev/sdc75` 106G ext4，`/etc/debian_version`=13.7 |
| systemd | ✅ running | `systemctl is-system-running` = **running**（无失败单元） |
| USB gadget | ✅ | `g1/UDC`=11201000.usb，`state`=**configured**，`/dev/ttyGS0` 可登录 |
| 串口控制台 | ✅ | Windows COM11 @115200 8N1；chopin/chopin（root 同密码） |
| 显示 | ✅ | DRM `card0-DSI-1` connected；xrandr 1080×2400（120Hz 模式） |
| 桌面 | ✅ | gdm.service + Xorg :0 + gnome-shell 48.7，自动登录 chopin |
| 渲染 | ⚠️ llvmpipe | EGL Surfaceless: llvmpipe (LLVM 19.1.7)；GBM/Wayland 不可用 |
| GPU panfrost | ❌ | probe -110：GPU soft/hard reset timeout、bus_clock=0、no core_clk_rate knob；无 renderD128 |
| 稳定性 | ❌ | X11 桌面下数分钟偶发 SError panic（ramoops 已取），UFS/显示 I/O 相关，见 P0 |
| 触摸 | ✅ | NVT 固件自愈后 IRQ33 正常计数，evtest 有真实 ABS_MT 事件（根因与修复见 §2.7） |
| 网络 | ❌ 仅 lo | RNDIS 未启用、WiFi 无 NVRAM |
| SSH | ✅（本机） | ssh.service active；自动生成 host key；无网络前仅本机可用 |

---

## 2. 本轮已定位并修复的问题（已固化进构建树/镜像）

1. **USB gadget 完全不枚举（M1 阻塞）**
   - 根因：幂等判断用 `[ -s "$G/UDC" ]`。sysfs/configfs 属性文件 stat 大小恒为 4096，
     `-s` 恒真 → 脚本误判"已绑定"直接跳过绑定。
   - 修复：改为读内容 `is_bound() { [ -n "$(cat "$G/UDC" 2>/dev/null)" ]; }`（debian/initramfs/chopin-gadget.sh）。
   - 验证：刷入后 initramfs 绑定成功，Windows 出现 COM11 + Debian 登录提示。
2. **GDM 启动即 abort（TRAP）**
   - 根因：`GdmSession: no session desktop files installed`。GNOME 48 的 Debian 包只带
     `/usr/share/wayland-sessions`，X11 会话文件缺失；而我们强制 WaylandEnable=false。
   - 修复：overlay 增加 `/usr/share/xsessions/gnome.desktop`（Exec=gnome-session），
     `/etc/gdm3/daemon.conf` 设 WaylandEnable=false。
3. **EGL 全平台初始化失败（连 llvmpipe 都没有）**
   - 根因：G77 版 libgallium 来自参考项目 build.sh，配置是 `-Dgallium-drivers=panfrost -Dllvm=disabled`，
     不含 swrast/kms_swrast；替换 Debian 原版后 EGL 无可加载驱动。
   - 修复：恢复 Debian 原版 libgallium（35 MB，llvmpipe 可用）；`04-build-mesa.sh` 默认跳过替换，
     仅 `MESA_INSTALL_G77=1` 时才构建安装（等 GPU 内核侧修好后再开）。
4. **ssh.service 每次启动失败**
   - 根因：Debian 单元第一条 ExecStartPre 是 `sshd -t`，无 host key 时先失败，
     追加的 `ssh-keygen -A` 永远轮不到执行。
   - 修复：drop-in 里 `ExecStartPre=` 清空后按 `ssh-keygen -A` → `sshd -t` 重排。
5. **zramswap.service 失败**
   - 根因：内核没有编入 zram（`CONFIG_ZRAM` 未开）。修复：build 时 mask；后续可改 CONFIG_ZRAM=m。
6. **构建产物与实机不一致**：`gdm3` 曾被手工 mask、`default.target` 手工改 multi-user——
   已写回构建树（overlay + 02/04 脚本 + build/rootfs），镜像可复现。
7. **触摸完全不工作（P1-a，2026-11-15 02:20 解决）**
   - 根因：NVT36672C 是 host-download 触摸 IC，冷启动后芯片里没有可用固件；原厂内核每次
     启动都会把 `novatek_nt36672c_k10a_fw01.bin` 通过 SPI 下载进芯片。mainline 的
     linux-firmware 没有该文件，于是驱动 probe 正常、IRQ 注册成功，但芯片不扫描、
     INT 线不触发（IRQ 33 计数恒 0，evtest 无事件）。
   - 固件来源：设备原厂 **vendor 逻辑分区**（物理 `super` 分区内，`/firmware/novatek_nt36672c_k10a_*.bin`）；
     用 `scripts/lp.py` 解析 liblp 元数据 + `losetup -r --offset ...` 只读挂载提取。
   - 固化：`debian/overlay/usr/local/sbin/chopin-nvt-firmware.sh` +
     `chopin-nvt-firmware.service`（幂等，首启自动提取；已 probe 过则 unbind/rebind
     触发下载）。离线构建可把固件预置到 `debian/third_party/firmware/`。
   - 验证：`Update firmware success!`、fw_ver=11、PID=0x5950、IRQ 33 正常计数、
     `evtest /dev/input/event2` 有真实 ABS_MT 事件；冷启动自动恢复。固件 sha256 见
     [README.md §1.1](README.md)。

### 当前镜像（2026-11-15 00:30 构建）

| 产物 | sha256 |
| --- | --- |
| `out/boot-chopin-debian.img`（19 MB） | `9a46cef3ef69e6740b7608074db73652f99e5fbf9fa5d15ee653f079ace5d1e8` |
| `out/chopin-rootfs.sparse.img`（2.9 GB） | `9b0652b23504feca52bed854665c7342deecced6030af5b35f866de5016f0eef` |

> 诊断镜像 `out/boot-chopin-probe.img`、`out/boot-chopin-rescue-probe.img` 保留，用于无串口时取证。

---

## 3. 验收标准（沿用 docs-debian.md，更新状态）

| 里程碑 | 内容 | 状态 |
| --- | --- | --- |
| M0 | rootfs/构建链可 chroot、可装包 | ✅ 完成 |
| M1 | 内核→initramfs→ext4→systemd，串口可登录 | ✅ 完成（2026-11-15 00:10 实机） |
| M2 | KMS + EGL + GPU：modetest/eglinfo/kmscube | 🔶 KMS ✅；EGL/llvmpipe ✅；GPU ❌ |
| M3 | GDM + GNOME 会话：自动登录、可交互 | 🔶 桌面 ✅；触摸 ✅；受 P0 SError 稳定性影响 |
| M4 | 网络、WiFi、电源、音频等日常可用 | ⬜ 未开始 |

---

## 4. 后续方案（按优先级）

### P0 稳定性：SError panic —— **候选修复已刷入，但 SError 仍复现（2026-11-15 04:20）**

> **最新结论：reserved-memory 按 LK 修正并没有根除 SError。** GPU 桌面（Wayland + panfrost）
> 跑了约 30 分钟后设备重启一次；boot 后 pstore 里仍是旧记录（483 s 的 `0xbe000411`），
> 而且上一次 panic 写 pstore 时报 `writing error (-28)`（ramoops 满），所以这次重启的
> 证据没有落盘。已 `rm /sys/fs/pstore/*` 清空，下次重启第一件事是取 ramoops 对比。
> 下一步：① 抓一次干净的新 panic；② 按 §BT§analysis/ufs-serror.md§BT§ §7 的实验矩阵继续；
> ③ 若仍是 §BT§0xbe000411§BT§（clear_page/首次触碰），重点回到「哪块 DRAM 其实不存在」而不是 UFS。
>
> **第二个候选修复（2026-11-15 04:30，已构建待刷）**：把 mblock-26 与 mblock-27 之间
> 237.25 MiB（§BT§0xe9b10000..0xf8850000§BT§）按 §BT§no-map§BT§ 保留——LK 的 mblock 表没描述它，
> 但首次触碰会总线中止。镜像 §BT§out/boot-chopin-touch.img§BT§（同一次刷机还带触摸修复）。
> 若刷入后 SError 消失，说明问题就是这块空档；若仍复现，改用「按页扫内存 + 记录 PFN」的办法定位。

> **进展**：用新内核的 CHOPIN-LKDT dump 拿到了 LK 真实内存布局，发现板级 DTS 的
> mblock-24/25/26/27 与 LK 相差 32 MiB、mblock-29/30 位置错误、mblock-1/2 是 8 GiB 版本
> 地址。已按 LK 值修正（commit `14266aef5`），并把可疑 32 MiB 窗口（0xf8850000，
> 正好覆盖旧 SWIOTLB bounce pool 的上半段）纳入保护。
> 新内核（`out/boot-chopin-p0.img`，release `7.3.4-g5775fb2ac0a1-dirty`）已刷入：
> 2.5 GiB 内存压力测试无 SError/无 UFS 错误；GNOME 桌面运行 5 分钟+ 无 panic
> （旧内核 1–3 分钟必崩）。继续观察 30 分钟+。

#### 原分析与排查方向（保留）

现象（ramoops 实机证据）：
- X11 桌面（gnome-shell）运行 1–3 分钟后随机 panic：`SError Interrupt on CPUx, code
  0x00000000be000411`，栈为 `clear_page`（缺页清零新页）/ 另一次为 `python3` 写 ext4 时
  `__arch_copy_from_user`（code 0xbe000011）；
- 其中一次 panic 前 300+ 次 `ufshcd-mtk: ufshcd_check_errors: saved_err 0x30004
  saved_uic_err 0x2` 刷屏 + host_regs dump；另一次没有 UFS 错误，只有 display
  `mtk_plane_atomic_disable, empty crtc state` 重复；
- multi-user（gdm 已停）下同样复现：一次运行到 483 s 即 panic（code 0xbe000411），
  说明与桌面/显示无关的概率很低，就是内存/总线问题；设备 panic 后有硬件看门狗自动重启。

排查方向：
1. **UFS/DMA**：对照 vendor `ufs-mediatek` 与参考分支，检查 quirk/DMA/时钟（`Clk-scaling
   not ready`），以及 cmdline `swiotlb=0 iommu.passthrough=1` 是否安全；
2. **内存/reserved-memory**：核对 DT memory 节点与 reserved-memory 是否覆盖所有 carveout
   （DT 里 memory 声明 8 GB，reserved 50 个节点，需确认没有可被伙伴系统分配但总线不响应的区间）；
3. **显示 SMI**：vendor mediatek_v2 的 plane/地址配置错误也可能让显示引擎 DMA 到无效地址，
   触发外部 abort（SError）。
验收：X11 桌面连续运行 30 分钟 + 2 小时 kmscube 不 panic。

### P1-a 触摸 ✅ 已完成（2026-11-15 02:20；根因与修复见 §2.7）

> 结论已明确：不是触发类型/极性，也不是 pinctrl，而是**缺少 NVT host-download 固件**。
> 已由 `chopin-nvt-firmware.service` 从 stock vendor 分区自愈；保留以下内容作为历史排查记录。

<details><summary>当时保留的排查思路（已不需要执行）</summary>

- 驱动 probe 成功、IRQ33 注册但计数恒 0；DT `novatek,irq-gpio = <&pio 0x13 0x2001>`；
- 曾计划：改 EDGE/LEVEL 触发类型、查 EINT19 复用、提取固件、SPI 读点。
- 实际根因：固件缺失（见 §2.7）；提取 vendor 分区固件放入 `/lib/firmware` 后 rebind 即恢复。

</details>

### P1-b GPU / panfrost ✅ 内核侧已解决（2026-11-15 02:55）

**根因**：mali 节点的七个 `mtcmos_mfg*` 时钟由 `clk-mt6893-pg.c`
（`compatible = "mediatek,mt6893-scpsys-clk"`）提供，但 `chopin_defconfig` 从未开
`CONFIG_COMMON_CLK_MT6893_PG`。于是 panfrost 的 chopin 钩子对每个时钟
`devm_clk_get_optional` 都拿到 `-EPROBE_DEFER`，打印 `-517` 后继续用 NULL 时钟初始化
→ MFG0..MFG6 电源域从未打开 → GPU 寄存器读回 0（`0 cores from 0`）、软/硬复位永远超时
→ probe -110、无 renderD128。次要问题：mfgcfg 门控的父时钟名写成了 mt8192 的
`mfg_pll_sel`，MT6893 应为 `mfg_sel`，所以 `bus_clock rate = 0`（已一并修复）。

**已验证**：在运行中的内核里 insmod 该时钟驱动后，panfrost 立刻识别出
`mali-g77 id 0x9080`、`shader_present=0x660067, l2_present=0x1`、
`Initialized panfrost 1.6.0`，`/dev/dri/renderD128` 出现。内核树已提交修复
（commit `eedb0f190`）。

**已刷入（2026-11-15 03:20）**：内置版内核（`boot-chopin-p0.img`）启动即完成 MTCMOS 注册
与 panfrost probe，`renderD128` 出现，`bus_clock rate = 349999848`（修复前 0），无需临时模块。
**待完成**：用户空间 Mesa/EGL 在
X11（vendor mediatek_v2 KMS）下仍走 llvmpipe，panfrost 的用户态渲染尚未接通（见 P1-c）。
临时方案：设备上 `/lib/modules/.../clk-mt6893-pg.ko` + `chopin-gpu.service` 每次启动加载。

> ⚠️ **刷机方式限制（重要）**：从 Linux 内直接 `dd` 写 `boot_a` 会被 UFS 拒绝
> （SCSI `ASC=0x27` WRITE PROTECTED；`para`/`boot_para`/`vendor_boot_a`/`dtbo_a`/
> `md1img_a` 同样保护，`boot_b`/`vbmeta_a`/`super` 可写）。因此**新内核必须经 LK/fastboot
> 刷写**：手机进 fastboot（音量下 + 电源）后用 Windows fastboot 刷 boot。
> 大文件传输已解决：`scripts/serial-xfer.ps1` 走 USB ACM 原始字节流 + base64 管道，
> 实测 19 MB boot 镜像约 1 s 写完（不再是 115200 波特率的瓶颈）。
> 备选的 kexec 免刷机路径调查过：内核有 `CONFIG_KEXEC_FILE`，但 kexec 会从**当前运行的
> 设备树**重新生成 DTB（里面 /memory 是 8 GB——板级 DTS 的硬编码值，和真实 6 GB 不符），
> 新内核会拿到错误内存布局，因此不可用；只能走 fastboot。

### P1-b 原排查记录（保留，已不需要执行）

现状证据：
- 首次 probe 时 mtcmos 电源域 -517（audio-controller 尚未 probe）；重载模块后 -517 消失，但仍
  `gpu soft/hard reset timed out`、`using only 1st core group (0 cores from 0)`、
  `clock rate = 349999848`、`bus_clock rate = 0`、`chopin: no core_clk_rate knob` → probe -110。
- 结论：电源域已通，问题在**时钟/复位**（bus clock 没拿到或 mfg 时钟没开，GPU 复位超时）。

排查方向：
1. 核对 chopin 的 panfrost 钩子取时钟名（`bus_clk`/`core_clk`/`mfg`）与 mt6893 clk 驱动提供的
   clock id 是否一致；`bus_clock rate = 0` 说明 bus clock 句柄存在但频率 0（时钟未开或未配置）。
2. 确认 GPU 复位前 mfg 电源域已上电、`mtcmos_mfg*` 已使能（可加 dev_info 打印 regulator/genpd 状态）。
3. 必要时用 vendor 的 `13fbb000.mali_dvfs_hint` / `mtk-mfg` 时钟路径对齐参考实现。

验收：`/dev/dri/renderD128` 出现；`eglinfo -B` 显示 Mali-G77 (Panfrost)；`kmscube` 稳定跑。

### P1-c Mesa / GPU 用户态 ✅ 已完成（2026-11-15 04:00）

- G77 型号补丁（参考 mesa 仓库）＋ `MESA_INSTALL_G77=1`（现在是默认）产出
  `libgallium-25.0.7-2+deb13u1.so`，已装进 rootfs；版本仍是 `25.0.7-2+deb13u1`。
- X11：glamor/GLX/EGL 都能建上下文（glxgears 122 FPS），但 **mutter 在 X11 上不出帧**
  （DRI2 GLX + kmsro 的 present 路径卡死），所以桌面不用 X11。
- **Wayland 是可用路径**：`WaylandEnable=true`，gnome-shell 以 wayland 合成器跑，
  显示正常、可交互。详见 [BRINGUP.md §12](docs/BRINGUP.md)。
- 遗留：这份 libgallium 只有 panfrost（无 llvmpipe 兜底）；触摸坐标待校准（P1-d）。

### P1-d 触摸坐标 ✅ 已完成（2026-11-15 13:15，实机确认）

- 根因：移植时加的 §BT§novatek,invert-y§BT§ + 驱动里「右半屏 Y 翻转」，原厂内核没有这个逻辑
  （已对照 stock 源码/DTS 确认），导致 x ≥ 540 的触摸 Y 被镜像。
- 修复：删属性 + 删代码，内核 commit §BT§676614a32§BT§；镜像 §BT§boot-chopin-touch.img§BT§ 已构建，待刷入验证。
- 验收：已刷入 `out/boot-chopin-touch.img`；用户按「上左→上中→上右→下一行…」共 24 次点击，
  evtest 三列坐标各自单调、无镜像；点右上角电池图标，快捷设置面板从右上角弹出 —— **位置正确**。

### P2 桌面完善（M3）

- 缩放：当前 dconf `text-scaling-factor=1.25`；1080×2400 手机形态可试 1.5–2.0，
  或写 `~/.config/monitors.xml` 固定 2x。
- 屏幕键盘（dconf 已开 `screen-keyboard-enabled`）、自动登录（已配）、电源/音量键（驱动已 probe）。
- journald 持久化（`/var/log/journal`）+ 开机诊断写盘，便于无串口取证。

### P3 网络与日常（M4）

1. **RNDIS**：`touch /etc/chopin-gadget-rndis` → 重建 gadget → Windows 192.168.42.100/设备 .2，
   走 SSH/apt（可配 Windows ICS 或端口转发）。
2. **WiFi**：从 nvdata 提取 `mediatek/mt6893/WIFI` + BT 固件，恢复 pre-cal 等待。
3. **充电/电量**：修 i2c5 上 MT6360（subpmic_pmic/ldo、tcpc），接 upower；**在此之前保持 USB 供电**。
4. **音频**：ASoC + UCM + pipewire（当前 pipewire-pulse 报 dbus 错误，属会话内问题）。

### P4 稳定性与工程化

- 30 分钟桌面空闲、2 小时 kmscube、过夜稳定性；ramoops/pstore 取证。
- `SHA256SUMS` 随构建自动生成（当前手写、已过期）；每次里程碑打 tag。
- 内核告警清理（section mismatch 等）、补丁拆分上游。

---

## 5. 风险

| # | 风险 | 影响 | 缓解 |
| --- | --- | --- | --- |
| R1 | Wayland/GBM 不可用（vendor KMS 无 Mesa 驱动） | 只能 X11 | X11 会话已可用；中期评估 mainline mtk-drm 或 kms_swrast 方案 |
| R2 | panfrost 修不好/不稳定 | 无 GPU 加速 | llvmpipe 退路已可用（桌面能跑） |
| R3 | 触摸不工作（INT/固件问题） | 无法交互 | 先修固件/中断；实在不行用 USB 键鼠 + 屏幕调试 |
| R4 | 无网络 | 无法在线装包 | 串口/RNDIS 传输；离线 .deb |
| R5 | MT6360 充电不工作 | 电池耗尽 | 保持 USB 供电；优先修 i2c5 |
| R6 | 32 位 fastboot 限制大镜像 | 刷机失败 | 已改用 2.9 GB sparse 镜像 |

---

## 6. 复现与操作

```bash
# 构建（WSL，Ubuntu 24.04 构建主机）
cd <workdir>
./scripts/build.sh                      # 内核 Image.gz + dtbs + modules
sudo debian/scripts/build-all.sh        # rootfs + initramfs + boot.img（04 默认跳过 Mesa 替换）
# 产物：debian/out/boot-chopin-debian.img、chopin-rootfs.sparse.img
```

```powershell
# 刷机（Windows，fastboot）
cd <workdir>
.\scripts\flash-debian.ps1              # boot + userdata（userdata 会被清空）
```

串口：Windows COM11 / 115200 8N1（DTR+RTS）；登录 chopin/chopin（root 同密码）。

---

## 7. 当前阻塞与下一步（按顺序）

1. ✅ **触摸已修好**（2026-11-15 02:20）：NVT 固件自愈；03:30 又修了驱动时序
   （lockdown 重试），新内核启动即自动刷对固件
2. ✅ **GPU 内核侧已修好**（03:20 刷入内置版内核）：MFG MTCMOS 时钟驱动编译进内核，
   panfrost 启动 2.8 s 完成 probe、renderD128、bus_clock 正常
3. 🔶 **P0 稳定性**：已按 LK 真实布局修正 DTS reserved-memory 并刷入（`boot-chopin-p0.img`）；
   内存压力 + 桌面 5 分钟无 panic，**长稳验证中**
4. ✅ **P1-c 用户态 GPU**：已完成（Wayland + kmsro + panfrost，见 §P1-c）
5. ⏭ RNDIS/SSH 网络 → WiFi NVRAM → MT6360 充电 → 音频
6. ⏭ 桌面打磨、内核告警清理、文档与上游化

> 注意：当前设备上的现场修改（gdm 停止、default.target=multi-user、journald=volatile、
> NVT 固件服务与脚本、PG 时钟模块 + chopin-gpu.service）尚未全部回流到 `debian/build`；
> P0 定位完成后再重建镜像固化。

> 注意：当前设备上的现场修改（gdm 停止、default.target=multi-user、journald=volatile、
> NVT 固件服务与脚本）尚未全部回流到 `debian/build`；P0 定位完成后再重建镜像固化。

---

## 8. 文件索引

- 方案：`docs-debian.md`（v1 总方案）、`docs/PLAN.md`（本文件，当前状态方案）
- 现场：`docs/BRINGUP.md`（实机记录）、`HANDOFF.md`（一页纸交接）
- 内核：`docs-kernel.md`
- 构建：`debian/README.md`、`debian/scripts/`
- 产物：`debian/out/`、Windows 侧 `<workdir>\out\`

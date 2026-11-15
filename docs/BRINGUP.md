# chopin Debian 13 实机 bring-up 记录

> 时间：2026-11-14 23:30
> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，MT6891Z/CZA）
> 说明：本文是从开发工作区原样搬运的现场记录，`<workdir>` 代表当时的私有工作目录，
> 里面的绝对路径只作参考；公开仓库的目录布局见 [../README.md](../README.md)。
> 镜像基线：Linux 7.3.4 + 18 补丁；Debian 13.7 + GNOME 48.7 + Mesa 25.0.7
> 本文是给下一个对话/下一次接手的**现场状态**，方案见 [docs-debian.md](../docs-debian.md)，
> 构建见 [README.md](README.md)。

## 0. 一句话状态

M0（rootfs + 桌面 + 镜像）已完成；M1（实机首启）到了 **Debian multi-user**，
gdm3 已暂时 mask，屏幕日志安静；**USB 串口仍未在正常启动里枚举**。
最后一个修复（systemd 服务不再拆掉 initramfs 已绑定的 gadget）已经构建，但**还没刷入**。

## 1. 设备当前是什么状态

- 运行的是 2026-11-14 23:19 刷入的镜像：
  - boot：`boot-chopin-debian.img`（gadget 初始化已修，但 systemd 服务还会 rm -rf g1）
  - rootfs：gdm3 已 mask、默认 multi-user.target、串口 getty 已启用
- 屏幕停在 CHOPIN-DIAG 日志，不再有 gdm 0.6 秒重启循环；日志里：
  - `udc 11201000.usb: state=not attached cur=UNKNOWN`
  - `gadget-configfs: g1`
  - `ttyGS: /dev/ttyGS0`
  - `failed-units: ssh.service zramswap.service`
- Windows 侧没有 COM 口、没有 VID_1D6B 设备。

## 2. 最新未刷入的镜像（23:28）

| 文件 | 大小 | SHA256 |
| --- | --- | --- |
| `debian/out/boot-chopin-debian.img` | 19 MB | `af4e264976b81c7c6e9008065b5eff0c941747a5677eb701338e4798b95c684d` |
| `debian/out/chopin-rootfs.sparse.img` | 2.9 GB | `6c3be5639b55b74554f8e7c8c5b09e13f8af4369c449133fb350fe39d77efe50` |

Windows 副本在 `<workdir>\out`，文件名相同。
它们包含的最后一个修复：`chopin-gadget.sh` 在 `$G/UDC` 非空时**直接退出**，
不再执行 `rm -rf g1`，避免 systemd 的 `chopin-gadget.service` 把 initramfs
刚绑好的 gadget 拆掉。

## 3. 已修复的问题

### 3.1 configfs 从未创建 config c.1（EINVAL）

第一次正常启动时 gadget 完全没枚举。debug 镜像显示：

    configfs-gadget gadget.0: Need at least one configuration in g1
    configfs-gadget gadget.0: probe with driver configfs-gadget.g1 failed with error -22
    configfs-gadget gadget.0: failed to start g1: -22

根因：initramfs 用 `[ ! -s "$G/idVendor" ]` 判断是否需要初始化 gadget；configfs
的 idVendor 文件存在且默认内容非空，于是整段初始化被跳过，`configs/c.1` 从未创建。
修复：`rm -rf "$G"` 后**无条件**写 idVendor/idProduct/strings/config，再建 function、
link、bind。修复后 debug3 镜像成功枚举：

- Windows 设备：`USB\VID_1D6B&PID_0104\CHOPIN`
- 串口：`COM11`

### 3.2 systemd 服务拆掉已绑定的 gadget（已构建，未刷入验证）

`chopin-gadget.service` 在 multi-user 阶段又跑一遍脚本；无条件 `rm -rf g1` 会把
initramfs 已绑定的 config/function 删掉，USB 链路随之消失。修复为：

    if [ -s "$G/UDC" ]; then
        log "gadget already bound to $(cat "$G/UDC"), skip"
        exit 0
    fi

### 3.3 gdm3 重启循环

首次启动 gdm3 每 ~0.6 s 重启一次，屏幕闪烁、tty0 被日志淹没。尚未定位根因
（需要 journalctl -u gdm3 / EGL/GBM 日志）。当前 rootfs 里：

    /etc/systemd/system/gdm3.service -> /dev/null
    /etc/systemd/system/default.target -> multi-user.target

串口 getty 保留。确认串口可用后再取消 mask，单独调 mutter/GBM。

## 4. 仍未解决

1. **正常启动（switch_root 到 Debian）后 USB 不枚举**。
   - debug3（不 switch_root、不跑 systemd）能枚举 COM11。
   - 23:19 镜像（systemd 服务会拆 gadget）不能枚举，UDC `not attached`。
   - 23:28 的幂等修复还没刷入，这是下一步第一件要验证的事。
2. 如果幂等修复仍不行，怀疑点变为 mtu3 端口切换/VBUS，而非 configfs：
   - DT 已是 `dr_mode="otg"` + `usb-role-switch` + `role-switch-default-mode="peripheral"`；
   - UDC 能注册、gadget 能绑、ttyGS0 能出现，但 host 看不到；
   - 可用 debug3 的串口 shell（CR 回车）读 `dmesg | grep mtu3`，或给 mtu3 加
     `dev_info` 后重编内核，确认 `ssusb_set_mode(DEVICE)`/`mtu3_start()` 是否成功。
3. `ssh.service` 在 diag 里显示 failed；host key 已从镜像删除，`ssh.service.d/host-keys.conf`
   里加了 `ExecStartPre=/usr/sbin/ssh-keygen -A`，需要在有串口后确认是否生效。
4. chopin-growroot 首次启动会把 3.7 GB ext4 扩到 107 GB userdata；还没在实机确认。
5. WiFi/BT NVRAM、MT6360 充电、音频仍未动。

## 5. 下一步操作（按顺序）

### 5.1 刷入 23:28 镜像

手机关机（长按电源 10 s），按住音量下 + 电源进 fastboot，然后 Windows：

    cd <workdir>
    .\scripts\flash-debian.ps1

等价手动：

    & "D:\Program Files (x86)\platform-tools\fastboot.exe" flash boot <workdir>\out\boot-chopin-debian.img
    & "D:\Program Files (x86)\platform-tools\fastboot.exe" flash userdata <workdir>\out\chopin-rootfs.sparse.img
    & "D:\Program Files (x86)\platform-tools\fastboot.exe" reboot

注意：userdata 是 2.9 GB sparse，分 12 个 chunk，约 90 s；32 位 fastboot 可用。
不要刷 3.7 GB 的 raw `chopin-rootfs.img`。

### 5.2 启动后看串口

Windows 出现 COM11 后：

    powershell -NoProfile -ExecutionPolicy Bypass -File <workdir>\scripts\serial-cmd.ps1 -Send "id" -WaitMs 2000

登录：`root` / 密码 `chopin`（用户 `chopin` 同密码）。
如果串口没有出现，但主机至少出现 `VID_1D6B&PID_0104`，说明 gadget 绑定成功、只是
getty/驱动问题；如果连 USB 设备都没有，进入 5.3。

### 5.3 没有 USB 时用 debug3

`boot-chopin-debug3.img`（<workdir>\out）是已知能枚举 COM11 的镜像：

    fastboot flash boot <workdir>\out\boot-chopin-debug3.img
    fastboot reboot

它只建 gadget、不起 Debian；串口 shell 用 **CR**（`serial-cmd.ps1` 已改为发 [char]13）。
在 shell 里可以：

    mount -t ext4 -o rw /dev/sdc75 /mnt
    dmesg | grep -iE 'mtu3|gadget|vbus|role|phy'
    cat /sys/class/udc/11201000.usb/state

debug3 没有 systemd，所以不能用来跑桌面；它只是救援/诊断通道。

### 5.4 重新打开 GNOME（串口可用之后）

    systemctl unmask gdm3
    systemctl set-default graphical.target
    systemctl start gdm3
    journalctl -b -u gdm3 --no-pager | tail -80

如果 gdm3 仍然循环，先跑 `modetest -M mediatek -c`、`eglinfo -B`、`kmscube` 分层定位，
再按 docs-debian.md 的 R1 退路（X11/llvmpipe、GNOME Flashback）。

## 6. 关键路径与文件

- 内核：`<workdir>/linux`，release `7.3.4-ga9777a8559e0-dirty`
- 内核产物：`<workdir>/out/modules/lib/modules/<release>`
- 正常镜像：`debian/out/boot-chopin-debian.img`、`chopin-rootfs.sparse.img`
- 诊断镜像：`boot-chopin-debug*.img`、`boot-chopin-rescue*.img`（同一目录）
- initramfs 源：`debian/initramfs/`（`init`、`chopin-gadget.sh`、debug/rescue 变体）
- 串口工具：`<workdir>\scripts\serial-cmd.ps1`（CR 回车、115200 8N1、DTR/RTS）
- 刷机脚本：`<workdir>\scripts\flash-debian.ps1`

## 7. Git

    ab6be94 debian: do not tear down an already-bound gadget
    9fe826a debian: fix configfs gadget init, add rescue images and bring-up notes
    3b4459b debian: keep host-specific files out of the image
    6a39675 debian: complete first M0 build (GNOME rootfs, G77 Mesa, images)
    e44c50a debian: start Debian 13 trixie + GNOME bring-up project

标签 `debian-v13-m0` 指 M0（构建完成，未含本轮 bring-up 修复）。

---

## 8. 2026-11-15 00:05–00:35：M1 打通 + X11 桌面（本轮）

### 8.1 关键突破：USB gadget 绑定 bug
- 23:28 镜像（幂等修复版）刷入后仍无 COM。屏幕照片 + probe 日志显示：
  `after gadget: ... state=[not attached] role=[device] g1_UDC=[]`，且
  `config c.1` 之后没有任何 `bind attempt` 行 —— gadget 从未尝试绑定。
- 根因：`chopin-gadget.sh` 用 `[ -s "$G/UDC" ]` 判断是否已绑定。configfs 属性
  文件的 stat 大小恒为 4096，`-s` 恒真 → 误判"已绑定"直接跳过/break。
- 修复：`is_bound() { [ -n "$(cat "$G/UDC" 2>/dev/null)" ]; }`。
- 验证：重建 boot（sha256 `9a46cef3…`）刷入后 Windows 出现 COM11，串口打印
  `Debian GNU/Linux 13 chopin ttyGS0` + `chopin login:`。
- 顺带确认：systemd 的 `chopin-gadget.service` 看到 UDC 已绑定会 skip
  （`gadget already bound to 11201000.usb, skip`），initramfs 的绑定得以保留。

### 8.2 实机状态（00:10 起）
- `systemctl is-system-running` = **running**；`udc 11201000.usb state=configured`；
  DRM `card0-DSI-1 connected`；`/dev/sdc75` 106G。
- gdm3（实际单元 `gdm.service`）在 rootfs 里是 masked。unmask 后启动失败（signal TRAP），
  日志 `GdmSession: no session desktop files installed`。
- 原因：GNOME 48 的 Debian 包只有 `wayland-sessions`，没有 `xsessions`；强制
  WaylandEnable=false 时 GDM 收集不到会话。
- 修复：补 `/usr/share/xsessions/gnome.desktop`（Exec=gnome-session），
  daemon.conf 设 WaylandEnable=false。之后 Xorg :0 + gnome-shell 48.7 正常启动，
  自动登录 chopin，`xrandr` 显示 DSI-1 1080×2400。

### 8.3 图形栈结论（M2 部分）
- 原 G77 libgallium 只有 panfrost（参考 build.sh 用 `-Dllvm=disabled`，无 swrast）
  → 换回 Debian 原版后 llvmpipe 可用（eglinfo Surfaceless: llvmpipe / LLVM 19.1.7）。
  `04-build-mesa.sh` 已改为默认跳过替换（`MESA_INSTALL_G77=1` 才安装）。
- GBM 平台仍 `eglInitialize failed`：vendor mediatek-drm 没有对应 Mesa 驱动；
  Wayland/mutter 暂不可用，X11 是当前工作路径。
- panfrost：初次 probe 时 mtcmos -517；模块重载后 -517 消失但仍
  `gpu soft/hard reset timed out`、`bus_clock rate = 0`、`no core_clk_rate knob`
  → probe -110，无 renderD128。待修内核时钟/电源（方案见 PLAN.md）。

### 8.4 触摸
- `evtest /dev/input/event2` 45 秒 + 用户滑动：无任何事件；`/proc/interrupts`
  IRQ 33 计数 0。驱动 probe 正常（chip id 读取成功、input 设备注册、libinput 已识别）。
- `/sys/kernel/debug/gpio`：`gpio-19 (NVT-int) in lo IRQ ACTIVE LOW`；DT
  `novatek,irq-gpio = <&pio 0x13 0x2001>`。下一步查触发类型/引脚复用/固件。

### 8.5 其它修复
- ssh：Debian 单元第一条 ExecStartPre 是 `sshd -t`，无 host key 时先失败，
  后面的 ssh-keygen 不执行 → drop-in 里 `ExecStartPre=` 清空并重排顺序。
- zramswap：内核没有 zram 模块 → 构建时 mask。
- 构建树已同步以上所有修改；镜像重建：
  boot `9a46cef3…`、rootfs sparse `9b0652b2…`。

### 8.6 当前设备
- boot：`boot-chopin-debian.img`（9a46cef3…）+ 旧 userdata（已含同等现场修改，运行正常）。
- 串口 COM11 @115200：`root`/`chopin`，密码 `chopin`。
- 下一步：触摸与 panfrost（见 [PLAN.md](PLAN.md)）。

---

## 9. 2026-11-15 02:00–02:50：触摸打通 + 稳定性问题（本轮）

### 9.1 触摸：根因是缺 NVT host-download 固件（已解决）

**现象回顾**：驱动 probe 成功（chip id 可读、input 设备注册、`request irq 33 succeed`），
但 `/proc/interrupts` 里 IRQ 33 计数恒 0，evtest 无任何事件；当时怀疑触发类型/极性/pinctrl。

**本轮定位**：
- 冷启动 dmesg 里驱动在 probe 后 ~10 s 请求固件：
  `Direct firmware load for novatek_nt36672c_k10a_fw01.bin failed with error -2`
  → `nvt_get_fw_info: FW info is broken! fw_ver=0xD5, ~fw_ver=0xF6`（芯片还在 bootloader 状态）
  → `FW type is 0x19, fw_ver=0`，PID=0x03A3；驱动继续完成 probe，但芯片不扫描、INT 不触发。
- NT36672C 是 **host-download** 型：芯片没有内部固件存储，原厂内核每次启动都会把
  `novatek_nt36672c_k10a_fw01.bin`（139264 B）经 SPI 下载进去；mainline 的 linux-firmware
  没有这个文件，因此出现上述现象。
- 固件就在设备原厂 **vendor 逻辑分区**里：`/vendor/firmware/novatek_nt36672c_k10a_fw01.bin`、
  `_fw02`、`_mp01`、`_mp02`。物理位置在 `/dev/sdc61`（PARTLABEL=super，8.5 GB）的
  vendor 逻辑分区（liblp，slot 0），只读挂载即可复制，不需要动 userdata 或刷机。

**验证步骤（实机）**：
```
python3 /root/lp.py map /dev/sdc61 vendor          # 6457131008 2007650304
losetup -f --show -r --offset 6457131008 --sizelimit 2007650304 /dev/sdc61
mount -t ext4 -o ro /dev/loop0 /mnt/vendor
cp /mnt/vendor/firmware/novatek_nt36672c_k10a_*.bin /lib/firmware/
echo spi0.0 > /sys/bus/spi/drivers/NVT-ts-spi/unbind   # 已 probe 过的驱动需要重载
echo spi0.0 > /sys/bus/spi/drivers/NVT-ts-spi/bind
```
重载后 dmesg：
```
nvt_update_firmware 1174: Update firmware success! <100126 us>
nvt_get_fw_info 673: FW type is 0x01, fw_ver=11
nvt_read_pid 599: PID=5950
```
IRQ 33 立刻开始计数（`grep ' 33:' /proc/interrupts` → mt-eint 19 Edge NVT-ts-spi），
`evtest /dev/input/event2` 输出真实事件：
```
Event: type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 30
Event: type 1 (EV_KEY), code 330 (BTN_TOUCH), value 1
Event: type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 742
Event: type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 18
```
**冷启动复测**：重启后固件已持久化在 userdata 的 `/lib/firmware`，启动 22 s 时打印
`Update firmware success!`，IRQ 33 正常，无需人工干预。

**固化到工程**（本轮新增）：
- `debian/overlay/usr/local/sbin/chopin-nvt-firmware.sh`：首启自动从 super/vendor 提取
  固件（幂等；已 probe 时自动 unbind/rebind）；
- `debian/overlay/usr/local/lib/chopin/lp.py`：最小 liblp 解析（list/map）；
- `debian/overlay/etc/systemd/system/chopin-nvt-firmware.service`：oneshot，
  `Before=graphical.target display-manager`；`02-configure-rootfs.sh` 负责 enable，
  并可选打入 `debian/third_party/firmware/`（已 gitignore）里的预置固件。
- 实机验证：删除 `/lib/firmware/novatek_*` 后执行服务脚本 → 4 个文件全部恢复、
  驱动自动 reload、`Update firmware success!`、触摸保持可用。
- 固件 sha256 见 `debian/README.md` §1.1。

**遗留观察**：空闲时 IRQ 33 仍以约 2 次/秒触发（驱动打印 `finger leave`），不影响功能，
但可在后续调 trigger type/pull-up 时再看。

### 9.2 新问题：X11 桌面下偶发 SError panic（P0）

- GNOME（X11 + llvmpipe）运行 1–3 分钟后随机 panic。ramoops 证据：
  - 一次：`SError Interrupt on CPU6, code 0xbe000411`，进程 gnome-shell，
    `pc: clear_page+0x34`（缺页清零新页）；
  - 另一次：写 2 GB 文件时先出现 300+ 次
    `ufshcd-mtk 11270000.ufshci: ufshcd_check_errors: saved_err 0x30004 saved_uic_err 0x2`
    + host_regs dump，随后 `SError ... 0xbe000011`，进程 python3，
    栈 `ext4_buffered_write_iter → __arch_copy_from_user`。
- 说明是**内存/总线层面的外部 abort**，且与 UFS 写入、显示/SMI 活动相关；multi-user
  空闲尚未复现。疑似方向：UFS DMA/IOMMU 配置（cmdline 有 `swiotlb=0 iommu.passthrough=1`）、
  DT reserved-memory 与真实内存布局、display SMI 地址配置。
- 现场已保存：`/root/chopin-crash/console-ramoops-latest.txt`（设备上）。
- 临时处置：`systemctl stop gdm`、`systemctl set-default multi-user.target`、
  journald `Storage=volatile`，设备在 multi-user 下观察稳定性，等待分析结论。

### 9.3 当前设备状态（2026-11-15 02:50）

- 运行内核不变：`7.3.4-ga9777a8559e0-dirty #10`；boot 仍为 `9a46cef3` 镜像；
- rootfs 未重刷，现场改动：`/lib/firmware/novatek_*.bin`、`chopin-nvt-firmware` 服务与脚本、
  multi-user/volatile 等（尚未全部回流到 `debian/build`）；
- 触摸：**正常**（IRQ 33、evtest 有事件）；
- GPU：panfrost 仍 probe -110；
- 串口：COM11 @115200，root/chopin；`scripts/serial-run.ps1` 可自动登录并执行多行命令。

---

## 10. 2026-11-15 02:30–03:15：GPU 内核打通 + 刷机通道调查（本轮）

### 10.1 GPU / panfrost：根因是 MFG MTCMOS 时钟驱动没编进内核（已修）

分析结论（详见 [../analysis/gpu-panfrost.md](../analysis/gpu-panfrost.md)）：

- mali 节点的 7 个 `mtcmos_mfg*` 时钟不是普通门控，而是 MT6893 的 MFG MTCMOS 电源域，
  由项目自写的 `drivers/clk/mediatek/clk-mt6893-pg.c`
  （`compatible = "mediatek,mt6893-scpsys-clk"`）提供；
- 该驱动受 `CONFIG_COMMON_CLK_MT6893_PG` 控制，而 `chopin_defconfig` 从未打开它：
  `.config` 里 `# CONFIG_COMMON_CLK_MT6893_PG is not set`，树里也没有 `clk-mt6893-pg.o`；
- 因此 panfrost 的 chopin 钩子对每个 mtcmos 时钟都拿到 `-EPROBE_DEFER`（打印 `-517`），
  吞掉错误后继续以 NULL 时钟初始化 → MFG 电源域一直关着 → GPU 寄存器读回 0
  （`using only 1st core group (0 cores from 0)`）、软/硬复位超时 → probe -110。
- 另一个独立问题：mfgcfg 门控的父时钟名写成了 mt8192 的 `mfg_pll_sel`，MT6893 是 `mfg_sel`，
  所以 `bus_clock rate = 0`。

**实机验证方法（不刷机）**：把 `clk-mt6893-pg` 临时编成模块（Kconfig bool→tristate 的临时改动，
内核树最终仍保持 `=y`），用桩版本号对齐运行内核后 `insmod`，再重载 panfrost：

```
mt6893-scpsys-clk 10001000.scpsys: MTCMOS clocks: 7 real (MFG), 33 placeholders
panfrost 13000000.mali: mali-g77 id 0x9080 major 0x0 minor 0x1 status 0x1
panfrost 13000000.mali: shader_present=0x660067 l2_present=0x1
panfrost 13000000.mali: [drm] Initialized panfrost 1.6.0 for 13000000.mali on minor 1
```

`/dev/dri/renderD128`、`card1` 随即出现。内核修复已提交：`eedb0f190`（defconfig +
mfg 父时钟名 + panfrost 延迟探测）；新内核已打包为 `out/boot-chopin-final.img`
（sha256 `5ac7ca44…`，含 LKDT 诊断的内存洞保留试验 `5775fb2ac`），**尚未刷入**（见 10.2）。

**用户空间还没通**：`eglinfo -B` 在 GBM/Surfaceless/Device 平台仍报 llvmpipe；
EGL device 平台枚举到 `/dev/dri/card1`（panfrost）但 `eglInitialize` 在 DRI2 加载阶段失败
（`using driver panfrost for 3` → `failed to create dri2 screen`）。X11 的显示 KMS 是
vendor `mediatek_v2`（无 Mesa 驱动），所以桌面加速是独立问题；panfrost 用户态需要
GBM/surfaceless 或 render-node offload 路线。已写 `scripts/gpu-egl-test.py` 用于枚举
EGL device 并打印 GL_RENDERER，继续排查时用。

### 10.2 刷机通道：Linux 下 boot_a 被 UFS 硬件写保护

尝试在 Debian 里直接 `dd` 写 `/dev/disk/by-partlabel/boot_a` 后读取校验失败，dmesg：

```
sd 0:0:0:2: [sdc] Sense Key : 0x7 [current]
sd 0:0:0:2: [sdc] ASC=0x27 ASCQ=0x1
critical target error, dev sdc, sector 1611776 op 0x1:(WRITE) ...
Buffer I/O error on dev sdc32, logical block 30720, lost async page write
```

`ASC=0x27` 即 WRITE PROTECTED：UFS 设备固件拒绝写这些 LBA。逐分区安全写回测试结果：

| 分区 | 可写 | 分区 | 可写 |
| --- | --- | --- | --- |
| boot_a / vendor_boot_a / dtbo_a | ❌ | boot_b | ✅ |
| para / boot_para | ❌ | vbmeta_a | ✅ |
| md1img_a | ❌ | super | ✅ |

所以**新内核必须走 LK/fastboot**（音量下 + 电源进 fastboot）。好消息是大文件传输不再是瓶颈：
`scripts/serial-xfer.ps1` 用 `stty raw` + `head -c N | base64 -d` 的管道，把 Windows 端
base64 直接灌进 ttyGS0，实测 19 MB boot 镜像 ~1 s 完成（USB ACM 高速度，约 20 MB/s 缓冲），
sha256 校验一致。

### 10.3 SError 诊断内核（已构建，待刷入）

按 [../analysis/ufs-serror.md](../analysis/ufs-serror.md) 的建议，本次内核额外带了两处试验：

1. `setup.c`：在覆盖 LK 设备树之前 dump LK 的 `/memory` 与 `/reserved-memory`
   （`CHOPIN-LKDT:` 行）——这是判断 reserved-memory 是否抄错的关键证据；
2. 板级 DTS：把两个 `md_mem_usage` carve-out 之间的 237.25 MiB 空洞
   （`0xebb10000..0xfa850000`）保留为 `no-map`，验证“伙伴系统发放了总线不响应的 DRAM”假设。

刷入后：`dmesg | grep CHOPIN-LKDT`，再跑内存压力测试（见 ufs-serror.md §6），
确认 SError/`0x30004` 是否消失。

### 10.4 现场设备状态（2026-11-15 03:15）

- 内核仍是 `7.3.4-ga9777a8559e0-dirty #10`（旧内核，尚未刷 10.3 的内核）；
- GPU：通过临时模块 + `chopin-gpu.service` 在启动后加载，`renderD128` 可用；
  已实测重启验证：boot 时 systemd-modules-load 先加载 PG 时钟模块（日志
  `MTCMOS clocks: 7 real (MFG), 33 placeholders`），随后 chopin-gpu.service 重载 panfrost，
  `mali-g77` 识别、`renderD128` 出现、无 failed units；
  模块文件在 `/lib/modules/<rel>/kernel/drivers/clk/mediatek/clk-mt6893-pg.ko`
  （vermagic 已手工对齐旧内核，刷入新内核后应删除并改用内置驱动）；
- 桌面仍停在 multi-user（gdm 停止）；触摸正常；**但 SError 在 multi-user 下同样会触发**：
  一次实机运行到 483 s 时仍 panic（ramoops: `SError Interrupt on CPU7, code 0xbe000411`，
  距离上一次启动约 8 分钟），说明它不是桌面/显示专属，而是内存/总线问题——更没有理由拖延
  P0 修复。设备 panic 后由 mtk 硬件看门狗（31 s）自动重启，可自恢复；
- 未提交的现场改动：`/etc/modules-load.d/chopin.conf` 增加 `clk-mt6893-pg`、
  `chopin-gpu.service`、journald volatile 等。

### 10.5 产物与提交

- 内核：`eedb0f190`（GPU 修复）、`5775fb2ac`（LKDT 诊断 + 内存洞试验）；
- boot 镜像：`out/boot-chopin-final.img`（19 MB，sha256
  `5ac7ca44d4d3955cce44685696254ad1e0c6e588beb50eea28a04b5951e57157`）；
- 分析报告：`analysis/gpu-panfrost.md`、`analysis/ufs-serror.md`；
- 工具：`scripts/serial-run.ps1`（串口登录/多行命令）、`scripts/serial-xfer.ps1`
  （高速文件传输）、`scripts/gpu-egl-test.py`（EGL device 枚举）、`scripts/lp.py`。

### 10.6 下一步

1. 手机进 fastboot，刷 `out/boot-chopin-final.img`；
2. 验证：启动 dmesg 无 `-517`、`renderD128` 出现、`CHOPIN-LKDT` 输出、触摸正常；
3. 用 LKDT 真实布局修正 DTS reserved-memory，消除 SError（P0）；
4. 再评估 Mesa/EGL panfrost 用户态（P1-c）与桌面稳定性。
---

## 11. 2026-11-15 03:00–03:35：P0 修复候选（reserved-memory 修正 + 触摸时序）

### 11.1 LK 真实内存布局（CHOPIN-LKDT 实测）

刷入带诊断的内核后，启动早期 dump 出 LK（bootloader）真正传给内核的设备树：

```
CHOPIN-LKDT: /memory reg: 00000000 40000000 00000001 80000000   -> 0x40000000 + 6 GiB
```

reserved-memory 的 mblock 表也全部打印出来。与板级 DTS 对比，发现 modem/adsp 相关的
6 个 carve-out 与真实布局不一致（这一台是 6 GiB 版本，DTS 抄的是 8 GiB 版本的地址）：

| 节点 | 板级 DTS 旧值 | LK 真实值 | 影响 |
| --- | --- | --- | --- |
| mblock-24-md_mem_usage | 0xe0000000 | 0xde000000 | 32 MiB 被误当空闲 RAM |
| mblock-25-md_mem_usage | 0xe3000000 | 0xe1000000 | 32 MiB 被误当空闲 RAM |
| mblock-26-md_mem_usage | 0xe4000000 | 0xe2000000 | 32 MiB 被误当空闲 RAM |
| mblock-27-md_mem_usage | 0xfa850000 | 0xf8850000 | **32 MiB 被误当空闲 RAM** |
| mblock-29-ap_md_c_smem  | 0x6e000000/0x5560000 | 0x70000000/0x3560000 | 浪费 32 MiB |
| mblock-30-adsp | 0x6c000000 | 0x6e000000 | 浪费 14.5 MiB |
| mblock-1/2-dramc-rk0/1 | 0x013ffff000 / 0x023ffff000 | 0xfffff000 / 0x1bffff000 | 8 GiB 版地址，超出本机 RAM |

其中 mblock-27 的 32 MiB 窗口（0xf8850000..0xfa850000）**正好覆盖之前 SError 的
swiotlb bounce pool 地址 0xf6850000..0xfa850000 的上半段**：LK 保留、Linux 却当空闲内存
交给伙伴系统，首次访问就产生总线外部 abort（补丁 `14266aef5`）。

### 11.2 触摸时序问题（新内核上暴露）

把 LKDT 诊断内核刷入后发现：触摸驱动在 ~1.6 s 就 probe，而 mi-dsi panel 还没起来，
`get_lockdown_info_for_nvt()` 失败；旧代码把失败也标记为“已读取”，10 s 后
`nvt_match_fw()` 看到全 0 的 lockdown，报 “mismatch panel type, use default fw”，
请求通用的 `novatek_ts_fw02.bin`（不存在）→ 固件下载失败、IRQ 33 恒 0、触摸失效。

修复（`cbef89868`）：`get_lockdown_info()` 每 500 ms 重试读 panel lockdown，最多 20 s，
读到有效值再锁定。实测启动 16 s 时 `match panle type, fw is [novatek_nt36672c_k10a_fw01.bin]`
→ `Update firmware success!` → IRQ 33 正常计数，**无需任何手工 rebind**。

### 11.3 刷入与验证（2026-11-15 03:20）

- 镜像：`out/boot-chopin-p0.img`（19 MB，sha256
  `2ec82ea0b21fa5abd6abc387f1e5a591ee261c6755e905f1298aa0bc88600a5b`），内核 release
  `7.3.4-g5775fb2ac0a1-dirty`（#13）；
- 模块：`out/p0-modules.tar.gz`（91 MB → 1640 个 .ko，已解压到
  `/usr/lib/modules/7.3.4-g5775fb2ac0a1-dirty`）；
- 启动验证：MTCMOS 时钟 0.69 s 注册、panfrost 2.79 s 完成 probe（`bus_clock rate =
  349999848`，之前是 0）、`renderD128` 出现；触摸 16 s 刷固件成功；
- 内存压力：分配/触碰/释放 2.5 GiB，无 SError、无 `ufshcd_check_errors`；
- 桌面：gdm + gnome-shell 启动，运行 5 分钟+ 无 panic（旧内核 1–3 分钟必崩）；
  继续长稳观察。

### 11.4 教训：不要用带目录条的 tar 解到 /

把 `p0-modules.tar.gz` 解到 `/` 时，归档里的 `lib/` 目录条目把 Debian 的
`/lib -> usr/lib` symlink 替换成了真实目录（usrmerge 被破坏），所有动态链接程序报
`required file not found`。串口 shell 本身已在内存中所以仍可操作，用
`/usr/lib/ld-linux-aarch64.so.1 /usr/bin/mv ...` 显式指定 loader 才把 `/lib/modules` 移回
`/usr/lib/modules` 并重建 symlink。

**以后解压模块 tarball 必须加 `--keep-directory-symlink`**（GNU tar）或者只打包
`usr/lib/modules/...` 子路径。
---

## 12. 2026-11-15 03:30–04:00：GPU 用户态打通（Mali-G77 + kmsro + glamor）

**结论：用户态 GPU 通了——glamor、GLX、EGL 全部走 panfrost**，`glxinfo` 报
`Mali-G77 (Panfrost)` / `Accelerated: yes`，`glxgears` 122 FPS（120 Hz 垂直同步）。

> ⚠️ 但 X11 这条路上 **mutter 不刷新**（见 §12.6）：X 服务器自己会画（glamor 正常），
> GLX 客户端也能渲染，可 gnome-shell 停在启动画面（静态帧、0% CPU、D-Bus 不回话）。
> **真正能用的桌面是 Wayland**：`WaylandEnable=true` 后 gnome-shell 以 wayland 合成器运行，
> 1080×2400@120、缩放 2.5，画面正常、触摸可用。

### 12.1 之前为什么只有 llvmpipe

三件事同时缺：

1. **Mesa 没有 G77 型号**。`src/panfrost/lib/pan_props.c` 的型号表里没有 product id
   `0x9080`（MT6893 的 Mali-G77），`panfrost_get_model()` 返回 NULL，DRI 驱动直接放弃。
   参考仓库 <https://github.com/MT6891-Mainline/mesa> 的 `panfrost: add the Mali-G77`
   提交补了一行 `MODEL(0x9080, 0, "G77", "TTRx", HAS_ANISO, 16384, {})`；Debian 的
   Mesa 25.0.7 没有这个补丁。
2. **内核侧没通**。panfrost probe 要 MFG MTCMOS 时钟（§10），旧内核 probe -110、没有
   `renderD128`；修好之后用户态才有东西可跑。
3. **X 跑错了设备**。KMS 是 `mediatek-drm`（card1），GPU 是 render-only（card0 /
   renderD128）。Xorg 自动配置找不到 primary，回退 fbdev，直接
   `Cannot run in framebuffer mode`。Mesa 的 kmsro 本来就能把「mediatek-drm 显示 +
   panfrost 渲染」配成一对（`pipe_loader_get_compatible_render_capable_device_fds()`
   在 platform bus 上找 panfrost 渲染节点），前提是 X 以**显示卡**为 KMS 设备启动。

### 12.2 实际步骤

1. `debian/scripts/04-build-mesa.sh`（现在默认 `MESA_INSTALL_G77=1`）交叉编译
   `libgallium-25.0.7-2+deb13u1.so`，装进 `/usr/lib/aarch64-linux-gnu/`（先备份
   `.debian`）。产物 sha256 `8aa303b618dee5c1abc33f719265f2314bc1df7bec2f776be2afd34ae64597f5`，
   17.5 MB，**只含 panfrost**（`-Dllvm=disabled`，没有 llvmpipe）。
2. `/etc/X11/xorg.conf.d/10-chopin-gpu.conf`：`Driver "modesetting"` +
   `Option "kmsdev" "/dev/dri/card1"`。
3. `systemctl restart gdm` → `Xorg.0.log` 出现
   `glamor X acceleration enabled on Mali-G77 (Panfrost)`，gnome-shell 正常。

### 12.3 三个坑（都已固化进镜像）

- **kmsdev 必须是真实路径**。写 `/dev/dri/by-path/platform-mediatek-drm.7.auto-card`
  时 Xorg 认不出这是它枚举过的设备：既建 `modeset(0)`（用该路径）又建 `modeset(G0)`
  （card1），主屏仍是 fbdev，报 `Cannot run in framebuffer mode`。必须 `readlink -f`
  成 `/dev/dri/cardN`。
- **配置文件必须是 644**。X 以用户 chopin 启动，`/etc/X11/xorg.conf.d/*.conf` 若是 600
  会被忽略，表现和上面一样（又回到 fbdev）。生成脚本用 `mktemp` 时踩过这个坑。
- **卡号不固定**。panfrost 2.8 s 就 probe，mediatek-drm 要等组件、defer 到 ~16 s，
  `card1` 只是当前顺序。新增 `chopin-xorg-kmsdev.service`（`Before=gdm.service`，
  `--wait 40`）在启动时按 by-path 解析真实卡号并重写配置；脚本幂等，内容没变不写盘。

### 12.4 证据

| 检查 | 结果 |
| --- | --- |
| `eglinfo -B` | GBM / Surfaceless / Device / **X11** 四个 platform 全是 `Mali-G77 (Panfrost)` |
| `glxinfo -B` | direct rendering **yes**，Accelerated **yes**，GL 3.1 / GLES 3.1 |
| `glxgears` | 614 frames / 5.0 s = **122.7 FPS**（vsync 120 Hz） |
| Xorg | `glamor X acceleration enabled on Mali-G77 (Panfrost)` |
| 桌面 | gdm + Xorg + gnome-shell 48.7 正常，截图见 `out/shot.png` |

Xorg 启动时有一次 `(EE) modeset(0): Failed to make import prime FD as pixmap: 22`
（kmsro 扫描输出路径上的 prime 导入探测），没有复现、不影响渲染，先记着。

### 12.5 仍未解决 / 注意

- 这份 libgallium **没有 swrast/llvmpipe**，没有软件渲染兜底：panfrost 起不来桌面就是黑的。
  要兜底就 `MESA_INSTALL_G77=0`（回到 Debian 原版，llvmpipe）或另编 `panfrost+softpipe`。
- **P0（SError）没有随 GPU 一起解决**：GPU 桌面跑了约 30 分钟后设备重启过一次；
  pstore 因满（`pstore: backend (ramoops) writing error (-28)`）没留下新记录，已
  `rm /sys/fs/pstore/*` 清空待取证。下次重启后第一件事是看 pstore 里是不是同一个
  `SError ... code 0xbe000411`。
- 厂商显示驱动偶发 `[DISP][E]mtk_plane_atomic_disable, empty crtc state`，暂无可见副作用。

### 12.6 X11 不刷新，Wayland 正常（2026-11-15 04:20）

X11 会话（modesetting + glamor + kmsro）能创建上下文、glxgears 122 FPS，但：

- 屏幕停在 gnome-shell 的启动画面（模糊壁纸 + 转圈），之后**不再更新**；
- 之后起的客户端窗口不会出现在屏幕上（后台跑 glxgears，截屏前后字节完全相同）；
- gnome-shell 的 CPU 时间冻结（0%，只有 4.9 s），`org.gnome.ScreenSaver.GetActive`
  无人应答 → 主循环卡在 present/fence 上；
- Xorg 侧是 `(II) AIGLX: Loaded and initialized mediatek`、`GLX: Initialized DRI2 GL provider`：
  GLX 走的是 **DRI2**（服务器端 DRI 名 "mediatek"，靠 libgallium 静态表兜底到 kmsro），
  Mesa 25 对 DRI2 客户端路径早已不维护，mutter 等 swap 完成事件大概率永远等不到。

把 `/etc/gdm3/daemon.conf` 改成 `WaylandEnable=true` 之后：gnome-shell 以 wayland 合成器
运行（`loginctl show-session <id> -p Type` → `wayland`），EGL/GBM 直接开在显示卡 card1 上、
由 kmsro 配到 panfrost，**桌面正常显示**（实机确认），1080×2400@120、缩放 2.5。

结论：**桌面走 Wayland**。X11 那套（`10-chopin-gpu.conf` + `chopin-xorg-kmsdev.service`）
留着当 fallback 和调试手段，但不要指望 mutter on X11 出画面。

### 12.7 遗留

- **触摸能用但坐标有偏差**（实机反馈"位置有点错误"）。驱动上报
  `ABS_MT_POSITION_X 0..1079`、`ABS_MT_POSITION_Y 0..2399`，和面板一致；
  偏差要么在合成器映射（scale 2.5），要么是面板有效区/固件坐标系有偏移，待量化。
- 截图工具：rootfs 里没有 xwd/imagemagick，用 `scripts/chopin-shot.py`（ctypes + XGetImage）
  或者 Wayland 下让用户目视确认；`scripts/serial-pull.ps1` 可以把文件从设备拉回 Windows
  （base64 over COM，20 KB 级文件约 3 s）。

---

## 13. 2026-11-15 04:00–05:00：触摸 Y 翻转的来历 + P0 第二个候选修复（构建完成，待刷入）

### 13.1 触摸：那个「右半屏 Y 翻转」是移植时加的，原厂没有

驱动里有这么一段（`nt36xxx.c`，移植补丁 0008 带进来的）：

```c
/* This panel reports the right half with the opposite
 * Y direction; only flip that half. */
if (nvt_invert_y && input_x >= (ts->abs_x_max / 2))
        input_y = ts->abs_y_max - input_y;
```

`nvt_invert_y` 来自 DTS 属性 `novatek,invert-y`（`mt6893-xiaomi-chopin.dts:3499`）。

对照原厂内核（`Xiaomi_Kernel_OpenSource-chopin-r-oss.zip`）：

- `drivers/input/touchscreen/NVT36672c/nt36xxx.c` —— **没有任何 invert / 镜像逻辑**，
  `input_y` 的算法和移植版逐字相同；
- `arch/arm64/boot/dts/mediatek/novatek-nt36xxx-spi.dtsi` —— **没有** `novatek,invert-y`
  之类的方向属性。

所以这是移植时凭现象加的猜测，效果是：**x ≥ 540 的所有触摸 Y 被镜像**。用实机四点触摸
（evtest 记录）验证，上报顺序与「用户按 左上→右上→右下→左下 点，但右半边 Y 被翻」完全吻合
（左上 85,86；右上被报成 1000,2337；右下被报成 1000,75；左下 123,2297）。

修复：删掉 DTS 属性 + 删掉驱动里的翻转代码（内核 commit `676614a32`）。

### 13.2 P0：mblock-26/mblock-27 之间 237.25 MiB 的空档

LK 真实布局里 `mblock-26`（`0xe2000000` + `0x7b10000`）结束于 `0xe9b10000`，
`mblock-27` 从 `0xf8850000` 开始，**两者之间 237.25 MiB（`0xe9b10000..0xf8850000`）
不在 LK 的 mblock 表里**，Linux 于是把它交给伙伴系统；首次触碰就在 `clear_page` 里
异步外部中止（`SError code 0xbe000411`）。

上一轮试过在同一位置（8 GiB 版本地址换算后）打 237 MiB 的 `no-map` 洞，短时间没崩；
这一轮正式把它作为 `chopin-md-usage-gap` 保留（`no-map`，`reg = <0 0xe9b10000 0 0xed40000>`）。
代价是可用内存少 237 MiB。

### 13.3 内核 release 钉住

设备上已装好 `7.3.4-g5775fb2ac0a1-dirty` 的模块，而源码树 HEAD 已经走到 `676614a32`。
直接重编会让 release 变成 `7.3.4-g676614a32...`，模块目录对不上（panfrost 等就加载不了）。
所以 `scripts/setlocalversion` 加了一个钩子：

```sh
if test -n "$CHOPIN_LOCALVERSION"; then echo "$CHOPIN_LOCALVERSION"; exit 0; fi
```

构建时带 `CHOPIN_LOCALVERSION='-g5775fb2ac0a1-dirty'`，这样**只换 boot 镜像里的
Image.gz + dtb，不用动模块**（本次只碰触摸驱动和 DTS，模块 ABI 没变）。

### 13.4 产物（待刷入）

| 项 | 值 |
| --- | --- |
| 镜像 | <workdir>\out\boot-chopin-touch-gap.img（19.5 MB，含触摸修复 + gap） |
| sha256 | `e6a3165f269a0865d41036b45fe0d2c2d114064ccfc87822e909b169a8bd915d` |
| 内含 | `chopin-md-usage-gap` 节点 ✅、`novatek,invert-y` 已删除 ✅（`zcat Image.gz | strings` 验证） |
| 回滚 | `out/boot-chopin-p0.img` |

刷入方式：关机后音量减 + 电源进 fastboot，`fastboot flash boot boot-chopin-touch.img`。

### 13.5 长稳观察（2026-11-15 05:10–07:10）：3.5 小时无 SError

Wayland + panfrost 桌面连续跑了 **3 小时 32 分**没有 SError：

- 其中 40 分钟是 dd 读写（96 MB 循环，fsync）+ 160 MB bytearray 反复分配 + glxgears 循环；
- 之后 2 小时完全空闲；
- `dmesg` 里 `SError` / `ufshcd_check_errors` 计数都是 0，内核日志从 327 s 起就没有任何输出；
- 负载期间 `free` 稳定，gnome-shell（pid 664）一直活着。

结论/影响：

- SError **不是纯 IO/内存压力能触发的**；
- 之前的两次重启（约 03:56、04:10）都落在「X11 会话还开着、反复 restart gdm、同时在批量走串口
  传文件」这段窗口里，嫌疑更偏向 X11/合成器反复初始化或 ttyGS0 大批量传输，而不是日常 Wayland 桌面；
- 所以 **P0 的严重性要重新评估**：先刷「只修触摸」的镜像，用交互式桌面跑几小时看会不会崩，
  再决定要不要付出 237 MiB 去保留那块 gap。

两个镜像：

| 镜像 | 内容 | sha256 |
| --- | --- | --- |
| `out/boot-chopin-touch.img` | **只修触摸**（建议先刷这个） | `7593c77245f75dd3a1204260162e7794470eff3bc3d99299d389e673a67e2b98` |
| `out/boot-chopin-touch-gap.img` | 触摸修复 + md gap 保留（P0 实验） | `e6a3165f269a0865d41036b45fe0d2c2d114064ccfc87822e909b169a8bd915d` |

两个镜像的 release 都是 `7.3.4-g5775fb2ac0a1-dirty`，都能直接配设备上现有的模块。

### 13.6 刷入与验证（2026-11-15 13:10）

这次刷机踩了两个坑，都记在这里免得再犯：

1. **boot 镜像的 dtb 段必须沿用原厂 blob（201,848 字节）**。第一次打包时传了
   `--dtb mt6893-xiaomi-chopin.dtb`（编译产物 280,640 字节），刷入后 LK 阶段就反复重启；
   不传 `--dtb`、沿用模板段后正常启动。**运行时设备树用的是内核里内嵌的
   `chopin-board.dtb`，和 boot 镜像的 dtb 段无关**，所以打包时不要动它。
2. **release 字符串钉错了**。`scripts/setlocalversion` 的钩子最初只输出
   `-g5775fb2ac0a1-dirty`，丢掉了 `7.3.4` 前缀（这个内核的 Makefile 直接拿脚本输出当整个
   release）。结果 `uname -r` 对不上，panfrost 等模块 vermagic 不匹配全部不加载、桌面起不来。
   改成 `echo "${KERNELVERSION}$CHOPIN_LOCALVERSION"` 后正常。

刷入后的实机状态：

| 检查 | 结果 |
| --- | --- |
| `uname -r` | `7.3.4-g5775fb2ac0a1-dirty` ✅ |
| 模块 | panfrost / gpu_sched / drm_shmem_helper 已加载，`renderD128` 在 |
| 会话 | `loginctl` → `Type=wayland`，gnome-shell 正常 |
| 设备树 | `novatek,invert-y` 不存在；`chopin-md-usage-gap` 不存在（这版只修触摸） |
| `dmesg` | `SError` / `ufshcd_check_errors` 计数 0 |

**触摸验证**：让用户在屏幕上按 3 列 × 8 行的网格点了一遍，evtest 记录的上报坐标：

- 三列 x ≈ {70–110, 480–570, 990–1050}，八行 y 从 ~1830 递减到 ~40，**每列都单调**；
- 右列 y 序列 1837→1600→1386→1074→772→551→340→231→39，**没有出现镜像跳变**；
- 也就是「右半边 Y 反向」的问题已经消失，剩下的偏差只剩手指落点本身的误差量级。

镜像结论：移植时加的 `novatek,invert-y` / 右半屏翻转确实是错的，删掉后触摸映射恢复正常。
## 14. 2026-11-15 13:40–14:10：USB 网络打通（CDC-NCM + SSH）

### 14.1 结论（已实机验证）

- 手机现在通过 USB 口提供一张 **CDC-NCM** 网卡：
  - 设备端：`usb0 = 192.168.42.2/24`，dnsmasq 发 192.168.42.100–110；
  - Windows 侧：自动枚举成 **UsbNcm Host Device**（“以太网 2”），DHCP 拿到 `192.168.42.106`；
  - `ping 192.168.42.2`、`ssh root@192.168.42.2` 都通。
- **SSH 免密可用**：私钥在 `out/chopin_key`，公钥已写入设备 `/root/.ssh/authorized_keys`。
- **重启后自动生效**：initramfs 先建 ACM-only gadget；systemd 的 `chopin-gadget.service` 发现
  `/etc/chopin-gadget-rndis` 存在、而当前 gadget 没有网络功能，就 unbind → 重建 acm+ncm → 重新 bind。
  本轮重启后实测：4.0 s 完成重建，usb0 / DHCP / SSH 全部正常。

### 14.2 为什么用 NCM 而不是 RNDIS

- RNDIS 功能本身能起来（Windows 也把它识别成 `RNDIS` 设备），但**这台 Windows 11（build 26300）没有绑定驱动**：
  `USB\VID_1D6B&PID_0104&MI_02` = Problem 28；系统里没有 `rndismpx.sys`，`netrndis.inf` 只匹配
  `ms_rndisusb`（需要 MS OS 描述符），Linux gadget 默认不带。
- Windows 11 自带 CDC-NCM 驱动：`usbncm.inf` 匹配 `USB\Class_02&SubClass_0d&Prot_00`，正好是 Linux
  `f_ncm` 控制接口的类/子类/协议。换成 `ncm.usb0` 后 Windows 立刻加载 `UsbNcm Host Device`，
  不需要 INF、不需要 OS 描述符。

### 14.3 两个坑（都踩过）

1. **configfs 不能用 `rm -rf` 拆 gadget**。属性文件不能 unlink，`rm -rf $G` 会留下 function 目录；
   下次 bind 时旧的 rndis 还占着 u_ether，NCM 只能拿到 usb1（usb0 一直是 down）。
   正确顺序：unbind → 删 `configs/c.1` 里的软链 → `rmdir` 各 function → `rmdir` strings/configs/functions
   → `rmdir` gadget。第一次用错误拆法把 USB 彻底搞没了（手机还在跑、桌面正常，但 USB 上什么都没有），
   只能断电重启恢复。
2. **串口密码提示符是 `????????? `，不是 `Password: `**。设备 locale 是中文，
   `login` 的 “Password: ” 被渲染成 9 个问号。`serial-run.ps1` / `serial-xfer.ps1` 原来只匹配
   `Password:`，于是永远卡在登录（表现为 “Login incorrect” / 超时）。已改成同时匹配 `\?{4,}`。

### 14.4 用法

```powershell
# 串口（COM11，root/chopin）
powershell -File D:\MT6891-Mainline\scripts\serial-run.ps1 -Cmd "uname -r"

# SSH（免密，走 USB 网络）
ssh -i D:\MT6891-Mainline\out\chopin_key root@192.168.42.2 "uptime"

# scp
scp -i D:\MT6891-Mainline\out\chopin_key 文件 root@192.168.42.2:/root/
```

### 14.5 还没做

- Windows 侧给这张网卡开 **ICS**（需要管理员）手机才能上外网；当前只有 host↔device，
  没有外网时 apt 仍然只能离线装包。
- gadget 脚本里 usb0 的地址/网段仍是写死的 `192.168.42.0/24`（沿用 RNDIS 方案）。
- `/etc/chopin-gadget-rndis` 这个名字已经不准了（脚本同时认 `chopin-gadget-net`），先留着兼容。

---

## 15. 2026-11-15 14:10–14:40：WiFi 驱动打通（WLAN-GEN4 + NVRAM + SoC 固件）

### 15.1 现象

驱动是 built-in 的，启动日志有 `Start to do wlan module init 0x6893`、`WLAN-GEN4 driver init, ret:0`、
conninfra pre-cal `ret=0`，但**从来没有 wlan0**，`/sys/class/net` 只有 lo 和 usb0。

### 15.2 根因链（三层）

1. **NVRAM 缺失**：驱动 probe 时 `request_firmware("mediatek/mt6893/WIFI")`；
   mainline 的 linux-firmware 没有这个文件。驱动把「加载 NVRAM + WiFi 上电」推迟到
   workqueue，2/6/9/13 s 各重试一次，4 次后放弃（`CHOPIN-NVRAM: giving up`）。
   NVRAM 真身在 **nvdata 分区** `/APCFG/APRDEB/WIFI`（6146 B，每台机器的出厂校准）。
2. **SoC 固件缺失**：NVRAM 有了以后上电要 `WIFI_RAM_CODE_soc3_0_1a_1.bin` 和
   `soc3_0_ram_*.bin`（vendor 逻辑分区 `/firmware/` 里）；**缺 `soc3_0_ram_wmmcu_1a_1_hdr.bin`
   时直接 `WiFi on/off op fail, g_data=-1`**，probe reason:3。
3. **用户态缺失**：rootfs 里没有 `wpasupplicant` / `iw` / `wireless-regdb`，
   NetworkManager 把 wlan0 标成 unavailable（`faux_driver regulatory: regulatory.db failed`）。

### 15.3 修复（已实机验证）

新增 `chopin-wifi-firmware.sh` + `chopin-wifi-firmware.service`（`WantedBy=sysinit.target`，
`Before=sysinit.target`，在驱动放弃之前跑完）：从 nvdata 取 NVRAM、从 vendor 逻辑分区取固件，
装进 `/lib/firmware`；幂等。刷入/重刷 rootfs 后第一次启动即生效。

实机证据：

```
[    2.088244] CHOPIN-NVRAM: loaded 'mediatek/mt6893/WIFI', size=6146, state=READY
[    2.088269] CHOPIN-NVRAM: loaded after deferral, powering on WiFi
...
wlan0  wlan1  p2p0  ap0  (ip link)
```

`CHOPIN-DIAG net:` 也能看到 wlan0（e6:02:f7:45:3a:1d，DOWN/NO-CARRIER）。

### 15.4 还没做

- rootfs 缺 `wpasupplicant`、`iw`、`wireless-regdb`：需要离线 .deb（Windows 下载后 scp），
  装完 NetworkManager 才能扫 AP、连网。
- 驱动还会请求 `wifi_sigma.cfg` / `txpowerctrl.cfg`（-2 警告，可选；vendor 只有 `wifi.cfg`，已装）。
- 蓝牙（同属 conninfra）还没验证；BT 固件同样在 vendor 分区。

---

## 16. 2026-11-15 14:45–15:05：WiFi 连上外网（用户态补齐 + 时间同步）

### 16.1 离线装 WiFi 用户态

设备没有外网，所以在构建机（WSL）上从 Debian trixie arm64 索引解析依赖并下载 .deb，
经 USB 网络 scp 到设备，`dpkg -i` 安装（`dpkg --audit` 干净）：

```
iw 6.9-1+b1            libnl-3-200 3.7.0-2      libnl-genl-3-200 3.7.0-2
libnl-route-3-200 3.7.0-2   libpcsclite1 2.3.3-1  wireless-regdb 2026.05.30-1~deb13u1
wpasupplicant 2:2.10-24
```

装完 NetworkManager 仍显示 wlan0 unavailable —— **需要 `systemctl restart NetworkManager`**
才会去用新的 wpa_supplicant（D-Bus 激活）。重启后 wlan0/wlan1/ap0 变为 disconnected（可用），
`nmcli device wifi rescan` 能列出周围 AP，`iw reg get` 也有 regdb 了。

### 16.2 连接与结果

```
nmcli device wifi connect C8:50:E9:CC:11:B0 password *** ifname wlan0
```

- 连上 5 GHz（5240 MHz，TX 780 Mbit/s，信号 -30 dBm），DHCP 拿到 **192.168.1.220/24**，
  默认路由 192.168.1.1；
- `ping 223.5.5.5` 14 ms；`apt-get update` 33 MB / 18 s（约 1.8 MB/s）。

### 16.3 坑：系统时间停在 2026-04-14，HTTPS 全挂

- 现象：`ping`/HTTP 正常，但 `curl https://mirrors.tuna...` 返回 000（5 s 超时）。
- 根因：RTC 没有电池（读出来是 2069-12-31 的垃圾值），系统时间停在 2026-04-14，
  TLS 证书"尚未生效" → 握手失败；`apt` 的源又全是 https，所以直接卡死。
- 修复：`date -u -s ...` 手动校准后 HTTPS 立即正常；再装 **systemd-timesyncd**
  （`timedatectl` 现在 `System clock synchronized: yes / NTP service: active`，
  RTC 也被内核写回正确时间）。

### 16.4 已固化

- `debian/config/packages.gnome` 增加：`wpasupplicant iw wireless-regdb systemd-timesyncd
  tcpdump iperf3`；
- `02-configure-rootfs.sh` 增加 enable `systemd-timesyncd`、`wpa_supplicant`；
- 设备上 NetworkManager 已保存 "WiFi 1" 配置（autoconnect），冷启动会自动连。

---

## 17. 2026-11-15 14:30–14:40：WLAN 多接口的解释与 NetworkManager 收口

### 17.1 四个 netdev 是哪来的

MTK WLAN-GEN4 驱动在**同一个 wiphy** 上建了四个 netdev：

| 接口 | 作用 | 正常状态 |
| --- | --- | --- |
| `wlan0` | 主 STA（station），日常上网用的就是它 | UP，连着 AP |
| `wlan1` | 第二个 STA，驱动支持双 STA 并发（如 2.4G+5G 同时连） | DOWN，不用 |
| `ap0` | Soft-AP（热点）接口 | DOWN，开热点才用 |
| `p2p0` | Wi-Fi Direct | DOWN，不用 |

所以终端里 `wlan1/p2p0/ap0` 全是 DOWN 是**正常的**，只有 `wlan0` 需要 UP
（当时 `wlan0` 已经是 `192.168.1.220` + 已连接，只是截图里滚过去了）。

### 17.2 当时的真实问题：多了一个野配置在 ap0 上乱连

`nmcli device` 里 `ap0` 显示 `connecting (configuring) → WiFi`，日志：

    device (ap0): state change: config -> failed (reason 'ssid-not-found')
    device (ap0): Activation: failed for connection 'WiFi'

原因是面板里点过 SSID "WiFi"，NetworkManager 建了一个**没绑定接口**的 "WiFi" 配置，
autoconnect 会在每个 wifi device（包括 ap0/wlan1）上尝试，而 ap0 是 AP 接口、永远
associate 不上，于是一直重试。已删除该配置，保留绑定到 `wlan0` 的 "WiFi 1"。

### 17.3 收口：NM 不管理多余接口

新增 `/etc/NetworkManager/conf.d/chopin-interfaces.conf`（合并了原来的
`chopin-usb-gadget.conf`，NM 对 `unmanaged-devices` 是**后者覆盖前者**，两个文件会打架）：

    [keyfile]
    unmanaged-devices=interface-name:usb0;interface-name:usb1;interface-name:ap0;interface-name:wlan1;interface-name:p2p0

效果：`nmcli device` 里 wifi 只剩 `wlan0`（connected），GNOME 控制中心不再出现
ap0/wlan1 两个多余的 Wi-Fi 页签。

**代价**：GNOME 的"打开 Wi-Fi 热点"目前不可用（ap0 被 unmanage 了）。要开热点时把
ap0 从 unmanaged 列表里去掉，或直接用 hostapd 在 ap0 上起。

---

## 18. 2026-11-15 14:50–15:10：扬声器出声（MT6893 + MT6359 + CS35L41）

### 18.1 之前为什么没有声卡

- machine driver 其实已经在树里：`sound/soc/mediatek/mt8192/mt6893-mt6359.c`（专门为 chopin 写的，
  DAI 链是 AFE I2S3 → 两颗 CS35L41），但 `CONFIG_SND_SOC_MT6893_MT6359` **从来没开**，
  CS35L41 codec 也没编 → `/proc/asound/cards` 一直是空的。
- 编成模块还差一个符号：machine driver 调 `mt8192_mck_enable()/mt8192_mck_disable()`，
  而 AFE 模块没有导出这两个（modpost: undefined!）→ 在 `mt8192-afe-clk.c` 补了
  `EXPORT_SYMBOL_GPL`（内核 commit `8bf059655`）。

### 18.2 改了哪些

- `chopin_defconfig`：`CONFIG_SND_SOC_MT6893_MT6359=m`（Kconfig 会 select MT6359 codec 和
  CS35L41_I2C）；
- 模块：`mt6893-mt6359.ko`、重编的 `snd-soc-mt8192-afe.ko`、`snd-soc-cs35l41{,-lib,-i2c}.ko`、
  `snd-soc-wm-adsp.ko`、`cs_dsp.ko`；开机由 udev 按 modalias 自动加载（不需要 modules-load）。

### 18.3 实机结果

- 两颗功放在 i2c6 0x40/0x42：`Cirrus Logic CS35L41 (35a40), Revision: B2`；
- **card 0 [mt6893mt6359]** 注册成功，`Playback_1` 可播放，264 个 mixer control；
- `speaker-test -D hw:0,0 -c 2 -t sine -f 440 -l 1` → **外放有声音**（用户确认，左右声道）；
- 音量：`Left/Right Digital PCM`（0–913，89% = 0 dB 最大），已调到 70%（-22.25 dB）。

### 18.4 注意 / 遗留

- **AFE 模块不能 rmmod 重载**：remove 路径有 refcount WARN，重载 probe 直接 `-EACCES`
  （第一次就是先加载 machine driver 再加载 codec，卡没起来；重启后由 udev 按正确顺序加载就好了）。
  以后动音频要重启，别热重载 AFE。
- 开机 15.9 s 有一条 `refcount_t: addition on 0` 的 WARN（kworker），暂时没有可见影响，待查。
- **耳机/听筒/麦克风**（MT6359 PMIC codec 侧）、UCM 配置、GNOME 音量键联动都还没验证。

### 18.5 PipeWire：桌面音频也通了（15:15）

- 卡出现后 `pactl` 仍看不到 sink：`pipewire.service` 的单元里是
  `Requires=pipewire.socket dbus.service`，而 rootfs 里**没有 `dbus-user-session`**，
  用户会话里根本没有 `dbus.service` → 只有 `pipewire-pulse.service` 起来，
  主 pipewire 和 wireplumber 都起不来。
- 修复：`apt-get install dbus-user-session pulseaudio-utils`，然后
  `systemctl --user enable --now pipewire.socket pipewire.service wireplumber.service`。
- 结果：
  ```
  $ pactl list short sinks
  45  alsa_output.platform-sound.stereo-fallback  PipeWire  s32le 2ch 48000Hz  IDLE
  ```
  `paplay /tmp/test440.wav` 返回 0，sink 从 SUSPENDED 变 IDLE，默认 sink 已设为它、
  音量 70%。GNOME 的声音面板和音量键现在有东西可控了。
- 构建树：`packages.gnome` 增加 `dbus-user-session`（pipewire/pipewire-pulse/wireplumber
  原本就有）。

---

## 19. 2026-11-15 15:30–15:50：系统音量条"最小还有声"的根因与修复

### 19.1 现象

- GNOME 音量条已经拖到最小（界面显示静音），**扬声器还是有声音**；
- 反过来调大也感觉变化不明显；
- WirePlumber 的保存音量还会自己往下掉（84% → 54% → 28% → 1%）。

### 19.2 根因

- CS35L41 声卡只暴露一个 **joined mono 的硬件音量控制**（Left/Right Analog PCM、
  Left/Right Digital PCM），PipeWire 的 ALSA 设备走的是 **hardware volume**
  （pw-dump 里能看到 route.hw-volume）；
- 但实测拖系统音量条时**这两个 mixer 控件根本不动**（始终 817 / 19），
  也就是 PipeWire 以为自己在调硬件，实际输出电平仍由固定的功放增益决定 →
  系统音量条变成"装饰"，0% 也照样出声；
- 保存的路由音量（0.216 线性 ≈ 18%）又会在每次播放开始/结束时被重新应用，
  造成"音量条自己往下掉"。

### 19.3 修复

新增 /etc/wireplumber/wireplumber.conf.d/51-chopin-soft-mixer.conf：

    monitor.alsa.rules = [
      { matches = [ { device.name = "alsa_card.platform-sound" } ]
        actions = { update-props = { api.alsa.soft-mixer = true } } },
      { matches = [ { node.name = "alsa_output.platform-sound.stereo-fallback" } ]
        actions = { update-props = { api.alsa.soft-mixer = true } } }
    ]

重启 pipewire/wireplumber 后，pw-dump 里 device 和 node 都带上了
api.alsa.soft-mixer: true → 系统音量改由 PipeWire 软件衰减，
0% 就是真正的 -inf，硬件增益固定（模拟 +19.5 dB / 数字 0 dB）。

### 19.4 另外

- WirePlumber 保存的路由音量被早期调试写成了 0.216（≈18%），
  已改回当前音量（0.343 ≈ 70%），避免它一直把音量往回拉。
- 重建 rootfs 时这个 conf 走 overlay，不需要额外脚本。

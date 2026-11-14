> **历史现场记录（2026-11-14 至 2026-11-15）**：路径已按三仓库布局更新，内容保留原样。
> 当前计划见 [PLAN.md](PLAN.md)，构建见 [../README.md](../README.md)。

# chopin Debian 13 实机 bring-up 记录

> 时间：2026-11-14 23:30
> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，MT6891Z/CZA）
> 镜像基线：Linux 7.3.4 + 20 补丁；Debian 13.7 + GNOME 48.7 + Mesa 25.0.7
> 本文是给下一个对话/下一次接手的**现场状态**，方案见 [debian.md](debian.md)，
> 构建见 [../README.md](../README.md)。

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

Windows 副本在 `D:\chopin-linux\out\`，文件名相同。
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

    cd D:\chopin-linux
    .\scripts\flash-debian.ps1

等价手动：

    & "D:\Program Files (x86)\platform-tools\fastboot.exe" flash boot D:\chopin-linux\out\boot-chopin-debian.img
    & "D:\Program Files (x86)\platform-tools\fastboot.exe" flash userdata D:\chopin-linux\out\chopin-rootfs.sparse.img
    & "D:\Program Files (x86)\platform-tools\fastboot.exe" reboot

注意：userdata 是 2.9 GB sparse，分 12 个 chunk，约 90 s；32 位 fastboot 可用。
不要刷 3.7 GB 的 raw `chopin-rootfs.img`。

### 5.2 启动后看串口

Windows 出现 COM11 后：

    powershell -NoProfile -ExecutionPolicy Bypass -File D:\chopin-linux\scripts\serial-cmd.ps1 -Send "id" -WaitMs 2000

登录：`root` / 密码 `chopin`（用户 `chopin` 同密码）。
如果串口没有出现，但主机至少出现 `VID_1D6B&PID_0104`，说明 gadget 绑定成功、只是
getty/驱动问题；如果连 USB 设备都没有，进入 5.3。

### 5.3 没有 USB 时用 debug3

`boot-chopin-debug3.img`（D:\chopin-linux\out）是已知能枚举 COM11 的镜像：

    fastboot flash boot D:\chopin-linux\out\boot-chopin-debug3.img
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

- 内核：`/root/chopin-linux/linux`，release `7.3.4-ga9777a8559e0-dirty`
- 内核产物：`/root/chopin-linux/out/modules/lib/modules/<release>`
- 正常镜像：`debian/out/boot-chopin-debian.img`、`chopin-rootfs.sparse.img`
- 诊断镜像：`boot-chopin-debug*.img`、`boot-chopin-rescue*.img`（同一目录）
- initramfs 源：`debian/initramfs/`（`init`、`chopin-gadget.sh`、debug/rescue 变体）
- 串口工具：`D:\chopin-linux\scripts\serial-cmd.ps1`（CR 回车、115200 8N1、DTR/RTS）
- 刷机脚本：`D:\chopin-linux\scripts\flash-debian.ps1`

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

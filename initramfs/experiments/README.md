# initramfs 历史实验变体

这些脚本是 2026-11-14 bring-up 期间用来分离问题的临时 initramfs，**不参与当前构建**。
当前 `05-mkinitramfs.sh` 只打包 `../init` 和 `../chopin-gadget.sh`。

| 文件 | 用途 |
| --- | --- |
| `debug-init` / `debug-init2` / `debug-init3` | 不 switch_root，只建 gadget、打印状态、给 shell；debug3 曾成功枚举 COM11 |
| `probe-init` | 采 UDC/DRM/PCIe 等状态后挂 rootfs |
| `rescue-init` / `rescue2-init` | 救援 shell / 重新绑定 gadget |
| `rescue-probe-init` | 救援 + 状态采集 |

保留它们是为了记录"为什么最终 init 长这样"，以及无 USB 时如何取证。使用方法：把对应文件
复制成 `initramfs/init` 后跑 `05-mkinitramfs.sh`（不要直接改当前 `init`）。

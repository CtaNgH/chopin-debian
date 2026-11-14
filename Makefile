# chopin-debian —— 顶层入口
SHELL := /bin/bash
ARGS ?=

.PHONY: all build rootfs bootimg clean distclean help

all: build

help:
	@echo "sudo make build            完整构建 rootfs + initramfs + rootfs 镜像 + boot.img"
	@echo "sudo make build ARGS='--skip-gnome --skip-mesa'  精简构建"
	@echo "sudo make build ARGS='--rebuild'                 强制重建 rootfs"
	@echo "sudo make bootimg          只重新打包 boot.img"
	@echo "sudo make clean            删除 build/ out/ third_party/"
	@echo "注意：构建需要 root（mmdebstrap/chroot/mount），推荐在 WSL2 Ubuntu 24.04 中运行。"

build:
	@if [ "$$(id -u)" -ne 0 ]; then echo "请用 sudo make build（或 sudo ./scripts/build-all.sh）"; exit 1; fi
	./scripts/build-all.sh $(ARGS)

rootfs:
	@if [ "$$(id -u)" -ne 0 ]; then echo "请用 sudo make rootfs"; exit 1; fi
	./scripts/build-all.sh --skip-mesa

bootimg:
	@if [ "$$(id -u)" -ne 0 ]; then echo "请用 sudo make bootimg"; exit 1; fi
	./scripts/07-mkbootimg.sh

clean:
	rm -rf build out third_party

distclean: clean

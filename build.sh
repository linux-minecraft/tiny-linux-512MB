#!/bin/bash
# ============================================================
# MyLinux 完整一键构建脚本
# 作者：林煊然
# 功能：编译内核 -> 编译BusyBox -> 安装到rootfs -> 生成initramfs -> 打包ISO
# ============================================================

set -e

# 基础目录（脚本所在目录）
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 各组件路径
KERNEL_DIR="$BASE_DIR/linux-7.1.8"
BUSYBOX_DIR="$BASE_DIR/busybox-1.36.1"
ROOTFS_DIR="$BASE_DIR/rootfs"
ISO_DIR="$BASE_DIR/iso-final"
ISOHDPFX="$BASE_DIR/isohdpfx.bin"

# 输出文件
OUTPUT_ISO="${1:-$BASE_DIR/mylinux.iso}"
JOBS=$(nproc)

echo "========================================"
echo "  MyLinux 完整一键构建工具"
echo "  作者：林煊然"
echo "  并行编译: $JOBS 线程"
echo "========================================"
echo ""

# 检查目录
for dir in "$KERNEL_DIR" "$BUSYBOX_DIR" "$ROOTFS_DIR" "$ISO_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "[错误] 找不到目录: $dir"
        exit 1
    fi
done

# 检查配置文件
if [ ! -f "$KERNEL_DIR/.config" ]; then
    echo "[错误] 内核配置文件不存在: $KERNEL_DIR/.config"
    exit 1
fi
if [ ! -f "$BUSYBOX_DIR/.config" ]; then
    echo "[错误] BusyBox配置文件不存在: $BUSYBOX_DIR/.config"
    exit 1
fi

# 提取 MBR 引导扇区（如果不存在）
if [ ! -f "$ISOHDPFX" ]; then
    echo "[0/6] 提取 MBR 引导扇区..."
    if [ -f "$BASE_DIR/mylinux-hybrid.iso" ]; then
        dd if="$BASE_DIR/mylinux-hybrid.iso" of="$ISOHDPFX" bs=446 count=1 2>/dev/null
        echo "  从 mylinux-hybrid.iso 提取"
    else
        echo "  警告: 找不到参考ISO，将不使用 isohybrid MBR"
        ISOHDPFX=""
    fi
fi

# 1. 编译内核
echo ""
echo "[1/6] 编译 Linux 内核 7.1.8..."
cd "$KERNEL_DIR"
make -j"$JOBS" bzImage 2>&1 | tail -5
echo "  内核编译完成: $(ls -lh arch/x86/boot/bzImage | awk '{print $5}')"

# 2. 编译 BusyBox
echo ""
echo "[2/6] 编译 BusyBox 1.36.1..."
cd "$BUSYBOX_DIR"
make -j"$JOBS" 2>&1 | tail -5
echo "  BusyBox编译完成: $(ls -lh busybox | awk '{print $5}')"

# 3. 安装 BusyBox 到 rootfs
echo ""
echo "[3/6] 安装 BusyBox 到 rootfs..."
cd "$BUSYBOX_DIR"
make install CONFIG_PREFIX="$ROOTFS_DIR" 2>&1 | tail -3
# 确保 busybox 二进制文件也复制过去
cp -f busybox "$ROOTFS_DIR/bin/busybox"
chmod +x "$ROOTFS_DIR/bin/busybox"
echo "  BusyBox安装完成"

# 4. 复制内核到 ISO 目录
echo ""
echo "[4/6] 复制内核到 ISO 目录..."
cp -f "$KERNEL_DIR/arch/x86/boot/bzImage" "$ISO_DIR/boot/vmlinuz"
echo "  内核已复制: $(ls -lh "$ISO_DIR/boot/vmlinuz" | awk '{print $5}')"

# 5. 生成 initramfs
echo ""
echo "[5/6] 生成 initramfs..."
cd "$ROOTFS_DIR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$ISO_DIR/boot/initramfs.gz"
echo "  initramfs生成完成: $(ls -lh "$ISO_DIR/boot/initramfs.gz" | awk '{print $5}')"

# 6. 打包 ISO
echo ""
echo "[6/6] 打包 ISO..."
cd "$ISO_DIR"
ISOHDPFX_OPTION=""
if [ -n "$ISOHDPFX" ] && [ -f "$ISOHDPFX" ]; then
    ISOHDPFX_OPTION="-isohybrid-mbr $ISOHDPFX"
fi

xorriso -as mkisofs \
    -z \
    -o "$OUTPUT_ISO" \
    -R -J \
    -V MYLINUX \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e efi.img \
    -no-emul-boot \
    $ISOHDPFX_OPTION \
    .

echo ""
echo "========================================"
echo "  构建完成！"
echo "  输出文件: $OUTPUT_ISO"
echo "  文件大小: $(du -h "$OUTPUT_ISO" | cut -f1)"
echo "========================================"

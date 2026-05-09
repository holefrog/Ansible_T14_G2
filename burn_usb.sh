#!/bin/bash
# ==============================================================================
# ThinkPad T14 Gen 2 Ubuntu UI - 制作脚本 (只修改目录逻辑)
# ==============================================================================
set -e

# --- 错误处理函数 ---
error_handler() {
    echo -e "\n\033[31m!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "错误：脚本在执行过程中意外中断！"
    echo "状态：这个 U 盘目前【不可用】。"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\033[0m"
}
trap 'error_handler' ERR

# --- 路径定义 ---
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_DIR="${BASE_DIR}/iso"
CONFIG_DIR="${BASE_DIR}/configs"
ANSIBLE_DIR="${BASE_DIR}/ansible"

# --- 1. 智能查找镜像 ---
# 自动寻找 iso/ 目录下的第一个 .iso 文件
TARGET_ISO=$(ls "${ISO_DIR}"/*.iso 2>/dev/null | head -n 1)

if [ -z "$TARGET_ISO" ]; then
    echo "错误：在 $ISO_DIR 中找不到任何 .iso 镜像。"
    exit 1
fi

# --- 2. 交互式选择 USB 设备 ---
echo -e "\n正在扫描 USB 存储设备..."
mapfile -t USB_LIST < <(lsblk -dpno NAME,SIZE,MODEL,TRAN | grep "usb")

if [ ${#USB_LIST[@]} -eq 0 ]; then
    echo "错误：未检测到 USB 设备。"
    exit 1
fi

echo -e "------------------------------------------------------------"
echo -e "ID\tPATH\t\tSIZE\tMODEL"
for i in "${!USB_LIST[@]}"; do
    echo -e "$((i+1))\t${USB_LIST[$i]}"
done
echo -e "------------------------------------------------------------"

read -p "请选择目标 U 盘编号 (1-${#USB_LIST[@]}): " idx
[ ! "$idx" =~ ^[0-9]+$ ] && exit 1

SELECTED_INFO="${USB_LIST[$((idx-1))]}"
USB_DEV=$(echo "$SELECTED_INFO" | awk '{print $1}')

# 二次确认
echo -e "\n\033[41;37m  ☢️  确认写入  ☢️  \033[0m"
echo -e "镜像: $(basename "$TARGET_ISO")"
echo -e "目标: $USB_DEV ($SELECTED_INFO)"
read -p "确认请输入 yes: " confirm
[[ "$confirm" != "yes" && "$confirm" != "YES" ]] && exit 0

# --- 3. 核心制作逻辑 (保持你提供的原始参数) ---
REMASTERED_ISO="/tmp/ubuntu-remastered.iso"

echo "==> 1. 正在生成引导配置..."
TMP_GRUB=$(mktemp)
cat <<'EOF' > "$TMP_GRUB"
set timeout=1
set default=0
menuentry 'Autoinstall Ubuntu Desktop (ThinkPad T14 Gen 2)' {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall ds=nocloud nomodeset ---
    initrd /casper/initrd
}
EOF

echo "==> 2. 正在重制 ISO..."
rm -f "$REMASTERED_ISO"
xorriso -indev "$TARGET_ISO" \
    -outdev "$REMASTERED_ISO" \
    -boot_image any replay \
    -map "$TMP_GRUB" /boot/grub/grub.cfg \
    -compliance no_emul_toc \
    -padding 0 \
    -overwrite on \
    -volid "UBUNTU_AUTO" >/dev/null 2>&1

echo "==> 3. 正在烧录 (dd)..."
sudo dd if="$REMASTERED_ISO" of="$USB_DEV" bs=4M status=progress
sync

echo "==> 4. 正在创建配置分区..."
sudo sgdisk -e "$USB_DEV"
sudo sgdisk -n 0:0:0 -t 0:0700 -c 0:"CIDATA" "$USB_DEV"
sudo partprobe "$USB_DEV" || true
sleep 3

TARGET_PART="/dev/$(lsblk "$USB_DEV" -l -o NAME | tail -n 1)"
sudo umount -l "$TARGET_PART" 2>/dev/null || true
sudo mkfs.vfat -n CIDATA "$TARGET_PART" >/dev/null

echo "==> 5. 正在原样注入配置与固件..."
USB_MNT=$(mktemp -d)
sudo mount "$TARGET_PART" "$USB_MNT"
# 原样拷贝 configs 下的所有文件 (user-data, meta-data)
sudo cp -v "${CONFIG_DIR}/"* "$USB_MNT/"
# 原样拷贝整个 ansible 目录
sudo cp -rv "$ANSIBLE_DIR" "$USB_MNT/"
sync
sudo umount "$USB_MNT"

# 清理并断电
rm -f "$REMASTERED_ISO" "$TMP_GRUB"
for p in $(lsblk "$USB_DEV" -no PATH | grep -v "^$USB_DEV$"); do sudo umount -l "$p" 2>/dev/null || true; done
sync
sudo udisksctl power-off -b "$USB_DEV" || true

trap - ERR
echo "=================================================="
echo "制作成功！"

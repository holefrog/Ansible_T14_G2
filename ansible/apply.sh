#!/bin/bash
set -euo pipefail
echo "==> 正在执行 Ansible 本地化部署 (Ubuntu 24.04)..."

# --- 新增下面这行，确保脚本在自身所在目录运行 ---
cd "$(dirname "$0")"


# 等待网络连通
echo "==> 检查网络连接..."
for i in {1..10}; do
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo "==> 网络已连接"
        break
    fi
    echo "==> 等待网络... ($i/10)"
    sleep 3
done

# 检查并安装 Ansible
if ! command -v ansible-playbook &>/dev/null; then
    echo "==> 未找到 Ansible，等待 apt 锁并开始安装..."
    # 使用 Timeout 参数防止被 unattended-upgrades 锁死导致安装失败
    sudo apt-get -o DPkg::Lock::Timeout=300 update -qq
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y ansible
fi

# 执行剧本：-i 指定主机文件，-c local 开启本地连接，-v 可选显示细节
if sudo -n true 2>/dev/null; then
    ansible-playbook -i inventory.yml site.yml -c local "$@"
else
    ansible-playbook -i inventory.yml site.yml -c local --ask-become-pass "$@"
fi

echo -e "\n✓ 部署完成！请重启系统以应用环境变量设置。"

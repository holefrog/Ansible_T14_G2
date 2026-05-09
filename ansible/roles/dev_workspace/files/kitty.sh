#!/bin/bash
set -e

echo "==> 1. 设置系统级的默认终端 (需要 sudo 权限)..."
sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 100
sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty

echo "==> 2. 覆盖 GNOME 桌面原生的 Ctrl+Alt+T 快捷键..."
# 禁用原生的默认终端快捷键绑定
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['']"

# 获取当前已有的自定义快捷键
CURRENT_BINDINGS=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)

# 将新的 Kitty 快捷键路径安全地追加进去
if [ "$CURRENT_BINDINGS" = "@as []" ]; then
  NEW_BINDINGS="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-kitty/']"
else
  NEW_BINDINGS=$(echo "$CURRENT_BINDINGS" | sed "s/]/, '\/org\/gnome\/settings-daemon\/plugins\/media-keys\/custom-keybindings\/custom-kitty\/']/")
fi
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_BINDINGS"

# 设置 Kitty 自定义快捷键的属性：名称、执行命令和按键
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-kitty/ name 'Kitty Terminal'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-kitty/ command 'kitty'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-kitty/ binding '<Control><Alt>t'

echo "==> 设置完成！现在按下 Ctrl+Alt+T 应该可以调用 Kitty 终端了。"
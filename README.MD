# 💻 Pure-T14-G2: ThinkPad T14 Gen 2 Ubuntu 24.04 深度定制方案

这是一个专为 **ThinkPad T14 Gen 2** 打造的 Ubuntu 24.04 LTS 自动化部署蓝图。

### 🛠️ 核心哲学
* **夺回主权**：坚决移除并锁定所有 Snap 包，回归纯净的 `.deb` 原生体验。
* **分层架构**：系统底层、硬件驱动、桌面外观、开发环境和日常应用严格解耦分离。
* **配置即代码**：将复杂的 Rime 词库同步、Aria2 守护进程及 VPN 逻辑完全自动化。

---

## 📂 架构与模块 (Role Architecture)

项目采用高度解耦的分层架构，各司其职，互不干扰：

```text
ansible/roles/
├── core_system/      # 【底层基座】时区、用户目录、sudoers、彻底锁定 Snap、挂载 NAS
├── hardware_t14/     # 【硬件特化】ThinkPad 专属配置、WiFi 节能模式调优、Netplan 规则
├── desktop_ui/       # 【桌面与交互】GNOME 扩展 (Vitals, Kbd-Informer)、DBus 修复、字体与主题
├── input_method/     # 【输入引擎】ibus-rime 安装与全套自定义词库同步
├── dev_workspace/    # 【开发工作台】SSH 密钥与环境、PuTTY、Kitty 终端
└── user_apps/        # 【日常应用】路由式分发安装 Firefox、Chrome、tmm、NextCloud、Aria2 等
```

项目根目录核心组件说明：

```text
.
├── ansible/                # Ansible 编排逻辑
│   ├── apply.sh            # 本地部署一键触发脚本
│   ├── site.yml            # 剧本总入口 (路由分发器)
│   └── roles/              # (见上方说明)
├── configs/                # 无人值守安装配置 (Autoinstall)
│   ├── meta-data
│   └── user-data           # 分区、david 用户创建及安装阶段逻辑
├── iso/                    # 原始 ISO 存放目录
├── burn_usb.sh             # 镜像重制与 U 盘烧录脚本
└── git_push_all.sh         # 代码提交脚本
```

---

## 🚀 实现逻辑

### 第一阶段：无人值守安装 (Cloud-init)

通过 `burn_usb.sh` 将 `user-data` 与 Ansible 编排文件注入镜像。

1. **镜像重制**：`xorriso` 将自定义 `grub.cfg` 注入原版 ISO，设置 `autoinstall` 引导参数。
2. **CIDATA 分区**：在 U 盘末尾创建独立的 FAT32 分区（标签 `CIDATA`），将 `configs/` 下的 `user-data`、`meta-data` 以及整个 `ansible/` 目录写入其中。
3. **安装阶段中转**：
   - `early-commands`：将 CIDATA 分区挂载至 `/tmp/cidata`，把 `ansible/` 目录复制到内存临时路径 `/tmp/ansible_tmp`，随后卸载分区（避免与安装程序竞争）。
   - `late-commands`：将内存中的 `ansible/` 持久化写入目标系统的 `/target/opt/ansible/`。
4. **首次启动**：系统重启后，`user-data` 的 `runcmd` 自动执行 `/opt/ansible/apply.sh`，日志写入 `/var/log/ansible_deploy.log`。

### 第二阶段：系统编排 (Ansible)

安装重启后，运行 `/opt/ansible/apply.sh` 进行深度定制：

* **模块化精准执行**：全量支持细粒度 Tags 管理，可随时执行 `ansible-playbook site.yml -t apps` 等命令精准重跑单个模块。
* **Snap 锁定方案**：卸载 `snapd` 后，通过写入 `/etc/apt/preferences.d/nosnap.pref`（APT Preferences Pin-Priority: -10）永久阻止其被 `apt upgrade` 重新拉起。
* **Firefox 官方化**：通过 APT Pinning 屏蔽 Ubuntu 默认仓库中的 Snap 版本，直接对接 Mozilla 官方 APT 仓库，确保获取原生 `.deb` 版本。
* **Headless DBUS 处理**：所有 `dconf` 写入操作均通过 `dbus-run-session` 包裹，并显式设置 `XDG_RUNTIME_DIR` 临时目录，确保在无图形会话的 Ansible 执行环境下可靠生效。

---

## ⚠️ 避坑指南 (Lessons Learned)

1. **结构重构原则**：绝不在 `tasks/main.yml` 中编写业务代码，必须使用 `include_tasks` 作为路由分发。

2. **YAML 语法地雷**：
   * `changed_when` 属性**绝对不能**挂在 `block` 层级，否则 Ansible 会解析失败。它必须精准挂在 `command` 或 `shell` 模块任务下。
   * **不可见字符错误**：严禁在代码中使用 **Non-breaking space (U+00A0)**。如果从网页直接复制，务必在 IDE 中清理一遍。

3. **变量抽象化**：为支持多设备共用一套逻辑，所有路径均已从硬编码抽象为变量（如 `user_home`）。

4. **dconf / DBUS 在 Headless 下的陷阱**：直接使用 Ansible `dconf` 模块在无图形会话时会静默失败。正确做法是改用 `shell: dbus-run-session dconf write ...`，并配合 `XDG_RUNTIME_DIR` 临时目录。`desktop_ui` 与 `input_method` 两个 role 均需保持这一写法一致。

5. **Netplan 覆写风险**：`hardware_t14` 中的 `01-netcfg.yaml` 是无条件写入的。若目标机器通过有线网运行 Ansible，当前配置仅包含 `wifis` 段，系统重启后有线连接将从 Netplan 管理中消失。如有有线依赖，需在 Netplan 配置中补充 `ethernets` 段。

6. **`systemd scope: user` 的环境变量依赖**：在 `become_user` 切换后，`$XDG_RUNTIME_DIR` 和 `$DBUS_SESSION_BUS_ADDRESS` 默认不会继承，导致 `systemctl --user` 静默失败。需在对应任务块的 `environment` 中显式注入 `XDG_RUNTIME_DIR: "/run/user/<uid>"`。

---

## 🔒 安全注意事项

> **以下内容不得明文提交至版本控制。**

| 敏感内容 | 当前位置 | 正确做法 |
|---|---|---|
| WiFi 密码 (`wifi_password`) | `group_vars/all.yml` | 移入 `ansible-vault` 加密文件 |
| 管理员密码哈希 (`admin_password_hash`) | `group_vars/all.yml` | 移入 `ansible-vault` 加密文件 |
| OpenVPN 客户端私钥 | `user_apps/files/*.ovpn` | 加入 `.gitignore`，通过 vault 或密钥管理系统分发 |

生成加密变量的快速命令：

```bash
ansible-vault encrypt_string 'your_secret' --name 'wifi_password'
```

---

## 📖 部署步骤

1. 将官方 Ubuntu 24.04 ISO 放入 `iso/` 目录。
2. 运行 `./burn_usb.sh` 制作定制镜像并烧录 U 盘。
3. 插入 ThinkPad T14 Gen 2 引导，系统自动完成无人值守安装并重启。
4. 系统首次启动后，`apply.sh` 将自动触发。如需手动重跑，执行：
   ```bash
   cd /opt/ansible && sudo ./apply.sh
   ```
5. 如需精准重跑单个模块：
   ```bash
   ansible-playbook -i inventory.yml site.yml -c local -t apps
   ```
6. 一切自动化执行完毕后，即可享受完美的纯净环境。

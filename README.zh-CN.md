# proxdump — 将 Proxmox VE 加密备份到云存储

[English](README.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | **简体中文** | [Русский](README.ru.md)

`proxdump` 使用 `vzdump` 备份 **Proxmox VE** 节点上的虚拟机和容器，在服务器上
**加密**归档，然后上传到 **Microsoft OneDrive**、**Google Drive**、**Dropbox**、
任何 **S3 兼容存储**（Backblaze B2、Cloudflare R2、Wasabi、Amazon S3、MinIO 等）
或 **SFTP 服务器**。所有操作都通过终端中的菜单完成，无需了解 `rclone`。

![proxdump 演示：将容器备份到 OneDrive、以新 ID 恢复、配置和外观菜单](docs/demo.gif)

*在真实节点上录制；较长的传输过程已加速。演示界面为英文。*

## 主要特点

- **离开服务器之前即已加密**：目标端只会收到无法读取的数据（XSalsa20-Poly1305，
  通过 `rclone crypt`）。文件名保持可读，并带有 `.encrypted` 后缀。
- **五类目标**，可同时使用多个：归档只创建一次，然后上传到所选的每个目标。
- **校验**：每次上传后，都会用校验和将远端副本与本地归档进行比较。
- **保留策略**：保留的版本数可全局设置，也可按客户机设置，每次备份后自动应用。
- **恢复**：以原 ID 恢复、以新 ID 恢复，或仅下载解密后的归档。归档是标准的
  `vzdump` 归档：不使用本工具也可以恢复。
- **计划任务**：可设置多个计划（每天或每周、全部客户机或部分客户机、一个或多个
  目标），每个计划都可以立即运行。
- **向导式连接**：在没有浏览器的服务器上，逐步完成 OneDrive、Google Drive 和
  Dropbox 的授权；S3 和 SFTP 只需填写简单的表单。
- **两种界面**：带配色主题、鼠标支持和动态进度窗口的原生界面，或经典的
  `whiptail` 对话框。
- **六种语言**：界面和日志支持英语、法语、西班牙语、德语、简体中文和俄语。
- **占用极小**：一个 bash 脚本、`rclone`、`jq`，以及 Proxmox VE 节点自带的组件。

## 工作原理

```
客户机 (VM/CT)                      本地暂存目录                               目标
┌─────────────┐   vzdump    ┌───────────────────────────┐   rclone   ┌──────────────────────┐
│ 100 web     │ ──────────> │ vzdump-qemu-100-….vma.zst │ ─────────> │ pve-backups/<node>/  │
└─────────────┘             │ 明文，上传后删除          │   crypt    │ ….vma.zst.encrypted  │
                            └───────────────────────────┘            └──────────────────────┘
```

对每个客户机：`vzdump` 在临时目录中创建归档，`rclone` 将其加密并上传，校验副本，
应用保留策略，最后删除临时目录。归档的内容由 `vzdump` 决定，因此 Proxmox VE 中
每个磁盘的“备份”设置都会被遵守。

## 目标

| 目标 | 连接方式 | 说明 |
|---|---|---|
| Microsoft OneDrive | 在浏览器中授权，将令牌粘贴到服务器 | 单个文件最大 250 GB |
| Google Drive | 同上，并使用您自己的 OAuth 客户端（免费） | 每天最多上传 750 GB |
| Dropbox | 在浏览器中授权，将令牌粘贴到服务器 | 单个文件最大 350 GB |
| S3 兼容存储 | 访问密钥、密钥值和存储桶 | Backblaze B2、Cloudflare R2、Wasabi、Amazon S3、Hetzner、OVHcloud、Scaleway、MinIO 等 |
| SFTP 服务器 | 由工具生成的 SSH 密钥，或密码 | NAS、另一台服务器、租用的存储 |

## 环境要求

- 一个 Proxmox VE 节点（在 PVE 9 / Debian 13 上开发和测试），root 权限；
- 至少一个空间充足的目标；
- 一个能临时存放最大归档的本地目录；
- 对于 OneDrive、Google Drive 和 Dropbox：一台带浏览器并安装了
  [rclone](https://rclone.org/downloads/) 的电脑，仅在授权时使用一次。

## 安装

```bash
git clone https://github.com/Mrdindon/proxdump.git
cd proxdump
./install.sh
```

`install.sh` 会安装缺少的组件（官方软件包中的 `rclone`、`jq`、`whiptail`、
`curl`），并把工具复制到 `/usr/local/bin/proxdump`。更新：
`git pull && ./install.sh`。卸载：`./install.sh --uninstall`（保留配置）。

节点上没有 git 时，可从 [Releases](https://github.com/Mrdindon/proxdump/releases)
下载 `.deb` 软件包，然后用 `apt install ./proxdump_*.deb` 安装。

## 快速开始

以 root 身份运行 `proxdump`，然后在**配置**中：

1. 连接至少一个目标；
2. 设置加密口令，并**将它记录在服务器之外**：没有它，备份将无法恢复；
3. 检查本地暂存目录和备份选项。

之后，选择**备份虚拟机和容器**进行第一次备份，再通过**自动计划**安排后续备份。

## 命令行

```bash
proxdump                                  # 菜单
proxdump backup --all                     # 所有客户机，所有目标
proxdump backup --to s3,onedrive 100 101  # 指定的客户机和目标
proxdump list                             # 已存储的备份
proxdump prune                            # 应用保留策略
proxdump update                           # 安装最新版本
```

## 文档

详细文档为英文：

- [Connecting the destinations](docs/CONNECTIONS.md) — OneDrive、Google Drive、
  Dropbox、S3、SFTP，访问令牌的有效期；
- [Using proxdump](docs/USAGE.md) — 语言和外观、加密、备份、管理、恢复、计划任务
  和命令行；
- [Encryption](docs/ENCRYPTION.md) — 算法、目标端可见的信息、密钥和口令的存放位置；
- [Disaster recovery](docs/RECOVERY.md) — 在新服务器上恢复（使用或不使用本工具）；
- [Reference](docs/REFERENCE.md) — 文件与安全、故障排除、已知限制；
- [Development](docs/DEVELOPMENT.md) — 不使用真实账户进行测试、翻译。

## 限制

- 一次一个节点：本工具只备份其所在节点上的客户机。
- 仅支持完整备份（不支持增量备份和去重）。
- 备份和恢复时都需要本地空间来存放压缩后的归档。
- 翻译未经母语人士审校，欢迎指正。

## 开发方式

proxdump 使用 Anthropic 的 AI 编程代理 [Claude Code](https://claude.com/claude-code)
编写，由作者指导和审查，并在真实的 Proxmox VE 节点上测试（参见
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)）。设计说明和经验总结也在该页面中；
[AGENTS.md](AGENTS.md) 是提供给参与开发的编程代理的指南。

## 许可证

[AGPL-3.0-or-later](LICENSE)。

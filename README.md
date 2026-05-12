# metatube-linux-installer

Debian/Ubuntu 下自动安装、部署、更新 MetaTube 的 Bash 工具。

## 功能

- 自动检测 Debian/Ubuntu 系统
- 严格校验 `linux-amd64-v3` CPU 能力，不支持则直接失败
- 自动安装依赖
- 使用 SQLite 数据库模式部署
- 自动生成 `TOKEN`
- 使用 `systemd` 管理服务并设置开机自启
- 使用 `cron` 定时检查更新并自动安装最新版本
- 记录安装和更新日志

## 默认路径

- 安装目录：`/opt/metatube`
- 配置目录：`/etc/metatube`
- 数据目录：`/var/lib/metatube`
- 数据库文件：`/var/lib/metatube/metatube.db`
- 日志目录：`/var/log/metatube`
- systemd 服务：`/etc/systemd/system/metatube.service`
- cron 配置：`/etc/cron.d/metatube`
- 更新器目录：`/opt/metatube/installer`

## 使用

需要 root。

```bash
curl -fsSL https://raw.githubusercontent.com/AkaiShuichi7/metatube-linux-installer/main/install.sh | sudo bash
```

脚本会自动拉取安装所需的辅助文件，因此支持直接通过 `curl | bash` 执行。

安装完成后：

- 服务名：`metatube`
- 查看状态：`systemctl status metatube`
- 查看日志：`journalctl -u metatube -f`
- 查看安装日志：`tail -f /var/log/metatube/install.log`
- 查看更新日志：`tail -f /var/log/metatube/update.log`
- TOKEN 配置文件：`/etc/metatube/metatube.env`
- 查看 TOKEN：`sudo grep '^TOKEN=' /etc/metatube/metatube.env`

> 安全说明：安装脚本不会直接打印 TOKEN 明文，只提示配置文件路径和查看命令，避免终端记录或录屏泄露。

## 更新机制

- `install.sh` 会安装当前最新 `metatube-server-linux-amd64-v3.zip`
- `update.sh` 会被复制到 `/opt/metatube/installer/update.sh`，并检查 GitHub Releases 最新版本
- cron 默认每天 `04:17` 自动执行一次更新检查
- 更新流程：下载并校验 → 停服务 → 备份 SQLite → 替换二进制 → 启动服务

## 说明

- 仅支持 Debian/Ubuntu
- 仅支持 `linux-amd64-v3`
- 不做静默降级
- 默认启用 `DB_AUTO_MIGRATE=true`
- SQLite `DSN` 使用裸文件路径：`/var/lib/metatube/metatube.db`
- 发布资产缺少 `digest` 时，安装和更新会直接失败

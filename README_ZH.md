# 🏛️ Hermes Gate

一个功能丰富的**终端 TUI**，用于在单个 Docker 容器中远程管理云服务器上的 [Hermes Agent](https://github.com/NousResearch/hermes-agent) tmux 会话。

> *"我喜欢通过 TUI 观察 Hermes Agent 的工作过程——但我的 Agent 跑在远程云服务器上，本地网络又不太稳定。连接断开时，我完全不知道任务还在不在跑。一个被中断的任务意味着数小时的努力白费。当然，我可以用原始的 tmux 来管理——但那不过是一遍又一遍地敲同样的命令。又浪费时间了。"*

> **注意：** Hermes Gate 是 [Hermes Agent](https://github.com/NousResearch/hermes-agent)（[官网](https://hermes-agent.nousresearch.com/)）的配套工具，后者是由 NousResearch 开发的开源 AI Agent 框架。

## 为什么用 Hermes Gate？

> **生命周期说明：** Hermes Gate 是一个**临时本地客户端**。当你退出 TUI 时，Docker 容器会停止。但远程服务器上的 tmux / Hermes Agent 会话**不受影响**——它们会继续运行。只需再次运行 `./run.sh` 即可重新连接。除了本地容器状态外，不会丢失任何东西。

在远程服务器上运行 Hermes Agent 通常意味着需要在多个 SSH 终端之间切换、担心连接断开、以及手动管理 tmux 会话。Hermes Gate 解决了所有这些问题：

- **完整的 TUI 体验** — 浏览服务器、管理会话、查看 Hermes Agent 的实时输出、发送提示词，全部通过基于 [Textual](https://textual.textualize.io/) 的交互式终端界面完成。无需记忆任何 SSH 命令。
- **网络状态监控** — 基于 TCP 探测的实时延迟监控。连接状态显示在 TUI 中，让你随时知道远程服务器是否可达。注意：如果 SSH 会话断开，需要手动重新进入会话。
- **通过 tmux 实现会话持久化** — 会话在远程 tmux 中运行，即使你关闭了 Hermes Gate，远程进程也会继续运行。但请注意，退出 TUI 时 Docker 容器会停止——再次运行 `./run.sh` 即可重新连接。
- **多服务器、多会话** — 在服务器和会话之间即时切换。每个会话独立追踪和管理。
- **一键启动** — `./run.sh` 自动构建、启动并进入 TUI。需要 Docker 和 `~/.ssh/` 中的 SSH 密钥（见前置要求）。

## 功能特性

- 交互式服务器选择与快速切换
- 远程 tmux 会话的创建 / 连接 / 销毁
- 远程 Hermes Agent 实时输出查看与提示词发送
- 网络状态监控（实时延迟显示和连接状态）
- 自动主机名解析（通过 `/etc/hosts`）
- SSH 配置别名支持（使用你的 `~/.ssh/config` 中的主机别名）
- 远程控制键：`Ctrl+C` 中断、`Ctrl+E` 转义（无需离开 TUI）
- **桌面通知与提示音** — Agent 任务完成时自动弹出系统通知并播放提示音

## 桌面通知与提示音

Hermes Gate 会在远程 Hermes Agent 完成任务时自动弹出**系统通知**并播放**提示音**。这对于高强度的 TUI 工作流来说是极大的效率提升——你不再需要一直盯着屏幕等待任务完成。

### 工作原理

`gate-notify` 插件（自动部署到远程服务器）会在 Agent 每次完成对话时写入一个信号文件。TUI 轮询这些信号，通过挂载卷转发到宿主机。宿主机上的后台监听进程随即：

1. **弹出桌面通知** — 显示会话名称和任务预览的原生系统弹窗
2. **播放提示音** — 默认使用 `sounds/complete.wav`

完全**跨平台**支持：

| 平台 | 通知方式 | 提示音 |
|------|---------|--------|
| **macOS** | `osascript`（原生通知中心） | `afplay` |
| **Linux** | `notify-send`（libnotify） | `paplay` / `aplay` |
| **Windows** | BurntToast（如已安装）或 `NotifyIcon` 气泡提示 | `System.Media.SoundPlayer` |

无需额外配置——监听进程随 `./run.sh` / `run.ps1` 自动启动。只需保持 TUI 运行，其他窗口照常工作。听到提示音后切回来，查看哪个会话需要你介入即可。

### 为什么这很重要

在 TUI 中管理多个 Agent 会话时，你经常需要在不同任务之间切换上下文。没有通知的情况下，你必须时不时检查每个会话是否完成——既枯燥又容易遗漏。有了通知 + 提示音：

- 你可以**专注于其他工作**（写代码、写文档、浏览网页）而不丢失对 Agent 的追踪
- **声音提醒**即使在终端被最小化或处于其他工作区时也能听到
- 通知会告诉你**哪个会话**完成了、**正在做什么**，让你精确知道下一步该去哪里
- 它将 TUI 从"盯着等"的体验转变为**高效的异步工作流**

## 安装

### 前置要求

- 目标服务器上已安装并运行 [Hermes Agent](https://github.com/nousresearch/hermes-agent)
- [Docker](https://docs.docker.com/get-docker/)
- `~/.ssh/` 中的 SSH 密钥已添加到目标服务器的 `authorized_keys`（支持任意密钥类型：`id_rsa`、`id_ed25519`、自定义 `IdentityFile` 或 SSH agent）

### 安装步骤

```bash
git clone https://github.com/LehaoLin/hermes-gate.git
cd hermes-gate
```

**macOS / Linux：**

```bash
./run.sh
```

**Windows (PowerShell)：**

```powershell
.\run.ps1
```

首次运行会自动构建 Docker 镜像并启动 TUI。请确保在启动前 Docker 已运行且 SSH 密钥已配置。

## 使用方法

### 启动

**macOS / Linux：**

```bash
./run.sh              # 启动（如已构建则跳过构建）
./run.sh rebuild      # 强制重新构建后启动
./run.sh update       # git pull + 重新构建 + 启动
./run.sh stop         # 停止并移除容器
./run.sh -h           # 显示帮助
```

多个终端可以同时运行 `./run.sh`——每个终端获得独立的 TUI 会话。当最后一个会话退出时，容器会自动停止。

**Windows (PowerShell)：**

```powershell
.\run.ps1              # 启动（如已构建则跳过构建）
.\run.ps1 rebuild      # 强制重新构建后启动
.\run.ps1 update       # git pull + 重新构建 + 启动
```

### TUI 控制键

| 阶段 | 按键 | 操作 |
|------|------|------|
| 服务器选择 | `↑↓` | 切换服务器 |
| | `Enter` | 连接到选中的服务器 |
| | `D` | 删除选中的服务器 |
| | `Q` | 退出 |
| 会话列表 | `↑↓` | 切换会话 |
| | `Enter` | 进入会话 |
| | `N` | 新建会话 |
| | `K` | 终止会话 |
| | `R` | 刷新列表 |
| | `Ctrl+B` | 返回服务器选择 |
| 查看器 | 在输入框中输入 + `Enter` | 向远程 Hermes Agent 发送提示词 |
| | `Ctrl+B` | 返回会话列表 |

### 添加服务器

在服务器选择界面选择"➕ Add Server..."。输入格式：

```
username@ip_address       例：root@1.2.3.4
username@hostname         例：admin@myserver
username@hostname:port    例：root@1.2.3.4:2222
```

默认端口为 22。非标准端口必须显式指定。

## 开发

`hermes_gate/` 目录作为卷挂载到容器中。修改 Python 代码后，**只需重启容器**——无需重新构建。

以下文件修改后需要重新构建（`./run.sh rebuild`）：

- `pyproject.toml` / `requirements.txt`
- `Dockerfile` / `entrypoint.sh`

### 常用命令

```bash
docker compose down              # 停止并移除容器
docker compose logs hermes-gate  # 查看日志
docker exec -it hermes-gate bash # 进入容器 shell
```

## 项目结构

```
hermes-gate/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── run.sh
├── run.ps1
├── pyproject.toml
├── sounds/              # 通知提示音文件
│   ├── complete.wav     # 任务完成
│   ├── error.wav        # 发生错误
│   ├── permission.wav   # 权限请求
│   └── question.wav     # 问题提示
├── plugins/
│   └── gate-notify/     # 自动部署到远程服务器
│       ├── __init__.py  # 挂载 Hermes post_llm_call 钩子
│       └── plugin.yaml
└── hermes_gate/
    ├── __main__.py    # 入口
    ├── app.py         # TUI 主界面 + 通知分发
    ├── servers.py     # 服务器管理与主机名解析
    ├── session.py     # 远程 tmux 会话管理 + 完成信号检测
    └── network.py     # 网络状态监控
```

## Star History

<a href="https://www.star-history.com/?repos=LehaoLin%2Fhermes-gate&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=LehaoLin/hermes-gate&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=LehaoLin/hermes-gate&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=LehaoLin/hermes-gate&type=date&legend=top-left" />
 </picture>
</a>

## 许可证

MIT

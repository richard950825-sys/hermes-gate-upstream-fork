# Hermes Gate — 本地 Docker TUI 远程管理方案

> **项目名称：** hermes-gate  
> **目标：** 在本地 Docker 容器中运行一个 TUI 管理器，通过 mosh + tmux 远程连接服务器上的多个 Hermes TUI 实例，支持 session 管理、网络状态实时监控、断线自动恢复。

---

## 一、整体架构

```
┌──────────────────────────────────────────────────────┐
│  本地 Docker 容器 (hermes-gate)                       │
│                                                        │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐         │
│  │ Manager   │  │ Window 1  │  │ Window 2  │  ...     │
│  │ (fzf菜单) │  │ mosh→ssh  │  │ mosh→ssh  │         │
│  │           │  │   ↓       │  │   ↓       │         │
│  │ N 新建    │  │ tmux      │  │ tmux      │         │
│  │ L 列表    │  │ hermes_1  │  │ hermes_2  │         │
│  │ S 切换    │  │ hermes tui│  │ hermes tui│         │
│  │ K 杀死    │  │           │  │           │         │
│  └───────────┘  └───────────┘  └───────────┘         │
│                                                        │
│  状态栏: 🟢 Connected | Sessions: 3 | CPU: 12%       │
│                                                        │
│  本地 tmux (prefix: Ctrl+A)                           │
└─────────────┬──────────────┬──────────────────────────┘
              │ mosh/ssh     │ mosh/ssh
              ▼              ▼
┌──────────────────────────────────────────────────────┐
│  服务器                                               │
│                                                        │
│  tmux session: hermes_1  →  hermes tui (运行中)       │
│  tmux session: hermes_2  →  hermes tui (运行中)       │
│  tmux session: hermes_3  →  hermes tui (运行中)       │
│                                                        │
│  即使本地断线，所有 session 继续运行                    │
└──────────────────────────────────────────────────────┘
```

---

## 二、核心设计

### 1. 双层 tmux，prefix 隔离

| 层级 | Prefix | 用途 |
|------|--------|------|
| 本地 tmux | `Ctrl+A` | 窗口管理、session 切换、状态栏显示 |
| 远端 tmux | `Ctrl+B` | hermes tui 内部操作 |

两层互不干扰，嵌套操作顺畅。

### 2. mosh 抗断线

- 基于 UDP，网络抖动不卡死
- 断线后自动重连，无需手动干预
- 重连后 `tmux attach -d` 直接恢复 hermes 上下文
- 如果服务器没装 mosh，自动降级为 `autossh`

### 3. Session ID 管理

- 命名规则：`hermes_1`, `hermes_2`, `hermes_3` ...
- 自动递增：查询服务器上已有 session，取最大 ID + 1
- 也支持自定义名称：`hermes_backtest`, `hermes_debug`

### 4. 网络状态灯（实时监控）

在本地 tmux 状态栏的输入框上方，显示醒目颜色的连接状态指示灯：

| 状态 | 颜色 | 含义 |
|------|------|------|
| 🟢 绿色 `●` | `#00FF00` | 连接通畅，延迟正常 |
| 🟡 黄色 `●` | `#FFFF00` | 连接不稳定，延迟偏高 |
| 🔴 红色 `●` | `#FF0000` | 网络中断，正在尝试重连 |

**实现方式：**
- 后台守护进程 `netwatch.sh`，每 3 秒执行一次 ICMP/SSH 探测
- 检测指标：ping 延迟 + mosh 进程状态 + SSH 连接存活
- 延迟 < 200ms → 绿色，200-500ms → 黄色，超时/失败 → 红色
- 状态写入临时文件 `/tmp/hermes-net-status`
- tmux 状态栏通过 `#(cat /tmp/hermes-net-status)` 实时读取显示
- 红色状态下附加闪烁效果（tmux `attr=blink`），确保用户能注意到

**状态栏示例：**
```
[🟢 Connected | 32ms] Sessions: hermes_1✓ hermes_2✓ hermes_3✗ | Ctrl+A:Help
```

---

## 三、文件结构

```
hermes-gate/
├── Dockerfile              # Alpine + mosh + tmux + fzf + bash
├── docker-compose.yml      # 配置入口
├── .env.example            # 环境变量模板
├── entrypoint.sh           # 容器入口：初始化 SSH、启动本地 tmux
├── hermes-manager.sh       # 核心管理脚本（fzf 交互菜单）
├── netwatch.sh             # 网络状态监控守护进程
├── tmux-local.conf         # 本地 tmux 配置（prefix、状态栏、快捷键）
├── ssh-config/
│   └── (挂载 ~/.ssh/)      # SSH 密钥挂载
├── PLAN.md                 # 本文档
└── README.md               # 使用说明
```

---

## 四、各文件详细设计

### 1. Dockerfile

```dockerfile
FROM alpine:latest

RUN apk add --no-cache \
    bash \
    openssh-client \
    mosh \
    tmux \
    fzf \
    jq \
    iputils \
    procps

# 创建非 root 用户
RUN adduser -D -s /bin/bash hermes
USER hermes
WORKDIR /home/hermes

# 复制配置和脚本
COPY --chown=hermes:hermes tmux-local.conf /home/hermes/.tmux.conf
COPY --chown=hermes:hermes entrypoint.sh hermes-manager.sh netwatch.sh /home/hermes/
RUN chmod +x /home/hermes/*.sh

ENTRYPOINT ["/home/hermes/entrypoint.sh"]
```

### 2. docker-compose.yml

```yaml
services:
  hermes-gate:
    build: .
    container_name: hermes-gate
    environment:
      - SERVER_HOST=${SERVER_HOST}
      - SERVER_USER=${SERVER_USER:-root}
      - SERVER_PORT=${SERVER_PORT:-22}
      - MOSH_UDP_RANGE=${MOSH_UDP_RANGE:-60000:61000}
    volumes:
      - ~/.ssh:/home/hermes/.ssh:ro    # SSH 密钥只读挂载
    ports:
      - "${MOSH_UDP_RANGE}:${MOSH_UDP_RANGE}/udp"  # mosh UDP 端口
    stdin_open: true                    # -i
    tty: true                           # -t
    restart: unless-stopped             # 容器异常退出自动重启
```

### 3. .env.example

```env
SERVER_HOST=xxx.xxx.xxx.xxx
SERVER_USER=root
SERVER_PORT=22
MOSH_UDP_RANGE=60000:61000
```

### 4. entrypoint.sh — 容器启动流程

```bash
#!/bin/bash
set -e

# 1. 检查 SSH 密钥
if [ ! -f ~/.ssh/id_rsa ] && [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "❌ 未找到 SSH 密钥，请挂载 ~/.ssh 目录"
    exit 1
fi
chmod 600 ~/.ssh/id_* 2>/dev/null || true

# 2. 测试 SSH 连通性
echo "🔍 测试连接 ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes -p ${SERVER_PORT} ${SERVER_USER}@${SERVER_HOST} "echo ok" &>/dev/null; then
    echo "❌ SSH 连接失败，请检查配置"
    exit 1
fi
echo "✅ SSH 连接成功"

# 3. 检查远端 tmux 是否安装
if ! ssh -p ${SERVER_PORT} ${SERVER_USER}@${SERVER_HOST} "which tmux" &>/dev/null; then
    echo "❌ 服务器未安装 tmux，请执行: apt install tmux"
    exit 1
fi

# 4. 启动网络监控守护进程
~/.hermes/netwatch.sh &

# 5. 启动本地 tmux session
tmux new-session -s gate -d "~/.hermes/hermes-manager.sh"

# 6. attach 进入
tmux attach -t gate
```

### 5. hermes-manager.sh — 核心交互脚本

这是关键文件，提供 fzf 交互菜单：

```
╔═══════════════════════════════════════════════╗
║           Hermes Gate — Session Manager        ║
╠═══════════════════════════════════════════════╣
║                                               ║
║  [N] 新建 Session      hermes_{N}            ║
║  [L] 列出所有 Session                         ║
║  [S] 切换到 Session    (fzf 选择器)          ║
║  [K] 杀死 Session      (fzf 选择器)          ║
║  [R] 重连当前 Session                         ║
║  [Q] 退出管理器                               ║
║                                               ║
║  当前 Session: hermes_1  [运行中]             ║
║  网络状态: 🟢 已连接 (32ms)                   ║
║                                               ║
╚═══════════════════════════════════════════════╝
```

**各功能详细行为：**

#### [N] 新建 Session

1. SSH 到服务器执行 `tmux list-sessions 2>/dev/null | grep hermes_`
2. 解析已有 ID，确定下一个 ID（如已有 1,2,3 → 下一个为 4）
3. 询问是否使用自定义名称（默认 `hermes_4`）
4. 在本地 tmux 新建 window，命名为 `hermes_4`
5. 在该 window 中执行：
   ```bash
   mosh ${SERVER_USER}@${SERVER_HOST} -- tmux new-session -s hermes_4 \; send-keys 'hermes tui' Enter
   ```
6. 自动切换到该 window

#### [L] 列出 Session

1. SSH 执行 `tmux list-sessions 2>/dev/null`
2. 过滤 `hermes_*`，显示格式：
   ```
   hermes_1    [attached]  创建于 04-16 14:26   窗口数: 1
   hermes_2    [detached]  创建于 04-16 15:30   窗口数: 1
   hermes_3    [detached]  创建于 04-16 16:02   窗口数: 1
   ```

#### [S] 切换 Session

1. 获取 `hermes_*` 列表
2. 用 fzf 弹出选择器，支持搜索过滤
3. 选择后：
   - 在本地 tmux 查找是否已有该 session 的 window
   - 有 → 切换到那个 window
   - 没有 → 新建 window，执行 `mosh $SERVER -- tmux attach -d -t hermes_{id}`
4. `-d` 参数确保踢掉其他 attach 的客户端

#### [K] 杀死 Session

1. fzf 选择要杀死的 session
2. 确认提示（y/N）
3. SSH 执行 `tmux kill-session -t hermes_{id}`
4. 关闭本地对应 window

#### [R] 重连当前 Session

1. 检测当前 mosh 进程是否还活着
2. 如果死了，自动重新 mosh attach

### 6. netwatch.sh — 网络状态监控守护进程

```bash
#!/bin/bash
# 后台运行，每 3 秒探测一次，结果写入 /tmp/hermes-net-status

STATUS_FILE="/tmp/hermes-net-status"

while true; do
    # 方式1: ICMP ping 探测
    latency=$(ping -c 1 -W 2 ${SERVER_HOST} 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
    
    if [ -z "$latency" ]; then
        # 网络中断
        echo "status:red" > "$STATUS_FILE"
        echo "latency:timeout" >> "$STATUS_FILE"
    elif (( $(echo "$latency < 200" | bc -l) )); then
        echo "status:green" > "$STATUS_FILE"
        echo "latency:${latency}ms" >> "$STATUS_FILE"
    elif (( $(echo "$latency < 500" | bc -l) )); then
        echo "status:yellow" > "$STATUS_FILE"
        echo "latency:${latency}ms" >> "$STATUS_FILE"
    else
        echo "status:red" > "$STATUS_FILE"
        echo "latency:${latency}ms" >> "$STATUS_FILE"
    fi
    
    sleep 3
done
```

**tmux 状态栏集成（tmux-local.conf）：**

```tmux
# 读取网络状态文件，动态渲染颜色灯
set -g status-right '#(cat /tmp/hermes-net-status | bash /home/hermes/render-status.sh)'
```

`render-status.sh` 根据状态文件输出对应的 tmux 格式字符串：

| 状态 | tmux 渲染 |
|------|-----------|
| green | `#[fg=#00FF00,bold]● Connected #[default]32ms` |
| yellow | `#[fg=#FFFF00,bold]● Unstable #[default]280ms` |
| red | `#[fg=#FF0000,bold,blink]● DISCONNECTED` |

### 7. tmux-local.conf — 本地 tmux 配置

```tmux
# Prefix 改为 Ctrl+A，避免和远端 Ctrl+B 冲突
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# 状态栏
set -g status-style "bg=#1a1a2e,fg=#e0e0e0"
set -g status-left-length 40
set -g status-left '#[fg=#FFD700,bold] ⚡ Hermes Gate #[default]'
set -g status-right-length 60
set -g status-right '#(bash /home/hermes/render-status.sh) | #[fg=cyan]Sessions: #{session_windows} | #[fg=white]%H:%M'

# 快捷键
bind N run-shell "bash /home/hermes/hermes-manager.sh new"       # Ctrl+A N 新建
bind S run-shell "bash /home/hermes/hermes-manager.sh switch"    # Ctrl+A S 切换
bind L run-shell "bash /home/hermes/hermes-manager.sh list"      # Ctrl+A L 列表
bind K run-shell "bash /home/hermes/hermes-manager.sh kill"      # Ctrl+A K 杀死
bind R run-shell "bash /home/hermes/hermes-manager.sh reconnect" # Ctrl+A R 重连

# 鼠标支持
set -g mouse on

# window 名称自动同步远端 session 名
set -g allow-rename on

# 256 色支持
set -g default-terminal "screen-256color"
```

---

## 五、使用流程

### 首次使用

```bash
# 1. 克隆项目
git clone https://github.com/<user>/hermes-gate.git
cd hermes-gate

# 2. 配置服务器信息
cp .env.example .env
vim .env  # 填入服务器 IP、用户名、端口

# 3. 构建镜像
docker compose build

# 4. 启动
docker compose run --rm hermes-gate
```

### 日常使用

```
进入容器后：
  Ctrl+A → N  → 新建 hermes_1，自动远端启动 hermes tui
  Ctrl+A → N  → 再建 hermes_2，另一个独立 hermes tui
  Ctrl+A → S  → fzf 选择器，切换到不同 session 查看
  Ctrl+A → L  → 查看所有 session 状态
  Ctrl+A → 数字 → 直接跳到对应 window

网络断了：
  不用管，服务器上 hermes 继续跑
  状态栏自动变红 🔴 闪烁提醒
  网络恢复后 mosh 自动重连，回到原来的上下文

下班了：
  直接关电脑 / 关 Docker
  明天 docker compose run → Ctrl+A S → 选 session → 回到昨天的工作现场
```

---

## 六、降级方案

| 场景 | 处理 |
|------|------|
| 服务器没装 mosh | 自动降级为 autossh，保持重连能力 |
| 服务器没装 tmux | entrypoint 阶段检测并提示安装命令 |
| SSH 密钥未配置 | 启动时检测，提示挂载路径 |
| 服务器 mosh 端口未开放 | 降级为 ssh + ServerAliveInterval 保活 |
| 多人共用服务器 | session 名加用户前缀：`hermes_{user}_{id}` |
| Docker 容器意外重启 | `restart: unless-stopped` 自动恢复，netwatch 重新启动 |
| fzf 不可用 | 降级为纯数字序号选择菜单 |

---

## 七、开发计划

| 阶段 | 内容 | 预估时间 |
|------|------|----------|
| Phase 1 | Dockerfile + docker-compose.yml + .env | 0.5h |
| Phase 2 | entrypoint.sh（SSH 检测 + tmux 启动） | 0.5h |
| Phase 3 | hermes-manager.sh（fzf 菜单 + CRUD） | 2h |
| Phase 4 | netwatch.sh + render-status.sh（网络状态灯） | 1h |
| Phase 5 | tmux-local.conf（快捷键 + 状态栏） | 0.5h |
| Phase 6 | 集成测试 + README.md | 1h |
| **合计** | | **约 5.5h** |

---

## 八、待确认事项

1. 服务器 IP / 端口 / 用户名 —— 需要你提供
2. 服务器是否已安装 mosh？是否开放了 UDP 60000-61000？
3. SSH 密钥路径（默认用 `~/.ssh/id_rsa`？）
4. 是否需要支持多服务器切换？（比如连不同服务器）
5. Docker 用 Docker Desktop 还是 Colima 或其他？
6. 本地操作系统？（macOS / Linux / Windows WSL）

---

*文档版本: v1.0 | 生成时间: 2026-04-16*

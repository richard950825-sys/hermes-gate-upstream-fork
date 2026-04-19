# 🏛️ Hermes Gate

[English](README.md) | [简体中文](README_ZH.md)

A feature-rich **terminal TUI** for remotely managing [Hermes Agent](https://github.com/NousResearch/hermes-agent) tmux sessions on cloud servers — all from a single Docker container.

> *"I love watching Hermes Agent work through a TUI — but mine runs on a remote cloud server, and my local network isn't always stable. When the connection drops mid-task, I have no idea if it's still running or already dead. An interrupted task means hours of wasted effort. Sure, I could manage it over raw tmux — but that's just typing the same boilerplate commands over and over. More time lost."*

> **Note:** Hermes Gate is a companion tool for [Hermes Agent](https://github.com/NousResearch/hermes-agent) ([Website](https://hermes-agent.nousresearch.com/)), an open-source AI agent framework by NousResearch.

## Why Hermes Gate?

> **Lifecycle clarification:** Hermes Gate is a **temporary local client**. When you quit the TUI, the Docker container stops. Your remote tmux / Hermes Agent sessions on the server are **not affected** — they keep running. Just run `./run.sh` again to reconnect. Nothing is lost except the local container state.

Running Hermes Agent on a remote server usually means juggling SSH terminals, worrying about dropped connections, and manually managing tmux sessions. Hermes Gate solves all of that:

- **Full TUI Experience** — Browse servers, manage sessions, view live Hermes Agent output, and send prompts, all from an interactive terminal UI built with [Textual](https://textual.textualize.io/). No raw SSH commands to remember.
- **Network Status Monitoring** — Real-time latency monitoring with TCP-level probing. Connection status is displayed in the TUI so you know when the remote server is reachable. Note: if your SSH session drops, you will need to re-enter the session manually.
- **Session Persistence via tmux** — Sessions run inside remote tmux, so your remote processes keep running even if you close Hermes Gate. However, note that the Docker container stops on TUI exit — run `./run.sh` again to reattach.
- **Multi-Server, Multi-Session** — Switch between servers and sessions instantly. Each session is independently tracked and managed.
- **One Command Start** — `./run.sh` builds, starts, and drops you into the TUI. Requires Docker and an SSH key in `~/.ssh/` (see Prerequisites).

## Features

- Interactive server selection with quick switching
- Remote tmux session create / connect / destroy
- Live remote Hermes Agent output viewing with prompt sending
- Network status monitoring (real-time latency display and connection status)
- Automatic hostname resolution (via `/etc/hosts`)
- SSH config alias support (use your `~/.ssh/config` host aliases)
- Remote control keys: `Ctrl+C` interrupt, `Ctrl+E` escape (without leaving the TUI)
- **Desktop Notifications & Sound Alerts** — Get notified with a system popup and sound when an Agent task finishes

## Desktop Notifications & Sound Alerts

Hermes Gate automatically pops up a **system notification** and plays a **sound alert** whenever a remote Hermes Agent session completes a task. This is a massive productivity booster when you're in a high-intensity TUI workflow — you no longer need to keep staring at the screen waiting for a task to finish.

### How it works

The `gate-notify` plugin (auto-deployed to your remote server) writes a signal file every time the Agent completes a turn. The TUI polls these signals and forwards them to your host system via a mounted volume. A background watcher on your host then:

1. **Shows a desktop notification** — a native system popup with the session name and task preview
2. **Plays a sound** — `sounds/complete.wav` by default

This is fully **cross-platform**:

| Platform | Notification | Sound |
|----------|-------------|-------|
| **macOS** | `osascript` (native Notification Center) | `afplay` |
| **Linux** | `notify-send` (libnotify) | `paplay` / `aplay` |
| **Windows** | BurntToast (if installed) or `NotifyIcon` balloon tip | `System.Media.SoundPlayer` |

No extra setup needed — the watcher starts automatically with `./run.sh` / `run.ps1`. Just keep the TUI open and let it run in the background. When you hear the sound, switch back and check which session needs your attention.

### Why this matters

When managing multiple Agent sessions in a TUI, you're often context-switching between different tasks. Without notifications, you'd have to periodically check each session to see if it's done — a tedious and error-prone process. With notifications + sound alerts:

- You can **focus on other work** (coding, writing, browsing) without losing track of your Agents
- The **audio cue** works even when the terminal is minimized or in another workspace
- The notification tells you **which session** finished and **what it was doing**, so you know exactly where to jump in next
- It transforms the TUI from a "stare and wait" experience into an **efficient asynchronous workflow**

## Installation

### Prerequisites

- [Hermes Agent](https://github.com/nousresearch/hermes-agent) installed and running on the target server
- [Docker](https://docs.docker.com/get-docker/)
- SSH key in `~/.ssh/` added to the target server's `authorized_keys` (any key type: `id_rsa`, `id_ed25519`, custom `IdentityFile`, or SSH agent)

### Steps

```bash
git clone https://github.com/LehaoLin/hermes-gate.git
cd hermes-gate
```

**macOS / Linux:**

```bash
./run.sh
```

**Windows (PowerShell):**

```powershell
.\run.ps1
```

The first run will automatically build the Docker image and launch the TUI. Make sure you have Docker running and your SSH key set up before starting.

## Usage

### Starting

**macOS / Linux:**

```bash
./run.sh              # Start (skips build if already built)
./run.sh rebuild      # Force rebuild then start
./run.sh update       # git pull + rebuild + start
./run.sh stop         # Stop and remove the container
./run.sh -h           # Show help
```

Multiple terminals can run `./run.sh` simultaneously — each gets an independent TUI session. The container auto-stops when the last session exits.

**Windows (PowerShell):**

```powershell
.\run.ps1              # Start (skips build if already built)
.\run.ps1 rebuild      # Force rebuild then start
.\run.ps1 update       # git pull + rebuild + start
.\run.ps1 stop         # Stop and remove the container
```

### TUI Controls

| Phase | Key | Action |
|-------|-----|--------|
| Server Selection | `↑↓` | Switch server |
| | `Enter` | Connect to selected server |
| | `D` | Delete selected server |
| | `Q` | Quit |
| Session List | `↑↓` | Switch session |
| | `Enter` | Enter session |
| | `N` | New session |
| | `K` | Kill session |
| | `R` | Refresh list |
| | `Ctrl+B` | Back to server selection |
| Viewer | Type in input + `Enter` | Send prompt to remote Hermes Agent |
| | `Ctrl+B` | Back to session list |

### Adding a Server

Select "➕ Add Server..." on the server selection screen. Input format:

```
username@ip_address       e.g. root@1.2.3.4
username@hostname         e.g. admin@myserver
username@hostname:port    e.g. root@1.2.3.4:2222
```

Default port is 22. Non-standard ports must be specified explicitly.

## Development

The `hermes_gate/` directory is mounted as a volume into the container. After modifying Python code, **just restart the container** — no rebuild needed.

The following files require a rebuild (`./run.sh rebuild`) after changes:

- `pyproject.toml` / `requirements.txt`
- `Dockerfile` / `entrypoint.sh`

### Common Commands

```bash
docker compose down              # Stop and remove container
docker compose logs hermes-gate  # View logs
docker exec -it hermes-gate bash # Enter container shell
```

## Project Structure

```
hermes-gate/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── run.sh
├── run.ps1
├── pyproject.toml
├── sounds/              # Notification sound files
│   ├── complete.wav     # Task completed
│   ├── error.wav        # Error occurred
│   ├── permission.wav   # Permission request
│   └── question.wav     # Question prompt
├── plugins/
│   └── gate-notify/     # Auto-deployed to remote server
│       ├── __init__.py  # Hooks into Hermes post_llm_call
│       └── plugin.yaml
└── hermes_gate/
    ├── __main__.py    # Entry point
    ├── app.py         # TUI main interface + notification dispatch
    ├── servers.py     # Server management & hostname resolution
    ├── session.py     # Remote tmux session management + completion signals
    └── network.py     # Network status monitoring
```

## Star History

<a href="https://www.star-history.com/?repos=LehaoLin%2Fhermes-gate&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=LehaoLin/hermes-gate&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=LehaoLin/hermes-gate&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=LehaoLin/hermes-gate&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT
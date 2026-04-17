# Hermes Gate

A feature-rich **terminal TUI** for remotely managing [Hermes](https://github.com/NomicFoundation/hermes) tmux sessions on cloud servers — all from a single Docker container, zero config.

## Why Hermes Gate?

Running Hermes on a remote server usually means juggling SSH terminals, worrying about dropped connections, and manually managing tmux sessions. Hermes Gate solves all of that:

- **Full TUI Experience** — Browse servers, manage sessions, view live Hermes output, and send prompts, all from an interactive terminal UI built with [Textual](https://textual.textualize.io/). No raw SSH commands to remember.
- **Auto-Reconnect on Network Drops** — Real-time latency monitoring with TCP-level probing. If your connection drops, Hermes Gate automatically reconnects and resumes output — your remote Hermes keeps running uninterrupted.
- **Detach-Friendly** — Sessions run inside remote tmux, so you can close Hermes Gate at any time. Reconnect later and pick up right where you left off — no lost work, no restarted agents.
- **Multi-Server, Multi-Session** — Switch between servers and sessions instantly. Each session is independently tracked and managed.
- **One Command, Zero Config** — `./start.sh` builds, starts, and drops you into the TUI. No config files, no environment variables.

## Features

- Interactive server selection with quick switching
- Remote tmux session create / connect / destroy
- Live remote Hermes output viewing with prompt sending
- Network status monitoring (real-time latency + auto-reconnect)
- Automatic hostname resolution (via `/etc/hosts`)
- SSH config alias support (use your `~/.ssh/config` host aliases)
- Remote control keys: `Ctrl+C` interrupt, `Ctrl+E` escape (without leaving the TUI)

## Installation

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- SSH key (`~/.ssh/id_rsa` or `~/.ssh/id_ed25519`) added to the target server's `authorized_keys`

### Steps

```bash
git clone https://github.com/LehaoLin/hermes-gate.git
cd hermes-gate
./start.sh
```

The first run will automatically build the Docker image and launch the TUI. No configuration files needed.

## Usage

### Starting

```bash
./start.sh              # Start (skips build if already built)
./start.sh --rebuild    # Force rebuild then start
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
| | `Shift+Tab` | Back to server selection |
| Viewer | Type in input + `Enter` | Send prompt to remote Hermes |
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

The following files require a rebuild (`./start.sh --rebuild`) after changes:

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
├── start.sh
├── pyproject.toml
└── hermes_gate/
    ├── __main__.py    # Entry point
    ├── app.py         # TUI main interface
    ├── servers.py     # Server management & hostname resolution
    ├── session.py     # Remote tmux session management
    └── network.py     # Network status monitoring
```

## License

MIT

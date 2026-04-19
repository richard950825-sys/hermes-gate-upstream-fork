# Changelog

## 2026-04-19 - Windows notifications use native sound only and log watcher failures

### Fixed

- Removed Windows `System.Media.SoundPlayer` wav playback from `run.ps1` so BurntToast and MessageBox now rely solely on native Windows notification sound behavior.
- Added safe default values for notification payloads before escaping: `Hermes Gate` for missing titles and `Notification received.` for missing messages.
- Replaced the outer watcher `catch {}` with watcher.log diagnostics so top-level JSON parsing / notification processing failures are recorded instead of silently swallowed.

### Tests

- Expanded `tests/test_run_ps1.py` to lock default title/message handling, absence of Windows wav playback, and watcher failure logging.
- Validation run: `python -m pytest -q tests/test_run_ps1.py tests/test_notification_content.py` (`19 passed`).

## 2026-04-19 - Notification content switched to session name plus response preview

### Fixed

- Changed `hermes_gate/app.py` host notifications to use the session name in the notification title and the agent `response_preview` as the notification body, instead of showing the original user prompt text.
- Added a shared host-notification emitter so foreground completion polling and background polling both format Windows/macOS/Linux notification payloads consistently.
- Kept a safe fallback order for completion text: `response_preview` first, then legacy `message_preview`, then `task completed` if neither preview is present.

### Tests

- Added `tests/test_notification_content.py` to lock notification title/body formatting and the `response_preview` preference logic.
- Validation run: `python -m pytest -q tests/test_notification_content.py tests/test_session_hint_text.py tests/test_run_ps1.py` (`17 passed`).

## 2026-04-19 - Windows adaptive toast host selection and logging

### Fixed

- Added runtime notification-host discovery in `run.ps1` so Windows toast delivery now prefers `pwsh` when available, falls back to Windows PowerShell, and no longer assumes a single host for all users.
- Split toast execution from MessageBox fallback into separate success/failure paths so BurntToast is attempted on each discovered host before any visible fallback dialog is shown.
- Added watcher logging to `.notify/watcher.log` so toast-host failures are no longer silently swallowed and the fallback reason is inspectable on the user's machine.

### Tests

- Expanded `tests/test_run_ps1.py` to lock adaptive host selection order, detached host execution, failure logging, and sound-before-notify ordering.
- Validation run: `python -m pytest -q tests/test_run_ps1.py` (`13 passed`).

## 2026-04-19 - Windows detached-process notification delivery

### Fixed

- Moved visible Windows notification delivery out of the background watcher job and into a detached PowerShell process so BurntToast no longer depends on the broken job-session context.
- Kept sound playback in the watcher and moved it ahead of visible notification launch so audio is preserved even if the visible notification path falls back.
- The detached notification process now tries BurntToast first and falls back to `System.Windows.Forms.MessageBox` only if toast delivery fails.

### Tests

- Expanded `tests/test_run_ps1.py` to lock detached-process notification execution, sound-before-notify ordering, and removal of the old direct job-scoped BurntToast pattern.
- Validation run: `pytest -q tests/test_run_ps1.py`.

## 2026-04-19 - Windows notification watcher fallback fix

### Fixed

- Reworked `run.ps1` notification fallback to stop using a transient `NotifyIcon` balloon tip that could disappear before rendering.
- Windows watcher now prefers BurntToast, but if BurntToast is unavailable or fails it falls back to a visible `System.Windows.Forms.MessageBox` instead of a short-lived tray notification.
- Removed the immediate `Start-Sleep -Milliseconds 100` plus `Dispose()` pattern that matched the local "sound but no visible notification" failure mode.

### Tests

- Expanded `tests/test_run_ps1.py` to require a visible fallback notification path and to forbid the old short-lived `NotifyIcon` disposal pattern.
- Validation run: `pytest -q tests/test_run_ps1.py` (`9 passed`).

## 2026-04-19 - Windows launcher full run.sh parity

### Fixed

- Reworked `run.ps1` to follow the same control flow as `run.sh`: `stop`, `update -> rebuild`, `rebuild`, smart container/image detection, `docker exec -it ... python -m hermes_gate`, and idle-only auto-stop.
- Removed runtime generation of `docker-compose.win.yml`; Windows startup now uses a checked-in `docker-compose.windows.yml` so the script no longer owns compose templating or PowerShell-specific UTF-8 file writing.
- Matched `run.sh` rebuild semantics by using `docker compose down --rmi local` before `up -d --build` on Windows.
- Added a checked-in Windows compose file that keeps the shared SSH/code mounts while omitting the Linux-only `/etc/hosts` bind.

### Tests

- Expanded `tests/test_run_ps1.py` to lock checked-in Windows compose usage, rebuild parity with `run.sh`, and the Windows compose mount contract.
- Validation run: `python -m pytest -q tests/test_run_ps1.py` (`7 passed`).
- Validation run: `python -m pytest -q` (`76 passed`).
- Validation run: `python -m compileall -q hermes_gate tests`.
- Validation run: `docker compose -f docker-compose.windows.yml config`.

## 2026-04-19 - Windows launcher parity and PowerShell 5.1 compatibility

### Fixed

- Reworked `run.ps1` to launch Hermes Gate via `docker exec -it ... python -m hermes_gate` instead of `docker attach`, aligning Windows startup with the current `run.sh` / `entrypoint.sh` lifecycle.
- Added Windows `stop` command support and replaced unconditional container shutdown with idle-only auto-stop behavior so multiple local TUI sessions can coexist without one exit killing the shared container.
- Regenerate `docker-compose.win.yml` deterministically on each run to avoid silent drift from current compose settings.
- Added preflight checks for `docker compose`, Docker daemon availability, `git` on `update`, and missing `~/.ssh` warnings.
- Replaced `Set-Content -Encoding UTF8NoBOM` with .NET UTF-8 no-BOM file writing so the script remains compatible with Windows PowerShell 5.1.

### Tests

- Added `tests/test_run_ps1.py` to lock Windows launcher behavior: `docker exec` launch path, `stop` command support, PowerShell 5.1-safe compose writing, and README command parity.
- Validation run: `python -m pytest -q tests/test_run_ps1.py` (`4 passed`).
- Validation run: `python -m pytest -q` (`71 passed`).
- Validation run: `python -m compileall -q hermes_gate tests`.

# Changelog

## 2026-04-17 - Compatibility and Stability Fixes

### Compatibility Review

- Confirmed the implementation does not depend on a specific server IP, SSH alias, key filename, Windows username, or local workspace path.
- Replaced local test fixtures that used real-looking host data with documentation-only addresses such as `203.0.113.10`.
- Removed hardcoded `/root/.ssh/config` usage from application code. SSH config discovery now uses `HERMES_GATE_SSH_CONFIG` when provided and falls back to the current user's `~/.ssh/config`.
- Changed Docker SSH handling to mount the host `~/.ssh` directory read-only at `/host/.ssh`, copy it into the container runtime SSH directory, and apply permission/path normalization only to the runtime copy.

### Fixed

- Preserved SSH config aliases for connections, session listing, session creation, output polling, prompt sending, and attach commands so `Host` entries with `IdentityFile`, `User`, `Port`, and `IdentitiesOnly` work consistently.
- Added support for entering either an SSH config alias or `user@host[:port]` in the server prompt.
- Scoped local session records by `user`, `host`, and `port`, with migration support for legacy port-22 records.
- Made session refresh surface errors instead of silently swallowing SSH/tmux failures, while keeping the previous session list intact on refresh failure.
- Discovered existing remote `gate-*` tmux sessions even when no local JSON record exists.
- Added explicit remote preflight checks for `tmux` and `hermes`.
- Replaced ICMP ping network checks with TCP probes against the configured SSH port.
- Prevented stale network monitor workers from continuing after viewer navigation.
- Sent prompts through SSH stdin and a tmux buffer instead of embedding user text into a remote shell command.
- Cleared stale remote input before pasting a prompt so new messages do not append to a half-entered command.
- Added remote control keys in viewer mode: `Ctrl+E` sends remote Escape/C-u and `Ctrl+C` interrupts a stuck remote Hermes request.
- Rendered tmux capture output as plain terminal text, avoiding Rich markup interpretation and remote ANSI background blocks.
- Fixed Textual runtime color reset by clearing the inline color rule instead of assigning a theme variable as a runtime color.
- Removed obsolete `.env.example` setup instructions from `GUIDE.md`.

### Docker

- The host SSH directory is now mounted read-only.
- SSH config path rewriting for Windows and Git Bash paths is applied only inside the container runtime copy.
- OpenSSH key permissions are normalized inside the container without mutating host files.
- Because the compose volume target changed, existing containers must be recreated, not only restarted.

### Tests

- Added coverage for SSH config alias matching, runtime SSH config path selection, tab-separated SSH config parsing, server record alias updates, port-scoped session records, legacy session migration, remote session discovery, tmux-missing errors, refresh failure surfacing, network port probing, network worker lifecycle, guide consistency, Textual hint color reset, tmux capture rendering, prompt command construction, and remote key command construction.
- Added `test` optional dependencies for `pytest` and `pytest-asyncio`, with explicit asyncio pytest configuration so async tests execute consistently in local and CI runs.
- Validation run: `python -m compileall -q hermes_gate tests`.
- Validation run: `python -m pytest -q` (`49 passed`).
- Validation run: `docker compose config`.
- Validation run: `bash -n entrypoint.sh` inside the project Docker image.

### Validation Notes

- Async tests now execute locally after installing `.[test]`; the previous skipped-async-test state is fixed.
- `StrictHostKeyChecking=no` remains an existing security debt from the current SSH command defaults. It is not a machine-specific change, but it should be addressed separately before treating the tool as hardened.

## 2026-04-17 - Session Kill Flow Improvements

### Fixed

- Changed the session-list destructive shortcut from lowercase `k` to uppercase `K` to match the issue requirement and reduce accidental activation.
- Added a confirmation modal before killing a session, with `Kill session <name>? [y/N]` semantics and keyboard/button confirm-cancel flows.
- Updated remote session teardown to detach attached tmux clients before killing the tmux session.
- Treated missing remote tmux sessions as a non-fatal cleanup case so the local record is still removed and the list can refresh cleanly.
- Preserved the local record when remote kill fails for real errors, and surfaced a clear error hint in the TUI instead of silently removing the entry.
- Returned explicit kill result metadata from `SessionManager.kill_session()` so the app can distinguish success, already-missing tmux sessions, and hard failures.

### Tests

- Added TUI tests for uppercase `K`, confirmation gating, confirmed-vs-cancelled behavior, success messaging, and failure messaging.
- Added session-manager tests for detach-before-kill ordering, missing-tmux cleanup, tmux-missing errors, and local-record preservation on remote kill failure.
- Added binding regression tests to prove session/select shortcuts are installed up front and enabled only in the correct phase.
- Added confirm-screen tests to lock keyboard-only kill confirmation behavior (`y`/`Enter` confirm, `n`/`Esc` cancel) with no redundant buttons.
- Added local interaction tests to verify uppercase `N` creates sessions and uppercase `K` opens kill flow only in session phase.
- Added session-hint text regression tests so the footer copy stays aligned with the actual `N/K/R/Esc/Shift+Tab/Q` bindings.
- Added kill-confirm title regression coverage so the prompt stays aligned with the actual `y/n` cancel-confirm semantics.
- Validation run: `. .venv/bin/activate && pytest -q` (`60 passed`).

# Hermes Gate Stability Fix Plan & Test Plan

This document covers 6 categories of issues from the current code review that directly affect usage stability:

1. Session local records do not distinguish SSH ports.
2. Network status uses ICMP ping instead of the SSH/TCP path the application actually depends on.
3. Network monitor worker lifecycle may leave residual tasks across page transitions.
4. Session refresh swallows all exceptions, causing silent UI failures.
5. Input sent to the remote Hermes may be interpreted by the remote shell rather than sent verbatim.
6. `GUIDE.md` still references the removed `.env.example` first-time setup flow.

The fix goal is to make the implementation satisfy real interface contracts and general failure modes, not to adapt to specific test cases. Tests should cover edge cases via mocks, temporary directories, and swappable probe functions — no real SSH server dependency.

## Test Infrastructure

The repository currently has no test directory. Suggested additions:

- `tests/test_session_records.py`
- `tests/test_network_monitor.py`
- `tests/test_network_worker.py`
- `tests/test_refresh_sessions.py`
- `tests/test_send_to_remote.py`
- `tests/test_docs.py`

Suggested dev dependency addition in `pyproject.toml`:

```toml
[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
]
```

Testing principles:

- No real server connections. SSH, tmux, and TCP probing are verified via monkeypatch/fake processes.
- Use temporary HOME or injectable config directories to avoid reading/writing the user's real `~/.hermes-gate`.
- Explicit assertions on error paths, not just "no exception thrown".
- Data boundary assertions on user input: user text must only appear in stdin/payload, never in remote shell command strings.

## 1. Session Records Isolated by Port

### Current State

In `hermes_gate/session.py`, `_sessions_file(user, host)` generates the filename using only `user` and `host`:

```python
sessions_{user}@{host}.json
```

But the UI already supports `user@host:port`. The same user and host with different ports will share the same local session record file, causing session lists, alive states, id allocation, and kill operations to interfere with each other.

### Expected Behavior

`user@host:22` and `user@host:2222` must be treated as two independent remote targets. Their local session records, id allocation, and deletion operations must not affect each other.

### Fix Plan

1. Modify the local record key to explicitly include the port:

   ```python
   def _sessions_file(user: str, host: str, port: str = "22") -> Path:
       ...
   ```

2. Do not concatenate unsanitized host/user directly in filenames. Use stable encoding to prevent characters like IPv6 colons, slashes, and spaces from breaking paths:

   ```python
   from urllib.parse import quote

   def _server_key(user: str, host: str, port: str) -> str:
       return f"{quote(user, safe='')}@{quote(host, safe='')}#{quote(str(port), safe='')}"
   ```

   The filename can be:

   ```text
   sessions_{server_key}.json
   ```

3. `_load_local()` and `_save_local()` should accept `port`. `SessionManager` should consistently pass `self.port` when calling them.

4. Add backward-compatible migration:

   - When `port == "22"` and the new file doesn't exist but the legacy file `sessions_{user}@{host}.json` does, read the legacy file and write to the new file.
   - For non-22 ports, do not auto-migrate legacy files to avoid incorrectly applying historical default-port records to other ports.
   - After migration, the legacy file can be retained to reduce disruption; this can be noted in a future release.

5. Add port validation. At minimum, require the port to be an integer from 1 to 65535. Invalid ports should be rejected during server addition, not deferred to SSH error.

### Tests

`tests/test_session_records.py`

- `test_session_files_are_port_scoped`
  - Use temporary HOME.
  - Create `SessionManager` instances for the same `user`/`host` with ports `22` and `2222`.
  - Mock `_ssh_output()` to return empty session list, mock `_ssh_cmd()` to return success.
  - Call `create_session()` on each.
  - Assert both targets get first id `0`, and two different JSON files are generated.

- `test_kill_session_only_removes_matching_port_record`
  - Pre-populate record files for both ports.
  - Execute `kill_session(0)` on port `2222`.
  - Assert port `22` record is unmodified.

- `test_default_port_migrates_legacy_record`
  - Create only the legacy file `sessions_root@example.com.json`.
  - Read with `SessionManager("root", "example.com", "22")`.
  - Assert legacy record is read and new port-scoped file is generated.

- `test_non_default_port_does_not_consume_legacy_record`
  - Create only the legacy file.
  - Read with `SessionManager("root", "example.com", "2222")`.
  - Assert legacy record is not treated as port `2222` record.

### Acceptance Criteria

- Different ports on the same host are independent when viewing, refreshing, creating, and deleting sessions in the UI.
- Default-port users can still see legacy session records after upgrade.

## 2. Network Status Changed to Probe SSH/TCP Path

### Current State

`NetworkMonitor._probe()` uses:

```bash
ping -c 1 -W 2 <host>
```

But the application actually depends on SSH connections to a specific port. Many cloud servers disable ICMP; ping failure does not mean SSH failure, and ping success does not mean the SSH port is available.

### Expected Behavior

The status bar should reflect the connection path that Hermes Gate actually depends on: the resolved host and the user-configured SSH port. Network status must not depend on ICMP.

### Fix Plan

1. Add `port` parameter to `NetworkMonitor`:

   ```python
   class NetworkMonitor:
       def __init__(self, host: str, port: str = "22"):
           ...
   ```

2. Change `_probe()` to TCP connect probing:

   ```python
   reader, writer = await asyncio.wait_for(
       asyncio.open_connection(self._ip, int(self.port)),
       timeout=5,
   )
   ```

   Close the writer immediately after successful connection. Use `time.monotonic()` to calculate latency.

3. Keep existing status threshold semantics:

   - `< 200ms`: green
   - `200ms <= latency < 500ms`: yellow
   - `>= 500ms`: red/unstable, suggested text `"Slow: 650ms"`, not to be confused with full disconnection.

4. `_show_session_list()` passes port when creating monitor:

   ```python
   self.net_monitor = NetworkMonitor(host, port)
   ```

5. If stricter SSH probing is needed later, an optional `ssh -o BatchMode=yes true` probe can be added after TCP connect. But by default, authentication failure should not be classified as network disconnect, since host/port reachability and user key validity are two different issues.

### Tests

`tests/test_network_monitor.py`

- `test_probe_uses_configured_port`
  - Monkeypatch `asyncio.open_connection`.
  - Create `NetworkMonitor("example.com", "2222")`.
  - Call `_probe()`.
  - Assert `open_connection` received port `2222`.

- `test_probe_success_sets_latency_state`
  - Fake `open_connection` returns fake reader/writer.
  - Monkeypatch `time.monotonic()` to return stable time sequence.
  - Assert state is green/yellow and includes millisecond text.

- `test_probe_timeout_sets_red_state`
  - Fake `open_connection` raises `asyncio.TimeoutError`.
  - Assert returns `False`, state is RED, message is clear timeout/disconnected text.

- `test_probe_closes_writer_on_success`
  - Fake writer records `close()` and `wait_closed()`.
  - Assert success path closes the connection.

### Acceptance Criteria

- Servers with ICMP disabled but SSH port open are not falsely reported as disconnected in the UI.
- When the SSH port is unreachable, the status bar enters disconnect/reconnect state.

## 3. Network Monitor Worker Lifecycle Convergence

### Current State

`_start_network_monitor()` continuously reads `self.net_monitor` in a loop:

```python
while self._phase in ("viewer", "session"):
    state = self.net_monitor.state
```

On navigation back, `action_back()` stops and clears `self.net_monitor`, then a new page creates a new monitor. The old worker may continue running, reading the new monitor or swallowing exceptions, causing state flickering, duplicate refreshes, and background task leaks.

### Expected Behavior

At most one network monitor worker per viewer entry. After leaving the viewer or switching server/session, the old worker must exit and must not continue reading the new `self.net_monitor`.

### Fix Plan

1. Capture local monitor reference at the start of `_start_network_monitor()`:

   ```python
   monitor = self.net_monitor
   if monitor is None:
       return
   await monitor.start()
   try:
       while self._phase == "viewer" and self.net_monitor is monitor:
           state = monitor.state
           ...
   finally:
       await monitor.stop()
   ```

2. When `action_back()` stops the monitor, disconnect the global reference first:

   ```python
   monitor = self.net_monitor
   self.net_monitor = None
   if monitor:
       asyncio.create_task(monitor.stop())
   ```

   This causes the old worker's `self.net_monitor is monitor` condition to fail immediately.

3. Before entering a new viewer, stop the old monitor instance if one exists before creating a new one.

4. Restrict the loop to the `viewer` phase. The session list page has no `#net-status` or `#latency`; continuing to run only relies on exception swallowing for failed queries.

### Tests

`tests/test_network_worker.py`

- `test_network_worker_exits_when_monitor_replaced`
  - Construct a fake app or extract a testable helper.
  - After worker starts, replace `app.net_monitor` with another object.
  - Assert old worker exits and calls old monitor's `stop()`.

- `test_network_worker_exits_when_leaving_viewer`
  - Change phase from `"viewer"` to `"session"`.
  - Assert loop stops and no longer updates UI.

- `test_only_current_monitor_updates_ui`
  - Old monitor and new monitor have different states.
  - Assert old worker does not write old state to new viewer's status bar.

### Acceptance Criteria

- After entering/exiting the viewer multiple times, the number of background monitors does not grow.
- The status bar only shows the monitor state for the current session.

## 4. Session Refresh Explicitly Surfaces Failures

### Current State

`_refresh_sessions()` catches all exceptions and just `pass`es:

```python
except Exception:
    pass
```

SSH timeout, authentication failure, missing tmux, corrupted local JSON, and code bugs all manifest as a static or blank list.

### Expected Behavior

Refresh failure should preserve the existing list and display a clear error in the UI hint. An expected empty remote session is not an error; connection failure, timeout, and unreadable local records are errors.

### Fix Plan

1. `SessionManager._ssh_cmd()` retains `CompletedProcess`, but the upper layer must distinguish SSH failure from no remote tmux sessions:

   - SSH connection failure typically returns `255`, which should be converted to `ConnectionError` or a custom `SSHCommandError`.
   - `tmux list-sessions` no server/no sessions can return non-zero, but this should be interpreted as an empty alive set, not a refresh failure.

2. `_refresh_sessions()` only catches specific exception types:

   ```python
   except (TimeoutError, subprocess.TimeoutExpired, ConnectionError, RuntimeError) as e:
       self._hint("session-hint", f"Refresh failed: {e}")
       self.log.error(...)
   ```

3. Only clear the ListView after successfully fetching a new session list. This way, failure doesn't wipe the old list.

4. Local JSON parse failure should return an empty list at the `load` layer and log a warning; if the file exists but schema is invalid, showing "local session record is invalid" is more helpful for troubleshooting.

### Tests

`tests/test_refresh_sessions.py`

- `test_refresh_keeps_existing_list_on_connection_failure`
  - Fake `session_mgr.list_sessions()` raises `ConnectionError`.
  - Pre-populate `self.sessions` and ListView content.
  - Call `_refresh_sessions()`.
  - Assert `self.sessions` is not overwritten to empty, hint shows refresh failed.

- `test_refresh_success_replaces_list`
  - Fake returns two sessions.
  - Assert ListView is cleared then two sessions and New Session item are appended.

- `test_session_manager_distinguishes_ssh_failure_from_no_tmux_sessions`
  - Mock `_ssh_cmd()` returning returncode 255 → `list_sessions()` raises connection error.
  - Mock tmux no sessions return → `list_sessions()` returns local records but alive is false, or empty alive set.

### Acceptance Criteria

- Network/authentication errors are visible to the user.
- Refresh failure does not destroy the currently visible session list.

## 5. Remote Input Sent Verbatim

### Current State

`_send_to_remote()` manually escapes single quotes in user input, then passes it as a remote command argument via SSH:

```python
safe = text.replace("'", "'\\''")
...
"tmux", "send-keys", "-t", name, "-l", safe
```

OpenSSH's remote command ultimately passes through the remote shell. Shell metacharacters in user input may be interpreted; prompts containing spaces, quotes, and newlines are not guaranteed to reach Hermes verbatim.

### Expected Behavior

Any text in the input field should be sent as data to the tmux pane, not participate in constructing remote shell syntax. The remote command string must only contain fixed commands generated by the program and strictly limited session names.

### Fix Plan

Recommended: use tmux buffer, transmitting user text through SSH stdin:

1. Session name only allows program-generated `gate-{int}`, no external strings.

2. Construct fixed remote command:

   ```bash
   tmux load-buffer -b hermes-gate-input - \
     \; paste-buffer -b hermes-gate-input -t gate-0 \
     \; send-keys -t gate-0 Enter
   ```

   User text is sent to stdin via `proc.communicate(input=text.encode())`. The remote shell only interprets fixed commands, not user text.

3. Python side:

   ```python
   proc = await asyncio.create_subprocess_exec(
       "ssh",
       ...,
       fixed_remote_command,
       stdin=asyncio.subprocess.PIPE,
       stdout=asyncio.subprocess.PIPE,
       stderr=asyncio.subprocess.PIPE,
   )
   stdout, stderr = await asyncio.wait_for(
       proc.communicate(input=text.encode("utf-8")),
       timeout=10,
   )
   if proc.returncode != 0:
       raise RuntimeError(stderr.decode(errors="replace").strip() or "send failed")
   ```

4. If compatibility with environments that don't support `tmux load-buffer -` is needed, fallback to a safe base64 stdin script, but user text must still only go through stdin, never concatenated into the remote command.

5. Send failure should display an error in the viewer hint or output, not fail silently.

### Tests

`tests/test_send_to_remote.py`

- `test_user_text_is_sent_via_stdin_not_remote_command`
  - Monkeypatch `asyncio.create_subprocess_exec` to capture argv and communicate input.
  - Input: `"hello; whoami $(id) 'x'\nnext"`.
  - Assert the input verbatim only appears in `communicate(input=...)`, not in the remote command string in argv.

- `test_send_preserves_whitespace_and_newlines`
  - Input contains leading/trailing spaces, multiple spaces, newlines.
  - Assert stdin bytes are exactly the UTF-8 encoding of the input.

- `test_send_uses_generated_session_name_only`
  - `_current_session_id = 3`.
  - Assert remote command target is `gate-3`, no other user-controllable session name.

- `test_send_failure_surfaces_error`
  - Fake process returncode non-zero, stderr is `"no such session"`.
  - Assert UI shows send failure, or `_send_to_remote()` raises a handleable exception.

### Acceptance Criteria

- Any valid prompt text reaches Hermes verbatim.
- Shell metacharacters are not executed remotely.
- User sees an error when remote tmux fails.

## 6. GUIDE.md First-Time Setup Flow Update

### Current State

`GUIDE.md` still requires:

```bash
cp .env.example .env
```

But the repository has no `.env.example`, and README states no configuration files are needed.

### Expected Behavior

Users should be able to complete first-time setup by following `GUIDE.md`. Documentation should be consistent with the current interactive server addition flow.

### Fix Plan

1. Remove `.env.example` related steps.

2. Change first-time use to:

   ```bash
   ./run.sh
   ```

   Then in the TUI, select `Add Server...` and enter `user@host` or `user@host:port`.

3. Add prerequisites:

   - Docker available.
   - Local `~/.ssh` has a usable private key.
   - Remote server allows login with that public key.
   - Remote has `tmux` and `hermes` installed.

### Tests

`tests/test_docs.py`

- `test_guide_does_not_reference_missing_env_example`
  - Read `GUIDE.md`.
  - Assert it does not contain `.env.example`.

- `test_guide_documents_interactive_server_input`
  - Assert it contains `Add Server` or `user@host:port`.

### Acceptance Criteria

- First-time users are not directed to a non-existent file.
- README and GUIDE do not have conflicting startup instructions.

## Recommended Implementation Order

1. First add test infrastructure and doc tests to ensure subsequent changes are verifiable.
2. Fix remote input sending. This affects both stability and security — highest risk.
3. Fix session record port isolation to prevent cross-server operation interference.
4. Fix network probing and worker lifecycle to reduce false status reports and residual background tasks.
5. Fix refresh exception display to make subsequent remote issues diagnosable.
6. Update `GUIDE.md`.

## Minimal Regression Commands

After implementation, run at minimum:

```bash
python -m compileall -q hermes_gate
python -m pytest -q
docker compose config --quiet
```

If Docker is available and building is permitted, also run:

```bash
docker compose build
```

Real remote server integration testing can be a manual item and should not be a default unit test prerequisite.

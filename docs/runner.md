# Teambus Runner

`teambus` now supports low-token autonomous wakeups through `wait_for_work(...)`. This repo adds a thin external runner that keeps a role alive, sends heartbeats, waits for work, and launches `codex exec` only when the server reports actionable events.

## Files

- `scripts/teambus_role_runner.py`: generic persistent role-runner
- `runner/roles.json`: role defaults and Codex execution settings
- `scripts/run_teambus_role.sh`: WSL/Linux launcher
- `scripts/run_teambus_role.ps1`: Windows launcher

## Control Plane Split

- `teambus`: live source of truth for tasks, locks, inboxes, artifacts, and role ownership
- `docs/*.md`: durable project memory such as project brief, decisions, board facts, and tooling notes

The runner does not replace `teambus`. It only keeps Codex alive long enough to react when `teambus` reports new work.

## Expected Behavior

With the runner active:

- the role registers once and keeps an `agent_id`
- the runner sends periodic `heartbeat(...)`
- the runner blocks on `wait_for_work(...)` using a persisted cursor
- transient teambus MCP failures are retried with bounded exponential backoff
- Codex is launched only when work arrives
- after the turn completes, the runner goes back to waiting

The orchestrator runner is configured with `wait_mode: edge_only`, so old unread messages or already-ready tasks do not cause immediate repeat wakes after the current wake has been handled.

Without the runner:

- a Codex session still ends after its current turn
- you must restart or wake it manually

## WSL Roles

`orchestrator` and `manual-reader` are configured to run from the repo root in WSL.

Example:

```bash
scripts/run_teambus_role.sh orchestrator
scripts/run_teambus_role.sh manual-reader
```

Interactive orchestrator example:

```bash
scripts/run_teambus_role.sh orchestrator --interactive
```

That mode waits for a wake, launches the interactive Codex TUI with the wake context as the initial prompt, and then returns to waiting after you exit Codex.

Resume the same interactive session without sending a new prompt:

```bash
scripts/run_teambus_role.sh orchestrator --interactive --resume-session
```

That mode behaves differently:

- if the runner already knows the last interactive session id for this role, it runs `codex resume <session-id>` and, if `resume_prompt` is configured for that role, sends a short wake prompt on resume
- if no tracked session exists yet, it launches a fresh promptless interactive Codex session once, captures the session id from Codex's own `codex resume <session-id>` hint when possible, records that id after exit, and resumes that same session on later wakes
- the wake payload is still saved under `tmp/runner-state/` so you can inspect it manually

Current default:

- `manual-reader` resumes with: read the saved wake payload and proceed with the current manual-reader task
- `manual-reader` also uses `codex exec resume` in non-interactive mode, currently pinned to session `019dad78-7c8c-7300-a722-5fbcb7a6577f`
- if that pinned session is not present in the local saved-session store, the runner falls back to one fresh `codex exec` bootstrap and then tracks the new saved non-interactive session for later wakes

Important bootstrap detail:

- a printed `codex resume <session-id>` hint is not enough by itself; the session must also be saved locally by Codex
- on the first promptless bootstrap launch, send at least one message before exiting if you want that session to become resumable later
- if Codex exits before saving a local session, the runner will now refuse to reuse that id and will fall back to another promptless bootstrap on the next wake

If the Python environment that contains the MCP client is not `/home/rdcraze/mcp/teambus/.venv/bin/python`, override it:

```bash
TEAMBUS_RUNNER_PYTHON=/path/to/python scripts/run_teambus_role.sh orchestrator
```

## Windows Roles

`implementer` and `verifier` use `${WINDOWS_REPO_ROOT}` from `runner/roles.json`. Before launching those roles, set `WINDOWS_REPO_ROOT` to the Windows path that Codex should use.

PowerShell example:

```powershell
$env:WINDOWS_REPO_ROOT = "C:\Users\you\projects\piano-agents"
scripts\run_teambus_role.ps1 implementer
scripts\run_teambus_role.ps1 verifier
```

The Python environment that runs the script must have the `mcp` client package installed.

## Config

`runner/roles.json` controls:

- `server_url`
- heartbeat, wait, and backoff intervals
- tool retry attempts and retry backoff for runner-owned teambus calls
- `wait_mode` (`level` or `edge_only`)
- whether to replace existing role bindings on startup
- Codex CLI defaults
- per-role `name` and `worktree`
- optional `resume_prompt` for roles that should resume an existing session with a short wake instruction
- optional `exec_resume_session_id` for roles that should use `codex exec resume <session-id>` instead of starting a fresh non-interactive session each wake

Useful overrides:

```bash
scripts/run_teambus_role.sh orchestrator --validate-config
scripts/run_teambus_role.sh orchestrator --dry-run --once
scripts/run_teambus_role.sh orchestrator --interactive --once
scripts/run_teambus_role.sh orchestrator --interactive --resume-session
scripts/run_teambus_role.sh orchestrator --no-replace-existing
```

## State Files

The runner stores local role state in `tmp/runner-state/`:

- `<role>.json`: agent id, last cursor, last wake payload, last Codex exit code, and the last tracked interactive Codex session id when available
- `<role>-last-prompt.txt`: last prompt handed to Codex
- `<role>-last-message.txt`: last final message emitted by Codex
- `<role>-last-wake.json`: last raw wake payload from `wait_for_work(...)`

Persisting the cursor prevents the orchestrator from replaying the full event history after every restart.

## Operational Notes

- `replace_existing` defaults to `true`, so starting a runner will take over that role binding.
- The runner owns heartbeats and waiting. The Codex prompt explicitly tells agents not to call `register_agent(...)`.
- `--interactive` launches `codex` TUI instead of `codex exec`. Use it when you want to steer a role manually but still let the runner own heartbeats and `wait_for_work`.
- `--resume-session` only applies with `--interactive`. It skips the startup prompt and reopens the last runner-tracked interactive Codex session instead.
- `approval` defaults to `never` in `runner/roles.json` so unattended roles do not hang waiting for terminal approval. Change that if you want manual approvals instead.
- The runner also passes explicit `mcp_servers.teambus.tools.<tool>.approval_mode="approve"` overrides for the full teambus tool set, because tool-specific approval entries are what the local Codex CLI actually honors for unattended MCP use.
- Retry hardening currently covers runner-owned teambus calls such as `register_agent`, `heartbeat`, and `wait_for_work`. It does not automatically retry arbitrary MCP tool calls made inside an interactive Codex session.

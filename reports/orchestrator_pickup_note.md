# Orchestrator Pickup Note

Date: `2026-05-02`
Repo: `/mnt/e/projects/piano-agents`
Active branch: `codex/phase1c-uart-boundary-fix`
Active orchestrator id: `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`

## Current State

The project is in controlled-scaling mode after accepting the Phase 1C UART RX command-ingress baseline.

Accepted UART RX baseline:

- Exact promoted SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`
- Resource/timing anchor: `7,963 / 10,320` LEs, `14 / 46` M9Ks, `80,896 / 423,936` memory bits, `6 / 46` DSP9s, `1 / 2` PLLs
- Timing anchor: slow-85C `sys_clk_50m` setup slack `+2.438 ns`, hold slack nonnegative, TNS `0.000`
- Firmware ROM anchor: `507 / 1024` words
- Frozen UART order: `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X`
- Accepted no-command profile: latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`
- Accepted six-command profile: latest `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`

Interpretation:

- The platform can host the current minimal hybrid architecture.
- Logic and on-chip memory remain the primary constraints.
- DSP headroom is still comparatively large.
- Do not infer "plenty of room"; future steps must be one controlled dimension at a time, with timing, resource, UART, and waveform evidence.

## Live Coordination Source

Use `pianoagent` as the live coordination source.

Do not use the old TeamBus MCP tools. In particular:

- Do not call any `mcp__teambus__` tool.
- Do not call `mcp__pianoagent__.wait_for_work`.
- Use `pianoagent` MCP tools only for dashboard/task/message/artifact/path-lock operations.
- Use the local wait runner for idle waiting, in the foreground.

Role bindings currently observed:

- Orchestrator: `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
- Implementer: `6f88abfe-bfb2-4cbd-a558-6d82248ed93c`
- Verifier: `e9722d83-b000-4165-a5a7-36b758c2e8d8`
- Manual-reader: `75ce19e2-58a5-4c98-a7f7-d9d4f3c93a5e`

Last observed `pianoagent` dashboard state:

- `106` done, `1` in progress, `1` todo, `0` blocked
- No active path locks
- No unread orchestrator inbox messages

## Idle Wait Convention

When idle, run the local wait runner in the foreground and preserve the cursor:

```bash
python3 /home/rdcraze/mcp/teambus/wait_teambus.py work --agent-id <agent-id> --after-cursor <cursor>
```

When a wait returns, inspect the JSON and act on:

- `cursor`: save it and pass it as `--after-cursor` on the next wait.
- `reasons`: decide why the runner woke.
- `message_ids`: read and acknowledge relevant messages with `pianoagent`.
- `claimable_task_ids`: claim/start the relevant task if it belongs to this role.
- `task_ids`, `artifact_ids`, `stale_agent_ids`: inspect and respond as appropriate.

After handling the wake reason, return to foreground waiting when idle.

Operational details:

- Do not busy-poll dashboard or inbox.
- If `all_agents_waiting` repeats without cursor progress, do not loop on dashboard/inbox. Notify the relevant agent or update the relevant queued/in-progress task status so that the affected runner wakes.
- For a known active task, prefer task-specific waiting to avoid repeated all-waiting wakeups:

```bash
python3 /home/rdcraze/mcp/teambus/wait_teambus.py work --agent-id <agent-id> --after-cursor <cursor> --task-id <task-id>
```

- If a Codex turn is interrupted while a wait runner is active, check for a stale local wait process before starting another one.
- Keep the wait runner in the foreground; do not intentionally leave it as a background terminal task.

## Git Convention

Track changes with Git from this point.

- Commits are allowed if they are reversible and non-destructive.
- Do not revert user or agent changes unless explicitly asked.
- Ignore unrelated dirty files unless they block the task.
- At the time this note was updated, pre-existing dirty work included CRLF-only changes in:
  - `reports/phase1c_uart_rx_host_smoke_tooling_parser_regression.log`
  - `reports/phase1c_uart_rx_host_smoke_tooling_selftest.log`
- Also present and not touched by this note update:
  - `.claude/`
  - `docs/verifier_handoff_manual.md`
  - `implementer_handoff.md`

Recent relevant commits:

- `56ef89c` Validate Phase 1C measurement hook options
- `54d3904` Add Phase 1C measurement hook options memo
- `4567f50` Validate Phase 1C UART RX host smoke tooling
- `5e6cd48` Add Phase 1C UART RX host smoke tooling
- `4a6138d` Add Phase 1C waveform validation checklist
- `5f1c94a` Accept Phase 1C UART RX command ingress

## Active Work

`task-68752505` is in progress with implementer `6f88abfe-bfb2-4cbd-a558-6d82248ed93c`.

Task: draft `reports/phase1c_first_measurement_hook_contract.md`.

Scope:

- Design-only.
- Pick exactly one lowest-risk first measurement hook candidate.
- Do not implement anything.
- Do not edit RTL, firmware, constraints, build scripts, project files, generated bitstreams, host tools, existing reports, register behavior, UART behavior, or resource-affecting files.

`task-fc35ad1e` is queued for verifier and depends on `task-68752505`.

Task: validate `reports/phase1c_first_measurement_hook_contract.md` into `reports/phase1c_first_measurement_hook_contract_validation.md`.

## Essential Artifacts

Use these before asking agents to rediscover context:

- `reports/phase1c_uart_rx_command_ingress_acceptance_decision.md`
- `reports/phase1c_uart_rx_boundary_audio_rerun_validation.md`
- `reports/phase1c_waveform_validation_checklist.md`
- `reports/phase1c_uart_rx_host_smoke_tooling_report.md`
- `reports/phase1c_uart_rx_host_smoke_tooling_validation.md`
- `reports/phase1c_measurement_hooks_options.md`
- `reports/phase1c_measurement_hooks_options_validation.md`
- `reports/phase1c_uart_rx_command_ingress_boundary_fix_report.md`
- `reports/phase1c_uart_rx_command_ingress_boundary_fix_validation.md`
- `reports/phase1c_uart_rx_command_ingress_impl_report.md`
- `reports/phase1c_uart_rx_command_ingress_validation.md`
- `reports/phase1c_uart_rx_command_ingress_contract_acceptance_decision.md`
- `reports/phase1c_uart_rx_command_ingress_contract.md`
- `docs/project_brief.md`
- `docs/platform_decisions.md`

Host-side tooling:

- `scripts/phase1c_uart_telemetry.py`
- `scripts/test_phase1c_uart_telemetry.py`
- `scripts/phase1c_uart_rx_baseline_smoke.py`
- `scripts/test_phase1c_uart_rx_baseline_smoke.py`

## Blocked Feature Gates

Do not authorize these without a separate explicit decision and full validation plan:

- SDRAM
- fourth voice
- richer physics
- exact 48 kHz PLL/sample-rate work
- larger CPU or ISA
- hardware dispatcher
- voice stealing
- per-note state
- per-voice parameter banks
- host-selected note/voice/parameter controls
- codec config RX
- diagnostic clear RX
- sample playback
- UI/TFT/touch
- CPU work in the audio sample loop
- non-prefix UART changes
- register-map changes before current accepted ranges

## Next Orchestrator Move

Wait for implementer to finish `task-68752505`.

Recommended wait command shape:

```bash
python3 /home/rdcraze/mcp/teambus/wait_teambus.py work --agent-id 1c005a25-956c-4b69-9b69-9bf3cd9a8d68 --after-cursor <cursor> --task-id task-68752505
```

When the artifact arrives:

- read `reports/phase1c_first_measurement_hook_contract.md`,
- acknowledge implementer messages,
- confirm the task is marked done and path locks are released,
- wake verifier for `task-fc35ad1e` if needed,
- wait for `reports/phase1c_first_measurement_hook_contract_validation.md`.

If all agents report waiting while an active task remains in progress:

- avoid dashboard/inbox polling loops,
- post a targeted message to the assigned agent or role,
- or update the task status with a concrete wake note.

Do not start implementation of any measurement hook from the contract memo. Treat the current workstream as design guidance only until an explicit implementation task is created and validated.

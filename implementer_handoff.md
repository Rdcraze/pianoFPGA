# Implementer Handoff Manual

Workspace: `E:\projects\piano-agents`

Role: `implementer`

Core rule: when idle, wait with the local teambus wait runner, not an MCP wait tool.

## Standard Workflow

1. Check unread inbox before waiting or starting new work.
2. Read and acknowledge relevant orchestrator messages.
3. Claim and start only tasks intended for the implementer role.
4. Reserve only the paths needed for the task.
5. Keep task scope narrow. Do not touch RTL, firmware, constraints, build outputs, host tools, register behavior, UART behavior, or resource-affecting files unless the task explicitly allows it.
6. Make the requested changes or report only.
7. Run focused validation.
8. Stage and commit only task-owned files.
9. Submit the requested artifact.
10. Mark the task done and release locks.
11. Heartbeat idle, check inbox once, then return to local wait.

## Local Wait Command

Use this when idle:

```powershell
$tb="\\wsl.localhost\Ubuntu\home\rdcraze\mcp\teambus"
python "$tb\wait_teambus.py" --state-path "$tb\state.json" instruction --agent-id <agent-id> --after-cursor <cursor>
```

After each wake:

- Save returned `cursor`.
- Read/ack relevant `message_ids`.
- Claim/start relevant `claimable_task_ids`.
- Return to wait with the new cursor when idle.

## Pianoagent MCP Lifecycle

Typical task flow:

```text
heartbeat
get_inbox
acknowledge_message
claim_next_task
start_task
reserve_path / reserve_paths
submit_artifact
update_task_status
release_task_locks
heartbeat idle
```

Use `post_message` when the orchestrator needs a completion clarification or blocker report.

## Git Commands

Inspect:

```powershell
git status --short
git diff -- <paths>
git diff --cached --stat
git branch --show-current
```

Branch:

```powershell
git switch -c codex/<task-branch>
```

Stage and commit narrowly:

```powershell
git add -- <task-owned-paths>
git status --short -- <task-owned-paths>
git commit -m "<message>"
```

Do not use destructive Git commands unless explicitly requested.

## Common Validation Commands

UART RX baseline checks:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check <capture.txt> --mode no-command
python scripts\phase1c_uart_rx_baseline_smoke.py check <capture.txt> --mode commanded
```

Parser and host-smoke tests:

```powershell
cmd /c "python scripts\test_phase1c_uart_telemetry.py > reports\<log>.log 2>&1"
cmd /c "python scripts\test_phase1c_uart_rx_baseline_smoke.py > reports\<log>.log 2>&1"
python -m py_compile scripts\<script>.py
```

Firmware build:

```powershell
& .\fw\phase0\build.ps1 *> reports\<fw_build_log>.log
```

## Quartus And Hardware Commands

Clear license environment first:

```powershell
$env:LM_LICENSE_FILE=''
$env:QUARTUS_LICENSE_FILE=''
```

Full compile:

```powershell
Push-Location quartus\phase0
& 'D:\quartus\quartus\bin64\quartus_sh.exe' --flow compile piano_phase0_top 2>&1 | Tee-Object -FilePath ..\..\reports\<compile_log>.log
Pop-Location
```

List programmer cables:

```powershell
& 'D:\quartus\quartus\bin64\quartus_pgm.exe' -l
```

Program accepted Phase 1C UART RX SOF:

```powershell
& 'D:\quartus\quartus\bin64\quartus_pgm.exe' -m JTAG -c "USB-Blaster [USB-0]" -o "p;E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof"
```

Accepted baseline identity:

```text
SOF SHA-256: CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5
Programmer checksum: 0x005F102E
```

## Current Baseline Guardrails

Do not expand or authorize these without a new explicit task:

- SDRAM
- fourth voice
- richer physics
- exact 48 kHz PLL
- larger CPU/ISA
- hardware dispatcher
- voice stealing
- per-note state
- per-voice parameter banks
- host-selected parameters
- codec config RX
- diagnostic clear RX
- sample playback
- UI/TFT/touch
- CPU audio-loop expansion
- non-prefix UART changes
- register-map changes outside accepted ranges

## Current Task Progress

Last active wait cursor: `5708`

Agent id: `6f88abfe-bfb2-4cbd-a558-6d82248ed93c`

Current branch:

```powershell
codex/phase1c-uart-boundary-fix
```

Relevant commits on this branch:

- `d1a7da3` - Fix Phase 1C UART RX parser boundary
- `f2bccb6` - Add Phase 1C UART RX audio rerun evidence
- `5e6cd48` - Add Phase 1C UART RX host smoke tooling
- `54d3904` - Add Phase 1C measurement hook options memo

Active task at interruption:

```text
task-68752505
Draft first Phase 1C measurement-hook contract option
```

Task state:

- Claimed and started.
- Reserved path: `reports/phase1c_first_measurement_hook_contract.md`
- No artifact submitted yet.
- Task not marked done yet.
- No implementation files should be edited for this task.
- User interrupted after context reading, before the contract report was written.

Context already read:

- `reports/phase1c_measurement_hooks_options.md`
- `reports/phase1c_measurement_hooks_options_validation.md`

Required output for active task:

```text
reports/phase1c_first_measurement_hook_contract.md
```

Scope for active task:

- Design-only.
- Pick exactly one lowest-risk first measurement hook.
- Prefer a firmware-derived event/report measurement unless a registered sticky RTL indicator is clearly justified.
- Do not edit RTL, firmware, constraints, build scripts, project files, generated bitstreams, host tools, existing reports, register behavior, UART behavior, or resource-affecting files.
- Do not authorize blocked expansions listed above.

Likely next step:

Draft `reports/phase1c_first_measurement_hook_contract.md` selecting a firmware-derived event/report measurement over the existing accepted telemetry counters as the one lowest-risk first hook. The contract should define purpose, precise data exposed, ownership domain, UART/MMIO impact, prefix compatibility, clear/set/snapshot semantics, resource/timing/ROM risk, validation evidence, rollback criteria, and explicit go/no-go gates.

After finishing the active task:

```text
submit_artifact
update_task_status done
release_task_locks
heartbeat idle
get_inbox unread_only
local wait runner with --after-cursor 5708 or newer cursor
```

## Reporting Pattern

A good task report should include:

- task id and scope;
- files changed;
- commands run;
- validation evidence paths;
- resource/timing or ROM deltas if relevant;
- hardware identity if relevant;
- residual risks;
- clear promotion or no-go recommendation.

After report submission:

```text
submit_artifact
update_task_status done
release_task_locks
heartbeat idle
get_inbox unread_only
local wait runner
```

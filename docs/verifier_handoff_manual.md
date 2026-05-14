# Verifier Handoff Manual

This manual captures the verifier workflow used in this repository during the Phase 1C UART RX baseline work. It is written for a replacement agent taking over the same workspace.

## Identity And Workspace

- Worktree: `E:\projects\piano-agents`
- Shell: PowerShell
- Role: `verifier`
- Current verifier agent id used in this run: `e9722d83-b000-4165-a5a7-36b758c2e8d8`
- Use `pianoagent` MCP for task coordination. Do not use teambus MCP tools.
- The local wait runner path contains `teambus`, but it is invoked as a shell command only because the orchestrator explicitly required it.

## Core Rules

- Track changes with Git from the start of work.
- Never revert changes you did not make.
- Keep report edits scoped to the reserved artifact path for the active task.
- When idle, wait in the foreground with the local wait runner and preserve the returned cursor.
- Do not busy-poll the inbox or dashboard.
- After a wait wake, inspect the JSON, handle the wake reason, acknowledge relevant messages, claim/start relevant tasks, and return to waiting when idle.
- If `rg.exe` fails with access denied, use PowerShell `Select-String`, `Get-ChildItem`, and `Get-Content` instead.

## Idle Wait Command

Use the last saved cursor as `--after-cursor`. Update the cursor from every wait result.

```powershell
$tb="\\wsl.localhost\Ubuntu\home\rdcraze\mcp\teambus"
python "$tb\wait_teambus.py" --state-path "$tb\state.json" instruction --agent-id e9722d83-b000-4165-a5a7-36b758c2e8d8 --after-cursor <cursor>
```

Important wait JSON fields:

- `cursor`: save this for the next wait.
- `message_ids`: read and acknowledge relevant messages.
- `claimable_task_ids`: claim/start relevant tasks.
- `task_ids`, `artifact_ids`, `stale_agent_ids`: normally orchestrator-facing, but inspect if relevant to the wake.
- `reasons`: explains why the wait returned.

## MCP Task Workflow

Use the `pianoagent` MCP sequence below for each task:

1. Read inbox for unread messages.
2. Acknowledge orchestrator message.
3. Claim the task.
4. Start the task.
5. Reserve only the intended output path.
6. Inspect implementation artifact, commit, and relevant prior reports.
7. Run focused verification commands.
8. Write the validation report.
9. Submit the report artifact.
10. Mark the task `done`.
11. Post a short result message to orchestrator.
12. Release task locks.
13. Check unread inbox once for messages that arrived during work.
14. Return to foreground wait.

Common MCP operations used:

```text
get_inbox(agent_id, unread_only=true)
acknowledge_message(agent_id, message_id)
claim_next_task(agent_id)
start_task(agent_id, task_id)
reserve_path(agent_id, task_id, path, ttl_seconds, note)
submit_artifact(agent_id, task_id, kind, uri, summary)
update_task_status(agent_id, task_id, status, note)
post_message(from_agent, to_role, task_id, subject, body)
release_task_locks(agent_id, task_id)
```

## Git Commands

Check baseline and keep unrelated changes visible:

```powershell
git status --short --untracked-files=normal
git log --oneline -6
git show --stat --oneline --decorate --no-renames <commit>
git show --name-status --no-renames <commit>
git diff --stat
git diff --numstat
git diff -- <path>
git ls-files <path>
```

Interpretation notes:

- A clean `git status --short --untracked-files=normal` means no tracked or untracked changes, apart from Git line-ending warnings that may appear during diff commands.
- If unrelated untracked files exist, note them and leave them alone.
- For report-only validation tasks, the implementation commit should normally add or modify only report files. Any RTL, firmware, constraint, build-script, host-tool, bitstream, or project-file change must be called out.

## File Inspection Commands

Read a whole report:

```powershell
Get-Content -Raw reports\<file>.md
```

Search reports without `rg`:

```powershell
Select-String -Path reports\<file>.md -Pattern 'SOF SHA-256|Programmer checksum|LEs:|setup slack|G=|Q=|X=|K='
```

List evidence files:

```powershell
Get-ChildItem reports -Filter '*uart_rx*' | Select-Object -ExpandProperty Name
Get-ChildItem reports -Filter '*round_robin*' | Select-Object -ExpandProperty Name
```

Check whether a report path already exists:

```powershell
Test-Path reports\<candidate_report>.md
```

Check for possibly leftover wait processes after an interrupted wait:

```powershell
Get-Process python -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path,StartTime | Format-List
```

## UART RX Host Smoke Validation Commands

Run the host smoke self-test:

```powershell
python scripts\test_phase1c_uart_rx_baseline_smoke.py
```

Run parser regression:

```powershell
python scripts\test_phase1c_uart_telemetry.py
```

Check accepted no-command capture:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_command_ingress_boundary_uart_capture.txt --mode no-command
```

Expected shape:

```text
UART_RX_BASELINE_SMOKE_PASS mode=no-command frames=170 cycles=7 G=00000006 Q=00000000 X=00000000 K=00000000
```

Check accepted six-command capture:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_boundary_audio_rerun_uart_capture.txt --mode commanded
```

Expected shape:

```text
UART_RX_BASELINE_SMOKE_PASS mode=commanded frames=266 cycles=10 G=0000000C Q=00000006 X=00000000 K=00000000
```

Check malformed capture as an expected failure for accepted no-command baseline:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_command_ingress_boundary_malformed_uart_capture.txt --mode no-command
```

Expected shape:

```text
UART_RX_BASELINE_SMOKE_FAIL mode=no-command frames=386 cycles=15 G=00000006 Q=00000000 X=00030004 K=00000000
error: X expected 0x00000000, got 0x00030004
```

Show operator help:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py --help
```

## Audio And Waveform Validation Commands

Use FFmpeg `astats` for basic waveform intensity metrics:

```powershell
ffmpeg -hide_banner -i reports\<capture>.wav -af astats=metadata=0:reset=0 -f null -
```

Metrics to record:

- duration, sample rate, channels, and format;
- min/max sample;
- peak dBFS;
- RMS dBFS;
- DC offset or mean;
- flat factor;
- clipped/full-scale sample count;
- dropout/silence windows;
- dominant frequency for the loud event window, not only the whole capture.

Reference waveform values used during Phase 1C:

| Capture | RMS | Peak | Frequency content | Decision |
| --- | ---: | ---: | --- | --- |
| `reports/phase1c_firmware_round_robin_validation_audio_capture.wav` | `-44.05 dBFS` | `-13.12 dBFS` | `436/872/1308 Hz` event bins | accepted |
| `reports/phase1c_uart_rx_command_ingress_audio_capture.wav` | `-42.55 dBFS` | `-13.14 dBFS` | `436/872/1308 Hz` event bins | accepted |
| `reports/phase1c_uart_rx_command_ingress_boundary_audio_capture.wav` | `-39.19 dBFS` | `-31.82 dBFS` | `250 Hz` pickup, flat low-level envelope | rejected unplugged-mic evidence |
| `reports/phase1c_uart_rx_boundary_audio_rerun_audio_capture.wav` | `-35.70 dBFS` | `-13.59 dBFS` | `436 Hz` event with `872 Hz` harmonic | accepted rerun |

Use the checklist in `reports/phase1c_waveform_validation_checklist.md` for hard waveform gates.

## Accepted UART RX Baseline

Accepted identity:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`

Accepted resource/timing baseline:

- LEs: `7,963 / 10,320`
- M9Ks: `14 / 46`
- Memory bits: `80,896 / 423,936`
- DSP9s: `6 / 46`
- Firmware ROM: `507 / 1024` words
- Slow-85C `sys_clk_50m` setup slack: `+2.438 ns`
- Slow-85C `sys_clk_50m` hold slack: `+0.406 ns`

Frozen telemetry order:

```text
I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X
```

Accepted profiles:

- No-command: `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`, `Q=0`, `X=0`.
- Six-command: `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `K=0`, `Q=6`, `X=0`, no `!N` echo.
- Malformed/boundary: final `X=00030004`, `K=0`, `Q=0`, no malformed input echo.

## Validation Report Pattern

Use this structure for verifier reports:

```text
# <Task Title> Validation

Verifier:
Task:
Implementation task:
Implementation artifact:
Implementation commit:
Reviewed artifact:

## Verdict
PASS/FAIL.

## Scope Review
What changed, what did not change, Git status.

## Evidence
Commands run, output summaries, paths.

## Findings
Blocking issues first, then warnings or limitations.

## Residual Risks
What remains outside this validation.

## Recommendation
Go/no-go and exact next condition.
```

Keep reports concrete: name artifact paths, commands, expected values, and the reason for PASS or FAIL.

## Blocked Feature Discipline

For Phase 1C UART RX baseline work, do not treat any memo as authorization for these without a separate task and full revalidation:

- SDRAM;
- fourth voice or broader polyphony;
- richer physics;
- exact-48 kHz PLL/sample-rate work;
- larger CPU or ISA;
- hardware note dispatcher;
- voice stealing;
- per-note state;
- per-voice parameter banks;
- host-selected voice, pitch, velocity, duration, or synthesis parameters;
- codec configuration over RX;
- diagnostic clear commands over RX;
- sample playback;
- UI/TFT/touch work;
- CPU work in the audio sample loop;
- non-prefix UART telemetry changes;
- register changes outside accepted ranges.

## Recently Completed Verifier Artifacts

- `reports/phase1c_waveform_validation_checklist.md`
- `reports/phase1c_uart_rx_host_smoke_tooling_validation.md`
- `reports/phase1c_measurement_hooks_options_validation.md`

## Current Task Progress

State as last verified in this thread:

- Registered verifier agent: `e9722d83-b000-4165-a5a7-36b758c2e8d8`.
- Active claimed verifier task: none.
- Last saved wait cursor: `5708`.
- The foreground wait from cursor `5708` was intentionally interrupted by the user before it returned. There is no newer cursor captured in this handoff.
- Next action for a replacement verifier: check unread inbox first, then either claim any newly available verifier task or return to the foreground wait using cursor `5708`.

Completed verifier tasks in this run:

| Task | Result | Artifact | Report |
| --- | --- | --- | --- |
| `task-50976e79` waveform-focused Phase 1C baseline validation checklist | DONE / submitted | `32b02d55-088e-4aca-8d64-4df47f7f224c` | `reports/phase1c_waveform_validation_checklist.md` |
| `task-8de6a7ae` Phase 1C UART RX host smoke tooling validation | PASS / DONE / submitted | `7dad6ce5-5a3d-4617-94b7-fc977953048d` | `reports/phase1c_uart_rx_host_smoke_tooling_validation.md` |
| `task-d7d85833` Phase 1C measurement-hook options memo validation | PASS / DONE / submitted | `8747e827-f57a-4670-a92c-a733f04c57aa` | `reports/phase1c_measurement_hooks_options_validation.md` |

Implementation commits validated:

- `5e6cd48` added Phase 1C UART RX host smoke tooling.
- `54d3904` added the Phase 1C measurement hook options memo.

Verifier commits visible in local history after those validations:

- `4a6138d` added the waveform validation checklist.
- `4567f50` validated Phase 1C UART RX host smoke tooling.
- `56ef89c` validated Phase 1C measurement hook options.

Queued or dependency-gated work at the last orchestration check:

- `task-fc35ad1e` is the dependent verifier task for the first one-hook measurement contract option.
- It was queued behind implementer task `task-68752505`.
- The orchestrator message for that queued task was acknowledged.
- It had not been claimed because the implementer dependency had not landed at the time of the last saved cursor.
- Expected validation focus when it becomes claimable: one-hook scope, compatibility with the accepted baseline, clear semantics, resource/timing risk, and blocked-feature discipline.

The last saved wait cursor before this manual request was `5708`.

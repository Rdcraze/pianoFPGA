# piano-agents — Orchestrator Commands

## Wait Loop (NEVER set --timeout)

```bash
wsl bash -c "cd /home/rdcraze/mcp/teambus && python3 wait_teambus.py work --agent-id 1c005a25-956c-4b69-9b69-9bf3cd9a8d68 --after-cursor <cursor> --task-id <task-id>"
```

After handling a wake event, save the cursor and pass it on the next wait. For task-specific waiting, use `--task-id`; omit for general waiting. Keep in foreground.

## Agents

| Role | Agent ID |
|---|---|
| Orchestrator | `1c005a25-956c-4b69-9b69-9bf3cd9a8d68` |
| Implementer | `5ed7d08b-d179-4fdc-ada6-5e1f57099943` |
| Verifier | `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c` |
| Manual-reader | `6c00703d-f4e9-4320-be40-354d65623776` |

## Manual-Reader Scope

For board facts only: pinout, clock/reset, codec registers, schematic/page references. NOT for phase-gate assessments, design judgment, or exit-criteria decisions.

## Key Paths

- Orchestrator pickup: `reports/orchestrator_pickup_note.md`
- Project brief: `docs/project_brief.md`
- Board capabilities: `docs/board_capabilities_report.md`
- Audio checklist: `reports/phase1c_audio_verification_checklist.md`
- Platform decisions: `docs/platform_decisions.md`

## Baseline Anchors

- Board: EP4CE10F17C8 (Wildfire "ZhengTu Pro")
- SOF: current varies (last: `0x005F4CC5` speaker vol fix, each commit changes it)
- LE: 7,963 / 10,320 (23%)
- M9K: 14 / 46 (70%)
- DSP: 6 / 46 (87%)
- ROM: 539 / 1,024 words
- setup slack: +2.438 ns (slow-85C)
- UART order (frozen): I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X (CC suffix)
- No-command profile: G=6 Q=0 X=0 K=0 CC=0x003D0900

## Orchestrator Loop Rule

**Always end every turn with a wait command** unless there are zero todo tasks. When todo=0 and no claimed/in_progress tasks exist, do not wait — instead proactively plan the next workstream and assign new tasks.

## Verification Flow Per Change

Every code modification needs a verifier validation task. After implementer submits:
1. Create verifier task with title "Validate <change>" referencing the implementer's report
2. Verifier must: compile Quartus, program FPGA, capture UART + audio, run audio checklist
3. Verifier submits validation report → orchestrator reviews → accept/revise

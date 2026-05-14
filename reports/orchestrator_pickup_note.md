# Orchestrator Pickup Note

Date: `2026-05-04`
Repo: `/mnt/e/projects/piano-agents`
Active branch: `codex/phase1c-uart-boundary-fix`
Active orchestrator id: `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`

## Current State

Phase 1 is complete (all exit criteria PASS). Phase 2 body filter is deployed. The codebase is clean after removing diagnostic scaffolding from the volume investigation.

### Baseline Anchors

| Anchor | Value |
|---|---|
| Board | EP4CE10F17C8 (Wildfire "ZhengTu Pro") |
| SOF checksum (latest) | `0x006815EE` (varies per commit) |
| LEs | 7,963 / 10,320 (23%) |
| M9Ks | 14 / 46 (70%) |
| DSP9s | ~10 / 46 (22%, includes body filter) |
| ROM words | 539 / 1,024 (53%) |
| setup slack (slow-85C) | +2.438 ns |
| hold slack (slow-85C) | +0.406 ns |
| UART order (frozen) | I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X (CC suffix) |
| No-command profile | G=6 Q=0 X=0 K=0 CC=0x003D0900 |

### Active Features (deployed and validated)

| Feature | Commit | Status |
|---|---|---|
| CC counter measurement hook | `7ed2c62`, `72e83d3` | PASS |
| WM8978 speaker output enable (R49 SPKOUTP_EN) | `6149c59` | PASS |
| Speaker volume (R54/R55 50→0, +20 dB) | `6934692` | PASS |
| Full-scale velocity (0x4000→0x7FFF, +6 dB) | `647edee` | PASS |
| Excitation >>>1 guard (K=105→K=0) | `c25d1a7` | PASS |
| Body FIR mix 25%→50% (+6 dB) | `c25d1a7` | PASS |
| Phase 2 body IIR filter (2 biquads) | `ad94631` | PASS, K=0 |
| Sample_gen test path (codec diagnostic) | `c1c922c` | Kept as diagnostic tool |
| ModelSim gain trace (pipeline analysis) | `fe34677`, `1242740` | Docs |

### Gain Calibration Summary

Per-voice digital: -11.7 dBFS (ModelSim measured)
3-voice sum: -2.1 dBFS digital (K=0)
sample_gen reference: -5.58 dBFS through external mic
Waveguide first-strike (3-voice simultaneous): -1.93 dBFS through external mic
Round-robin single voice: -37.5 dBFS through external mic

The codec path is verified. The digital gain chain is calibrated. The external mic attenuates ~5-6 dB. K=0 at all gain settings.

### Obsoleted Code

`obsolete/` directory contains the re-trigger and 3-voice simultaneous diagnostic code that was removed in `c95f08a`. The re-trigger approach was architecturally incompatible with the waveguide RTL (`trigger_strobe && enable` clears the delay line). See `obsolete/README.md`.

## Live Coordination

Use `pianoagent` MCP tools. Never call `mcp__teambus__` or `mcp__pianoagent__.wait_for_work`.

### Agent IDs (current from dashboard)

| Role | Agent ID |
|---|---|
| Orchestrator | `1c005a25-956c-4b69-9b69-9bf3cd9a8d68` |
| Implementer | `5ed7d08b-d179-4fdc-ada6-5e1f57099943` |
| Verifier | `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c` |
| Manual-reader | `6c00703d-f4e9-4320-be40-354d65623776` |

### Manual-Reader Scope

Board facts only: pinout, clock/reset, codec registers, schematic/page references. NOT phase-gate assessments, design judgment, or exit-criteria decisions.

## Wait Loop (NEVER set --timeout)

```bash
wsl bash -c "cd /home/rdcraze/mcp/teambus && python3 wait_teambus.py work --agent-id 1c005a25-956c-4b69-9b69-9bf3cd9a8d68 --after-cursor <cursor> --task-id <task-id>"
```

Keep in foreground. After each wake: save cursor, inspect reasons, read/ack messages, act on task completions.

**Last known cursor: `6591`**

### Orchestrator Loop Rule

Always end every turn with a wait command unless there are zero todo tasks. When todo=0 and no claimed/in_progress tasks exist, do not wait — instead proactively plan the next workstream and assign new tasks.

## Verification Flow

Every code modification needs a verifier validation task:
1. Create verifier task referencing implementer's report
2. Verifier must: compile Quartus, program FPGA, capture UART + audio, run audio checklist
3. Verifier submits validation report → orchestrator reviews → accept/revise

## Key Paths

- Project brief: `docs/project_brief.md`
- Board capabilities: `docs/board_capabilities_report.md`
- Audio checklist: `reports/phase1c_audio_verification_checklist.md`
- Platform decisions: `docs/platform_decisions.md`
- Orchestrator commands: `CLAUDE.md` (project root)
- Gain trace: `reports/phase1c_modelsim_gain_trace.md`
- Volume fix reports: `reports/phase1c_waveguide_gain_fix_v2_validation.md`
- Clean baseline: `reports/phase1c_clean_baseline_revalidation.md`
- Phase 1 exit: `reports/phase1_exit_assessment.md`
- Phase 2 proposal: `reports/phase2_first_step_proposal.md`
- Obsolete code: `obsolete/README.md`

## Blocked Feature Gates

Do not authorize without explicit decision + validation plan:
SDRAM, fourth voice, richer physics, exact-48k PLL, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, host-selected parameters, codec config RX, diagnostic clear RX, sample playback, UI/TFT/touch, CPU audio-loop expansion, non-prefix UART changes, register-map changes.

## Next Workstream

Phase 2 per `docs/project_brief.md` lines 124-138:
- Multi-string coupling (two- or three-string per note)
- Improved hammer dynamics and damper behavior
- Body/soundboard stage is DONE (body IIR filter, `ad94631`)

All remaining Phase 2 items are single-strike physics — no re-trigger needed. Propose one scoped improvement, create implementer task, validate, repeat.

## Recent Commits (most recent first)

```
c95f08a revert: remove 3-voice simultaneous and re-trigger diagnostic code
c5f0709 fix: add explicit ENABLE bit to voice trigger writes        [obsoleted]
e381f3c fix: add clear-then-set edge on voice trigger for re-trigger [obsoleted]
f2a938a feat: add 3-voice simultaneous trigger test mode             [obsoleted]
1242740 docs: update gain trace with ModelSim measured values
fe34677 docs: add waveguide pipeline gain trace (bit-accurate analysis)
c25d1a7 fix: back off excitation gain to >>> 1 (K=105 overshoot)     ← ACTIVE BASELINE
4c5ab03 fix: increase waveguide digital gain by 18 dB
c1c922c feat: add sample_gen test tone path for codec output isolation
ad94631 feat: add Phase 2 biquad IIR body/soundboard filter
647edee fix: increase audio output level to match reference volume
6149c59 fix: enable WM8978 speaker output driver (R49 SPKOUTP_EN=1)
```

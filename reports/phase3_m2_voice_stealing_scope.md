# Phase 3 M2 Voice Stealing Scope

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-7629ecaa`
Sources: Phase 3 architecture scope, M1 baseline acceptance

## Verdict

**GO-with-constraints — firmware-only voice stealing, 6 logical → 4 physical slots.**

No RTL changes required. Per-note state stays in firmware data structures. The 4 physical voice engines remain unchanged. The 9,938 LE / +2.948 ns M1 baseline is untouched.

## Design

### Round-Robin with LRU Stealing (Recommended)

Current M1: 4-way round-robin, 2 events per voice, G=8. Each `!N` UART command increments through voices 0→1→2→3→0.

M2: N logical slots (N=6 recommended) mapped to 4 physical voices. The round-robin index now runs 0..N-1 (0..5 for N=6). Each logical slot maps to a physical voice via a firmware lookup table. When all 4 physical slots are active and a new `!N` arrives, steal the oldest active physical voice and re-trigger it for the new note.

### Physical-Slot Contract

| Operation | Behavior |
| --- | --- |
| Assign | Find first idle physical voice, write enable+trigger to its control register |
| Steal | If all 4 voices active, pick the voice with oldest `last_trigger_time` (LRU), write reset+enable+trigger |
| Release | Voice auto-deactivates when quiet_count saturates (existing RTL behavior, no firmware action) |
| Fallback | If steal/drop counter exceeds threshold, fall back to 4-way round-robin (M1 baseline) |

### Firmware Data Structures

```c
#define M2_LOGICAL_SLOTS 6
#define M2_PHYSICAL_SLOTS 4

static uint32_t m2_logical_to_physical[M2_LOGICAL_SLOTS]; // slot → voice index (0xFF = idle)
static uint32_t m2_physical_age[M2_PHYSICAL_SLOTS];       // monotonic age counter per physical voice
static uint32_t m2_age_counter;                            // global age increment
static uint32_t m2_steal_count;                            // tracked by existing P/drop counter
```

### Steal Policy

On `!N` when all 4 physical voices active:
1. Scan `m2_physical_age[0..3]` for minimum age value
2. Reset (clear delay line) the oldest physical voice
3. Re-trigger with velocity/default waveform
4. Update age counter for the stolen voice
5. Increment steal counter → reported via existing `P` tag (or new multi-char steal tag)

### UART Impact

| Element | Impact |
| --- | --- |
| Frozen tags (I..X) | Unchanged |
| CC tag | Unchanged |
| V3/VT/VA/VV/S3 tags | Unchanged |
| G (event count) | Increases proportionally (G=12 for 6-slot × 2 events in no-command) |
| P (drop/steal count) | Reused for steal count; semantics documented |
| New tag (optional) | If steal/drop need separate tracking, append new multi-char tag after existing order |

Expected no-command: `G=12, Q=0, X=0, K=0, CC=0x003D0900, P=0`

### ROM/RAM Budget

| Resource | Current | M2 Estimate | Headroom |
| --- | --- | --- | --- |
| ROM words | 559/1024 (55%) | ~600/1024 (59%) | 424 words free |
| Data RAM | ~100 bytes used / 4096 | ~150 bytes (6×4-byte mappings + ages) | >3,900 bytes free |

ROM headroom: comfortable. Data RAM: negligible cost.

## Implementation Milestones

### M2a: Firmware-only 6→4 LRU Stealing

- Modify `phase0_main.c`: add slot mapping arrays, LRU steal logic, extend round-robin to N slots
- No RTL changes
- No SDC/constraint changes
- Firmware build + parser update only

**Gates**: Firmware builds clean, ROM < 700 words. No Quartus recompile needed (RTL unchanged). UART no-command profile shows G=12, K=0, P=0. Commanded profile shows correct steal behavior.

### M2b: Hardware Validation

- Program M1 SOF (RTL unchanged, only firmware MIF differs)
- Capture UART no-command + commanded
- Audio: K=0, waveform unchanged from M1 baseline

## Go/No-Go Gates

| Gate | Threshold |
| --- | --- |
| ROM words | ≤ 700 |
| Firmware build | Clean (0 errors) |
| Quartus compile | Unchanged from M1 (no RTL delta) |
| K=0 | No clipping |
| G=12 (N=6, no-command) | Correct event count |
| Existing UART tags | Unchanged |
| Steal behavior | Correct LRU selection under 6→4 load |

## Boundary Note

This design keeps per-note state in firmware (logical-to-physical mapping, age counters). No RTL per-note state. This stays within the blocked-feature boundary — the "per-note state" restriction applies to RTL/hardware state, not firmware data structures. If the orchestrator interprets "per-note state" as including firmware, reduce scope to simple 4-way RR with fixed slot assignment (N=4, no stealing).

## Next Implementer Task

"Implement Phase 3 M2a: firmware 6→4 LRU voice stealing" — modify `fw/phase0/phase0_main.c` only. Add slot mapping, LRU steal, N-slot round-robin. Build firmware, update parser smoke profiles for G=12. No RTL changes.

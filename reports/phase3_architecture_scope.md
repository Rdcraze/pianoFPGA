# Phase 3 Architecture Scope

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-62c542a0`
Sources: `docs/project_brief.md`, `reports/phase2_detuned_unison_impl.md`, `reports/phase2_next_physics_step_proposal.md`, `reports/phase2_hammer_excitation_hardware_smoke.md`, current RTL

## Phase 2 Closure

### Deployed and Hardware-Accepted

| Feature | Commit | LE Impact | Status |
| --- | --- | --- | --- |
| Body/soundboard IIR filter (2 biquads) | `ad94631` | ~200 LEs + 14 DSP | Hardware PASS, K=0 |
| Asymmetric hammer excitation ROM | `0ca2ec2` | 0 LEs (16 constants) | Hardware PASS, +11.7 dB peak |
| Body filter multicycle SDC | `d0aef18` | 0 LEs (SDC only) | Timing closed, +3.329 ns |
| CC counter measurement hook | `72e83d3` | 0 LEs (firmware only) | Hardware PASS |

### Closed / No-Go

| Candidate | Disposition | Reason |
| --- | --- | --- |
| True second-loop detuned unison | **No-go** (`e5f300d`) | FSM complexity explosion; ~100-line RTL diff touching all 16 FSM states; timing risk at 87% LE utilization |
| Damper behavior | **Deferred** | Per-note state border risk; requires note-off detection |
| Cross-coupling | **Deferred** | "Richer physics" border risk; coupling coefficients need per-note tuning |

### Phase 2 Verdict

Phase 2 is **complete**. The body filter and hammer excitation deliver clear perceptual improvement over Phase 1 ("string-like" → "piano-like" attack + body resonance). Remaining Phase 2 candidates are architecturally blocked or too risky at current resource utilization. Proceed to Phase 3.

## Phase 3 Objective

Per `docs/project_brief.md` lines 140-144: **"Prove a playable low-polyphony instrument architecture."**

The current system has 3 identical waveguide voices with firmware-owned round-robin scheduling. Phase 3 must answer: how many voices can EP4CE10 host, how are they scheduled, and what architecture changes are needed to get there?

## Baseline Resource Posture

| Resource | Used | Free | Per-Voice Cost (estimated) |
| --- | --- | --- | --- |
| LEs | 8,968 (87%) | 1,352 (13%) | ~700-900 LEs per voice (varies by synthesis) |
| M9Ks | 14 (30%) | 32 (70%) | ~3 M9Ks per voice (2 delay line + 1 body history) |
| DSP 9-bit | 6 (13%) | 40 (87%) | ~1-2 DSPs per voice (multiplier) |
| setup slack | +3.329 ns | — | ~0 ns per voice (pipelines are register-rich, parallel not serial) |

Current per-voice M9K breakdown:
- 2 M9Ks: delay_line (128×18, dual-port, Quartus packs 2 logical into 1 physical per 128×18; actually 2 physical per voice since dual-port needs separate read/write ports)
- 1 M9K: body_history (32×16)
- Total: ~3 M9Ks per voice instance × 3 voices = 9 M9Ks for voices

Remaining 5 M9Ks (14 - 9 = 5): boot ROM (4 M9Ks) + data RAM (1 M9K or part thereof).

## Voice Scaling Analysis

### Replication Limit

At ~700-900 LEs per voice and 1,352 LEs free: **at most 1 additional voice instance** (total: 4 voices) fits within the LE budget. Adding 1 voice:
- LEs: ~8,968 + 800 = 9,768 / 10,320 (95%)
- M9Ks: 14 + 3 = 17 / 46 (37%)
- DSPs: 6 + 2 = 8 / 46 (17%)

At 95% LE utilization, fitter congestion becomes the dominant risk. The body filter multicycle constraint is already at setup=4 (80 ns). A 4th voice instance is feasible but at the edge of routability.

Beyond 4 voices: **impossible without a different resource strategy** (see time-multiplexing below).

### Instance Replication (4 voices)

Simplest approach: instantiate a 4th `phase1_reduced_voice` in `phase0_audio_path.v`, add its mix contribution, update register map and diagnostics.

| Aspect | Assessment |
| --- | --- |
| RTL change | ~30 lines in audio_path (instantiation + mix), 0 lines in voice module |
| Firmware change | Register map expansion (0x84-0x98 for voice3 controls), round-robin update to 4-way |
| UART change | New voice3 diagnostic tags (3 new single-letter tags — but all 26 letters used) |
| LE cost | +700-900 (one full voice instance) |
| M9K cost | +3 (17/46) |
| Risk | Low — copy of proven voice module, no new RTL architecture |

### Time-Multiplexed Voice Engines (>4 voices)

For 6-8 voices: time-multiplex the existing voice compute pipeline. A single voice engine processes multiple voices sequentially within one sample_tick. At 50 MHz / 46.875 kHz = ~1066 cycles per sample, and ~16 cycles per voice per sample, the theoretical max is 1066/16 ≈ 66 voices. Practical max with state storage overhead: 8-12 voices.

| Aspect | Assessment |
| --- | --- |
| RTL change | Major — voice state RAM, sequencer, pipeline scheduling |
| LE cost | +500-1,000 (sequencer, state RAM MUX, additional pipeline registers) |
| M9K cost | ~6-8 additional M9Ks for per-voice state storage (delay line context) |
| Complexity | High — requires a voice dispatch sequencer, context save/restore per sample |
| Risk | Highest — new RTL architecture, simulation-intensive |
| Timing risk | Low if pipelining is register-rich; sample_tick has ample budget |

## Recommended Phase 3 Milestones

### Milestone 1: Safe 4-Voice Instance Replication

**Goal**: Add a 4th `phase1_reduced_voice` instance via module replication. Update firmware round-robin, register map (voice3 at 0x84-0x98), and UART telemetry tags.

**Why this first**: It's the lowest-risk Phase 3 entry point. The voice module is proven (3 instances, hardware-accepted). A 4th instance is a copy-paste with mix path extension. No new RTL architecture. No timing risk. The LE budget supports it at 95% utilization.

**Key design decisions**:
- Voice3 diagnostic tags: all 26 single letters are used. Options: (a) use multi-character tags like `CC` pattern (V3=voice3_status, etc.), or (b) version the UART format with a new prefix. Recommend multi-character tags per `CC` precedent.
- Register map: extend from 0x84 (VOICE3_CONTROL) through 0x98 (VOICE3_VALID_COUNT), following the existing voice1/voice2 pattern.
- Firmware round-robin: extend from 3-way to 4-way (`PHASE0_RR_EVENT_COUNT` 6→8, voice_index loop 0..3).

**Go/no-go gates**:
| Gate | Threshold |
| --- | --- |
| LE ≤ 9,800 | 95% utilization ceiling |
| M9K ≤ 20 | 43% utilization ceiling |
| setup slack ≥ +2.0 ns | 1.3 ns erosion budget |
| K=0 in both profiles | Mix clipping = fail |
| UART tags unchanged for voices 0-2 | Regression gate |
| Round-robin G=8 (4 voices × 2 events) | Correct schedule |
| ModelSim voice TB PASS | Golden sample check |

**Files touched**:
- `rtl/audio/phase0_audio_path.v` — voice3 instantiation, mix extension
- `fw/phase0/phase0_hw.h` — voice3 register map (0x84-0x98)
- `fw/phase0/phase0_main.c` — 4-way round-robin
- `scripts/phase1c_uart_telemetry.py` — voice3 tag parsing

**Resource estimate**:
| Resource | Current | After M1 | Delta |
| --- | --- | --- | --- |
| LEs | 8,968 | ~9,700 | +732 |
| M9Ks | 14 | 17 | +3 |
| DSP 9-bit | 6 | 8 | +2 |

### Milestone 2: Hardware Voice Stealing (6-voice logical, 4-voice physical)

**Goal**: Extend the firmware round-robin to support 6 logical voices mapped to 4 physical voice slots via a simple LRU or oldest-note stealing policy. This tests the "limited polyphony" objective without adding more RTL instances.

**Why second**: It validates the polyphony scheduling concept (Phase 3's core goal) without the resource cost of more instances. The firmware chooses which 4 of 6 logical voices to render at any given time.

**Risk**: Voice stealing logic touches per-note state (which voice is playing which "note"). This approaches the "per-note state" blocked-feature boundary. Mitigation: keep the stealing policy entirely in firmware, with hardware providing only the physical voice slots. No per-note state in RTL.

**Deferred**: This milestone should only proceed after Milestone 1 is hardware-validated and the orchestrator explicitly authorizes firmware-level note-to-voice mapping (which is distinct from per-note RTL state).

## Resource/Timing Risk Table

| Module/Section | Risk | Concern | Mitigation |
| --- | --- | --- | --- |
| `phase0_audio_path.v` mix path | Low | 4-voice sum extends existing 3-voice sum pattern | Same saturation logic, K=0 proven at 3 voices |
| `phase1_reduced_voice.v` (4th instance) | Low | Copy of proven module, no internal changes | Same constraints, same timing |
| Body filter path | Low | Filter sees 4-voice mix instead of 3-voice | Body filter is linear; +33% more input energy but still below saturation at current gains |
| Fitter congestion at 95% LE | Medium | Routability degrades above 90% LE utilization | M1 at 9,700 LEs is below 95% but tight; fall back if fitter fails |
| UART tag namespace | Low | All 26 letters used | Multi-char tags per CC pattern, already parser-supported via `[A-Z]+` regex |
| Firmware ROM headroom | Low | 4-way round-robin adds ~20 instructions | Current ROM at 539/1024 words; 20 more = 559, well under limit |
| Clock domain crossings | None | No new clocks | All audio in sys_clk_50m domain |

## Phase 2 Ideas: Final Disposition

| Idea | Status | Reasoning |
| --- | --- | --- |
| Body/soundboard IIR filter | **Deployed** | Hardware-accepted |
| Asymmetric hammer excitation | **Deployed** | Hardware-accepted, +11.7 dB |
| True second-loop detuned unison | **No-go** | FSM complexity, 87% LE risk |
| Damper behavior | **Deferred to Phase 3+** | Requires note-off semantics; revisit after voice scheduling exists |
| Cross-coupling | **Deferred to Phase 3+** | Requires per-note parameter sensitivity; revisit after polyphony architecture |
| Tap-based detune coloration | **Valid low-risk option** | Single read tap at rd_addr+1, mixed at low level, no M9K/FSM changes. 50 LEs only. Differs from "true second loop" — explicitly a comb/coloration effect, not physics coupling. Available if orchestrator wants one more Phase 2 coloration step before Phase 3. |

## Recommended Next Task

**Implement Phase 3 Milestone 1: 4-voice instance replication.**

- Implementer: instantiate 4th voice, extend mix, update firmware, update parser
- Verifier: compile Quartus, program FPGA, capture UART (4-voice round-robin), audio checklist
- Hard gates: LE ≤ 9,800, K=0, timing clean, UART regression-free

Phase 3 Milestone 2 (voice stealing) should be a separate scoping task after M1 is hardware-accepted.

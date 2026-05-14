# Phase 2 Next Physics Step Proposal

Date: 2026-05-14
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-69c29a72`
Sources: `docs/project_brief.md`, `reports/phase2_first_step_proposal.md`, `reports/phase2_body_filter_validation.md`, `reports/phase2_hammer_excitation_scope.md`, `reports/phase2_hammer_excitation_impl.md`, `reports/phase2_hammer_excitation_hardware_smoke.md`

## Current Phase 2 Status

| Feature | Status | Commit |
| --- | --- | --- |
| Body/soundboard IIR filter (2 biquads) | Hardware-accepted, K=0 | `ad94631` |
| Asymmetric hammer excitation ROM | Hardware-accepted, +11.7 dB peak | `ad9af18` |
| CC counter measurement hook | Hardware-accepted | `7ed2c62` |
| Body filter multicycle SDC | Timing closed, +3.329 ns | `d0aef18` |

### Hardware Headroom

| Resource | Used | Free | Note |
| --- | --- | --- | --- |
| LEs | 8,968 / 10,320 (87%) | 1,352 (13%) | Tight — need < 500 LE budget |
| M9Ks | 14 / 46 (30%) | 32 (70%) | Plenty |
| DSP 9-bit | 6 / 46 (13%) | 40 (87%) | Plenty |
| PLLs | 1 / 2 (50%) | 1 (50%) | — |
| setup slack (slow-85C) | +3.329 ns | — | Above +2.0 ns floor |
| hold slack (slow-85C) | +0.421 ns | — | — |

DSP count note: synthesis reports 26 DSP elements, but fitter summary reports DSP 9-bit = 6. The synthesis count includes DSP block internal elements (multipliers, adders within M9K/DSP blocks); the fitter count reports discrete DSP9 blocks. Use fitter DSP count (6) for headroom assessment.

## Candidate Comparison

### A: Fixed-per-voice detuned unison string (two-string approximation)

Add a second delay line per voice with a slightly different loop length (e.g., 107 vs 106), summing both outputs at equal mix. This models the two-string unison of a piano note without cross-coupling or per-note detune parameters.

| Aspect | Assessment |
| --- | --- |
| Physics model | Two detuned delay lines per voice, equal mix, shared excitation/damping |
| LE estimate | +200-400 (delay line MUX/address logic, extra sum path) |
| M9K estimate | +3 (one 128×18 per voice for second delay line, packed as M9K) |
| DSP estimate | +0 (existing multipliers reused) |
| Timing risk | Low — parallel delay line read adds one MUX level |
| Blocked features | Does not touch SDRAM, fourth voice, polyphony, scheduler, per-note state, parameter banks, UART, PLL, CPU path, or registers |
| Scope creep risk | Medium — "two strings per note" could expand to variable detune or cross-coupling |
| Perceptual gain | High — detuned unison is the single most recognizable piano characteristic missing from the current single-string model |

### B: Fixed two-string with cross-coupling

Same as A but adds a small energy transfer path (e.g., 5% coupling coefficient) between the two delay lines per voice. This models the energy exchange between coupled piano strings.

| Aspect | Assessment |
| --- | --- |
| LE estimate | +400-700 (coupling arithmetic adds 2 multipliers + mixing per voice) |
| M9K estimate | +3 (same as A) |
| DSP estimate | +3-6 (coupling multiply-accumulate per voice) |
| Timing risk | Medium — coupling path adds combinational depth between delay line reads |
| Blocked features | "Richer physics" border risk — cross-coupling parameters could become per-note |
| Perceptual gain | Medium-high over A — coupling adds the "beating" and chorus depth of real piano strings |

### C: Damper/termination behavior

Add a per-voice state that models the felt damper: when a voice has been ringing for a configurable duration, apply increased damping to simulate the damper engaging (or the note being released). The simplest form is a hardwired decay-rate modulation after a fixed quiet-count threshold.

| Aspect | Assessment |
| --- | --- |
| LE estimate | +100-200 (quiet-count comparator, decay modulation MUX) |
| M9K estimate | 0 (no new memories) |
| Timing risk | Low — only affects decay path which is already registered |
| Blocked features | "Per-note state" risk — damper timing interacts with note duration which is inherently per-note |
| Scope creep risk | High — damper logic naturally wants per-note duration, soft-pedal control, and note-off events |
| Perceptual gain | Medium — damper modeling adds note articulation but is less immediately audible than string detuning |

### D: Hammer excitation refinement (contact-duration parameter)

Add a second excitation ROM shape (e.g., softer hammer at lower velocity) selectable by a hardwired threshold. This is a modest extension of the existing hammer ROM change.

| Aspect | Assessment |
| --- | --- |
| LE estimate | +50-100 (ROM MUX, comparator) |
| M9K estimate | 0 |
| Timing risk | Zero — excitation path unchanged |
| Blocked features | None |
| Perceptual gain | Low-medium — velocity-dependent hammer shape is subtle vs existing single-ROM hammer |

### E: Stop Phase 2 — proceed to Phase 3 preparation

All safe single-strike Phase 2 improvements have been implemented. Remaining candidates (multi-string coupling, damper) are blocked or marginal under current headroom. Recommend moving to Phase 3 scoping.

## Recommendation

**Recommend Candidate A: Fixed-per-voice detuned unison string (two-string approximation).**

Rationale:

1. **Highest perceptual gain per LE**: A detuned second string per voice is the single most recognizable piano acoustic feature missing from the current model. Real piano notes above middle C have two strings per note; the detuned unison creates the characteristic "chorus" or "shimmer" that distinguishes a piano from a generic plucked string.

2. **Cleanly avoids blocked features**: The loop_len difference (107 vs 106) is hardwired as a localparam. No registers, no per-note state, no parameter banks, no UART changes. The implementation is: read two delay lines per sample, sum outputs, proceed through existing damping and body path.

3. **Fits within headroom**: +200-400 LEs (88-91% utilization), +3 M9Ks (17/46 = 37%), zero additional DSPs. Timing impact is minimal — one extra M9K read and one extra sum per voice per sample.

4. **Smallest code change**: The delay line read is already in the voice FSM state machine. Adding a second parallel read (at a different address) reuses the existing read/write infrastructure. The main changes are: second `rd_addr` (wr_ptr - loop_len_detune), second `dl_sample` register, and one extra addition in the injection path.

5. **Single-strike**: No sustained state, no re-trigger interaction, no per-note dependence. The detune effect is immediate on first strike.

6. **No cross-coupling risk**: Candidate B (cross-coupling) is deferred because:
   - Coupling coefficients are "richer physics" with per-note implications
   - Cross-coupling energy transfer can destabilize the waveguide if gains aren't carefully tuned
   - The LE cost of coupling arithmetic (+200-300 more than A) is risky at 87% utilization
   - A two-string detuned unison without coupling is a well-established simplification that captures ~80% of the perceptual benefit

## Rejected Candidates

| Candidate | Primary rejection reason |
| --- | --- |
| B: Cross-coupling | "Richer physics" border risk; +200-300 extra LEs tightens headroom |
| C: Damper | Per-note state border risk; scope creep toward note-off detection |
| D: Hammer refinement | Diminishing returns after just-completed asymmetric ROM |
| E: Stop Phase 2 | Premature — Candidate A is safe and has high perceptual value |

## Proposed Design

### RTL changes: `rtl/audio/phase1_reduced_voice.v`

1. Add second loop length parameter: `localparam DETUNE_LOOP_LEN = 7'd107` (vs main `loop_len` = 106)
2. Add second delay line read address: `wire [6:0] rd_addr_detune = wr_ptr - DETUNE_LOOP_LEN`
3. Add second delay line sample register: `reg signed [17:0] dl_sample_detune`
4. In `STATE_READ_DELAY`: read both `delay_line[rd_addr_q]` and `delay_line[rd_addr_detune]`
5. In `STATE_WRITE_SAMPLE`: inject `excite_sample` into both delay line positions (wr_ptr for main, same wr_ptr for detune — they share the write but read at different addresses)
6. Sum `dl_sample` and `dl_sample_detune` equally before the dispersion/damping path

### Signal flow

```
wr_ptr → delay_line[wr_ptr] ← excite_sample + fb_sample   (same write, both strings)
         delay_line[rd_addr]        → dl_sample            (main string, loop_len=106)
         delay_line[rd_addr_detune] → dl_sample_detune     (detune string, loop_len=107)
         (dl_sample + dl_sample_detune) >>> 1               (equal mix, -6dB to prevent clipping)
         → disp_sample → damping → body → output
```

The `>>> 1` on the sum preserves the existing K=0 margin — two equal-amplitude signals summed and halved produce the same amplitude as one signal alone. The detune creates phase cancellation and reinforcement that varies over time, creating the unison chorus effect without amplitude increase.

### No changes to
- `rtl/audio/phase0_audio_path.v` — voice instantiation unchanged
- `fw/phase0/phase0_main.c` — firmware unchanged
- `fw/phase0/phase0_hw.h` — no register changes
- `quartus/phase0/piano_phase0_top.sdc` — timing model unchanged
- Any constraints, project files, UART, or blocked domains

## Resource/Timing Risk

| Category | Estimate | Rationale |
| --- | --- | --- |
| LEs | +200-400 | Second rd_addr wire (7-bit subtract), second dl_sample register (18-bit), sum + shift logic, one extra M9K read port MUX per voice |
| M9Ks | +3 (17/46) | One 128×18 per voice for second delay line. Packed as separate M9K blocks |
| DSPs | 0 | Existing multiplier reused; sum is simple addition |
| PLLs | 0 | No clock changes |
| setup slack | -0.3 to -0.5 ns | One extra M9K read + one extra adder in the sample path. Register-rich pipeline absorbs this |
| ROM | 0 | No firmware changes |

### Go/no-go thresholds

| Gate | Threshold | Rationale |
| --- | --- | --- |
| LEs | ≤ 9,300 (90%) | 332 LE budget beyond current 8,968 |
| M9Ks | ≤ 20 (43%) | 6 M9K budget beyond current 14 |
| setup slack | ≥ +2.0 ns | 1.3 ns erosion budget |
| K=0 | Must be 0 | Clipping = fail |
| UART profile | Unchanged (G=6 Q=0 X=0 K=0 CC=0x003D0900) | Any deviation = fail |
| Harmonic quality | No harsh artifacts | Subjective listening + FFT |
| Blocked features | Zero touched | Any blocked feature = stop and revert |

## Simulation Plan

1. ModelSim `phase1_reduced_voice_tb`: run with `DETUNE_LOOP_LEN = 107` vs baseline `loop_len = 106`
2. Verify: `dl_sample_detune` valid, sum output has expected phase variation
3. Verify: `clip_seen = 0` for single voice at velocity=0x7FFF
4. Verify: fundamental pitch unchanged (same `loop_len = 106` for main string)
5. Regenerate golden samples via `+WRITE_GOLDEN` and confirm PASS

## Hardware Validation Plan

1. Quartus full compile: confirm LE ≤ 9,300, M9K ≤ 20, setup slack ≥ +2.0 ns, 0 errors
2. Program FPGA with new SOF, record checksum
3. UART no-command: G=6, Q=0, X=0, K=0, CC=0x003D0900
4. UART commanded (6×!N): G=12, Q=6, X=0, K=0
5. Audio capture: external mic recording, compare against hammer baseline
6. FFT: look for spectral broadening/spreading from detune (expected — two close frequencies beating)
7. A/B listening: compare against single-string hammer baseline for perceived "piano chorus"

## Rollback Criteria

Stop and revert if:
- LE > 9,300
- setup slack < +2.0 ns
- K > 0 in either profile
- Any UART tag value changes
- Audio becomes audibly harsh or unstable (uncontrolled beating)
- Waveform DC offset exceeds baseline
- Any blocked feature is touched

## Deferred

- **Cross-coupling** (Candidate B): The unison detune alone provides ~80% of the perceptual benefit. Cross-coupling can be added later as a Phase 2 follow-up if the detune proves safe and headroom allows.
- **Damper behavior** (Candidate C): Requires a separate scoping task to define the minimum viable damper model that stays within blocked-feature boundaries.
- **Three-string coupling**: Piano treble notes use three strings. Deferred until two-string detune is validated.

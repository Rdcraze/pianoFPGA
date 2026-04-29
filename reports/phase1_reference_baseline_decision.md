# Phase 1 Reference Baseline Decision

Date: `2026-04-24`  
Task: `task-6d508eea`  
Role: orchestrator

## Decision

Freeze the current Phase 1 reduced-voice build as the project reference baseline.

Verdict: continue, but in controlled-scaling mode. Phase 1 proves that the EP4CE10 platform can host the minimal hybrid architecture: a small RV32I control plane plus a hardware-owned reduced physical-model voice through the WM8978 path. It does not prove there is room for careless feature growth.

No Phase 2 feature expansion should start until the next measurement/observability task is complete.

## Baseline Record

Reference evidence:

- Implementation: `reports/phase1_reduced_voice_impl_report.md`
- Independent validation: `reports/phase1_reduced_voice_validation.md`
- Model contract: `reports/phase1_reduced_voice_model_spec.md`
- Prior Phase 0 board-I/O baseline: `reports/phase0_board_io_timing_validation.md`

Build identity:

- Programmed SOF checksum: `0x004C7C05`
- SOF SHA-256: `3C2D80FCF5CE4579C2E9AB9F3EC1922BEC0BB3306D30EC0907E64810C4D55C62`
- Firmware, ModelSim voice/top/NACK tests, Quartus full compile, TimeQuest, UART, and external audio capture all passed verifier review.

Clock and sample-rate contract:

- Fabric clock: `50 MHz`
- Audio master clock: `12.000 MHz`
- Codec direct-MCLK path remains in use.
- Nominal sample rate: `46.875 kHz`
- Audio bit clock: `1.500 MHz`
- Fabric cycles per sample: `50,000,000 / 46,875 = 1066.667`

Soft-core configuration:

- Minimal in-repo multi-cycle RV32I control plane.
- On-chip ROM/RAM only for this baseline.
- No interrupts, caches, SDRAM boot dependency, RTOS, or broad bus fabric.
- CPU role is limited to codec/control setup, parameter writes, status/UART reporting, and one voice trigger.
- CPU is not in the per-sample synthesis loop.

Current voice model:

- One fixed A4 reduced digital-waveguide/Karplus-Strong-family voice.
- `128` entry Q1.17 delay line, synchronous M9K-backed.
- Default integer loop length: `106`.
- First-order allpass coefficient default: `9952`.
- Damping mix default: `16384`.
- Loop gain default: `32640`.
- Hammer excitation: 16-sample Q1.15 half-sine burst, default velocity `0x4000`.
- Optional small body-coloration path is present.
- Saturating Q1.17 feedback/write path and Q1.15 output conversion.
- Sticky clip and peak status exist in RTL/status registers.

Register map:

- Phase 0 offsets through `0x18` are preserved.
- Phase 1 voice registers are `0x20..0x3C`:
  - `VOICE_CONTROL`
  - `VOICE_STATUS`
  - `VOICE_VELOCITY`
  - `VOICE_LOOP_LEN`
  - `VOICE_LOOP_GAIN`
  - `VOICE_DAMP_MIX`
  - `VOICE_DISP_COEFF`
  - `VOICE_BODY_MIX`

Observed latency/audio behavior:

- Standalone voice TB first nonzero sample: `106`.
- Standalone voice TB frequency: `438.084112 Hz`.
- Hardware run-2 fundamental: `437.10 Hz` mono, `436.28 Hz` left, `439.75 Hz` right.
- Hardware attack-to-peak: about `10 ms`.
- Hardware decay: about `-21 dB` by `1-2 s`.
- Hardware clipping: zero exact rail samples and zero near-full-scale fraction in the accepted capture.

## Resource And Timing Baseline

Resource comparison against the final Phase 0 board-I/O-timed baseline:

| Resource | Phase 0 | Phase 1 | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | `4796 / 10320` | `6308 / 10320` | `+1512` |
| Registers | `1520` | `2394` | `+874` |
| Memory bits | `262144 / 423936` | `266752 / 423936` | `+4608` |
| M9Ks | `32 / 46` | `33 / 46` | `+1` |
| DSP9 elements | `2 / 46` | `2 / 46` | `0` |
| PLLs | `1 / 2` | `1 / 2` | `0` |

Timing:

- TimeQuest is fully constrained for setup and hold under the current modeled scope.
- Slow-85C `sys_clk_50m` setup slack: `+1.234 ns`, TNS `0.000 ns`.
- Slow-85C `sys_clk_50m` hold slack: `+0.429 ns`, TNS `0.000 ns`.
- Reported `sys_clk_50m` Fmax: `53.29 MHz`.
- Worst observed setup category remains RV32I/writeback, not the voice datapath.
- Voice datapath representative setup slack: `+4.757 ns`.
- Delay-line RAM representative setup slack: `+6.606 ns`.

Resource interpretation:

- Logic and on-chip RAM are the binding resources.
- DSP capacity remains mostly available.
- The voice multiplier maps to embedded DSP, not LUT logic.
- The delay line must remain synchronous RAM/M9K-backed. The async-read delay-line implementation fit at `8889` LEs and is the known bad scaling pattern.

## Controlled-Scaling Policy

Effective immediately:

- Treat this build as the rollback baseline.
- Do not combine feature expansion with optimization.
- Do not start polyphony, richer physics, UI, SDRAM, sample playback, exact-48-kHz clocking, or larger CPU work from this baseline.
- Scale one dimension at a time, with timing/resource/audio evidence after each change.

Preferred sequence:

1. Improve runtime observability and cycle/accounting instrumentation.
2. Revalidate the frozen single-voice reference with those hooks.
3. Only then consider one controlled experiment: either timing/packing optimization, a second voice, or a slightly richer kernel.

## Next Task Direction

Create an implementer task for Phase 1 measurement hooks, not a feature task.

Required direction:

- Expose `VOICE_STATUS` or equivalent peak/clip/active state over UART or a clearly documented debug read path.
- Add or expose counters sufficient to reason about runtime behavior before scaling:
  - sample/frame counter
  - trigger/note-event counter
  - voice active/sample-valid counter
  - clip/saturation counter or sticky plus clear path
  - optional peak meter readout
  - optional bounded voice-step/busy-cycle counter if the current scheduler exposes a natural boundary
- Preserve the current audio model, sample rate, timing model, and register compatibility unless the task explicitly documents a minimal diagnostic-only register extension.
- Re-run firmware, ModelSim, Quartus/TimeQuest, UART, and hardware audio smoke.

Create a dependent verifier task to confirm that the added observability does not regress timing, resources, UART, or audio behavior.

## Risk Register

- Routing/timing headroom is now the primary go/no-go metric, not raw fit percentage.
- Logic growth can become nonlinear through routing congestion, fanout, and BRAM packing inefficiency.
- On-chip memory is already around two thirds used; every future delay line, table, or voice state allocation needs an explicit memory plan.
- UART diagnostics do not yet report full `VOICE_STATUS`, so current field diagnosis is weaker than simulation diagnosis.
- Board-I/O timing still inherits Phase 0 caveats for `audio_mclk`, I2C, UART, and async reset exclusions where local collateral lacks board-level timing apertures.
- The current audio evidence is through analog capture, so exact amplitude and harmonic balance include codec/cabling/input effects; frequency, decay, and clipping conclusions are strong enough for Phase 1 freeze.

## Bottom Line

Phase 1 V1 feasibility is confirmed. The correct next move is disciplined measurement, not additional musical features.

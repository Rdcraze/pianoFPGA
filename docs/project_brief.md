# Project Brief

Status: draft baseline on 2026-04-20

## Goal

Build a realistic first physics-based piano prototype on the EP4CE10 board, prioritizing a path that is actually implementable on this hardware over a maximally complete piano simulation.

The original intended architecture was a split system with a small RISC-V soft core for control-plane duties and custom RTL/DSP for the audio path. As of Phase 5 M0 (2026-05-24), the RISC-V SoC + firmware MMIO + register-file control stack has been retired and replaced with a fixed-function RTL controller (`rtl/control/phase0_fixed_control.v`). The legacy CPU/firmware code is archived under `obsolete/riscv_control/` for reference. The live architecture is now:

- a small fixed-function RTL controller for control-plane duties,
- custom RTL/DSP blocks for the hard real-time sound-generation path.

UART command/telemetry support is intentionally deferred in M0 (`uart1_tx` idle, `uart1_rx` unconsumed). A later Phase 5 milestone may reintroduce a tiny RTL UART telemetry transmitter and command parser without re-introducing a CPU. See `reports/phase5_m0_fixed_control_flattening.md` for the architecture details and resource impact.

## Candidate Implementation Families

### 1. Digital waveguide piano

- Best fit for efficient string modeling.
- Maps naturally to delay lines plus small filter blocks.
- Historically the dominant route for real-time piano physical models.
- Best candidate for a first FPGA implementation on EP4CE10.

### 2. Modal synthesis piano

- Strong match for nonlinear and longitudinal effects.
- Naturally parallel and physically elegant.
- More arithmetic-heavy because the string is represented as resonator banks instead of a compact delay-line structure.
- Better as a later hybrid or reduced add-on than as phase one.

### 3. Finite-difference / fuller PDE simulation

- Best suited to complex structures such as the soundboard and higher-fidelity distributed physics.
- Computationally the heaviest option.
- Appropriate for offline study or later reduced experiments, not for the first board milestone.

## Paper-Backed Feasibility Summary

- Bank et al. (2003) frame piano physical modeling as a tradeoff between efficiency and accuracy across hammer, string, and soundboard models, which is the right lens for this FPGA project.
- Bensa et al. (2003) show that the string model can be expressed in a way that supports stable finite-difference schemes and also maps to a digital-waveguide realization. That matters because it means the efficient waveguide route is still grounded in the same physical string model family.
- Bank, Zambon, and Fontana (2010) present a real-time modal piano and explicitly discuss computational complexity. They note finite-difference methods are especially suited to complex structures like the soundboard, but for simple linear systems the closed-form solution leads to much lower complexity. That makes modal and finite-difference methods useful references, but not the smallest first step for EP4CE10.
- The same modal paper is valuable as a later target because it gives a path for adding richer longitudinal and soundboard behavior after the board has a working reduced core.

## Board-Reality Summary

- The board already gives us a workable audio path through the on-board `WM8978`, a `50 MHz` clock, USB-UART debug, and `32 MiB` SDRAM.
- The FPGA itself is small: about `10k` LEs, `23` DSP blocks, `414 Kb` embedded memory, `2` PLLs.
- The vendor `audio_sd_play` example uses only about `7%` of LEs, `8%` of memory bits, `0` DSP blocks, and `1` PLL. That is good news: codec bring-up is cheap.
- Manual-reader's example report shows that the bundled design is a useful WM8978 bring-up reference: codec-master `16-bit` I2S-style playback, on-chip FIFO buffering, and known-good pin use.
- The same example ships with negative timing slack, so it is not a safe copy-paste base. The project must rebuild a smaller and cleaner audio baseline instead of inheriting its clock-domain issues.
- Manual-reader's display/touch report shows the board has a real `16-bit` RGB565 TFT path with multiple working examples, but the external `CTP_*` touchscreen path is not proven by the bundled examples.
- The board docs already indicate LCD/touch sharing on the expansion/header side, so a screen UI is feasible but must be planned as a later integration step with explicit pin-budget discipline.
- The board-realistic first UI target is `480x272` display-first, using keys, UART, or the on-board capacitive touch pads before attempting external touchscreen bring-up.

## Chosen Initial Direction

Start with a reduced digital-waveguide piano voice plus a lightweight hammer/body model, implemented as custom RTL/DSP blocks under a small RISC-V control plane.

Why this fits EP4CE10:

- It is the most efficient paper-backed family for the string core.
- It avoids the arithmetic explosion of a full modal bank or full finite-difference mesh.
- It lets the project exploit the board's strongest proven assets first: the codec path, modest logic budget, and enough control-clock headroom for scheduled fixed-point processing.
- It gives the system a clean place to put non-audio-rate concerns such as codec initialization, debug, note events, parameter updates, and later MIDI or UI handling without polluting the hard real-time DSP path.
- It preserves a clean upgrade path: later phases can add hybrid modal or richer body modeling once the board baseline is stable.

## Control And Data-Path Split

RISC-V soft core responsibilities:

- codec bring-up and peripheral register programming,
- UART and later MIDI or UI command handling,
- parameter management and preset/state control,
- note-event dispatch and, later, voice allocation policy,
- diagnostics and debug observability.

Custom RTL/DSP responsibilities:

- audio-rate oscillator or excitation generation,
- digital-waveguide state update,
- hammer, damper, coupling, and body filters,
- sample mixing, saturation, and codec-facing audio data flow,
- low-latency buffering and clock-domain-safe audio streaming.

Constraint:

- The CPU must not sit in the per-sample synthesis loop. If a function must run every sample or every BCLK edge, it belongs in dedicated RTL/DSP.

## Phase-By-Phase Plan

### Phase 0: Board-Clean Audio Baseline

Objective:
Bring up a timing-clean audio path through the on-board WM8978 with no SD-card dependency, using the RISC-V core as the control plane.

Scope:
- Reuse the known-good pinout from the bundled example.
- Keep only codec configuration, clocks, a tiny RISC-V subsystem, and a minimal RTL sample source.
- Move codec programming and debug control onto the soft core.
- Add UART and LED observability.

Exit criteria:
- The soft core boots and can configure the codec path deterministically.
- Deterministic tone, impulse, or ramp audible from the board.
- Clean timing on the chosen baseline clocks.
- A small top-level that is understandable enough to extend.

### Phase 1: Single Reduced Piano Voice

Objective:
Produce one convincing struck-string voice in fixed-point.

Scope:
- One note at a fixed pitch.
- Hammer excitation plus one reduced digital-waveguide string in dedicated RTL/DSP.
- Simple decay and dispersion handling.
- RISC-V-triggered note and parameter control through registers or a small command interface.
- No pedal, no multi-string coupling, no polyphony.

Exit criteria:
- Audible piano-like decay, not just a generic beep.
- Stable fixed-point behavior with no obvious limit cycles or clipping in normal use.
- Resource and timing report that leaves clear headroom for the next phase, including soft-core overhead.

### Phase 2: Piano-Specific Behavior

Objective:
Move from "string-like" to "piano-like."

Scope:
- Add two- or three-string coupling for selected notes, or a controlled approximation of it.
- Improve hammer dynamics and damper behavior.
- Add a lightweight soundboard/body stage, likely low-order IIR/FDN or another compact filter structure rather than large convolution.
- Keep orchestration and parameter updates on the CPU side while retaining an RTL-only sample path.

Exit criteria:
- Clear perceptual improvement over Phase 1.
- Still timing-clean without requiring SDRAM.
- Architecture remains schedulable at the board clock rate.

### Phase 3: Limited Polyphony And Voice Scheduling

Objective:
Prove a playable low-polyphony instrument architecture.

Scope:
- Shared arithmetic engine or otherwise scheduled core.
- Small number of simultaneous voices.
- Voice allocation, note on/off handling, and basic velocity mapping, with policy in RISC-V and voice engines in hardware.

Exit criteria:
- Multiple concurrent notes with acceptable artifacts.
- Measured resource usage consistent with later expansion.
- Debug visibility for dropped voices, overload, and clipping.

### Phase 4: Memory And Body-Model Expansion

Objective:
Use external memory only where it buys clear value.

Scope:
- SDRAM for longer delay/state buffers, richer body models, or tables that no longer fit comfortably on-chip.
- Optional hybridization with modal submodels for longitudinal or body behavior.
- CPU-managed table or buffer loading only if the control complexity remains clearly separated from the audio datapath.

Exit criteria:
- External-memory controller complexity is justified by audible gain.
- The added realism is measurable and not just architectural novelty.

### Phase 5: Display-First 12-Key UI

Objective:
Add a usable screen front end without compromising the audio engine.

Scope:
- A `480x272` TFT path driven within the board's real pin and PLL budget.
- A visible `12`-key piano interface on screen.
- UI ownership on the RISC-V side: key events, patch selection, status display, and simple configuration pages.
- Initial interaction through proven inputs: keys, UART, or the on-board capacitive touch pads.
- Keep graphics intentionally simple; the display is for control and playability, not for a heavyweight compositor.

Exit criteria:
- The user can operate a visible `12`-key on-screen keyboard through the proven non-CTP control path.
- UI activity does not break audio timing or destabilize the RTL audio engine.
- Display/touch pin use and peripheral conflicts are explicitly documented.

### Phase 6: External Touchscreen Bring-Up

Objective:
Upgrade the display-first UI into an actual screen-controlled piano, if the attached TFT module's touch controller is proven on hardware.

Scope:
- Bring up the external `CTP_RST`, `CTP_INT`, `CTP_SDA`, and `CTP_SCL` path.
- Identify the actual TFT module's touch controller behavior and map touch regions to piano keys and coarse controls.
- Keep touchscreen handling on the RISC-V side while preserving a hardware-owned audio path.

Exit criteria:
- The user can trigger the `12` on-screen piano keys through the screen-touch path itself.
- Touchscreen traffic and UI updates do not destabilize audio timing.
- The external touch path is documented as proven on the actual hardware setup.

### Phase 7: Instrument Completion

Objective:
Turn the prototype into a coherent board-level instrument.

Scope:
- Broader note coverage.
- More consistent voicing across range.
- Better control mapping and test/demo flows beyond the initial `12`-key UI.

Exit criteria:
- Repeatable demo build.
- Stable board operation.
- Clear list of what remains impossible on EP4CE10 without changing the architecture or hardware target.

## What We Are Not Doing First

- No full-concert-grand simulation.
- No giant modal soundboard.
- No full finite-difference soundboard mesh.
- No dependence on sample playback to hide a weak physical model.
- No early SDRAM complexity unless Phase 1 and Phase 2 prove it is needed.
- No software sample synthesis on the RISC-V core.
- No heavyweight software stack whose control overhead crowds out the instrument core.
- No early display/touch integration before the audio/control baseline is proven.
- No assumption that the external `CTP_*` touchscreen path works until it is explicitly proven on hardware.

## Near-Term Risks

- Clock-domain handling around codec-generated clocks is the first real board risk.
- Fixed-point scaling and saturation strategy will decide whether the reduced model sounds controlled or broken.
- Soft-core feature creep is a real risk; the CPU should stay a control processor, not become the instrument.
- Polyphony ambition can grow faster than the device budget; it needs to be earned phase by phase, not assumed.
- CPU/audio-datapath register boundaries and CDC need to stay simple enough to verify.
- Display/touch integration can quietly consume pins, clocks, and verification effort; it needs to be treated as a scoped subsystem, not a side quest.
- The external touchscreen path is currently only document-backed, not example-backed, so it is a distinct hardware risk.

## Sources

- Board constraints: `docs/board_capabilities_report.md`
- Example-board evidence:
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/audio_sd_play.qsf`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/output_files/audio_sd_play.fit.summary`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/quartus_prj/output_files/audio_sd_play.sta.summary`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/audio_sd_play.v`
  - `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/59_audio_sd_play/rtl/sd_play_ctrl.v`
  - `docs/manual_audio_example_report.md`
  - `docs/display_touch_report.md`
- Paper sources:
  - Bank et al., "Physically Informed Signal Processing Methods for Piano Sound Synthesis: A Research Overview" (2003)
    https://doi.org/10.1155/S1110865703304093
  - Bensa et al., "The simulation of piano string vibration: From physical models to finite difference schemes and digital waveguides" (2003)
    https://doi.org/10.1121/1.1587146
  - Bank, Zambon, and Fontana, "A Modal-Based Real-Time Piano Synthesizer" (2010)
    https://doi.org/10.1109/TASL.2010.2040524
- FPGA capacity:
  - Intel `Cyclone IV EP4CE10 FPGA`
    https://www.intel.com/content/www/us/en/products/sku/210464/cyclone-iv-ep4ce10-fpga/specifications.html

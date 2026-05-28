# Phase 6 M6.5-DAMP Raised-Cap Acceptance

Date: 2026-05-28
Task: `task-917a1697`
Parent: `0ad5a10` (M6.5-DAMP NO-GO containment)

## TL;DR

**PASS under the raised +150 LE cap.**

RTL unchanged from the verified NO-GO commit `b43f17d` /
containment `0ad5a10`. Orchestrator raised the LE hard cap
to +150 (max 5,252 LE). Current RTL at 5,237 LE fits with
+15 LE margin. This commit adds only the deferred host
sweep helper and this acceptance report.

## Files

- `scripts/phase6_m6_5_damp_sweep.py` (new, ASCII-only)
- `reports/phase6_m6_5_damp_runtime_acceptance_impl.md` (this)

No RTL changes. Quartus result cited from verifier
task-e3edf103 independent compile: LE 5,237, setup +5.213 ns,
hold clean, all TNS 0, M9K 5, DSP9 26, PLL 1, 0 errors,
16 warnings.

## Host helper

`scripts/phase6_m6_5_damp_sweep.py` --self-check PASS
(PHASE6_M6_5_DAMP_SWEEP_PASS cells=14). 20+ assertions
covering grid size, !D format, range 0x0000..0x7FFF, CRLF
framing, sidecar round-trip, command counts (38 valid with
isolation), pacing, and parse helpers.

Default grid: `[0x0000, 0x0800, 0x1000, 0x2000, 0x4000,
0x6000, 0x7FFF]` x A4/C5, velocity 0x7FFF, isolation ON.

Semantic direction: higher damp_mix = longer sustain (more
lp_state memory weight in the loop LPF), lower = shorter
sustain (faster HF decay).

## Verifier handoff

1. Program the M6.5-DAMP SOF (from commit `b43f17d` or
   `0ad5a10` Quartus output).
2. Run `scripts/phase6_m6_5_damp_sweep.py --run --port COM5`.
3. Capture analog audio over the full ~85 s session.
4. Compute tail-RMS slope (dB/s) in the 100ms..1.5s window
   per cell in the 1-3 kHz band.
5. Acceptance: absolute decay-rate swing >= +5 dB/s between
   the lowest and highest damp_mix cells on at least one
   pitch. PASS >= +5 dB/s, CONDITIONAL_PASS >= +2 dB/s.
6. P5M2 Q advances by exactly 38; X stable.

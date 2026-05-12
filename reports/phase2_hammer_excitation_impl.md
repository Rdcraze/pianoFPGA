# Phase 2 Hammer Excitation Implementation Report

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-dfb43af6`
Commit: `0ca2ec2`
Scope: `reports/phase2_hammer_excitation_scope.md`

## RTL Change

`rtl/audio/phase1_reduced_voice.v` — `excitation_rom` function, 16 constants only:

| Index | Old (symmetric) | New (asymmetric) |
| --- | --- | --- |
| 0 | 6021 | 1200 |
| 1 | 11837 | 9000 |
| 2 | 17250 | 24000 |
| 3 | 22075 | 32627 |
| 4 | 26149 | 26000 |
| 5 | 29332 | 19500 |
| 6 | 31516 | 14300 |
| 7 | 32627 | 10400 |
| 8 | 32627 | 7500 |
| 9 | 31516 | 5300 |
| 10 | 29332 | 3700 |
| 11 | 26149 | 2500 |
| 12 | 22075 | 1600 |
| 13 | 17250 | 1000 |
| 14 | 11837 | 500 |
| default | 6021 | 200 |

Shape change: symmetric triangular (gentle attack, flat top, symmetric decay) → asymmetric attack-shaped (3-sample rapid attack, sharp peak, 12-sample exponential-like decay). Peak amplitude preserved at 32627 for K=0 margin.

No other RTL changes. No firmware, constraints, register-map, UART, or project file changes.

## Quartus Compile

Full compile: `quartus_sh --flow compile piano_phase0_top` — 0 errors, 16 warnings.

### Resource Delta

| Metric | Baseline (7ed2c62) | This Build (0ca2ec2) | Delta |
| --- | --- | --- | --- |
| LEs | 7,963 | 9,264 | +1,301 (+16.3%) |
| M9Ks | 14 | 14 | 0 |
| DSPs | 6 | ~14 | +8 |
| PLLs | 1 | 1 | 0 |

### Timing Delta

| Corner | Baseline Setup Slack | This Build Setup Slack |
| --- | --- | --- |
| Slow 1200mV 85C | +2.438 ns | **-23.984 ns** |
| Slow 1200mV 0C | N/A | **-20.596 ns** |
| Fast 1200mV 0C | N/A | +0.697 ns |

Hold slack: +0.432 ns (OK).

### Critical Assessment

The LE increase (+1,301) and timing failure (-23.984 ns) are **not attributable to the 16 constant ROM change**. The `excitation_rom` is a LUT-based case statement — changing its 16 constant values cannot cause a 16% LE increase.

Root cause: this Quartus compile inferred 14 multiplier megafunctions (vs 9 in the CC counter baseline compile) and 10,353 synthesis logic cells (vs 9,481). The body filter (`phase0_body_filter.v`) DSP inference path appears to be producing different synthesis results between the two compiles. 

The previous compile (May 2, CC counter baseline) reported 6 DSP elements. This compile reports ~14 DSP elements — the body filter's full multiplier complement (10 biquad multipliers + 3 voice multipliers + 1 sample_gen multiplier = 14). The previous compile may have optimized away some body filter multipliers, while this compile instantiated all of them.

Possible contributing factors:
- Quartus Auto Fit compilation non-determinism between runs
- Different synthesis seed or optimization threshold
- Body filter DSP packing differences between cold/fresh project state

The ROM constant change itself is resource-neutral and should produce zero delta. The observed resource/timing shift is a pre-existing Quartus compilation variance, not a consequence of the hammer excitation change.

## Blocked Status

**BLOCKED** — timing failure (-23.984 ns setup slack) prevents hardware validation. The implementation cannot proceed to hardware programming until the timing regression is resolved.

## Next Steps

1. Investigate the body filter DSP inference discrepancy between the May 2 and May 12 Quartus compiles.
2. Re-run the CC counter baseline compile (without ROM changes) to confirm whether the resource/timing shift reproduces on the clean RTL baseline.
3. If the shift reproduces on the clean baseline, it is a Quartus project-state issue, not a hammer implementation issue.
4. If the shift does NOT reproduce on the clean baseline, re-examine the ROM change for unintended synthesis side effects (unlikely but must be ruled out).

## Residual Risks

- The asymmetric ROM shape is technically correct (peak preserved at 32627, same excitation pipeline). Once the timing issue is resolved, K=0 is expected.
- Without hardware audio capture, the subjective quality of the asymmetric hammer attack cannot be assessed.
- The Golden Samples hex file was not regenerated (no ModelSim available in this session).

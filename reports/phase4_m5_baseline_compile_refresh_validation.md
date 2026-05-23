# Phase 4 M5 Baseline Compile Refresh Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-347d3d89` (depends on implementer `task-54da0900`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `eafb6d3`

## Verdict

**PASS.** Local Quartus output files have been refreshed against current source and now reflect the accepted post-M2/M3/M4/M5 baseline exactly. Commit `eafb6d3` is report-only and adds `reports/phase4_m5_baseline_compile_refresh.md` with no source change. The verifier-flagged stale `output_files/` issue from `task-07c78294` is resolved.

## Scope check

`git show --stat eafb6d3`:
- `reports/phase4_m5_baseline_compile_refresh.md` (+179 lines, new)

`git diff c00ee38 eafb6d3 -- ':!reports'` returns no diff, confirming no RTL, firmware, host tools, SDC, constraints, QSF/project files, PLL, generated outputs in tracked paths, or unrelated docs were modified. PASS.

(Untracked `quartus/phase0/output_files/` updates are local artifacts, as the report explicitly notes; they are not in the index.)

## ASCII check

`reports/phase4_m5_baseline_compile_refresh.md`: 0 non-ASCII bytes (size 7,913). PASS.

## Output-file metric check

Read directly from `quartus/phase0/output_files/piano_phase0_top.fit.summary` (Last Write Time Sat May 23 2026 22:36:40, post-revert recompile):

| Metric | Read at HEAD | Accepted baseline | Match |
| --- | ---: | ---: | --- |
| Fitter Status | Successful | Successful | yes |
| Total logic elements | 9,992 / 10,320 (97%) | 9,992 / 10,320 (97%) | yes |
| Total combinational functions | 9,417 / 10,320 (91%) | 9,417 / 10,320 (91%) | yes |
| Dedicated logic registers | 4,233 / 10,320 (41%) | 4,233 / 10,320 (41%) | yes |
| Total memory bits | 86,016 / 423,936 (20%) | 86,016 | yes |
| M9K equivalent | 16 (from 86,016 bits / 5,376 bits/M9K) | 16 | yes |
| Embedded Multiplier 9-bit elements | 28 / 46 (61%) | 28 / 46 | yes |
| Total PLLs | 1 / 2 (50%) | 1 / 2 | yes |

Read directly from `quartus/phase0/output_files/piano_phase0_top.sta.summary` (Last Write Time Sat May 23 2026 22:36:49):

| Metric | Read at HEAD | Accepted baseline | Match |
| --- | ---: | ---: | --- |
| Slow 1200mV 85C Setup `sys_clk_50m` slack | +2.914 ns | +2.914 ns | yes |
| Slow 1200mV 85C Setup `sys_clk_50m` TNS | 0.000 | 0.000 | yes |
| Slow 1200mV 85C Hold `sys_clk_50m` slack | +0.405 ns | +0.405 ns | yes |
| Slow 1200mV 85C Hold `sys_clk_50m` TNS | 0.000 | 0.000 | yes |

Bit-exact match to the M2/M3/M4 accepted baseline numbers. The output files now correctly reflect HEAD source rather than the rejected M5 gate experiment. PASS.

## Firmware / ROM

`fw/phase0/build/phase0.bin`: 3,724 bytes = **931 words**. Matches accepted baseline. PASS.

A fresh firmware rebuild was not run because firmware source is unchanged at HEAD; the existing artifact is authoritative.

## Source-equivalence check

No tracked source changed between `c00ee38` (post-M5 NO-GO accepted baseline) and `eafb6d3` (this refresh commit). The four physical voice instances and the `use_sample_gen` mux remain in `rtl/audio/phase0_audio_path.v` exactly as accepted. PASS.

## Report-hygiene assessment

The implementer report has the line:

```
HEAD after:  (this commit)
```

This is a placeholder rather than a blank or stale hash. The commit it ships in is `eafb6d3` (recoverable from `git log` ancestry on this branch), and `HEAD before: c00ee38` is correct. Treating this as a non-blocking documentation hygiene note: future implementer reports may want to substitute the actual commit hash after `git commit` produces it (or simply omit the `HEAD after` line, since `git log` is authoritative). Not a blocker for acceptance.

## Hardware skip

Hardware UART/audio not run. Justification: commit `eafb6d3` is report-only; no RTL or firmware source change relative to accepted baseline; no SOF regeneration is needed. This is a build-evidence refresh, not a behavior change. PASS by inertia.

## Final verdict

**PASS.** The local `quartus/phase0/output_files/` set now reproducibly reflects the accepted post-M5 baseline (LE 9,992, M9K 16, DSP9 28, +2.914 ns setup, +0.405 ns hold, TNS 0, 0 errors, 16 warnings, ROM 931). The stale-output-files concern from `task-07c78294` is resolved. Future verifier runs that need authoritative accepted-baseline numbers from `output_files/` can read them directly without rerunning a full compile, until the next source change forces a refresh.

One non-blocking note: implementer's `HEAD after: (this commit)` placeholder is fine for now; recording for future report hygiene.

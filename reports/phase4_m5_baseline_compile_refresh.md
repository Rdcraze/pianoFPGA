# Phase 4 M5 Baseline Compile Refresh

Date: 2026-05-23
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-54da0900`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD before: `c00ee38`
HEAD after:  (this commit)

## TL;DR

**PASS.** A full Quartus 13.0.1 compile against the unchanged HEAD
source restored `quartus/phase0/output_files/piano_phase0_top.fit.summary`
and `.sta.summary` to the accepted baseline numbers. The local artifact
mismatch flagged by the M5 verifier (`task-07c78294`) is resolved. No
RTL, firmware, host-tool, SDC, QSF, PLL, pin, constraint, or stale
untracked file was modified. ROM remains 931 words. The Quartus
output_files directory is not tracked in git, so the refreshed local
summaries are not part of this commit; only this report is committed.

| Metric | Stale (rejected M5 experiment) | Refreshed (current accepted source) | Accepted baseline target | Verdict |
| --- | ---: | ---: | ---: | --- |
| Total logic elements | 9,949 / 10,320 | **9,992 / 10,320 (97%)** | 9,992 | match |
| Combinational functions | 9,257 | 9,417 | 9,417 | match |
| Dedicated logic registers | 4,175 | 4,233 | 4,233 | match |
| Total memory bits | 86,016 | 86,016 | 86,016 | match |
| M9K blocks | 16 | 16 | 16 | match |
| Embedded multiplier 9-bit | 26 / 46 | 28 / 46 | 28 | match |
| PLLs | 1 / 2 | 1 / 2 | 1 | match |
| Slow-85C setup `sys_clk_50m` | +2.620 ns | +2.914 ns | +2.914 ns | match |
| Slow-85C hold `sys_clk_50m` | +0.410 ns | +0.405 ns | +0.405 ns | match |
| Slow-85C setup `i2c_clk` | +16.979 ns | +17.573 ns | +17.573 ns | match |
| Slow-85C setup `audio_bclk` | +314.061 ns | +316.385 ns | +316.385 ns | match |
| All Slow-85C TNS | 0 | 0 | 0 | match |
| Quartus errors | 0 | 0 | 0 | match |
| Quartus warnings | 21 (M5 experimental + 5 cosmetic) | **16** | 16 | match |
| ROM words | 931 | 931 | 931 | match |

## Why the Refresh Was Needed

The Phase 4 M5 NO-GO experiment compiled the gated RTL locally,
captured the result (-43 LE, below the +50 LE gate), then reverted the
RTL via `git checkout` per the task stop rule. The committed source
went back to the accepted M3/M4 baseline byte-for-byte, but the
on-disk Quartus `output_files/*.summary` artifacts still reflected
the rejected experimental compile (LE 9,949, DSP9 26, setup +2.620 ns,
21 warnings). The verifier task `task-07c78294` flagged this as a
local artifact-evidence mismatch even though source acceptance was
PASS. This task addresses only that artifact mismatch.

## Commands Run

### Firmware rebuild

```
PS> .\fw\phase0\build.ps1
Using toolchain prefix 'C:\Users\Rainb\AppData\Roaming\xPacks\@xpack-dev-tools\riscv-none-elf-gcc\15.2.0-1.1\.content\\bin\riscv-none-elf-'
Built build/phase0.elf, build/phase0.bin, and build/phase0.mem
```

ROM word count: **931** (unchanged). `fw/phase0/build/phase0.bin` is
3,724 bytes = 931 32-bit words.

### Quartus full compile

```
PS> cd quartus\phase0
PS> .\build.ps1 -Stage compile *> ..\..\.kiro\quartus_baseline_refresh.log
```

Result tail (from `.kiro/quartus_baseline_refresh.log`):

```
Info: Quartus II 64-Bit Shell was successful. 0 errors, 16 warnings
    Info: Peak virtual memory: 4336 megabytes
    Info: Processing ended: Sat May 23 22:36:57 2026
    Info: Elapsed time: 00:01:27
    Info: Total CPU time (on all processors): 00:00:29
```

Compile log is local-only (multi-megabyte Quartus stdout dump; not
committed; redundant with the `.fit.summary`/`.sta.summary` content).

## Refreshed Output Summaries (Authoritative Now)

Source: `quartus/phase0/output_files/piano_phase0_top.fit.summary`,
timestamp `Sat May 23 22:36:40 2026`.

```
Fitter Status : Successful - Sat May 23 22:36:40 2026
Quartus II 64-Bit Version : 13.0.1 Build 232 06/12/2013 SP 1 SJ Full Version
Revision Name : piano_phase0_top
Top-level Entity Name : piano_phase0_top
Family : Cyclone IV E
Device : EP4CE10F17C8
Timing Models : Final
Total logic elements : 9,992 / 10,320 ( 97 % )
    Total combinational functions : 9,417 / 10,320 ( 91 % )
    Dedicated logic registers : 4,233 / 10,320 ( 41 % )
Total registers : 4233
Total pins : 11 / 180 ( 6 % )
Total virtual pins : 0
Total memory bits : 86,016 / 423,936 ( 20 % )
Embedded Multiplier 9-bit elements : 28 / 46 ( 61 % )
Total PLLs : 1 / 2 ( 50 % )
```

Source: `quartus/phase0/output_files/piano_phase0_top.sta.summary`,
slow-1200mV-85C corner (worst-case):

```
Type  : Slow 1200mV 85C Model Setup 'sys_clk_50m'    Slack : 2.914  TNS : 0.000
Type  : Slow 1200mV 85C Model Setup 'i2c_clk'        Slack : 17.573 TNS : 0.000
Type  : Slow 1200mV 85C Model Setup 'audio_bclk'     Slack : 316.385 TNS : 0.000
Type  : Slow 1200mV 85C Model Hold  'sys_clk_50m'    Slack : 0.405  TNS : 0.000
Type  : Slow 1200mV 85C Model Hold  'audio_bclk'     Slack : 0.453  TNS : 0.000
Type  : Slow 1200mV 85C Model Hold  'i2c_clk'        Slack : 0.453  TNS : 0.000
```

All other corners (Slow-0C, Fast-0C) and all other timing types
(recovery, removal, minimum-pulse-width) are clean with TNS = 0 and
match the accepted baseline numbers from `phase4_m2_reclamation_validation.md`.

## Source Equivalence

Verified at HEAD `c00ee38`:

- `git diff 386698d c00ee38 -- rtl/audio/phase0_audio_path.v` is empty.
- `git diff 386698d c00ee38 -- rtl/control/phase0_control_regs.v` is empty.
- `git diff 386698d c00ee38 -- 'rtl/**/*.v' 'rtl/**/*.sv' 'fw/**' 'quartus/phase0/*.qsf' 'quartus/phase0/*.sdc' 'quartus/phase0/*.tcl'` is empty (only `reports/` and the obsolete-stub deletion landed since the accepted M2 baseline).
- The four physical voice instances remain in
  `rtl/audio/phase0_audio_path.v` (`phase1_reduced_voice_inst`,
  `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`,
  `phase1_reduced_voice3_inst`).
- ROM bin is byte-identical to the accepted post-M2 baseline (3,724 bytes / 931 words).

The refreshed Quartus output therefore correctly reflects the accepted
source, and the artifact mismatch is fully resolved.

## What Was Not Touched

- No RTL, firmware, host-tool, SDC, QSF/project, PLL, pin, constraint
  change. Verified by `git status` and the explicit `git diff` checks
  above.
- The four untracked verifier UART files
  (`reports/phase3_m3b_debug_uart.txt`,
  `reports/phase3_m3b_single_uart.txt`,
  `reports/phase3_m5_hardware_uart.txt`,
  `reports/phase3_m6_hardware_uart.txt`) were not touched.
- `.kiro/` was not edited as a tracked path; the local
  `.kiro/quartus_baseline_refresh.log` is a local stdout dump and is
  not committed (`.kiro/` is untracked per project convention).
- Quartus `output_files/` is not tracked in git, so the refreshed
  summaries are local-only artifacts. They are not staged for commit.

## Commit Plan

This task commits **report only**. Per task description: "Commit the
report only unless project conventions require generated Quartus
summaries to be committed. Do not commit large generated files unless
they are already tracked and changed intentionally."

The Quartus `output_files/` tree is not tracked in git in this repo,
so the refreshed summaries are not committed. The verifier (and any
later acceptance run) can reproduce them deterministically by running
`.\build.ps1 -Stage compile` in `quartus\phase0`.

Single-file commit contents:
- add `reports/phase4_m5_baseline_compile_refresh.md`

## Verdict

**PASS.** Local Quartus build artifacts now reflect the accepted
source. Baseline numbers are restored: LE 9,992, M9K 16, DSP9 28,
PLL 1, slow-85C setup +2.914 ns, hold +0.405 ns, all TNS 0, ROM 931,
0 errors, 16 warnings. Phase 4 reclamation status remains: M2 partial
NO-GO + Candidate C accepted, M3 NO-GO, M5 NO-GO; all RTL reverted to
baseline; no source change net since `81105ab` aside from the inert
report adds in `c00ee38` and (this commit).

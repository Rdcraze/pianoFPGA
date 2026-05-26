# Verifier Handoff after Phase 6 M5 PASS

Date: 2026-05-25
From: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Last completed task: `task-52e7c860` (Phase 6 M5 B2 body-knob
under revised cap). Validation commit: `40f44e2`. Status: done.
Branch: `codex/phase1c-uart-boundary-fix` (HEAD = `40f44e2`).

This note exists to bootstrap the next verifier session if the
current one is rotated out.

## Current accepted baseline

Phase 6 M5 B2 runtime body-mix knob is the latest accepted RTL
slice. Live point on `codex/phase1c-uart-boundary-fix`:

- Source HEAD: `40f44e2` (verifier validation report only).
- Last RTL/control commit: `2fa70e8` (M5 B2 reapply under +200 LE
  cap, by implementer task `task-3beccc57`).
- Quartus full compile: 0 errors, 16 warnings (cosmetic
  baseline).
- LE: 5,105 / 10,320 (49 %), +173 vs M3/M4 baseline 4,932,
  under the orchestrator's revised +200 LE hard cap by 27.
- Combinational: 4,843; Registers: 2,305; Memory bits: 20,480.
- M9K block count: 8 (unchanged across M3/M4/M5 rebuilds).
  The implementer's "M9K = 5" wording is the memory-bits
  utilization percentage (20,480 / 423,936 = 5%); the actual
  block count is 8. This is non-blocking and recorded in the
  validation report.
- Embedded Multiplier 9-bit: 26 / 46 (57 %).
- PLL: 1 / 2.
- Slow-85C `sys_clk_50m` setup slack: +4.620 ns.
- Hold slow-85C: +0.414 ns. All TNS = 0.
- SOF identity: SHA-256
  `1E59C516502B8E603ED66DB50A4CDEA0ED466F093351C89AF80D2E9EF2BC6F09`,
  programmer checksum `0x00397207`. Programmed cleanly over
  USB-Blaster onto EP4CE10F17.
- ModelSim TBs (all PASS in fresh `.kiro/msim_phase6_m5_v/`
  work library):
  - `phase0_uart_command_tb`: notes=6 releases=1 errors=4
    isolation=1 body_mix=3000.
  - `phase0_fixed_control_isolation_tb`: 11 ISO_TB_PASS
    assertions then ISOLATION_TB_PASS.
  - `phase0_uart_status_tx_tb`: frames=2 collected_count=170.
  - `phase1_reduced_voice_tb`: golden bit-exact peak=3952,
    first_nonzero_sample=106, golden_samples=4096.
- Hardware UART (`COM5`, 115200 8N1) confirmed valid commands
  advance Q monotonically, malformed `!BG000` raises
  `last_error = 0x0007` (`ERR_UNSUPPORTED_ARG`) without wedging
  the parser, and `!N`/`!NLLLLVVVV`/`!F`/`!I0`/`!I1` continue
  to work after `!B` activity.

Validation artifacts:

- `reports/phase6_m5_body_knob_cap_raise_validation.md`
- `reports/phase6_m5_hardware_uart.txt`

Local-only diagnostics (not committed):

- `.kiro/msim_phase6_m5_v/` ModelSim work + per-TB logs.
- `.kiro/quartus_phase6_m5_verifier.log` Quartus compile log.
- `.kiro/phase6_m5_uart.ps1` UART smoke runner.

## Live UART command surface

The accepted Phase 5 / Phase 6 M5 control protocol on `COM5`
at 115200 8N1, line-terminated by `\r\n`:

| Command | Length | Effect |
| --- | ---: | --- |
| `!N\r\n` | 4 bytes | bare note, loop_len=106, vel=0x7FFF, single trigger |
| `!NLLLLVVVV\r\n` | 12 bytes | parameterized note. LLLL hex, clamped to 32..127. VVVV hex, clamped to 0..0x7FFF |
| `!F\r\n` | 4 bytes | release. In normal mode raises shared damp_mix. In isolation mode also resets voice0 |
| `!I0\r\n` / `!I1\r\n` | 5 bytes | disable / enable single-voice isolation mode |
| `!Bvvvv\r\n` | 8 bytes | (M5) set runtime body_mix_q15 to vvvv (4 hex digits, case-insensitive). Default at reset is 0x3000 (M3 preset) |

P5M2 status frame on `uart1_tx`, ~500 ms cadence, 62 bytes
including CRLF:

```
P5M2 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX Q=XXXXXXXX X=XXXXXXXX\r\n
```

- BOOT: 32-bit incrementing frame counter.
- TICK: 32-bit sample_tick snapshot (~46,875 ticks per 500 ms
  expected; observed delta 0x5B8D matches).
- VC: round-robin physical voice index 00..03.
- Q: command_count (accepted commands).
- X: `{last_error[15:0], error_count[15:0]}`.

## Pending workstream and known gates

The B2 body-mix knob is accepted as a runtime tuning surface
today, but final audio A/B characterization is deliberately
deferred until the user-ordered passive 3.5 mm transformer
ground-loop isolator arrives. Per
`reports/phase6_chain_noise_debug.md`, the current Realtek
endpoint is HUM_60HZ_DOMINATED with the strike RMS at the
noise floor before averaging; coherent averaging from M4
cannot recover usable SNR until the chain noise is fixed.

The verifier-recommended audio protocol once the isolator is
installed is in the implementer report's section 7
(`reports/phase6_m5_body_knob_cap_raise_impl.md`): K=16
coherent-averaging A/B between two contrasting body_mix values
such as `!B3000` and `!B6000`, comparing 1-3 kHz FFT band
energy. The bench tooling already supports this in
`scripts/phase6_m1_voice_bench.py --repeats K`.

## Verifier ergonomics

- Use teambus MCP exclusively. WSL is allowed only for
  `wait_teambus.py work --mode edge_only` calls; everything
  else runs in PowerShell.
- Verifier wait command form:
  `wsl bash -c "cd /home/rdcraze/mcp/teambus && python3 wait_teambus.py work --agent-id 143ef321-d70f-4f01-97f3-e44e31022699 --after-cursor <CURSOR> --mode edge_only"`
- Last cursor used: `9941` (no events since M5 PASS). Pass
  this back on the next wait to avoid replay noise.
- ASCII-only on every committed report. Verify with the
  PowerShell foreach-byte loop (do not use
  `Where-Object {$_ -gt 127}`; that returns null when no
  matches). Re-encode any UTF-16 BOM via
  `[System.IO.File]::WriteAllText($p, $content, [System.Text.Encoding]::ASCII)`.
- Em-dashes `--`, curly quotes `"` `'`, multiplication signs
  `x`, and arrows `->` are forbidden in committed reports.
- Reserve the validation report path with
  `mcp_teambus_reserve_path` before writing it. Release the
  lock with `release_task_locks` after committing.
- Commit using
  `git -c user.name="kiro-verifier" -c user.email="verifier@piano-agents.local" commit ...`
  Never push (orchestrator handles).

## Hardware tooling

- USB-Blaster reachable as `USB-Blaster [USB-0]` (verified
  during M5 hardware smoke).
- Quartus 13.0.1 SP1 at `D:\quartus\quartus\bin64`. Build
  script: `quartus\phase0\build.ps1 -Stage compile`.
- ModelSim SE-64 10.5 at `D:\modelsim\win64\vsim.exe`. Add to
  PATH per session: `$env:PATH = 'D:\modelsim\win64;' + $env:PATH`.
- COM port: `COM5` for the CH340 USB-UART path.
- Audio capture endpoint on this verifier machine:
  `wave_{090C046E-D2D2-49F8-A09A-EFCF188AA3FE}` (the SECOND
  Realtek endpoint). The other Realtek endpoint
  `wave_C3E84FAF` only sees ambient noise on this machine and
  has produced false negatives in earlier Phase 6 work.

## What to do next session

1. Refresh teambus state with `mcp_teambus_dashboard` and
   `mcp_teambus_get_inbox --unread-only true`. Acknowledge
   only messages relevant to the next claimable verifier task;
   do not bulk-acknowledge stale Phase 0-5 messages.
2. Pick up the next claimable verifier task with
   `claim_next_task`. If the orchestrator queues hardware-A/B
   for the body knob after the isolator arrives, follow the
   implementer report's section 7 protocol. If the next task
   is a fresh scope or report, follow the standard verifier
   review flow.
3. If no claimable verifier work appears, sit in
   `wait_teambus.py work --mode edge_only` from the latest
   cursor.

## Files to read for context

- `reports/phase6_m5_body_knob_cap_raise_validation.md` (this
  cycle's verdict).
- `reports/phase6_m5_body_knob_cap_raise_impl.md` (implementer
  recovery notes).
- `reports/phase6_m5_body_knob_impl.md` (historical NO-GO,
  preserved unchanged).
- `reports/phase6_chain_noise_debug.md` (USB-ground-loop root
  cause and isolator decision).
- `reports/phase6_m4_repeated_capture_validation.md` (M4
  M5_FALLBACK_REQUIRED chain that triggered M5).
- `rtl/control/phase0_uart_command.v` and
  `rtl/control/phase0_fixed_control.v` for the live control
  surface.
- `scripts/phase6_m1_voice_bench.py` for the K-repeat bench
  driver.
- `.kiro/phase6_m5_uart.ps1` for a known-good UART smoke
  runner.

ASCII-only.

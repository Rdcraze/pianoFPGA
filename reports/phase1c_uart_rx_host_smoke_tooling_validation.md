# Phase 1C UART RX Host Smoke Tooling Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-8de6a7ae`  
Implementation task: `task-c9de1991`  
Implementation artifact: `94def9a9-1ce9-4baa-a79f-74a78c869466`  
Implementation commit: `5e6cd48`

## Verdict

PASS.

The host-only UART RX baseline smoke tooling preserves the accepted narrow Phase 1C UART RX contract and adds useful operator checks without touching RTL, firmware, constraints, clocks, register maps, UART semantics, or resource-affecting project files. I validated the self-tests, parser regression tests, accepted no-command and six-command captures, and an expected-fail malformed capture.

Live hardware capture was not rerun for this validation. The practical exercise used existing accepted captures from the promoted UART RX boundary-fix SOF.

## Scope Review

PASS.

Commit `5e6cd48` adds only:

- `scripts/phase1c_uart_rx_baseline_smoke.py`
- `scripts/test_phase1c_uart_rx_baseline_smoke.py`
- `reports/phase1c_uart_rx_host_smoke_tooling_report.md`
- host-smoke evidence logs under `reports/phase1c_uart_rx_host_smoke_tooling_*`

No RTL, firmware, Quartus constraints, clocking, register, ROM/RAM, or resource files changed. `git status --short --untracked-files=normal` was clean during validation. Git emitted Windows LF-to-CRLF warnings when diffing, but I found no substantive working-tree changes.

## Tool Behavior Review

PASS.

The script checks the accepted UART RX baseline rather than expanding behavior:

- Frozen telemetry order is checked as `I/S` startup plus repeated `R,V,F,T,A,W,Y,U,B,C,M,K,Z,O,D,E,G,H,J,L,N,P,Q,X` cycles.
- No-command profile requires latest `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `Q=0`, `X=0`, and `K=0`.
- Commanded profile requires latest `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `P=0`, `Q=6`, `X=0`, and `K=0`.
- Nonzero voice health tags `V/Y/Z/M` are checked.
- Raw command echo is rejected when `!N` appears in received telemetry.
- Standalone `ACK` or `OK` lines are rejected.
- LF-normalized text captures are accepted with a warning; raw `.bin` captures remain the right evidence for byte-level CRLF parser behavior.
- Operator output is concise and includes PASS/FAIL, mode, frame count, cycle count, and key `G/Q/X/K` values.

The tool does not include a positive malformed/boundary acceptance mode. That is acceptable for this host smoke tool because it is documented as a narrow accepted-baseline checker. I verified that the malformed boundary capture fails no-command mode because `X=00030004` does not match the accepted no-command baseline.

## Commands Run

Self-test:

```powershell
python scripts\test_phase1c_uart_rx_baseline_smoke.py
```

Result:

```text
Ran 9 tests in 0.002s
OK
```

Parser regression:

```powershell
python scripts\test_phase1c_uart_telemetry.py
```

Result:

```text
Ran 10 tests in 0.002s
OK
```

Accepted no-command capture:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_command_ingress_boundary_uart_capture.txt --mode no-command
```

Result:

```text
UART_RX_BASELINE_SMOKE_PASS mode=no-command frames=170 cycles=7 G=00000006 Q=00000000 X=00000000 K=00000000
warning: using latest values for repeated tags: A,B,C,D,E,F,G,H,J,K,L,M,N,O,P,Q,R,T,U,V,W,X,Y,Z
```

Accepted six-command capture:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_boundary_audio_rerun_uart_capture.txt --mode commanded
```

Result:

```text
UART_RX_BASELINE_SMOKE_PASS mode=commanded frames=266 cycles=10 G=0000000C Q=00000006 X=00000000 K=00000000
warning: parsed LF-normalized text capture as CRLF telemetry
warning: using latest values for repeated tags: A,B,C,D,E,F,G,H,J,K,L,M,N,O,P,Q,R,T,U,V,W,X,Y,Z
```

Malformed boundary capture as expected-fail baseline check:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py check reports\phase1c_uart_rx_command_ingress_boundary_malformed_uart_capture.txt --mode no-command
```

Result:

```text
UART_RX_BASELINE_SMOKE_FAIL mode=no-command frames=386 cycles=15 G=00000006 Q=00000000 X=00030004 K=00000000
warning: using latest values for repeated tags: A,B,C,D,E,F,G,H,J,K,L,M,N,O,P,Q,R,T,U,V,W,X,Y,Z
error: X expected 0x00000000, got 0x00030004
```

Help output:

```powershell
python scripts\phase1c_uart_rx_baseline_smoke.py --help
```

Result: PASS, shows `check` and `capture` subcommands with clear operator entry points.

## Evidence Paths

- Implementation report: `reports/phase1c_uart_rx_host_smoke_tooling_report.md`
- Self-test log: `reports/phase1c_uart_rx_host_smoke_tooling_selftest.log`
- Parser regression log: `reports/phase1c_uart_rx_host_smoke_tooling_parser_regression.log`
- No-command check log: `reports/phase1c_uart_rx_host_smoke_tooling_no_command_check.log`
- Commanded check log: `reports/phase1c_uart_rx_host_smoke_tooling_commanded_check.log`
- Help log: `reports/phase1c_uart_rx_host_smoke_tooling_help.log`
- No-command capture exercised: `reports/phase1c_uart_rx_command_ingress_boundary_uart_capture.txt`
- Commanded capture exercised: `reports/phase1c_uart_rx_boundary_audio_rerun_uart_capture.txt`
- Malformed capture exercised: `reports/phase1c_uart_rx_command_ingress_boundary_malformed_uart_capture.txt`

## Blocking Gaps

None.

The only limitation is intentional scope: this host tool validates accepted UART RX baseline telemetry and optional serial capture; it does not replace audio waveform validation, Quartus/ModelSim evidence, firmware-build evidence, or byte-exact malformed CRLF parser validation.

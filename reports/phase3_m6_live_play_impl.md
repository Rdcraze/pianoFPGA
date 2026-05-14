# Phase 3 M6 Live-Play Wrapper

Date: 2026-05-14 | Agent: claude-implementer | Commit: `c70e82d`

**Zero firmware/RTL changes.** Host-side only.

`scripts/phase3_m6_live_play.py` wraps the M5 mapper to send sequences of note names and release commands to the FPGA via UART.

## Usage

```
# Dry-run
python scripts/phase3_m6_live_play.py --sequence "A4,C5,off,C4,panic,bare" --dry-run

# Self-check
python scripts/phase3_m6_live_play.py --self-check

# Hardware send
python scripts/phase3_m6_live_play.py --port COM3 --sequence "A4,C5,off" --delay-ms 100
```

## Dependencies

- Standard library only for dry-run
- `pyserial` required for `--port` hardware mode

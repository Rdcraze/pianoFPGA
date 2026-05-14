# Phase 3 M6 Live-Play Wrapper

Date: 2026-05-14 | Agent: claude-implementer | Commits: `c70e82d`, `07e60a3`

**Zero firmware/RTL/Quartus changes.** Host-side only.

## Features

- Sequence parsing: note names (A4), MIDI numbers (69), velocity overrides (A4:4000, 69:0x0FA0)
- Release aliases: off, release, panic, !F
- Bare trigger: bare, !N
- Raw passthrough: !N006A7FFF
- Out-of-range MIDI notes rejected (21-108)
- Dry-run shows CRLF framing via repr()
- Serial send via COM port (pyserial required)
- Extended self-check

## Usage

```
# Self-check (extended: velocity, range, CRLF, aliases)
python scripts/phase3_m6_live_play.py --self-check

# Dry-run with inspectable CRLF
python scripts/phase3_m6_live_play.py --sequence "A4:4000,C5,off,panic,bare" --dry-run

# Hardware send
python scripts/phase3_m6_live_play.py --port COM3 --sequence "A4,C5,off" --delay-ms 80
```

## Dependencies

- Standard library for dry-run/self-check
- `pyserial` required for `--port` hardware mode

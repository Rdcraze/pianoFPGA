# Phase 3 M7a Track-and-Release Implementation

Date: 2026-05-14 | Agent: claude-implementer | Commit: `ef1cc5e`

**Zero firmware/RTL/Quartus changes.** Host-side only.

## Event Grammar

| Event | Behavior |
| --- | --- |
| `down:A4`, `down:69`, `d:C4` | Send `!N`, mark note active |
| `down:A4:4000`, `d:69:0x0FA0` | Send `!N` with velocity override |
| `up:A4`, `u:69` | Mark inactive; suppress UART if other notes active; send `!F` when active set empties |
| `panic`, `release`, `off`, `all-off` | Clear active set, send `!F` |

## Usage

```
# Self-check
python scripts/phase3_m7_track_release.py --self-check

# Dry-run (shows active-set transitions, repr() framing, 0 raw UART bytes)
python scripts/phase3_m7_track_release.py --sequence "down:A4,down:C5,up:A4,up:C5,down:C4,panic" --dry-run

# Hardware send
python scripts/phase3_m7_track_release.py --port COM3 --sequence "down:A4,down:C5,up:A4,up:C5"
```

## Dry-Run Example

`down:A4,down:C5,up:A4,up:C5,down:C4,panic` sends 5 commands: `!N006A7FFF`, `!N00597FFF`, `!F` (up:C5 clears active), `!N007F7FFF`, `!F` (panic). `up:A4` is suppressed because C5 remains active.

## Dependencies

- Standard library for dry-run/self-check
- `pyserial` required for `--port` hardware mode

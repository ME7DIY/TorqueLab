# TORQUELAB Phase 2 Lua Feed

Phase 2 extends the Phase 1 OutGauge stream with a second telemetry channel intended to be fed by a BeamNG Lua extension.

## Backend contract

The backend now listens on:

- OutGauge UDP: `127.0.0.1:4444`
- Extended telemetry UDP JSON: `127.0.0.1:4445`
- WebSocket output: `ws://127.0.0.1:8765`

The WebSocket payload keeps the existing Phase 1 fields at the top level and adds an `extended` object.

Example payload:

```json
{
  "rpm": 3420.5,
  "speed": 118.2,
  "gear": 4,
  "throttle": 0.84,
  "extended": {
    "wheelSpeeds": {
      "fl": 117.8,
      "fr": 118.1,
      "rl": 116.9,
      "rr": 117.0
    },
    "suspensionTravel": {
      "fl": 0.081,
      "fr": 0.078,
      "rl": 0.062,
      "rr": 0.064
    },
    "boostCurve": {
      "targetBar": 1.4,
      "actualBar": 1.32
    },
    "torqueNm": 512.4,
    "gearRatio": 1.19
  }
}
```

## Recommended Phase 2 fields

Start with these before adding anything more complex:

- `wheelSpeeds.fl`
- `wheelSpeeds.fr`
- `wheelSpeeds.rl`
- `wheelSpeeds.rr`
- `suspensionTravel.fl`
- `suspensionTravel.fr`
- `suspensionTravel.rl`
- `suspensionTravel.rr`
- `torqueNm`
- `gearRatio`
- `boostCurve.targetBar`
- `boostCurve.actualBar`

## Integration note

This folder currently documents the transport contract only. The actual BeamNG Lua implementation can be added here next without changing the Phase 1 dashboard protocol again.

## Files in this folder

- [README.md](/C:/Users/kitza/Documents/TORQUELAB/lua/README.md): payload contract
- [INSTALL.md](/C:/Users/kitza/Documents/TORQUELAB/lua/INSTALL.md): install and loading steps
- [torquelabPhase2.lua](/C:/Users/kitza/Documents/TORQUELAB/lua/vehicle/extensions/torquelabPhase2.lua): vehicle Lua sender

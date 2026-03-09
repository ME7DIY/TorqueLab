# TORQUELAB
### A live telemetry, dashboard, and tuning interface for BeamNG.drive

---

## What is TORQUELAB?

TORQUELAB is an external desktop application that connects to BeamNG.drive via UDP telemetry, displays live vehicle data on a professional automotive-style dashboard, and eventually allows real-time tuning of engine parameters — all from a second monitor while you drive.

Think HolleyEFI or AEM Series 2 dash — but for your sim rig, built from scratch.

---

## Full Project Scope

### Phase 1 — Live Dashboard (current focus)
A clean, real-time dashboard displaying all available OutGauge telemetry data from BeamNG in a professional automotive UI style.

### Phase 2 — Extended Telemetry
Expand beyond OutGauge using BeamNG's Lua extension API to capture deeper data — individual wheel speeds, suspension travel, boost curves, torque output, gear ratios.

### Phase 3 — Data Logging
Record sessions to CSV/JSON. Replay and analyze runs. Overlay data on graphs. Lap timing. Identify where power is being lost.

### Phase 4 — Live Tuning Interface
Send parameter changes back into BeamNG in real time. Adjust fuel maps, ignition timing, boost targets, rev limiters — live, while the engine is running. Watch the dyno graph update as you tune.

### Phase 5 — Physical Hardware Integration
Connect an Arduino to TORQUELAB. Drive physical gauges, LEDs, and displays on a real hardware dash panel sitting on your desk. The software and hardware talking together as one system.

### Phase 6 — Map Editor
Visual fuel and ignition map editor with a grid interface similar to WinOLS. Click cells, change values, push to BeamNG live. Full table editing with 3D surface view.

---

## Phase 1 — Minimal Scope (current milestone)

**Goal:** A good looking, stable, real-time dashboard running on a second monitor displaying live BeamNG data.

**Data available via OutGauge right now:**
- RPM
- Speed (km/h or mph)
- Gear (Reverse, Neutral, 1–6+)
- Boost pressure (BAR)
- Engine temperature (°C)
- Oil temperature (°C)
- Fuel level (%)
- Throttle position (0–100%)
- Brake pressure (0–100%)
- Clutch position (0–100%)
- Dash warning lights — ABS, handbrake, battery, oil warning, full beam, turn signals, shift light

**Stack:**
- Python — UDP listener (already working)
- Python → sends data to frontend via WebSocket or local HTTP
- React + Tailwind — dashboard UI running in browser on monitor 2

**Deliverables for Phase 1:**
- [ ] Python UDP listener running stably in background
- [ ] WebSocket bridge passing live data to frontend
- [ ] React dashboard UI with automotive styling
- [ ] RPM gauge (arc style)
- [ ] Speed display
- [ ] Gear indicator
- [ ] Boost gauge
- [ ] Engine and oil temp gauges
- [ ] Fuel level bar
- [ ] Throttle / brake / clutch bars
- [ ] Warning light indicators (ABS, handbrake, signals, battery, oil)
- [ ] Clean startup / no connection state

**Aesthetic target:** HolleyEFI / AEM Infinity feel — dark background, red and white accents, industrial typography, real motorsport dashboard energy. Not a video game UI. A tool.

---

## Tech Stack Overview

| Layer | Technology | Purpose |
|---|---|---|
| Telemetry capture | Python + socket | Receives UDP from BeamNG |
| Data bridge | Python WebSocket server | Pushes live data to frontend |
| Dashboard UI | React + Tailwind | Renders gauges and displays |
| Extended telemetry (later) | BeamNG Lua mod | Deeper vehicle data |
| Hardware (later) | Arduino + Serial | Physical gauge output |
| Map editor (later) | React + Canvas | Visual tuning tables |

---

## Project Folder Structure

```
TORQUELAB/
├── backend/
│   ├── listener.py        # UDP receiver from BeamNG
│   └── server.py          # WebSocket server to frontend
├── frontend/
│   ├── src/
│   │   ├── App.jsx
│   │   ├── components/
│   │   │   ├── RPMGauge.jsx
│   │   │   ├── SpeedDisplay.jsx
│   │   │   ├── BoostGauge.jsx
│   │   │   ├── TempGauge.jsx
│   │   │   ├── FuelBar.jsx
│   │   │   ├── PedalBars.jsx
│   │   │   └── WarningLights.jsx
│   │   └── hooks/
│   │       └── useTelemetry.js
├── arduino/               # Phase 5
├── lua/                   # Phase 2
└── TORQUELAB_SCOPE.md
```

---

## Current Status

| Item | Status |
|---|---|
| BeamNG OutGauge connection | ✅ Working |
| Python UDP listener | ✅ Working |
| Data correctly unpacked | ✅ Working |
| WebSocket bridge | 🔲 Not started |
| Dashboard UI | 🔲 Not started |

---

*TORQUELAB — built from scratch, one packet at a time.*

# TORQUELAB Handoff

## Project Summary

TORQUELAB is a BeamNG telemetry project with:

- a Python backend that ingests live telemetry
- a React + Vite frontend that renders multiple dashboard presets
- a vehicle Lua extension for extended BeamNG-only telemetry
- a Phase 3 logging system with in-app session browsing

The project is already backed up to GitHub:

- `git@github.com:ME7DIY/TorqueLab.git`

Current branch:

- `main`

## High-Level Architecture

### Backend

Location:

- `backend/`

Responsibilities:

- receive BeamNG OutGauge UDP on `127.0.0.1:4444`
- receive extended vehicle Lua UDP JSON on `127.0.0.1:4445`
- merge both streams into one telemetry state
- broadcast merged telemetry over WebSocket on `ws://127.0.0.1:8765`
- expose logs API on `http://127.0.0.1:8766/api/...`
- optionally record sessions to CSV + JSONL

Main files:

- [backend/main.py](C:/Users/kitza/Documents/TORQUELAB/backend/main.py)
- [backend/torquelab_backend/server.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/server.py)
- [backend/torquelab_backend/listener.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/listener.py)
- [backend/torquelab_backend/extended_listener.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/extended_listener.py)
- [backend/torquelab_backend/models.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/models.py)
- [backend/torquelab_backend/logs_api.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/logs_api.py)
- [backend/torquelab_backend/session_logger.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/session_logger.py)
- [backend/torquelab_backend/config.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/config.py)

### Frontend

Location:

- `frontend/`

Responsibilities:

- connect to backend WebSocket
- render multiple dashboard presets
- provide hidden diagnostics view
- provide Phase 3 logs browser / compare tool
- provide settings modal for unit switching

Main files:

- [frontend/src/App.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/App.jsx)
- [frontend/src/hooks/useTelemetry.js](C:/Users/kitza/Documents/TORQUELAB/frontend/src/hooks/useTelemetry.js)
- [frontend/src/utils/dashboard.js](C:/Users/kitza/Documents/TORQUELAB/frontend/src/utils/dashboard.js)
- [frontend/src/styles.css](C:/Users/kitza/Documents/TORQUELAB/frontend/src/styles.css)

Core components:

- [frontend/src/components/TopBar.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/TopBar.jsx)
- [frontend/src/components/SettingsModal.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/SettingsModal.jsx)
- [frontend/src/components/FocusDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/FocusDashboard.jsx)
- [frontend/src/components/AdvancedDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/AdvancedDashboard.jsx)
- [frontend/src/components/MultiGaugeDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/MultiGaugeDashboard.jsx)
- [frontend/src/components/ExtendedTelemetryDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/ExtendedTelemetryDashboard.jsx)
- [frontend/src/components/LogsDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/LogsDashboard.jsx)

### BeamNG Lua Extension

Location in repo:

- [lua/vehicle/extensions/torquelabPhase2.lua](C:/Users/kitza/Documents/TORQUELAB/lua/vehicle/extensions/torquelabPhase2.lua)

Purpose:

- runs inside the vehicle Lua VM
- emits extended telemetry over UDP to `127.0.0.1:4445`

This file must be copied into BeamNG’s actual vehicle extension path when testing in-game.

## What Is Working

### Phase 1

Stable:

- OutGauge ingestion
- core dash telemetry
- focus-style dashboard

### Phase 2

Stable enough to build on:

- live extended telemetry transport from BeamNG vehicle Lua
- wheel speeds
- suspension proxy values
- torque
- gear ratio
- boost actual
- hidden diagnostics page

Important note:

- `boost actual` is usable
- `boost target` is not reliable yet across vehicles and is intentionally sanitized / hidden as `N/A` when invalid

### Phase 3

Working:

- backend session logging
- CSV + JSONL session output
- logs API
- in-app log browser
- load saved runs into `Baseline` and `Tuned`
- show/hide loaded runs
- compare runs
- delete saved sessions
- start/stop logging from the `LOGS` page

### Settings / UX

Working:

- settings cog opens a centered modal
- `KM/H` <-> `MPH`
- `BAR` <-> `PSI`
- settings persist in `localStorage`
- hidden `PHASE2` preset still requires Shift+click behavior through the cog path

## Current Dashboard Presets

### `FOCUS`

Use:

- primary clean dashboard

Characteristics:

- stable
- hero RPM + speed + gear
- classic side rails

### `ADV`

Use:

- performance/telemetry page

Characteristics:

- reuses the stable hero layout
- shows wheel speed split
- shows suspension motion
- shows drive torque, gear ratio, boost, wheel delta
- smoother than earlier noisy versions

Known nuance:

- `Boost Target` may show `N/A` if no reliable value is available

### `MULTI`

Use:

- alt presentation with multiple electronic arc gauges

Characteristics:

- much better than earlier broken layout iterations
- visually usable
- not the main current development target

### `LOGS`

Use:

- Phase 3 / Phase 4 analysis page

Characteristics:

- recorder controls
- manual CSV load
- saved session browser
- charts
- compare view
- raw data table

### `PHASE2`

Use:

- diagnostics only

Characteristics:

- intentionally semi-hidden
- heavy debug is behind a toggle

## Important Files By Responsibility

### Telemetry Formatting / Display Model

- [frontend/src/utils/dashboard.js](C:/Users/kitza/Documents/TORQUELAB/frontend/src/utils/dashboard.js)

This file is central. It:

- normalizes frontend telemetry
- applies speed/pressure unit conversion
- builds all dashboard-facing display values
- feeds `FOCUS`, `ADV`, and `MULTI`

If display behavior seems inconsistent, check this file first.

### Logs Viewer

- [frontend/src/components/LogsDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/LogsDashboard.jsx)

This file currently owns:

- recorder UI
- session browser
- CSV parsing
- chart rendering
- compare cards
- raw table

It is becoming the main Phase 4 area.

### Logs Backend API

- [backend/torquelab_backend/logs_api.py](C:/Users/kitza/Documents/TORQUELAB/backend/torquelab_backend/logs_api.py)

Endpoints currently include:

- `GET /api/logs`
- `GET /api/logs/<name>`
- `DELETE /api/logs/<name>`
- `GET /api/logging`
- `POST /api/logging/start`
- `POST /api/logging/stop`

## How To Run

### Backend

From repo root:

```powershell
cd C:\Users\kitza\Documents\TORQUELAB\backend
python3 .\main.py
```

Defaults:

- UDP OutGauge: `127.0.0.1:4444`
- UDP Lua telemetry: `127.0.0.1:4445`
- WebSocket: `127.0.0.1:8765`
- Logs API: `127.0.0.1:8766`

Logging behavior:

- logging is manual by default now
- start and stop it from the `LOGS` page
- `--auto-start-logging` exists if needed

### Frontend

From repo root:

```powershell
cd C:\Users\kitza\Documents\TORQUELAB\frontend
npm run dev
```

Optional env:

- `VITE_TELEMETRY_URL`
- `VITE_LOGS_API_URL`

### BeamNG Lua

Repo copy:

- [lua/vehicle/extensions/torquelabPhase2.lua](C:/Users/kitza/Documents/TORQUELAB/lua/vehicle/extensions/torquelabPhase2.lua)

Needs to be copied into BeamNG’s actual vehicle extension directory.

Load from vehicle Lua:

```lua
extensions.load("torquelabPhase2")
```

If using GE Lua:

```lua
be:getPlayerVehicle(0):queueLuaCommand('extensions.load("torquelabPhase2")')
```

## Git / Repo Notes

### GitHub Remote

- `origin = git@github.com:ME7DIY/TorqueLab.git`

### Files Intentionally Excluded

From `.gitignore`:

- `frontend/node_modules/`
- `frontend/dist/`
- `frontend/.env`
- `backend/.venv/`
- `backend/logs/`
- `BeamNGs/`
- stray file `a`

### Current Commit Context

Initial backup commit pushed:

- `581e8b2` `Initial TorqueLab project`

## Known Issues / Open Questions

### 1. Boost Target

Status:

- unresolved

Details:

- current cross-vehicle source is unreliable
- some vehicles produce garbage values
- frontend now sanitizes it and shows `N/A` when invalid

Do not assume this is solved.

### 2. Replay Mode

Status:

- not built yet

This was discussed for Phase 4 but not implemented yet.

### 3. Shared Chart Cursor / Hover

Status:

- not built yet

This is still a strong next Phase 4 task.

### 4. Logs Page Complexity

Status:

- acceptable but getting dense

`LogsDashboard.jsx` is carrying a lot of responsibility and may need splitting later.

## Recommended Next Steps

### Highest Priority: Phase 4

Best next tasks:

1. Add replay mode to `LOGS`
2. Add synchronized chart cursor / hover readouts
3. Add a replay scrubber and current-frame detail panel
4. Add summary cards for selected runs

### Suggested Replay Design

Good first pass:

- choose one loaded run as replay source
- scrub through frames with a range slider
- show current frame values in a compact summary panel
- optionally later feed replayed data back into dashboard components

### Suggested Chart Interaction

Good first pass:

- hover any chart
- show one shared cursor index
- all charts show the same vertical cursor
- side panel shows values for all selected channels at that frame

## Things To Be Careful About

### Do Not Re-Introduce Demo Data

The user explicitly does not want fake moving placeholder telemetry anymore.

### Do Not Break `ADV`

`ADV` is now the most useful “real data” dashboard. It should be treated carefully.

### Do Not Commit BeamNG Dump

The `BeamNGs/` folder was intentionally excluded before GitHub push.

### Be Careful With Boost Target Claims

Do not present `boost target` as correct unless it is actually verified on real cars.

## User Preferences / Working Style

Important collaboration notes:

- user likes direct implementation over heavy planning
- user is highly iterative and often works from screenshots/live feedback
- user is okay with rough experimentation if the outcome is improving quickly
- user gets frustrated by fake data, broken alignment, and vague explanations
- user wants practical UI that feels clean and purposeful
- user wanted the project backed up ASAP, which is now done

## If Starting A New Chat

Recommended opening move:

1. Read this file
2. Read [README.md](C:/Users/kitza/Documents/TORQUELAB/README.md)
3. Read [frontend/src/utils/dashboard.js](C:/Users/kitza/Documents/TORQUELAB/frontend/src/utils/dashboard.js)
4. Read [frontend/src/components/LogsDashboard.jsx](C:/Users/kitza/Documents/TORQUELAB/frontend/src/components/LogsDashboard.jsx)
5. Ask whether to continue with:
   - replay mode
   - chart cursor/hover
   - log summary cards
   - boost-target investigation

That should be enough context to continue effectively without re-discovering the project history.

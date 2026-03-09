# TORQUELAB

TORQUELAB is now organized as a Python telemetry backend plus a Vite/React dashboard frontend.

## Structure

```text
TORQUELAB/
|-- backend/                 # UDP listener + WebSocket bridge
|-- frontend/                # Vite React dashboard UI
|-- script.py                # original prototype listener
|-- torquelab_dash.html      # original prototype dashboard
`-- TORQUELAB_SCOPE.md
```

`script.py` and `torquelab_dash.html` are kept as working prototypes for reference. The new app lives in `backend/` and `frontend/`.

## Why this setup

- `React + Vite` is the right base for the dashboard because it is easy to iterate on and easy to deploy publicly later.
- Vite alone does not produce a Windows `.exe`.
- If you want a desktop `.exe` later, keep this structure and wrap the frontend with Tauri or Electron after the dashboard is stable.

## Backend

The backend receives BeamNG OutGauge packets over UDP and rebroadcasts normalized telemetry over WebSocket.

### Run

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```

Defaults:

- UDP listen: `127.0.0.1:4444`
- Extended telemetry UDP listen: `127.0.0.1:4445`
- WebSocket server: `ws://127.0.0.1:8765`
- Logs API: `http://127.0.0.1:8766/api/logs`
- Session logs: `backend/logs/`

Logging behavior:

- Logging is now manual by default
- Start and stop sessions from the frontend `LOGS` page
- If you want logging to start immediately with the backend, use `--auto-start-logging`

### Phase 3 logging

The backend now writes each session to both:

- CSV: flattened telemetry for quick spreadsheet analysis
- JSONL: full payload snapshots for replay/analysis tooling later

Optional flags:

```powershell
python main.py --log-dir logs
python main.py --disable-logging
python main.py --api-port 8766
python main.py --auto-start-logging
```

## Frontend

The frontend is a Vite React app that uses the backend WebSocket feed and stays in a clean waiting state until live telemetry arrives.

### Run

```powershell
cd frontend
npm install
npm run dev
```

Optional env file:

```text
VITE_TELEMETRY_URL=ws://127.0.0.1:8765
VITE_LOGS_API_URL=http://127.0.0.1:8766/api
```

## Logs Viewer

The frontend now includes a dedicated `LOGS` page for Phase 3.

- It can still load CSVs manually
- It can now also browse saved backend sessions through the logs API
- Saved sessions can be loaded into `Baseline` and `Final` slots for chart overlay and comparison
- It can start and stop backend log sessions directly from the sidebar

## Current Phase

- Phase 1: stable and in use
- Phase 2: live extended telemetry working in the UI
- Phase 3: session logging scaffolded in the backend

## Next steps

1. Start capturing real sessions into `backend/logs/`.
2. Add a log browser / replay selector in the frontend.
3. Plot key channels like RPM, speed, torque, boost, and wheel delta over time.
4. Add lap/run markers and export-ready analysis views.

## TODO

- Investigate a reliable cross-vehicle `boost target` source from BeamNG vehicle Lua. `Boost actual` is live and usable now, but the current target field is not stable enough to show in the dash.

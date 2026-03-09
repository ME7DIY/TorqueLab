import { useEffect, useMemo, useState } from "react";
import { convertPressure, convertSpeed, pressureUnitLabel, speedUnitLabel } from "../utils/dashboard.js";

const PAGE_SIZE = 120;
const LOGS_API_URL = import.meta.env.VITE_LOGS_API_URL ?? "http://127.0.0.1:8766/api";

const CHANNEL_DEFS = [
  { key: "rpm", label: "RPM", unit: "rpm", color: "#00d4ff" },
  { key: "speed", label: "Speed", unit: "km/h", color: "#39e07a" },
  { key: "turbo", label: "Turbo", unit: "bar", color: "#ffb830" },
  { key: "engtemp", label: "Water Temp", unit: "C", color: "#ff7043" },
  { key: "oiltemp", label: "Oil Temp", unit: "C", color: "#ffb830" },
  { key: "fuel", label: "Fuel", unit: "%", color: "#cdd6e8" },
  { key: "throttle", label: "Throttle", unit: "%", color: "#39e07a" },
  { key: "brake", label: "Brake", unit: "%", color: "#ff3a3a" },
  { key: "clutch", label: "Clutch", unit: "%", color: "#ffb830" },
  { key: "extended_torqueNm", label: "Torque", unit: "Nm", color: "#ffb830" },
  { key: "extended_gearRatio", label: "Gear Ratio", unit: "ratio", color: "#00d4ff" },
  { key: "wheelSpeed_fl", label: "Wheel FL", unit: "km/h", color: "#00d4ff" },
  { key: "wheelSpeed_fr", label: "Wheel FR", unit: "km/h", color: "#39e07a" },
  { key: "wheelSpeed_rl", label: "Wheel RL", unit: "km/h", color: "#ffb830" },
  { key: "wheelSpeed_rr", label: "Wheel RR", unit: "km/h", color: "#ff3a3a" },
  { key: "suspension_fl", label: "Susp FL", unit: "m", color: "#ffb830" },
  { key: "suspension_fr", label: "Susp FR", unit: "m", color: "#ffcc66" },
  { key: "suspension_rl", label: "Susp RL", unit: "m", color: "#d08c2e" },
  { key: "suspension_rr", label: "Susp RR", unit: "m", color: "#ff7043" },
  { key: "boost_actualBar", label: "Boost Actual", unit: "bar", color: "#39e07a" },
  { key: "boost_targetBar", label: "Boost Target", unit: "bar", color: "#cdd6e8" },
];

function parseCsvLine(line) {
  const cells = [];
  let current = "";
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];

    if (char === "\"") {
      if (inQuotes && line[i + 1] === "\"") {
        current += "\"";
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === "," && !inQuotes) {
      cells.push(current);
      current = "";
    } else {
      current += char;
    }
  }

  cells.push(current);
  return cells;
}

function parseCellValue(value) {
  if (value == null || value === "") {
    return null;
  }

  const numeric = Number(value);
  if (!Number.isNaN(numeric)) {
    return numeric;
  }

  return value;
}

function parseCsv(text) {
  const lines = text.replace(/\r/g, "").split("\n").filter(Boolean);
  if (lines.length < 2) {
    return [];
  }

  const headers = parseCsvLine(lines[0]);
  return lines.slice(1).map((line, index) => {
    const values = parseCsvLine(line);
    const row = { __index: index };

    headers.forEach((header, columnIndex) => {
      row[header] = parseCellValue(values[columnIndex]);
    });

    return row;
  });
}

function formatStat(value, digits = 3) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return "--";
  }

  return value.toFixed(digits);
}

function formatTableValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.abs(value) < 0.0001 ? "0" : value.toFixed(4);
  }

  return value == null ? "--" : String(value);
}

function formatSessionTime(value) {
  if (!value || typeof value !== "string") {
    return "--";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatVehicleIds(vehicleIds) {
  if (!Array.isArray(vehicleIds) || !vehicleIds.length) {
    return "--";
  }

  return vehicleIds.join(", ");
}

function datasetRows(dataset) {
  return dataset?.rows ?? [];
}

function convertChannelValue(key, value, displaySettings) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return value;
  }

  if (key === "speed" || key.startsWith("wheelSpeed_")) {
    return convertSpeed(value, displaySettings.speedUnit);
  }

  if (key === "turbo" || key === "boost_actualBar" || key === "boost_targetBar") {
    return convertPressure(value, displaySettings.pressureUnit);
  }

  return value;
}

function availableChannels(datasets) {
  const rows = datasets.flatMap(datasetRows);
  const sample = rows[0];
  if (!sample) {
    return [];
  }

  return CHANNEL_DEFS.filter((channel) => rows.some((row) => typeof row[channel.key] === "number"));
}

function computeStats(rows, key, displaySettings) {
  const values = rows
    .map((row) => convertChannelValue(key, row[key], displaySettings))
    .filter((value) => typeof value === "number" && Number.isFinite(value));
  if (!values.length) {
    return null;
  }

  const sum = values.reduce((total, value) => total + value, 0);
  return {
    min: Math.min(...values),
    max: Math.max(...values),
    avg: sum / values.length,
    count: values.length,
  };
}

function buildPolylinePoints(values, width = 760, height = 170) {
  const numericValues = values.filter((value) => typeof value === "number" && Number.isFinite(value));
  if (numericValues.length < 2) {
    return "";
  }

  const min = Math.min(...numericValues);
  const max = Math.max(...numericValues);
  const span = max - min || 1;

  return values
    .map((value, index) => {
      const x = (index / Math.max(values.length - 1, 1)) * width;
      const y = height - (((value ?? min) - min) / span) * height;
      return `${x},${y}`;
    })
    .join(" ");
}

function ChartCard({ channel, datasets, displaySettings }) {
  const width = 760;
  const height = 170;

  return (
    <div className="logs-chart-card">
      <div className="logs-chart-header">
        <div className="logs-chart-title">
          {channel.label} <span>{channel.unit}</span>
        </div>
        <div className="logs-chart-legend">
          {datasets.map((dataset) => (
            <div key={dataset.id} className="logs-legend-item">
              <span className="logs-legend-line" style={{ background: dataset.color }} />
              <span>{dataset.label}</span>
            </div>
          ))}
        </div>
      </div>
      <svg className="logs-chart-svg" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
        <rect x="0" y="0" width={width} height={height} className="logs-chart-bg" />
        {[0.25, 0.5, 0.75].map((fraction) => (
          <line
            key={fraction}
            x1="0"
            x2={width}
            y1={height * fraction}
            y2={height * fraction}
            className="logs-chart-line"
          />
        ))}
        {datasets.map((dataset) => {
          const points = buildPolylinePoints(
            dataset.rows.map((row) => convertChannelValue(channel.key, row[channel.key], displaySettings)),
            width,
            height,
          );
          if (!points) {
            return null;
          }

          return (
            <polyline
              key={dataset.id}
              points={points}
              fill="none"
              stroke={dataset.color}
              strokeWidth="2"
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          );
        })}
      </svg>
    </div>
  );
}

function compareDelta(tunedStats, baselineStats) {
  if (!tunedStats || !baselineStats) {
    return "--";
  }

  const delta = tunedStats.avg - baselineStats.avg;
  const sign = delta > 0 ? "+" : "";
  return `${sign}${delta.toFixed(4)}`;
}

export function LogsDashboard({ displaySettings }) {
  const [baseline, setBaseline] = useState(null);
  const [tunedLog, setTunedLog] = useState(null);
  const [baselineVisible, setBaselineVisible] = useState(true);
  const [tunedVisible, setTunedVisible] = useState(true);
  const [loggingStatus, setLoggingStatus] = useState(null);
  const [loggingBusy, setLoggingBusy] = useState(false);
  const [savedSessions, setSavedSessions] = useState([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [sessionsError, setSessionsError] = useState("");
  const [sessionActionError, setSessionActionError] = useState("");
  const [loggingError, setLoggingError] = useState("");
  const [loadingTarget, setLoadingTarget] = useState("");
  const [deletingSession, setDeletingSession] = useState("");
  const [activeTab, setActiveTab] = useState("charts");
  const [selectedChannels, setSelectedChannels] = useState(() => new Set(["rpm", "speed", "extended_torqueNm", "wheelSpeed_fl"]));
  const [tablePage, setTablePage] = useState(0);

  const datasets = useMemo(() => {
    const entries = [];
    if (baseline && baselineVisible) {
      entries.push({ ...baseline, color: "#00d4ff" });
    }
    if (tunedLog && tunedVisible) {
      entries.push({ ...tunedLog, color: "#39e07a" });
    }
    return entries;
  }, [baseline, tunedLog, baselineVisible, tunedVisible]);

  const channelDefs = useMemo(
    () =>
      CHANNEL_DEFS.map((channel) => {
        if (channel.key === "speed" || channel.key.startsWith("wheelSpeed_")) {
          return { ...channel, unit: speedUnitLabel(displaySettings.speedUnit, { short: true }) };
        }
        if (channel.key === "turbo" || channel.key === "boost_actualBar" || channel.key === "boost_targetBar") {
          return { ...channel, unit: pressureUnitLabel(displaySettings.pressureUnit, { short: true }) };
        }
        return channel;
      }),
    [displaySettings],
  );

  const channels = useMemo(() => {
    const rows = datasets.flatMap(datasetRows);
    const sample = rows[0];
    if (!sample) {
      return [];
    }

    return channelDefs.filter((channel) => rows.some((row) => typeof row[channel.key] === "number"));
  }, [channelDefs, datasets]);
  const activeChannelDefs = channels.filter((channel) => selectedChannels.has(channel.key));

  const mergedRows = useMemo(() => {
    const rows = [];
    for (const dataset of datasets) {
      for (const row of dataset.rows) {
        rows.push({ ...row, __source: dataset.label });
      }
    }
    return rows;
  }, [datasets]);

  const tablePages = Math.max(1, Math.ceil(mergedRows.length / PAGE_SIZE));
  const currentRows = mergedRows.slice(tablePage * PAGE_SIZE, (tablePage + 1) * PAGE_SIZE);

  async function refreshSavedSessions() {
    setSessionsLoading(true);
    setSessionsError("");

    try {
      const response = await fetch(`${LOGS_API_URL}/logs`);
      if (!response.ok) {
        throw new Error(`Failed to load logs (${response.status})`);
      }

      const payload = await response.json();
      setSavedSessions(payload.sessions ?? []);
    } catch (error) {
      setSessionsError(error instanceof Error ? error.message : "Failed to load logs");
    } finally {
      setSessionsLoading(false);
    }
  }

  async function refreshLoggingStatus() {
    setLoggingError("");

    try {
      const response = await fetch(`${LOGS_API_URL}/logging`);
      if (!response.ok) {
        throw new Error(`Failed to load logging status (${response.status})`);
      }

      const payload = await response.json();
      setLoggingStatus(payload);
    } catch (error) {
      setLoggingError(error instanceof Error ? error.message : "Failed to load logging status");
    }
  }

  useEffect(() => {
    async function initialLoad() {
      await Promise.all([refreshSavedSessions(), refreshLoggingStatus()]);
    }

    initialLoad();
  }, []);

  async function loadCsvFile(file, setter, label, id) {
    const text = await file.text();
    const rows = parseCsv(text);
    setter({
      id,
      label,
      filename: file.name,
      rows,
    });
    if (id === "baseline") {
      setBaselineVisible(true);
    }
    if (id === "tuned") {
      setTunedVisible(true);
    }
    setTablePage(0);
  }

  async function deleteSavedSession(sessionName) {
    setSessionActionError("");
    setDeletingSession(sessionName);

    try {
      const response = await fetch(`${LOGS_API_URL}/logs/${encodeURIComponent(sessionName)}`, {
        method: "DELETE",
      });
      if (!response.ok) {
        throw new Error(`Failed to delete ${sessionName}`);
      }

      if (baseline?.filename === sessionName) {
        setBaseline(null);
      }
      if (tunedLog?.filename === sessionName) {
        setTunedLog(null);
      }
      await refreshSavedSessions();
    } catch (error) {
      setSessionActionError(error instanceof Error ? error.message : `Failed to delete ${sessionName}`);
    } finally {
      setDeletingSession("");
    }
  }

  async function loadSavedSession(sessionName, setter, label, id) {
    setSessionActionError("");
    setLoadingTarget(`${id}:${sessionName}`);

    try {
      const response = await fetch(`${LOGS_API_URL}/logs/${encodeURIComponent(sessionName)}`);
      if (!response.ok) {
        throw new Error(`Failed to load ${sessionName}`);
      }

      const text = await response.text();
      const rows = parseCsv(text);
      setter({
        id,
        label,
        filename: sessionName,
        rows,
      });
      if (id === "baseline") {
        setBaselineVisible(true);
      }
      if (id === "tuned") {
        setTunedVisible(true);
      }
      setTablePage(0);
    } catch (error) {
      setSessionActionError(error instanceof Error ? error.message : `Failed to load ${sessionName}`);
    } finally {
      setLoadingTarget("");
    }
  }

  async function controlLogging(action) {
    setLoggingBusy(true);
    setLoggingError("");

    try {
      const response = await fetch(`${LOGS_API_URL}/logging/${action}`, {
        method: "POST",
      });
      if (!response.ok) {
        throw new Error(`Failed to ${action} logging`);
      }

      const payload = await response.json();
      setLoggingStatus(payload);
      await refreshSavedSessions();
    } catch (error) {
      setLoggingError(error instanceof Error ? error.message : `Failed to ${action} logging`);
    } finally {
      setLoggingBusy(false);
    }
  }

  function toggleChannel(key) {
    setSelectedChannels((current) => {
      const next = new Set(current);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }

  return (
    <main className="logs-shell">
      <aside className="logs-sidebar">
        <div className="logs-sidebar-section">
          <div className="logs-sidebar-header">
            <div className="logs-sidebar-label">Recorder</div>
            <button type="button" className="logs-refresh-btn" onClick={refreshLoggingStatus} disabled={loggingBusy}>
              {loggingBusy ? "..." : "STATUS"}
            </button>
          </div>
          <div className={`logs-recorder-card${loggingStatus?.active ? " active" : ""}`}>
            <div className="logs-recorder-state">
              <span className="logs-recorder-dot" />
              <span>{loggingStatus?.active ? "Recording" : "Idle"}</span>
            </div>
            <div className="logs-recorder-meta">
              <span>Session {loggingStatus?.sessionId ?? "--"}</span>
              <span>{loggingStatus?.enabled === false ? "Logging disabled" : "Ready"}</span>
            </div>
            <div className="logs-recorder-actions">
              <button
                type="button"
                className="logs-recorder-btn start"
                onClick={() => controlLogging("start")}
                disabled={loggingBusy || loggingStatus?.enabled === false || loggingStatus?.active}
              >
                START LOG
              </button>
              <button
                type="button"
                className="logs-recorder-btn stop"
                onClick={() => controlLogging("stop")}
                disabled={loggingBusy || !loggingStatus?.active}
              >
                STOP LOG
              </button>
            </div>
            {loggingStatus?.active ? (
              <div className="logs-recorder-path">
                <span>{loggingStatus.csvPath}</span>
              </div>
            ) : null}
          </div>
          {loggingError ? <div className="logs-session-state error">{loggingError}</div> : null}
        </div>

        <div className="logs-sidebar-section">
          <div className="logs-sidebar-label">Load Logs</div>
          <label className={`logs-dropzone${baseline ? " loaded" : ""}`}>
            <input type="file" accept=".csv" onChange={(event) => event.target.files?.[0] && loadCsvFile(event.target.files[0], setBaseline, "Baseline", "baseline")} />
            <div className="logs-drop-title">Baseline</div>
            <div className="logs-drop-sub">{baseline ? `${baseline.rows.length} rows - ${baseline.filename}` : "Drop CSV or click"}</div>
            {baseline ? (
              <div className="logs-drop-actions">
                <button
                  type="button"
                  className={`logs-assign-btn${baselineVisible ? " active" : ""}`}
                  onClick={(event) => {
                    event.preventDefault();
                    setBaselineVisible((current) => !current);
                  }}
                >
                  {baselineVisible ? "HIDE" : "SHOW"}
                </button>
                <button
                  type="button"
                  className="logs-assign-btn clear"
                  onClick={(event) => {
                    event.preventDefault();
                    setBaseline(null);
                  }}
                >
                  CLEAR
                </button>
              </div>
            ) : null}
          </label>
          <label className={`logs-dropzone${tunedLog ? " loaded" : ""}`}>
            <input type="file" accept=".csv" onChange={(event) => event.target.files?.[0] && loadCsvFile(event.target.files[0], setTunedLog, "Tuned", "tuned")} />
            <div className="logs-drop-title">Tuned</div>
            <div className="logs-drop-sub">{tunedLog ? `${tunedLog.rows.length} rows - ${tunedLog.filename}` : "Drop CSV or click"}</div>
            {tunedLog ? (
              <div className="logs-drop-actions">
                <button
                  type="button"
                  className={`logs-assign-btn${tunedVisible ? " active" : ""}`}
                  onClick={(event) => {
                    event.preventDefault();
                    setTunedVisible((current) => !current);
                  }}
                >
                  {tunedVisible ? "HIDE" : "SHOW"}
                </button>
                <button
                  type="button"
                  className="logs-assign-btn clear"
                  onClick={(event) => {
                    event.preventDefault();
                    setTunedLog(null);
                  }}
                >
                  CLEAR
                </button>
              </div>
            ) : null}
          </label>
        </div>

        <div className="logs-sidebar-section">
          <div className="logs-sidebar-header">
            <div className="logs-sidebar-label">Saved Sessions</div>
            <button type="button" className="logs-refresh-btn" onClick={refreshSavedSessions} disabled={sessionsLoading}>
              {sessionsLoading ? "..." : "REFRESH"}
            </button>
          </div>
          {sessionsLoading ? <div className="logs-session-state">Loading...</div> : null}
          {sessionsError ? <div className="logs-session-state error">{sessionsError}</div> : null}
          {sessionActionError ? <div className="logs-session-state error">{sessionActionError}</div> : null}
          {!sessionsLoading && !sessionsError ? (
            <div className="logs-session-list">
              {savedSessions.map((session) => (
                <div key={session.name} className="logs-session-card">
                  <button
                    type="button"
                    className="logs-session-delete"
                    onClick={() => deleteSavedSession(session.name)}
                    disabled={Boolean(deletingSession) || Boolean(loadingTarget)}
                    title="Delete saved session"
                  >
                    {deletingSession === session.name ? "..." : "x"}
                  </button>
                  <div className="logs-session-name">{session.name}</div>
                  <div className="logs-session-meta">
                    <span>{session.rowCount} rows</span>
                    <span>{formatSessionTime(session.startedAt)}</span>
                  </div>
                  <div className="logs-session-submeta">
                    <span>End {formatSessionTime(session.endedAt)}</span>
                    <span>Veh {formatVehicleIds(session.vehicleIds)}</span>
                  </div>
                  <div className="logs-session-actions">
                    <button
                      type="button"
                      className={`logs-session-btn${baseline?.filename === session.name ? " active" : ""}`}
                      onClick={() => loadSavedSession(session.name, setBaseline, "Baseline", "baseline")}
                      disabled={Boolean(loadingTarget) || Boolean(deletingSession)}
                    >
                      {loadingTarget === `baseline:${session.name}` ? "..." : "LOAD INTO BASELINE"}
                    </button>
                    <button
                      type="button"
                      className={`logs-session-btn${tunedLog?.filename === session.name ? " active" : ""}`}
                      onClick={() => loadSavedSession(session.name, setTunedLog, "Tuned", "tuned")}
                      disabled={Boolean(loadingTarget) || Boolean(deletingSession)}
                    >
                      {loadingTarget === `tuned:${session.name}` ? "..." : "LOAD INTO TUNED"}
                    </button>
                  </div>
                </div>
              ))}
            </div>
          ) : null}
        </div>

        <div className="logs-sidebar-section">
          <div className="logs-sidebar-label">Channels</div>
          <div className="logs-channel-list">
            {channels.map((channel) => (
              <button
                key={channel.key}
                type="button"
                className={`logs-channel-toggle${selectedChannels.has(channel.key) ? " active" : ""}`}
                onClick={() => toggleChannel(channel.key)}
              >
                <span className="logs-channel-left">
                  <span className="logs-channel-swatch" style={{ background: channel.color }} />
                  <span className="logs-channel-name">{channel.label}</span>
                </span>
                <span className="logs-channel-unit">{channel.unit}</span>
              </button>
            ))}
          </div>
        </div>

        <div className="logs-sidebar-section">
          <div className="logs-sidebar-label">Quick Stats</div>
          <div className="logs-quick-grid">
            <div className="logs-quick-card">
              <div className="logs-quick-label">Baseline Rows</div>
              <div className="logs-quick-value">{baseline ? baseline.rows.length : "--"}</div>
            </div>
            <div className="logs-quick-card">
              <div className="logs-quick-label">Tuned Rows</div>
              <div className="logs-quick-value">{tunedLog ? tunedLog.rows.length : "--"}</div>
            </div>
            <div className="logs-quick-card">
              <div className="logs-quick-label">Peak RPM</div>
              <div className="logs-quick-value">
                {formatStat(Math.max(computeStats(datasetRows(baseline), "rpm", displaySettings)?.max ?? 0, computeStats(datasetRows(tunedLog), "rpm", displaySettings)?.max ?? 0), 0)}
              </div>
            </div>
            <div className="logs-quick-card">
              <div className="logs-quick-label">Peak Speed</div>
              <div className="logs-quick-value">
                {formatStat(Math.max(computeStats(datasetRows(baseline), "speed", displaySettings)?.max ?? 0, computeStats(datasetRows(tunedLog), "speed", displaySettings)?.max ?? 0), 1)}
              </div>
            </div>
          </div>
        </div>
      </aside>

      <section className="logs-content">
        <div className="logs-toolbar">
          <button type="button" className={`logs-tab${activeTab === "charts" ? " active" : ""}`} onClick={() => setActiveTab("charts")}>
            Charts
          </button>
          <button type="button" className={`logs-tab${activeTab === "compare" ? " active" : ""}`} onClick={() => setActiveTab("compare")}>
            Compare
          </button>
          <button type="button" className={`logs-tab${activeTab === "table" ? " active" : ""}`} onClick={() => setActiveTab("table")}>
            Raw Data
          </button>
        </div>

        <div className="logs-view">
          {!datasets.length ? (
            <div className="logs-empty">
              <div className="logs-empty-icon">LOG</div>
              <div className="logs-empty-title">No Logs Loaded</div>
              <div className="logs-empty-sub">Load one or two CSV session logs from `backend/logs/` to view charts and compare runs.</div>
            </div>
          ) : null}

          {datasets.length > 0 && activeTab === "charts" ? (
            <div className="logs-chart-grid">
              {activeChannelDefs.map((channel) => (
                <ChartCard key={channel.key} channel={channel} datasets={datasets} displaySettings={displaySettings} />
              ))}
            </div>
          ) : null}

          {datasets.length > 0 && activeTab === "compare" ? (
            <div className="logs-compare-wrap">
              {channels.map((channel) => {
                const baselineStats = computeStats(datasetRows(baseline), channel.key, displaySettings);
                const tunedStats = computeStats(datasetRows(tunedLog), channel.key, displaySettings);
                if (!baselineStats && !tunedStats) {
                  return null;
                }

                return (
                  <div key={channel.key} className="logs-compare-card">
                    <div className="logs-compare-title">{channel.label}</div>
                    <div className="logs-compare-row">
                      <span>Baseline Avg</span>
                      <span>{formatStat(baselineStats?.avg, 4)}</span>
                    </div>
                    <div className="logs-compare-row">
                      <span>Tuned Avg</span>
                      <span>{formatStat(tunedStats?.avg, 4)}</span>
                    </div>
                    <div className="logs-compare-row delta">
                      <span>Delta</span>
                      <span>{compareDelta(tunedStats, baselineStats)}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : null}

          {datasets.length > 0 && activeTab === "table" ? (
            <div className="logs-table-wrap">
              <table className="logs-table">
                <thead>
                  <tr>
                    <th>Source</th>
                    <th>loggedAt</th>
                    <th>rpm</th>
                    <th>speed</th>
                    <th>gear</th>
                    <th>torque</th>
                    <th>gear ratio</th>
                    <th>wheel FL</th>
                    <th>wheel FR</th>
                    <th>susp FL</th>
                    <th>susp FR</th>
                  </tr>
                </thead>
                <tbody>
                  {currentRows.map((row, index) => (
                    <tr key={`${row.__source}-${index}`}>
                      <td>{row.__source}</td>
                      <td>{formatTableValue(row.loggedAt)}</td>
                      <td>{formatTableValue(convertChannelValue("rpm", row.rpm, displaySettings))}</td>
                      <td>{formatTableValue(convertChannelValue("speed", row.speed, displaySettings))}</td>
                      <td>{formatTableValue(row.gear)}</td>
                      <td>{formatTableValue(convertChannelValue("extended_torqueNm", row.extended_torqueNm, displaySettings))}</td>
                      <td>{formatTableValue(row.extended_gearRatio)}</td>
                      <td>{formatTableValue(convertChannelValue("wheelSpeed_fl", row.wheelSpeed_fl, displaySettings))}</td>
                      <td>{formatTableValue(convertChannelValue("wheelSpeed_fr", row.wheelSpeed_fr, displaySettings))}</td>
                      <td>{formatTableValue(row.suspension_fl)}</td>
                      <td>{formatTableValue(row.suspension_fr)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <div className="logs-pagination">
                <button type="button" className="logs-page-btn" onClick={() => setTablePage((page) => Math.max(page - 1, 0))}>
                  Prev
                </button>
                <span className="logs-page-info">
                  Page {tablePage + 1} / {tablePages}
                </span>
                <button type="button" className="logs-page-btn" onClick={() => setTablePage((page) => Math.min(page + 1, tablePages - 1))}>
                  Next
                </button>
              </div>
            </div>
          ) : null}
        </div>
      </section>
    </main>
  );
}

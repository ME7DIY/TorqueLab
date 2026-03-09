import { useState } from "react";
import { convertPressure, convertSpeed, pressureUnitLabel, speedUnitLabel } from "../utils/dashboard.js";

function formatValue(value, digits = 3) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return "--";
  }

  return value.toFixed(digits);
}

function formatDebugValue(value) {
  if (typeof value === "number") {
    const normalized = Math.abs(value) < 0.0001 ? 0 : value;
    return Number.isInteger(normalized) ? String(normalized) : normalized.toFixed(4);
  }

  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }

  if (value == null || value === "") {
    return "--";
  }

  return String(value);
}

function CornerRow({ label, values, digits = 3 }) {
  return (
    <div className="phase2-corner-card">
      <div className="phase2-card-label">{label}</div>
      <div className="phase2-corner-grid">
        <div className="phase2-corner-cell">
          <span className="phase2-corner-name">FL</span>
          <span className="phase2-corner-value">{formatValue(values?.fl, digits)}</span>
        </div>
        <div className="phase2-corner-cell">
          <span className="phase2-corner-name">FR</span>
          <span className="phase2-corner-value">{formatValue(values?.fr, digits)}</span>
        </div>
        <div className="phase2-corner-cell">
          <span className="phase2-corner-name">RL</span>
          <span className="phase2-corner-value">{formatValue(values?.rl, digits)}</span>
        </div>
        <div className="phase2-corner-cell">
          <span className="phase2-corner-name">RR</span>
          <span className="phase2-corner-value">{formatValue(values?.rr, digits)}</span>
        </div>
      </div>
    </div>
  );
}

function MetricCard({ label, value, unit, digits = 3 }) {
  return (
    <div className="phase2-metric-card">
      <div className="phase2-card-label">{label}</div>
      <div className="phase2-metric-value">{formatValue(value, digits)}</div>
      <div className="phase2-metric-unit">{unit}</div>
    </div>
  );
}

function DebugRow({ label, value }) {
  return (
    <div className="phase2-debug-row">
      <span className="phase2-debug-label">{label}</span>
      <span className="phase2-debug-value">{formatDebugValue(value)}</span>
    </div>
  );
}

export function ExtendedTelemetryDashboard({ telemetry, connected, displaySettings }) {
  const [showDebug, setShowDebug] = useState(false);
  const extended = telemetry.extended ?? {};
  const debug = extended.debug ?? {};
  const electrics = debug.electrics ?? {};
  const frontLeftWheel = debug.frontLeftWheel ?? {};
  const wheelIdSummary = `FL:${debug.wheelIdMap?.FL ?? "--"} FR:${debug.wheelIdMap?.FR ?? "--"} RL:${debug.wheelIdMap?.RL ?? "--"} RR:${debug.wheelIdMap?.RR ?? "--"}`;
  const wheelSpeeds = extended.wheelSpeeds
    ? {
        fl: convertSpeed(Number(extended.wheelSpeeds.fl ?? 0), displaySettings.speedUnit),
        fr: convertSpeed(Number(extended.wheelSpeeds.fr ?? 0), displaySettings.speedUnit),
        rl: convertSpeed(Number(extended.wheelSpeeds.rl ?? 0), displaySettings.speedUnit),
        rr: convertSpeed(Number(extended.wheelSpeeds.rr ?? 0), displaySettings.speedUnit),
      }
    : null;
  const boostActual = convertPressure(Number(extended.boostCurve?.actualBar ?? 0), displaySettings.pressureUnit);
  const boostTarget = convertPressure(Number(extended.boostCurve?.targetBar ?? 0), displaySettings.pressureUnit);

  return (
    <main className="phase2-page">
      <section className="phase2-hero">
        <div className="phase2-hero-block">
          <div className="phase2-hero-label">Phase 2 Feed</div>
          <div className="phase2-hero-status">{connected ? "LIVE" : "WAITING"}</div>
          <div className="phase2-hero-sub">{"BeamNG Lua -> UDP 4445 -> WebSocket 8765"}</div>
        </div>
        <div className="phase2-hero-block">
          <div className="phase2-hero-label">Vehicle ID</div>
          <div className="phase2-hero-number">{extended.vehicleId ?? telemetry.vehicleId ?? "--"}</div>
        </div>
      </section>

      <section className="phase2-grid">
        <CornerRow label={`Wheel Speeds (${speedUnitLabel(displaySettings.speedUnit, { short: true })})`} values={wheelSpeeds} digits={2} />
        <CornerRow label="Suspension Travel" values={extended.suspensionTravel} digits={4} />

        <MetricCard label="Torque" value={extended.torqueNm} unit="Nm" digits={1} />
        <MetricCard label="Gear Ratio" value={extended.gearRatio} unit="ratio" digits={3} />
        <MetricCard label="Boost Actual" value={boostActual} unit={pressureUnitLabel(displaySettings.pressureUnit, { short: true })} digits={3} />
        <MetricCard label="Boost Target" value={boostTarget} unit={pressureUnitLabel(displaySettings.pressureUnit, { short: true })} digits={3} />
        <div className="phase2-debug-card">
          <div className="phase2-debug-header">
            <div className="phase2-card-label">Diagnostics</div>
            <button
              type="button"
              className={`phase2-debug-toggle${showDebug ? " active" : ""}`}
              onClick={() => setShowDebug((current) => !current)}
            >
              {showDebug ? "HIDE DEBUG" : "SHOW DEBUG"}
            </button>
          </div>
          <div className="phase2-debug-summary">
            <DebugRow label="Engine Found" value={String(debug.engineFound)} />
            <DebugRow label="Gearbox Found" value={String(debug.gearboxFound)} />
            <DebugRow label="Wheel IDs" value={wheelIdSummary} />
            <DebugRow label="Controller Gear" value={debug.controllerGearIndex} />
            <DebugRow label="Indexed Ratio" value={debug.gearboxIndexedRatio} />
            <DebugRow label="Object Speed" value={debug.objectSpeed} />
          </div>
          {showDebug ? (
            <div className="phase2-debug-grid">
              <DebugRow label="Gear Index" value={debug.gearboxGearIndex} />
              <DebugRow label="Gear Ratio Raw" value={debug.gearboxGearRatio} />
              <DebugRow label="Engine Torque Raw" value={debug.engineTorque} />
              <DebugRow label="Engine Output Tq" value={debug.engineOutputTorque} />
              <DebugRow label="Electrics Gear" value={electrics.gearIndex} />
              <DebugRow label="Electrics Speed" value={electrics.wheelspeed} />
              <DebugRow label="Electrics Boost" value={electrics.boost} />
              <DebugRow label="Turbo Boost" value={electrics.turboBoost} />
              <DebugRow label="FL Name" value={frontLeftWheel.name} />
              <DebugRow label="FL WheelSpeed" value={frontLeftWheel.wheelSpeed} />
              <DebugRow label="FL AngularVel" value={frontLeftWheel.angularVelocity} />
              <DebugRow label="FL Susp Len" value={frontLeftWheel.suspensionLength} />
              <DebugRow label="FL Spring Len" value={frontLeftWheel.springLength} />
              <DebugRow label="FL Compression" value={frontLeftWheel.compression} />
              <DebugRow label="FL Susp Comp" value={frontLeftWheel.suspensionCompression} />
              <DebugRow label="FL Spring Comp" value={frontLeftWheel.springCompression} />
              <DebugRow label="FL Ray Len" value={frontLeftWheel.rayLen} />
            </div>
          ) : null}
        </div>
      </section>
    </main>
  );
}

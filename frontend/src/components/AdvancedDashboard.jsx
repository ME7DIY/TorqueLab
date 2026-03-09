import { RPMGauge } from "./RPMGauge.jsx";
import { WarningLights } from "./WarningLights.jsx";

function TelemetryLane({ title, unit, items, tone = "cyan", subPrefix = "raw" }) {
  return (
    <section className="advanced-lane">
      <div className="advanced-lane-header">
        <div className="advanced-lane-title">{title}</div>
        <div className="advanced-lane-unit">{unit}</div>
      </div>
      <div className="advanced-lane-grid">
        {items.map((item) => (
          <div key={item.id} className="advanced-lane-card">
            <div className="advanced-lane-top">
              <span className="advanced-corner-label">{item.label}</span>
              <span className="advanced-corner-value">{item.value}</span>
            </div>
            <div className="advanced-lane-track">
              <div
                className={`advanced-lane-fill ${tone}`}
                style={{ width: `${item.percent}%` }}
              />
            </div>
            {item.signed ? <div className="advanced-lane-sub">{subPrefix} {item.signed}</div> : null}
          </div>
        ))}
      </div>
    </section>
  );
}

function RailMetric({ label, value, unit, accent = "cyan", sub = "" }) {
  return (
    <div className="advanced-rail-card">
      <div className="advanced-rail-label">{label}</div>
      <div className={`advanced-rail-value ${accent}`}>{value}</div>
      <div className="advanced-rail-unit">{unit}</div>
      {sub ? <div className="advanced-rail-sub">{sub}</div> : null}
    </div>
  );
}

export function AdvancedDashboard({ model }) {
  const advanced = model.advanced;

  return (
    <main className="advanced-grid">
      <section className="advanced-left">
        <div className="advanced-hero">
          <div className="advanced-rpm-wrap">
            <RPMGauge model={model.rpmGauge} />
          </div>

          <div className="advanced-center-readouts">
            <div className="advanced-gear-card">
              <div className="advanced-hero-label">Current Gear</div>
              <div className="advanced-gear-value" style={{ color: `var(--${model.gear.tone})` }}>
                {model.gear.value}
              </div>
            </div>

            <div className="advanced-speed-card">
              <div className="advanced-hero-label">Vehicle Speed</div>
              <div className="advanced-speed-value">{model.speed.value}</div>
              <div className="advanced-speed-unit">{model.units.speed}</div>
            </div>
          </div>
        </div>

        <div className="advanced-telemetry-stack">
          <TelemetryLane title="Wheel Speed Split" unit={model.units.speedShort} items={advanced.wheelSpeeds} tone="cyan" />
          <TelemetryLane title="Suspension Motion" unit="mm" items={advanced.suspension} tone="amber" subPrefix="signed" />
        </div>

        <WarningLights warnings={model.warnings} />
      </section>

      <aside className="advanced-rail">
        <RailMetric
          label="Drive Torque"
          value={advanced.driveTorque.value}
          unit="Nm"
          accent="amber"
          sub={`signed ${advanced.driveTorque.signedValue}`}
        />
        <RailMetric label="Gear Ratio" value={advanced.gearRatio.value} unit="ratio" accent="cyan" />
        <RailMetric label="Boost Actual" value={advanced.boostActual.value} unit={model.units.pressureShort} accent="green" />
        <RailMetric label="Boost Target" value={advanced.boostTarget.value} unit={model.units.pressureShort} accent="text" />
        <RailMetric label="Wheel Delta" value={advanced.wheelDelta.value} unit={model.units.speedShort} accent="red" />

        <div className="advanced-pedal-card">
          {model.pedals.map((pedal) => (
            <div className="advanced-pedal-row" key={pedal.label}>
              <span className="advanced-pedal-label">{pedal.label}</span>
              <div className="advanced-pedal-track">
                <div className={`advanced-pedal-fill ${pedal.className}`} style={{ width: `${pedal.value}%` }} />
              </div>
              <span className="advanced-pedal-value">{pedal.displayValue}</span>
            </div>
          ))}
        </div>
      </aside>
    </main>
  );
}

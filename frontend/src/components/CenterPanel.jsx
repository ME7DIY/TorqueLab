import { RPMGauge } from "./RPMGauge.jsx";
import { WarningLights } from "./WarningLights.jsx";

function StatCell({ value, label, sub, tone = "text" }) {
  return (
    <div className="stat-cell">
      <div className="stat-val" style={{ color: `var(--${tone})` }}>
        {value}
      </div>
      <div className="stat-lbl">{label}</div>
      <div className="stat-sub">{sub}</div>
    </div>
  );
}

export function CenterPanel({ model }) {
  return (
    <section className="center">
      <div className="center-cluster">
        <RPMGauge model={model.rpmGauge} />

        <div className="center-mid">
          <div className="gear-display">
            <div className="gear-label">GEAR</div>
            <div className="gear-number" style={{ color: `var(--${model.gear.tone})` }}>
              {model.gear.value}
            </div>
          </div>
          <div className="speed-display">
            <div className="speed-number">{model.speed.value}</div>
            <div className="speed-unit">{model.units.speed}</div>
          </div>
        </div>
      </div>

      <div className="stat-row stat-strip">
        <StatCell value={model.boost.value} label="Boost" sub={model.units.pressure} tone={model.boost.tone} />
        <StatCell value={model.engineTemp.value} label="H2O Temp" sub="C" tone={model.engineTemp.tone} />
        <StatCell value={model.oilTemp.value} label="Oil Temp" sub="C" tone={model.oilTemp.tone} />
        <StatCell value={model.fuel.value} label="Fuel" sub="%" tone={model.fuel.tone} />
      </div>

      <WarningLights warnings={model.warnings} />
    </section>
  );
}

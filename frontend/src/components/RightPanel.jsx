function PedalGauge({ label, value, percent, tone }) {
  return (
    <div className="bar-block">
      <div className="bar-header">
        <span className="bar-label">{label}</span>
        <span>
          <span className="bar-value">{value}</span>
          <span className="bar-unit">%</span>
        </span>
      </div>
      <div>
        <div className="bar-track">
          <div
            className="bar-fill"
            style={{ width: `${percent}%`, background: `var(--${tone})` }}
          />
        </div>
        <div className="bar-minmax">
          <span>0</span>
          <span></span>
          <span>100</span>
        </div>
      </div>
    </div>
  );
}

export function RightPanel({ model }) {
  return (
    <section className="side">
      <div className="bar-block rpm-column">
        <div className="bar-header section-gap">
          <span className="bar-label">RPM</span>
          <span>
            <span className="bar-value">{model.rpmGauge.value}</span>
            <span className="bar-unit">rpm</span>
          </span>
        </div>
        <div className="vertical-rpm-track">
          <div
            className="vertical-rpm-fill"
            style={{
              height: `${model.rpmGauge.percent}%`,
              background: `var(--${model.rpmGauge.tone})`,
            }}
          />
          <div className="vertical-rpm-marker" />
        </div>
        <div className="bar-minmax section-gap-top">
          <span>0</span>
          <span>REDLINE 7k</span>
          <span>8000</span>
        </div>
      </div>

      <PedalGauge
        label="Throttle"
        value={model.throttle.value}
        percent={model.throttle.percent}
        tone="green"
      />
      <PedalGauge
        label="Brake"
        value={model.brake.value}
        percent={model.brake.percent}
        tone="red"
      />
      <PedalGauge
        label="Clutch"
        value={model.clutch.value}
        percent={model.clutch.percent}
        tone="amber"
      />

      <div className="bar-block speed-card">
        <div className="speed-card-label">SPEED</div>
        <div className="speed-card-value">{model.speed.value}</div>
        <div className="speed-card-unit">{model.units.speed}</div>
      </div>
    </section>
  );
}

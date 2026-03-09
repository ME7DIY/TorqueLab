function GaugeBlock({ label, value, unit, percent, minLabel, midLabel, maxLabel, tone }) {
  return (
    <div className="bar-block">
      <div className="bar-header">
        <span className="bar-label">{label}</span>
        <span>
          <span className="bar-value">{value}</span>
          <span className="bar-unit">{unit}</span>
        </span>
      </div>
      <div>
        <div className="bar-track">
          <div
            className="bar-fill"
            style={{
              width: `${percent}%`,
              background: `var(--${tone})`,
            }}
          />
        </div>
        <div className="bar-minmax">
          <span>{minLabel}</span>
          <span>{midLabel}</span>
          <span>{maxLabel}</span>
        </div>
      </div>
    </div>
  );
}

export function LeftPanel({ model }) {
  return (
    <section className="side">
      <GaugeBlock
        label="Water Temp"
        value={model.engineTemp.value}
        unit="C"
        percent={model.engineTemp.percent}
        minLabel="40"
        midLabel="WARN 100"
        maxLabel="130"
        tone={model.engineTemp.tone}
      />
      <GaugeBlock
        label="Oil Temp"
        value={model.oilTemp.value}
        unit="C"
        percent={model.oilTemp.percent}
        minLabel="40"
        midLabel="WARN 110"
        maxLabel="140"
        tone={model.oilTemp.tone}
      />
      <GaugeBlock
        label="Boost"
        value={model.boost.value}
        unit={model.units.pressureShort}
        percent={model.boost.percent}
        minLabel={model.boost.minLabel}
        midLabel=""
        maxLabel={model.boost.maxLabel}
        tone={model.boost.tone}
      />
      <GaugeBlock
        label="Fuel Level"
        value={model.fuel.value}
        unit="%"
        percent={model.fuel.percent}
        minLabel="0"
        midLabel="LOW 15%"
        maxLabel="100"
        tone={model.fuel.tone}
      />

      <div className="pedal-block pedal-grow">
        {model.pedals.map((pedal) => (
          <div className="pedal-row" key={pedal.label}>
            <span className="pedal-name">{pedal.label}</span>
            <div className="pedal-track">
              <div
                className={`pedal-fill ${pedal.className}`}
                style={{ width: `${pedal.value}%` }}
              />
            </div>
            <span className="pedal-num">{pedal.displayValue}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

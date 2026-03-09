import { RPMGauge } from "./RPMGauge.jsx";
import { WarningLights } from "./WarningLights.jsx";

const MINI_GAUGE = {
  width: 220,
  height: 176,
  centerX: 110,
  centerY: 106,
  radius: 74,
  startDegrees: 205,
  endDegrees: 335,
  valueX: 154,
  valueY: 98,
  labelY: 123,
  unitY: 137,
};

function polarToXY(degrees, radius) {
  const radians = ((degrees - 90) * Math.PI) / 180;
  return {
    x: MINI_GAUGE.centerX + radius * Math.cos(radians),
    y: MINI_GAUGE.centerY + radius * Math.sin(radians),
  };
}

function miniArcPath(startDegrees, endDegrees, radius) {
  const start = polarToXY(startDegrees, radius);
  const end = polarToXY(endDegrees, radius);
  const largeArc = endDegrees - startDegrees > 180 ? 1 : 0;
  return `M ${start.x} ${start.y} A ${radius} ${radius} 0 ${largeArc} 1 ${end.x} ${end.y}`;
}

function gaugeToneClass(tone) {
  if (tone === "red") {
    return "crit";
  }
  if (tone === "amber") {
    return "warn";
  }
  return "";
}

function ElectronicGauge({ label, value, unit, percent, tone, minLabel, maxLabel }) {
  const boundedPercent = Math.max(0, Math.min(100, percent));
  const sweep = MINI_GAUGE.endDegrees - MINI_GAUGE.startDegrees;
  const endDegrees = MINI_GAUGE.startDegrees + (boundedPercent / 100) * sweep;
  const minAnchor = polarToXY(MINI_GAUGE.startDegrees, MINI_GAUGE.radius);
  const maxAnchor = polarToXY(MINI_GAUGE.endDegrees, MINI_GAUGE.radius);
  const minLabelPosition = {
    x: minAnchor.x + 18,
    y: minAnchor.y + 18,
  };
  const maxLabelPosition = {
    x: maxAnchor.x + 10,
    y: maxAnchor.y - 10,
  };

  return (
    <article className="multi-electronic-gauge">
      <div className="multi-electronic-canvas">
        <svg
          viewBox={`0 0 ${MINI_GAUGE.width} ${MINI_GAUGE.height}`}
          className="multi-electronic-svg"
          preserveAspectRatio="xMidYMid meet"
        >
          <path
            className="multi-electronic-track"
            d={miniArcPath(MINI_GAUGE.startDegrees, MINI_GAUGE.endDegrees, MINI_GAUGE.radius)}
          />
          <path
            className={`multi-electronic-fill ${gaugeToneClass(tone)}`}
            d={
              boundedPercent > 0
                ? miniArcPath(MINI_GAUGE.startDegrees, endDegrees, MINI_GAUGE.radius)
                : ""
            }
          />
          <text
            x={MINI_GAUGE.valueX}
            y={MINI_GAUGE.valueY}
            textAnchor="middle"
            dominantBaseline="central"
            className="multi-electronic-value-text"
          >
            {value}
          </text>
          <text
            x={MINI_GAUGE.valueX}
            y={MINI_GAUGE.labelY + 4}
            textAnchor="middle"
            dominantBaseline="central"
            className="multi-electronic-label-text"
          >
            {label.toUpperCase()}
          </text>
          <text
            x={MINI_GAUGE.valueX}
            y={MINI_GAUGE.unitY + 4}
            textAnchor="middle"
            dominantBaseline="central"
            className="multi-electronic-unit-text"
          >
            {unit}
          </text>
          <text
            x={minLabelPosition.x}
            y={minLabelPosition.y}
            textAnchor="middle"
            dominantBaseline="central"
            className="multi-electronic-scale-text"
          >
            {minLabel}
          </text>
          <text
            x={maxLabelPosition.x}
            y={maxLabelPosition.y}
            textAnchor="middle"
            dominantBaseline="central"
            className="multi-electronic-scale-text"
          >
            {maxLabel}
          </text>
        </svg>
      </div>
    </article>
  );
}

export function MultiGaugeDashboard({ model }) {
  return (
    <main className="multi-dash">
      <section className="multi-hero">
        <div className="multi-rpm-panel">
          <div className="multi-rpm-gauge">
            <RPMGauge model={model.rpmGauge} />
          </div>
        </div>
        <div className="multi-core-panel">
          <div className="multi-core-label">CURRENT GEAR</div>
          <div className="multi-core-gear" style={{ color: `var(--${model.gear.tone})` }}>
            {model.gear.value}
          </div>
          <div className="multi-core-divider" />
          <div className="multi-core-label">SPEED</div>
          <div className="multi-core-speed">{model.speed.value}</div>
          <div className="multi-core-unit">{model.units.speed}</div>
        </div>
      </section>

      <section className="multi-gauge-grid">
        <ElectronicGauge label="Boost" value={model.boost.value} unit={model.units.pressureShort} percent={model.boost.percent} tone={model.boost.tone} minLabel={model.boost.minLabel} maxLabel={model.boost.maxLabel} />
        <ElectronicGauge label="Water Temp" value={model.engineTemp.value} unit="C" percent={model.engineTemp.percent} tone={model.engineTemp.tone} minLabel="40" maxLabel="130" />
        <ElectronicGauge label="Oil Temp" value={model.oilTemp.value} unit="C" percent={model.oilTemp.percent} tone={model.oilTemp.tone} minLabel="40" maxLabel="140" />
        <ElectronicGauge label="Fuel" value={model.fuel.value} unit="%" percent={model.fuel.percent} tone={model.fuel.tone} minLabel="0" maxLabel="100" />
        <ElectronicGauge label="Throttle" value={model.throttle.value} unit="%" percent={model.throttle.percent} tone="green" minLabel="0" maxLabel="100" />
        <ElectronicGauge label="Brake" value={model.brake.value} unit="%" percent={model.brake.percent} tone="red" minLabel="0" maxLabel="100" />
        <ElectronicGauge label="Clutch" value={model.clutch.value} unit="%" percent={model.clutch.percent} tone="amber" minLabel="0" maxLabel="100" />
        <ElectronicGauge label="RPM Load" value={model.rpmGauge.value} unit="rpm" percent={model.rpmGauge.percent} tone={model.rpmGauge.tone} minLabel="0" maxLabel="8k" />
      </section>

      <WarningLights warnings={model.warnings} />
    </main>
  );
}

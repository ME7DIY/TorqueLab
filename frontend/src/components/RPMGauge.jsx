import { MAX_RPM, arcPath, createRpmTicks } from "../utils/dashboard.js";

export function RPMGauge({ model }) {
  const ticks = createRpmTicks();

  return (
    <div className="rpm-wrap">
      <svg className="rpm-svg" viewBox="0 0 300 175">
        <g className="rpm-ticks">
          {ticks.map((tick) => (
            <g key={tick.label}>
              <line
                x1={tick.inner.x}
                y1={tick.inner.y}
                x2={tick.outer.x}
                y2={tick.outer.y}
                stroke={tick.stroke}
                strokeWidth="2"
              />
              <text
                x={tick.labelPoint.x}
                y={tick.labelPoint.y}
                textAnchor="middle"
                fill={tick.textColor}
                fontSize="11"
                fontWeight="700"
              >
                {tick.label}
              </text>
            </g>
          ))}
        </g>
        <path className="rpm-track" d={arcPath(200, 340, 130)} />
        <path className={`rpm-fill ${model.toneClass}`} d={model.arcPath} />
      </svg>
      <div className="rpm-center">
        <div className="rpm-number">{model.value}</div>
        <div className="rpm-label">RPM</div>
      </div>
      <div className="rpm-cap">{MAX_RPM.toLocaleString()} max</div>
    </div>
  );
}

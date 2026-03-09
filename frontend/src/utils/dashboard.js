export const MAX_RPM = 8000;
export const DEFAULT_DISPLAY_SETTINGS = {
  speedUnit: "kph",
  pressureUnit: "bar",
};

const START_DEG = 200;
const END_DEG = 340;
const CX = 150;
const CY = 165;
const R = 130;
const SHIFT_THRESHOLDS = [0.55, 0.6, 0.65, 0.7, 0.74, 0.78, 0.82, 0.86, 0.89, 0.92, 0.95, 0.98];
const MAX_WHEEL_SPEED_KPH = 260;
const MAX_SUSPENSION_TRAVEL = 0.12;
const KPH_TO_MPH = 0.621371;
const BAR_TO_PSI = 14.5038;

export const DEFAULT_TELEMETRY = {
  rpm: 0,
  speed: 0,
  gear: 1,
  turbo: 0,
  engtemp: 0,
  oiltemp: 0,
  fuel: 0,
  throttle: 0,
  brake: 0,
  clutch: 0,
  showLights: 0,
  extended: {},
};

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value));
}

function formatExtendedNumber(value, digits = 2) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return "--";
  }

  return value.toFixed(digits);
}

function metersToMillimeters(value) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return null;
  }

  return value * 1000;
}

function sanitizeBoostTarget(value) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return null;
  }

  if (value < -1 || value > 4) {
    return null;
  }

  return value;
}

export function convertSpeed(value, speedUnit = "kph") {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return value;
  }

  return speedUnit === "mph" ? value * KPH_TO_MPH : value;
}

export function convertPressure(value, pressureUnit = "bar") {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return value;
  }

  return pressureUnit === "psi" ? value * BAR_TO_PSI : value;
}

export function speedUnitLabel(speedUnit = "kph", { short = false } = {}) {
  if (speedUnit === "mph") {
    return short ? "mph" : "MPH";
  }
  return short ? "km/h" : "KM/H";
}

export function pressureUnitLabel(pressureUnit = "bar", { short = false } = {}) {
  if (pressureUnit === "psi") {
    return short ? "psi" : "PSI";
  }
  return short ? "bar" : "BAR";
}

export function polarToXY(deg, radius) {
  const radians = ((deg - 90) * Math.PI) / 180;
  return {
    x: CX + radius * Math.cos(radians),
    y: CY + radius * Math.sin(radians),
  };
}

export function arcPath(startDeg, endDeg, radius) {
  const start = polarToXY(startDeg, radius);
  const end = polarToXY(endDeg, radius);
  const largeArc = endDeg - startDeg > 180 ? 1 : 0;
  return `M ${start.x} ${start.y} A ${radius} ${radius} 0 ${largeArc} 1 ${end.x} ${end.y}`;
}

export function createRpmTicks() {
  return Array.from({ length: 9 }, (_, index) => {
    const fraction = index / 8;
    const degrees = START_DEG + fraction * (END_DEG - START_DEG);
    const labelPoint = polarToXY(degrees, R - 32);

    return {
      label: index,
      inner: polarToXY(degrees, R - 18),
      outer: polarToXY(degrees, R + 2),
      labelPoint: { x: labelPoint.x, y: labelPoint.y + 4 },
      stroke: index >= 7 ? "#ff3a3a" : "#2a2f3a",
      textColor: index >= 7 ? "#ff3a3a" : "#3a4050",
    };
  });
}

function gearLabel(gear) {
  if (gear <= 0) {
    return "R";
  }
  if (gear === 1) {
    return "N";
  }
  return String(gear - 1);
}

function gearTone(label) {
  if (label === "R") {
    return "red";
  }
  if (label === "N") {
    return "amber";
  }
  return "cyan";
}

function warningTone(value, warnAt, critAt) {
  if (value >= critAt) {
    return "red";
  }
  if (value >= warnAt) {
    return "amber";
  }
  return "green";
}

function fuelTone(percent) {
  if (percent <= 10) {
    return "red";
  }
  if (percent <= 20) {
    return "amber";
  }
  return "text";
}

function rpmTone(rpm) {
  if (rpm > 7000) {
    return { tone: "red", toneClass: "crit" };
  }
  if (rpm > 5500) {
    return { tone: "amber", toneClass: "warn" };
  }
  return { tone: "cyan", toneClass: "" };
}

function shiftLights(rpm) {
  const fraction = rpm / MAX_RPM;
  return SHIFT_THRESHOLDS.map((threshold, index) => {
    if (fraction < threshold) {
      return "";
    }
    if (index < 4) {
      return "on-g";
    }
    if (index < 8) {
      return "on-a";
    }
    return "on-r";
  });
}

export function buildDashboardModel(frame, hasTelemetry = false, settings = DEFAULT_DISPLAY_SETTINGS) {
  const rpm = clamp(frame.rpm ?? 0, 0, MAX_RPM);
  const speed = convertSpeed(Number(frame.speed ?? 0), settings.speedUnit);
  const boost = Number(frame.turbo ?? 0);
  const engineTemp = Math.round(frame.engtemp ?? 0);
  const oilTemp = Math.round(frame.oiltemp ?? 0);
  const fuelPercent = clamp(Math.round((frame.fuel ?? 0) * 100), 0, 100);
  const throttle = clamp(Math.round((frame.throttle ?? 0) * 100), 0, 100);
  const brake = clamp(Math.round((frame.brake ?? 0) * 100), 0, 100);
  const clutch = clamp(Math.round((frame.clutch ?? 0) * 100), 0, 100);
  const currentGearLabel = gearLabel(frame.gear ?? 1);
  const rpmState = rpmTone(rpm);
  const rpmPercent = clamp((rpm / MAX_RPM) * 100, 0, 100);
  const rpmEndDeg = START_DEG + (rpm / MAX_RPM) * (END_DEG - START_DEG);
  const showLights = frame.showLights ?? 0;
  const extended = frame.extended ?? {};
  const wheelSpeeds = extended.wheelSpeeds ?? {};
  const suspensionTravel = extended.suspensionTravel ?? {};
  const driveTorque = Math.max(Number(extended.torqueNm ?? 0), 0);
  const signedTorque = Number(extended.torqueNm ?? 0);
  const gearRatio = Number(extended.gearRatio ?? 0);
  const boostActual = Number(extended.boostCurve?.actualBar ?? 0);
  const boostTarget = sanitizeBoostTarget(Number(extended.boostCurve?.targetBar ?? 0));
  const wheelSpeedValues = [wheelSpeeds.fl, wheelSpeeds.fr, wheelSpeeds.rl, wheelSpeeds.rr]
    .filter((value) => typeof value === "number" && !Number.isNaN(value));
  const suspensionValues = [suspensionTravel.fl, suspensionTravel.fr, suspensionTravel.rl, suspensionTravel.rr]
    .filter((value) => typeof value === "number" && !Number.isNaN(value));
  const maxWheelSpeed = wheelSpeedValues.length ? Math.max(...wheelSpeedValues) : 0;
  const minWheelSpeed = wheelSpeedValues.length ? Math.min(...wheelSpeedValues) : 0;
  const wheelDelta = maxWheelSpeed - minWheelSpeed;
  const maxSuspension = suspensionValues.length
    ? Math.max(...suspensionValues.map((value) => Math.abs(value)))
    : 0;
  const displayBoost = convertPressure(boost, settings.pressureUnit);
  const displayBoostActual = convertPressure(boost, settings.pressureUnit);
  const displayBoostTarget = boostTarget == null ? null : convertPressure(boostTarget, settings.pressureUnit);
  const boostMin = convertPressure(-0.5, settings.pressureUnit);
  const boostMax = convertPressure(2.5, settings.pressureUnit);
  const wheelDeltaDisplay = convertSpeed(wheelDelta, settings.speedUnit);

  return {
    hasTelemetry,
    units: {
      speed: speedUnitLabel(settings.speedUnit),
      speedShort: speedUnitLabel(settings.speedUnit, { short: true }),
      pressure: pressureUnitLabel(settings.pressureUnit),
      pressureShort: pressureUnitLabel(settings.pressureUnit, { short: true }),
    },
    shiftLights: shiftLights(rpm),
    rpmGauge: {
      value: hasTelemetry ? Math.round(rpm).toLocaleString() : "--",
      percent: rpmPercent,
      tone: rpmState.tone,
      toneClass: rpmState.toneClass,
      arcPath: hasTelemetry && rpm > 0 ? arcPath(START_DEG, rpmEndDeg, R) : "",
    },
    gear: {
      value: hasTelemetry ? currentGearLabel : "--",
      tone: hasTelemetry ? gearTone(currentGearLabel) : "text-dim",
    },
    speed: {
      value: hasTelemetry ? Math.round(speed) : "--",
    },
    boost: {
      value: hasTelemetry ? displayBoost.toFixed(2) : "--",
      percent: clamp(((boost + 0.5) / 3) * 100, 0, 100),
      tone: boost > 1.8 ? "red" : boost > 1.2 ? "amber" : "green",
      minLabel: boostMin.toFixed(1),
      maxLabel: boostMax.toFixed(1),
    },
    engineTemp: {
      value: hasTelemetry ? engineTemp : "--",
      percent: clamp(((engineTemp - 40) / 90) * 100, 0, 100),
      tone: warningTone(engineTemp, 95, 105),
    },
    oilTemp: {
      value: hasTelemetry ? oilTemp : "--",
      percent: clamp(((oilTemp - 40) / 100) * 100, 0, 100),
      tone: warningTone(oilTemp, 105, 115),
    },
    fuel: {
      value: hasTelemetry ? fuelPercent : "--",
      percent: fuelPercent,
      tone: fuelTone(fuelPercent),
    },
    throttle: {
      percent: throttle,
      value: hasTelemetry ? throttle : "--",
    },
    brake: {
      percent: brake,
      value: hasTelemetry ? brake : "--",
    },
    clutch: {
      percent: clutch,
      value: hasTelemetry ? clutch : "--",
    },
    pedals: [
      { label: "THR", value: throttle, displayValue: hasTelemetry ? `${throttle}%` : "--", className: "thr" },
      { label: "BRK", value: brake, displayValue: hasTelemetry ? `${brake}%` : "--", className: "brk" },
      { label: "CLT", value: clutch, displayValue: hasTelemetry ? `${clutch}%` : "--", className: "clt" },
    ],
    warnings: [
      { id: "abs", label: "ABS", tone: "amber", active: hasTelemetry && Boolean(showLights & (1 << 10)) },
      { id: "oil", label: "OIL", tone: "red", active: hasTelemetry && Boolean(showLights & (1 << 8)) },
      { id: "bat", label: "BATT", tone: "amber", active: hasTelemetry && Boolean(showLights & (1 << 9)) },
      { id: "hbk", label: "HBK", tone: "red", active: hasTelemetry && Boolean(showLights & (1 << 2)) },
      { id: "shift", label: "SHIFT", tone: "green", active: hasTelemetry && Boolean(showLights & (1 << 0)) },
      { id: "sigl", label: "SIG-L", tone: "amber", active: hasTelemetry && Boolean(showLights & (1 << 5)) },
      { id: "sigr", label: "SIG-R", tone: "amber", active: hasTelemetry && Boolean(showLights & (1 << 6)) },
      { id: "beam", label: "BEAM", tone: "green", active: hasTelemetry && Boolean(showLights & (1 << 1)) },
      { id: "tc", label: "TC", tone: "amber", active: hasTelemetry && Boolean(showLights & (1 << 4)) },
    ],
    advanced: {
      wheelSpeeds: [
        {
          id: "fl",
          label: "FL",
          value: hasTelemetry ? formatExtendedNumber(convertSpeed(Number(wheelSpeeds.fl ?? 0), settings.speedUnit), 2) : "--",
          percent: clamp((Number(wheelSpeeds.fl ?? 0) / MAX_WHEEL_SPEED_KPH) * 100, 0, 100),
        },
        {
          id: "fr",
          label: "FR",
          value: hasTelemetry ? formatExtendedNumber(convertSpeed(Number(wheelSpeeds.fr ?? 0), settings.speedUnit), 2) : "--",
          percent: clamp((Number(wheelSpeeds.fr ?? 0) / MAX_WHEEL_SPEED_KPH) * 100, 0, 100),
        },
        {
          id: "rl",
          label: "RL",
          value: hasTelemetry ? formatExtendedNumber(convertSpeed(Number(wheelSpeeds.rl ?? 0), settings.speedUnit), 2) : "--",
          percent: clamp((Number(wheelSpeeds.rl ?? 0) / MAX_WHEEL_SPEED_KPH) * 100, 0, 100),
        },
        {
          id: "rr",
          label: "RR",
          value: hasTelemetry ? formatExtendedNumber(convertSpeed(Number(wheelSpeeds.rr ?? 0), settings.speedUnit), 2) : "--",
          percent: clamp((Number(wheelSpeeds.rr ?? 0) / MAX_WHEEL_SPEED_KPH) * 100, 0, 100),
        },
      ],
      suspension: [
        {
          id: "fl",
          label: "FL",
          value: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Math.abs(Number(suspensionTravel.fl ?? 0))), 1) : "--",
          signed: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Number(suspensionTravel.fl ?? 0)), 1) : "--",
          percent: clamp((Math.abs(Number(suspensionTravel.fl ?? 0)) / Math.max(maxSuspension, MAX_SUSPENSION_TRAVEL)) * 100, 0, 100),
        },
        {
          id: "fr",
          label: "FR",
          value: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Math.abs(Number(suspensionTravel.fr ?? 0))), 1) : "--",
          signed: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Number(suspensionTravel.fr ?? 0)), 1) : "--",
          percent: clamp((Math.abs(Number(suspensionTravel.fr ?? 0)) / Math.max(maxSuspension, MAX_SUSPENSION_TRAVEL)) * 100, 0, 100),
        },
        {
          id: "rl",
          label: "RL",
          value: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Math.abs(Number(suspensionTravel.rl ?? 0))), 1) : "--",
          signed: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Number(suspensionTravel.rl ?? 0)), 1) : "--",
          percent: clamp((Math.abs(Number(suspensionTravel.rl ?? 0)) / Math.max(maxSuspension, MAX_SUSPENSION_TRAVEL)) * 100, 0, 100),
        },
        {
          id: "rr",
          label: "RR",
          value: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Math.abs(Number(suspensionTravel.rr ?? 0))), 1) : "--",
          signed: hasTelemetry ? formatExtendedNumber(metersToMillimeters(Number(suspensionTravel.rr ?? 0)), 1) : "--",
          percent: clamp((Math.abs(Number(suspensionTravel.rr ?? 0)) / Math.max(maxSuspension, MAX_SUSPENSION_TRAVEL)) * 100, 0, 100),
        },
      ],
      driveTorque: {
        value: hasTelemetry ? formatExtendedNumber(driveTorque, 1) : "--",
        signedValue: hasTelemetry ? formatExtendedNumber(signedTorque, 1) : "--",
        percent: clamp(driveTorque / 800, 0, 1) * 100,
      },
      gearRatio: {
        value: hasTelemetry ? formatExtendedNumber(gearRatio, 3) : "--",
      },
      boostActual: {
        value: hasTelemetry ? formatExtendedNumber(displayBoostActual, 3) : "--",
      },
      boostTarget: {
        value: hasTelemetry && displayBoostTarget != null ? formatExtendedNumber(displayBoostTarget, 3) : "N/A",
      },
      wheelDelta: {
        value: hasTelemetry ? formatExtendedNumber(wheelDeltaDisplay, 2) : "--",
      },
    },
  };
}

import { useEffect, useRef, useState } from "react";
import { DEFAULT_TELEMETRY } from "../utils/dashboard.js";

const WS_URL = import.meta.env.VITE_TELEMETRY_URL ?? "ws://127.0.0.1:8765";
const EXTENDED_SMOOTHING = 0.18;
const EXTENDED_KEYS = ["fl", "fr", "rl", "rr"];

function formatSession(secondsElapsed) {
  const minutes = String(Math.floor(secondsElapsed / 60)).padStart(2, "0");
  const seconds = String(secondsElapsed % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function smoothNumber(previous, next, factor = EXTENDED_SMOOTHING) {
  if (typeof next !== "number" || Number.isNaN(next)) {
    return previous;
  }

  if (typeof previous !== "number" || Number.isNaN(previous)) {
    return next;
  }

  return previous + (next - previous) * factor;
}

function smoothCornerValues(previousGroup = {}, nextGroup = {}) {
  const smoothed = { ...nextGroup };

  for (const key of EXTENDED_KEYS) {
    smoothed[key] = smoothNumber(previousGroup?.[key], nextGroup?.[key]);
  }

  return smoothed;
}

function smoothExtended(previousExtended = {}, nextExtended = {}) {
  return {
    ...nextExtended,
    torqueNm: smoothNumber(previousExtended?.torqueNm, nextExtended?.torqueNm, 0.14),
    gearRatio: smoothNumber(previousExtended?.gearRatio, nextExtended?.gearRatio, 0.22),
    wheelSpeeds: smoothCornerValues(previousExtended?.wheelSpeeds, nextExtended?.wheelSpeeds),
    suspensionTravel: smoothCornerValues(previousExtended?.suspensionTravel, nextExtended?.suspensionTravel),
    boostCurve: {
      ...nextExtended?.boostCurve,
      actualBar: smoothNumber(previousExtended?.boostCurve?.actualBar, nextExtended?.boostCurve?.actualBar, 0.18),
      targetBar: smoothNumber(previousExtended?.boostCurve?.targetBar, nextExtended?.boostCurve?.targetBar, 0.22),
    },
  };
}

function mergeTelemetry(current, nextTelemetry) {
  const merged = { ...current, ...nextTelemetry };

  if (nextTelemetry?.extended) {
    merged.extended = smoothExtended(current?.extended, nextTelemetry.extended);
  }

  return merged;
}

export function useTelemetry() {
  const [telemetry, setTelemetry] = useState(DEFAULT_TELEMETRY);
  const [connected, setConnected] = useState(false);
  const [hasTelemetry, setHasTelemetry] = useState(false);
  const [sourceLabel, setSourceLabel] = useState("WAIT");
  const [sessionText, setSessionText] = useState("00:00");
  const hasTelemetryRef = useRef(false);

  useEffect(() => {
    const startedAt = Date.now();
    const timer = window.setInterval(() => {
      const elapsed = Math.floor((Date.now() - startedAt) / 1000);
      setSessionText(formatSession(elapsed));
    }, 1000);

    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    let ws;
    let reconnectTimer;
    let cancelled = false;

    const connect = () => {
      try {
        ws = new WebSocket(WS_URL);
      } catch {
        setConnected(false);
        setSourceLabel(hasTelemetryRef.current ? "LOST" : "WAIT");
        reconnectTimer = window.setTimeout(connect, 2000);
        return;
      }

      ws.onopen = () => {
        if (cancelled) {
          return;
        }
        setConnected(true);
        setSourceLabel(hasTelemetryRef.current ? "LIVE" : "WAIT");
      };

      ws.onmessage = (event) => {
        if (cancelled) {
          return;
        }
        try {
          const nextTelemetry = JSON.parse(event.data);
          setTelemetry((current) => mergeTelemetry(current, nextTelemetry));
          setConnected(true);
          hasTelemetryRef.current = true;
          setHasTelemetry(true);
          setSourceLabel("LIVE");
        } catch {
          // Ignore malformed frames and keep the last valid telemetry snapshot.
        }
      };

      ws.onerror = () => {
        ws.close();
      };

      ws.onclose = () => {
        if (cancelled) {
          return;
        }
        setConnected(false);
        setSourceLabel(hasTelemetryRef.current ? "LOST" : "WAIT");
        reconnectTimer = window.setTimeout(connect, 2000);
      };
    };

    connect();

    return () => {
      cancelled = true;
      window.clearTimeout(reconnectTimer);
      ws?.close();
    };
  }, []);

  return {
    telemetry,
    connected,
    hasTelemetry,
    sessionText,
    sourceLabel,
  };
}

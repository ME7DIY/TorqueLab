import { useEffect, useState } from "react";
import { AdvancedDashboard } from "./components/AdvancedDashboard.jsx";
import { ExtendedTelemetryDashboard } from "./components/ExtendedTelemetryDashboard.jsx";
import { FocusDashboard } from "./components/FocusDashboard.jsx";
import { LogsDashboard } from "./components/LogsDashboard.jsx";
import { MultiGaugeDashboard } from "./components/MultiGaugeDashboard.jsx";
import { SettingsModal } from "./components/SettingsModal.jsx";
import { TopBar } from "./components/TopBar.jsx";
import { useTelemetry } from "./hooks/useTelemetry.js";
import { buildDashboardModel, DEFAULT_DISPLAY_SETTINGS } from "./utils/dashboard.js";

const SETTINGS_STORAGE_KEY = "torquelab-display-settings";

export default function App() {
  const [preset, setPreset] = useState("focus");
  const [diagnosticsUnlocked, setDiagnosticsUnlocked] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [displaySettings, setDisplaySettings] = useState(() => {
    try {
      const stored = window.localStorage.getItem(SETTINGS_STORAGE_KEY);
      return stored ? { ...DEFAULT_DISPLAY_SETTINGS, ...JSON.parse(stored) } : DEFAULT_DISPLAY_SETTINGS;
    } catch {
      return DEFAULT_DISPLAY_SETTINGS;
    }
  });
  const { telemetry, connected, hasTelemetry, sessionText, sourceLabel } = useTelemetry();
  const model = buildDashboardModel(telemetry, hasTelemetry, displaySettings);

  useEffect(() => {
    window.localStorage.setItem(SETTINGS_STORAGE_KEY, JSON.stringify(displaySettings));
  }, [displaySettings]);

  return (
    <div className="app-shell">
      <TopBar
        connected={connected}
        preset={preset}
        sessionText={sessionText}
        shiftLights={model.shiftLights}
        sourceLabel={sourceLabel}
        onPresetChange={setPreset}
        diagnosticsUnlocked={diagnosticsUnlocked}
        onDiagnosticsToggle={setDiagnosticsUnlocked}
        onSettingsOpen={() => setSettingsOpen(true)}
      />
      {preset === "advanced" && <AdvancedDashboard model={model} />}
      {preset === "focus" && <FocusDashboard model={model} />}
      {preset === "logs" && <LogsDashboard displaySettings={displaySettings} />}
      {preset === "multi" && <MultiGaugeDashboard model={model} />}
      {preset === "phase2" && <ExtendedTelemetryDashboard telemetry={telemetry} connected={connected} displaySettings={displaySettings} />}
      <SettingsModal
        open={settingsOpen}
        settings={displaySettings}
        onClose={() => setSettingsOpen(false)}
        onChange={(next) => setDisplaySettings((current) => ({ ...current, ...next }))}
      />
    </div>
  );
}

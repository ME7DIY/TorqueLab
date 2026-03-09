const PRESETS = [
  { id: "focus", label: "FOCUS" },
  { id: "advanced", label: "ADV" },
  { id: "multi", label: "MULTI" },
  { id: "logs", label: "LOGS" },
  { id: "phase2", label: "PHASE2" },
];

export function TopBar({
  connected,
  preset,
  sessionText,
  shiftLights,
  sourceLabel,
  onPresetChange,
  diagnosticsUnlocked,
  onDiagnosticsToggle,
  onSettingsOpen,
}) {
  const visiblePresets = PRESETS.filter((option) => {
    if (option.id !== "phase2") {
      return true;
    }

    return diagnosticsUnlocked || preset === "phase2";
  });

  function handleSettingsClick(event) {
    if (event.shiftKey) {
      onDiagnosticsToggle((current) => !current);
    }
    onSettingsOpen();
  }

  return (
    <header className="topbar">
      <div className="topbar-left">
        <div className="logo">
          TORQUE<span>LAB</span>
        </div>
        <div className="preset-switch" aria-label="Dashboard preset switch">
          {visiblePresets.map((option) => (
            <button
              key={option.id}
              type="button"
              className={`preset-chip${preset === option.id ? " active" : ""}`}
              onClick={() => onPresetChange(option.id)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      <div className="shiftbar" aria-label="Shift lights">
        {shiftLights.map((tone, index) => (
          <div key={index} className={`shiftled${tone ? ` ${tone}` : ""}`} />
        ))}
      </div>

      <div className="topright">
        <div>
          <span>SESSION</span> <span className="val">{sessionText}</span>
        </div>
        <div>
          <span>SOURCE</span> <span className="val">{sourceLabel}</span>
        </div>
        <button
          type="button"
          className={`settings-chip${diagnosticsUnlocked ? " unlocked" : ""}`}
          onClick={handleSettingsClick}
          title="Settings. Hold Shift while clicking to toggle diagnostics."
          aria-label="Open settings"
        >
          {String.fromCharCode(9881)}
        </button>
        <div
          className={`nodot${connected ? " connected" : ""}`}
          title={connected ? "Telemetry connected" : "Telemetry disconnected"}
        />
      </div>
    </header>
  );
}

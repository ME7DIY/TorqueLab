export function SettingsModal({ open, settings, onClose, onChange }) {
  if (!open) {
    return null;
  }

  return (
    <div className="settings-overlay" onClick={onClose} role="presentation">
      <div
        className="settings-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Display settings"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="settings-modal-header">
          <div>
            <div className="settings-modal-kicker">Display Settings</div>
            <div className="settings-modal-title">Units</div>
          </div>
          <button type="button" className="settings-close" onClick={onClose} aria-label="Close settings">
            x
          </button>
        </div>

        <div className="settings-group">
          <div className="settings-group-label">Speed</div>
          <div className="settings-option-row">
            <button
              type="button"
              className={`settings-option${settings.speedUnit === "kph" ? " active" : ""}`}
              onClick={() => onChange({ speedUnit: "kph" })}
            >
              KM/H
            </button>
            <button
              type="button"
              className={`settings-option${settings.speedUnit === "mph" ? " active" : ""}`}
              onClick={() => onChange({ speedUnit: "mph" })}
            >
              MPH
            </button>
          </div>
        </div>

        <div className="settings-group">
          <div className="settings-group-label">Pressure</div>
          <div className="settings-option-row">
            <button
              type="button"
              className={`settings-option${settings.pressureUnit === "bar" ? " active" : ""}`}
              onClick={() => onChange({ pressureUnit: "bar" })}
            >
              BAR
            </button>
            <button
              type="button"
              className={`settings-option${settings.pressureUnit === "psi" ? " active" : ""}`}
              onClick={() => onChange({ pressureUnit: "psi" })}
            >
              PSI
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

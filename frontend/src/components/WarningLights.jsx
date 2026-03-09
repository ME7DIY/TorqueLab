export function WarningLights({ warnings }) {
  return (
    <div className="warn-row">
      {warnings.map((warning) => (
        <div
          key={warning.id}
          className={[
            "warn-light",
            warning.active ? "active" : "",
            warning.active ? warning.tone : "",
          ]
            .filter(Boolean)
            .join(" ")}
        >
          <div className="warn-dot" />
          {warning.label}
        </div>
      ))}
    </div>
  );
}

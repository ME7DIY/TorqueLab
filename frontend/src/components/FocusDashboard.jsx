import { CenterPanel } from "./CenterPanel.jsx";
import { LeftPanel } from "./LeftPanel.jsx";
import { RightPanel } from "./RightPanel.jsx";

export function FocusDashboard({ model }) {
  return (
    <main className="main-grid">
      <LeftPanel model={model} />
      <CenterPanel model={model} />
      <RightPanel model={model} />
    </main>
  );
}

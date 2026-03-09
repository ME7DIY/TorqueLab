from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import csv
import json
from pathlib import Path

CSV_FIELDNAMES = [
    "loggedAt",
    "packetTime",
    "vehicleId",
    "car",
    "gear",
    "speed",
    "rpm",
    "turbo",
    "engtemp",
    "oiltemp",
    "fuel",
    "throttle",
    "brake",
    "clutch",
    "dashLights",
    "showLights",
    "extended_vehicleId",
    "extended_source",
    "extended_torqueNm",
    "extended_gearRatio",
    "wheelSpeed_fl",
    "wheelSpeed_fr",
    "wheelSpeed_rl",
    "wheelSpeed_rr",
    "suspension_fl",
    "suspension_fr",
    "suspension_rl",
    "suspension_rr",
    "boost_actualBar",
    "boost_targetBar",
]


def utc_timestamp() -> str:
    return datetime.utcnow().isoformat(timespec="milliseconds") + "Z"


def flatten_extended_group(group: object, prefix: str) -> dict[str, object]:
    if not isinstance(group, dict):
        return {}

    flat: dict[str, object] = {}
    for key, value in group.items():
        flat[f"{prefix}_{key}"] = value
    return flat


def build_csv_row(payload: dict[str, object]) -> dict[str, object]:
    extended = payload.get("extended")
    extended_payload = extended if isinstance(extended, dict) else {}

    row: dict[str, object] = {
        "loggedAt": utc_timestamp(),
        "packetTime": payload.get("packetTime"),
        "vehicleId": payload.get("vehicleId"),
        "car": payload.get("car"),
        "gear": payload.get("gear"),
        "speed": payload.get("speed"),
        "rpm": payload.get("rpm"),
        "turbo": payload.get("turbo"),
        "engtemp": payload.get("engtemp"),
        "oiltemp": payload.get("oiltemp"),
        "fuel": payload.get("fuel"),
        "throttle": payload.get("throttle"),
        "brake": payload.get("brake"),
        "clutch": payload.get("clutch"),
        "dashLights": payload.get("dashLights"),
        "showLights": payload.get("showLights"),
        "extended_vehicleId": extended_payload.get("vehicleId"),
        "extended_source": extended_payload.get("source"),
        "extended_torqueNm": extended_payload.get("torqueNm"),
        "extended_gearRatio": extended_payload.get("gearRatio"),
    }

    row.update(flatten_extended_group(extended_payload.get("wheelSpeeds"), "wheelSpeed"))
    row.update(flatten_extended_group(extended_payload.get("suspensionTravel"), "suspension"))
    row.update(flatten_extended_group(extended_payload.get("boostCurve"), "boost"))
    return row


@dataclass(slots=True)
class SessionFiles:
    session_id: str
    csv_path: Path
    jsonl_path: Path


class SessionLogger:
    def __init__(self, log_dir: str | Path) -> None:
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.files = SessionFiles(
            session_id=session_id,
            csv_path=self.log_dir / f"session_{session_id}.csv",
            jsonl_path=self.log_dir / f"session_{session_id}.jsonl",
        )
        self.csv_file = self.files.csv_path.open("w", encoding="utf-8", newline="")
        self.jsonl_file = self.files.jsonl_path.open("w", encoding="utf-8")
        self.csv_writer = csv.DictWriter(
            self.csv_file,
            fieldnames=CSV_FIELDNAMES,
            extrasaction="ignore",
        )
        self.csv_writer.writeheader()

    def write(self, payload: dict[str, object]) -> None:
        csv_row = build_csv_row(payload)
        self.csv_writer.writerow(csv_row)
        self.csv_file.flush()

        json.dump(
            {
                "loggedAt": utc_timestamp(),
                "payload": payload,
            },
            self.jsonl_file,
            separators=(",", ":"),
        )
        self.jsonl_file.write("\n")
        self.jsonl_file.flush()

    def close(self) -> None:
        self.csv_file.close()
        self.jsonl_file.close()

    def describe(self) -> dict[str, object]:
        return {
            "active": True,
            "sessionId": self.files.session_id,
            "csvPath": str(self.files.csv_path),
            "jsonlPath": str(self.files.jsonl_path),
        }

from __future__ import annotations

from dataclasses import dataclass
import json


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


@dataclass(slots=True)
class TelemetryFrame:
    packet_time: int
    car: str
    flags: int
    gear: int
    speed_kph: float
    rpm: float
    turbo_bar: float
    engine_temp_c: float
    fuel_fraction: float
    oil_temp_c: float
    dash_lights: int
    show_lights: int
    throttle: float
    brake: float
    clutch: float
    vehicle_id: int

    def as_payload(self) -> dict[str, float | int | str]:
        return {
            "packetTime": self.packet_time,
            "car": self.car,
            "flags": self.flags,
            "gear": self.gear,
            "speed": round(self.speed_kph, 3),
            "rpm": round(self.rpm, 3),
            "turbo": round(self.turbo_bar, 3),
            "engtemp": round(self.engine_temp_c, 3),
            "fuel": round(clamp(self.fuel_fraction, 0.0, 1.0), 5),
            "oiltemp": round(self.oil_temp_c, 3),
            "dashLights": self.dash_lights,
            "showLights": self.show_lights,
            "throttle": round(clamp(self.throttle, 0.0, 1.0), 5),
            "brake": round(clamp(self.brake, 0.0, 1.0), 5),
            "clutch": round(clamp(self.clutch, 0.0, 1.0), 5),
            "vehicleId": self.vehicle_id,
        }

    def to_json(self) -> str:
        return json.dumps(self.as_payload(), separators=(",", ":"))


class TelemetryState:
    def __init__(self) -> None:
        self.outgauge_payload: dict[str, float | int | str] = {}
        self.extended_payload: dict[str, object] = {}

    def update_outgauge(self, frame: TelemetryFrame) -> None:
        self.outgauge_payload = frame.as_payload()

    def update_extended(self, payload: dict[str, object]) -> None:
        self.extended_payload = payload

    def build_payload(self) -> dict[str, object]:
        merged: dict[str, object] = {}
        merged.update(self.outgauge_payload)
        merged["extended"] = self.extended_payload
        return merged

    def to_json(self) -> str:
        return json.dumps(self.build_payload(), separators=(",", ":"))

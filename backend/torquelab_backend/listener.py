from __future__ import annotations

import asyncio
import socket
import struct

from .config import Settings
from .models import TelemetryFrame, clamp

OUTGAUGE_PACKET = struct.Struct("I4sH2b7f2I3f16s16sI")


class OutGaugeListener:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind((settings.udp_host, settings.udp_port))
        self.socket.setblocking(False)

    async def frames(self):
        loop = asyncio.get_running_loop()
        while True:
            raw = await loop.sock_recv(self.socket, OUTGAUGE_PACKET.size)
            if len(raw) < OUTGAUGE_PACKET.size:
                continue
            yield self.parse_frame(raw[: OUTGAUGE_PACKET.size])

    def parse_frame(self, raw: bytes) -> TelemetryFrame:
        unpacked = OUTGAUGE_PACKET.unpack(raw)
        return TelemetryFrame(
            packet_time=unpacked[0],
            car=unpacked[1].split(b"\x00", 1)[0].decode("ascii", errors="ignore"),
            flags=unpacked[2],
            gear=unpacked[3],
            speed_kph=unpacked[5] * 3.6,
            rpm=unpacked[6],
            turbo_bar=unpacked[7],
            engine_temp_c=unpacked[8],
            fuel_fraction=clamp(unpacked[9], 0.0, 1.0),
            oil_temp_c=unpacked[11],
            dash_lights=unpacked[12],
            show_lights=unpacked[13],
            throttle=clamp(unpacked[14], 0.0, 1.0),
            brake=clamp(unpacked[15], 0.0, 1.0),
            clutch=clamp(unpacked[16], 0.0, 1.0),
            vehicle_id=unpacked[19],
        )

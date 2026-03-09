from __future__ import annotations

import asyncio
import json
import socket

from .config import Settings


class ExtendedTelemetryListener:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind((settings.lua_udp_host, settings.lua_udp_port))
        self.socket.setblocking(False)

    async def payloads(self):
        loop = asyncio.get_running_loop()
        while True:
            raw = await loop.sock_recv(self.socket, 65535)
            payload = self.parse_payload(raw)
            if payload is None:
                continue
            yield payload

    def parse_payload(self, raw: bytes) -> dict[str, object] | None:
        try:
            decoded = raw.decode("utf-8")
            payload = json.loads(decoded)
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

        if not isinstance(payload, dict):
            return None

        return payload

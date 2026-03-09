from __future__ import annotations

import asyncio
import websockets
from websockets.exceptions import ConnectionClosed

from .config import Settings
from .extended_listener import ExtendedTelemetryListener
from .listener import OutGaugeListener
from .logs_api import LogsApiServer
from .models import TelemetryState
from .session_logger import SessionLogger


class TelemetryBridgeServer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.listener = OutGaugeListener(settings)
        self.extended_listener = ExtendedTelemetryListener(settings)
        self.logs_api = LogsApiServer(settings, self)
        self.state = TelemetryState()
        self.clients: set[object] = set()
        self.last_message: str | None = None
        self.outgauge_frames_seen = 0
        self.extended_frames_seen = 0
        self.session_logger = SessionLogger(settings.log_dir) if settings.enable_logging and settings.auto_start_logging else None

    async def run(self) -> None:
        try:
            await self.logs_api.start()
            async with websockets.serve(self.handle_client, self.settings.ws_host, self.settings.ws_port):
                print(
                    f"TORQUELAB backend listening for UDP on "
                    f"{self.settings.udp_host}:{self.settings.udp_port}"
                )
                print(
                    f"TORQUELAB backend broadcasting WebSocket telemetry on "
                    f"ws://{self.settings.ws_host}:{self.settings.ws_port}"
                )
                print(
                    f"TORQUELAB backend listening for extended Lua telemetry on "
                    f"{self.settings.lua_udp_host}:{self.settings.lua_udp_port}"
                )
                print(
                    f"TORQUELAB logs API available at "
                    f"http://{self.settings.api_host}:{self.settings.api_port}/api/logs"
                )
                if self.session_logger is not None:
                    print(
                        f"TORQUELAB session logging enabled: "
                        f"{self.session_logger.files.csv_path} and {self.session_logger.files.jsonl_path}"
                    )
                elif self.settings.enable_logging:
                    print("TORQUELAB session logging ready: start a session from the LOGS page or API")
                await asyncio.gather(
                    self.run_outgauge_loop(),
                    self.run_extended_loop(),
                )
        finally:
            await self.logs_api.close()
            if self.session_logger is not None:
                self.session_logger.close()

    async def run_outgauge_loop(self) -> None:
        async for frame in self.listener.frames():
            self.outgauge_frames_seen += 1
            self.state.update_outgauge(frame)
            if self.outgauge_frames_seen == 1:
                print("Received first OutGauge frame")
            await self.publish_state()

    async def run_extended_loop(self) -> None:
        async for payload in self.extended_listener.payloads():
            self.extended_frames_seen += 1
            self.state.update_extended(payload)
            if self.extended_frames_seen == 1:
                print("Received first extended Lua telemetry frame")
                print(f"Extended payload keys: {', '.join(sorted(payload.keys()))}")
            await self.publish_state()

    async def publish_state(self) -> None:
        payload = self.state.build_payload()
        message = self.state.to_json()
        self.last_message = message
        if self.session_logger is not None:
            self.session_logger.write(payload)
        await self.broadcast(message)

    async def handle_client(self, websocket) -> None:
        self.clients.add(websocket)
        if self.last_message is not None:
            await websocket.send(self.last_message)

        try:
            await websocket.wait_closed()
        finally:
            self.clients.discard(websocket)

    async def broadcast(self, message: str) -> None:
        if not self.clients:
            return

        stale_clients: list[object] = []
        for client in self.clients:
            try:
                await client.send(message)
            except ConnectionClosed:
                stale_clients.append(client)

        for client in stale_clients:
            self.clients.discard(client)

    def start_logging(self) -> dict[str, object]:
        if not self.settings.enable_logging:
            return {
                "enabled": False,
                "active": False,
                "error": "logging disabled",
            }

        if self.session_logger is None:
            self.session_logger = SessionLogger(self.settings.log_dir)
            print(
                f"TORQUELAB session logging started: "
                f"{self.session_logger.files.csv_path} and {self.session_logger.files.jsonl_path}"
            )

        return self.logging_status()

    def stop_logging(self) -> dict[str, object]:
        status = self.logging_status()
        if self.session_logger is not None:
            self.session_logger.close()
            self.session_logger = None
            print("TORQUELAB session logging stopped")

        status["active"] = False
        return status

    def logging_status(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "enabled": self.settings.enable_logging,
            "active": self.session_logger is not None,
        }
        if self.session_logger is not None:
            payload.update(self.session_logger.describe())
        return payload

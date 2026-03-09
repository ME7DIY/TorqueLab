from __future__ import annotations

import asyncio
import csv
import json
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import unquote

from .config import Settings

if TYPE_CHECKING:
    from .server import TelemetryBridgeServer


class LogsApiServer:
    def __init__(self, settings: Settings, bridge: "TelemetryBridgeServer") -> None:
        self.settings = settings
        self.bridge = bridge
        self.log_dir = Path(settings.log_dir)
        self.server: asyncio.base_events.Server | None = None

    async def start(self) -> None:
        self.server = await asyncio.start_server(
            self.handle_connection,
            self.settings.api_host,
            self.settings.api_port,
        )

    async def close(self) -> None:
        if self.server is None:
            return

        self.server.close()
        await self.server.wait_closed()

    async def handle_connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            request_line = await reader.readline()
            if not request_line:
                writer.close()
                await writer.wait_closed()
                return

            try:
                method, raw_path, _ = request_line.decode("utf-8").strip().split(" ", 2)
            except ValueError:
                await self.send_json(writer, 400, {"error": "bad request"})
                return

            while True:
                header_line = await reader.readline()
                if not header_line or header_line in {b"\r\n", b"\n"}:
                    break

            if method == "OPTIONS":
                await self.send_empty(writer, 204)
                return

            path = raw_path.split("?", 1)[0]

            if method == "GET" and path == "/api/logs":
                await self.send_json(writer, 200, {"sessions": self.list_sessions()})
                return

            if method == "GET" and path == "/api/logging":
                await self.send_json(writer, 200, self.bridge.logging_status())
                return

            if method == "POST" and path == "/api/logging/start":
                await self.send_json(writer, 200, self.bridge.start_logging())
                return

            if method == "POST" and path == "/api/logging/stop":
                await self.send_json(writer, 200, self.bridge.stop_logging())
                return

            if method == "DELETE" and path.startswith("/api/logs/"):
                name = unquote(path.removeprefix("/api/logs/"))
                await self.delete_log_file(writer, name)
                return

            if method == "GET" and path.startswith("/api/logs/"):
                name = unquote(path.removeprefix("/api/logs/"))
                await self.send_log_file(writer, name)
                return

            await self.send_json(writer, 404, {"error": "not found"})
        finally:
            writer.close()
            await writer.wait_closed()

    def list_sessions(self) -> list[dict[str, object]]:
        if not self.log_dir.exists():
            return []

        sessions: list[dict[str, object]] = []
        for csv_path in sorted(self.log_dir.glob("session_*.csv"), reverse=True):
            jsonl_path = csv_path.with_suffix(".jsonl")
            stat = csv_path.stat()
            summary = self.summarize_csv(csv_path)
            sessions.append(
                {
                    "name": csv_path.name,
                    "sessionId": csv_path.stem.removeprefix("session_"),
                    "modifiedAt": stat.st_mtime,
                    "sizeBytes": stat.st_size,
                    "rowCount": summary["rowCount"],
                    "hasJsonl": jsonl_path.exists(),
                    "startedAt": summary["startedAt"],
                    "endedAt": summary["endedAt"],
                    "vehicleIds": summary["vehicleIds"],
                }
            )

        return sessions

    def summarize_csv(self, path: Path) -> dict[str, object]:
        started_at: str | None = None
        ended_at: str | None = None
        vehicle_ids: set[str] = set()
        row_count = 0

        try:
            with path.open("r", encoding="utf-8") as handle:
                reader = csv.DictReader(handle)
                for row in reader:
                    row_count += 1
                    logged_at = row.get("loggedAt")
                    if started_at is None:
                        started_at = logged_at
                    ended_at = logged_at or ended_at

                    vehicle_id = row.get("vehicleId") or row.get("extended_vehicleId")
                    if vehicle_id:
                        vehicle_ids.add(str(vehicle_id))
        except OSError:
            return {
                "rowCount": 0,
                "startedAt": None,
                "endedAt": None,
                "vehicleIds": [],
            }

        return {
            "rowCount": row_count,
            "startedAt": started_at,
            "endedAt": ended_at,
            "vehicleIds": sorted(vehicle_ids),
        }

    async def send_log_file(self, writer: asyncio.StreamWriter, name: str) -> None:
        safe_name = Path(name).name
        path = self.log_dir / safe_name
        if not path.exists() or path.suffix.lower() != ".csv":
            await self.send_json(writer, 404, {"error": "log not found"})
            return

        try:
            body = path.read_bytes()
        except OSError:
            await self.send_json(writer, 500, {"error": "failed to read log"})
            return

        headers = self.build_headers(200, "text/csv; charset=utf-8", len(body))
        writer.write(headers + body)
        await writer.drain()

    async def delete_log_file(self, writer: asyncio.StreamWriter, name: str) -> None:
        safe_name = Path(name).name
        csv_path = self.log_dir / safe_name
        jsonl_path = csv_path.with_suffix(".jsonl")

        if not csv_path.exists() or csv_path.suffix.lower() != ".csv":
            await self.send_json(writer, 404, {"error": "log not found"})
            return

        try:
            csv_path.unlink()
            if jsonl_path.exists():
                jsonl_path.unlink()
        except OSError:
            await self.send_json(writer, 500, {"error": "failed to delete log"})
            return

        await self.send_json(writer, 200, {"deleted": safe_name})

    async def send_json(self, writer: asyncio.StreamWriter, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers = self.build_headers(status, "application/json; charset=utf-8", len(body))
        writer.write(headers + body)
        await writer.drain()

    async def send_empty(self, writer: asyncio.StreamWriter, status: int) -> None:
        headers = self.build_headers(status, "text/plain; charset=utf-8", 0)
        writer.write(headers)
        await writer.drain()

    def build_headers(self, status: int, content_type: str, content_length: int) -> bytes:
        reason = {
            200: "OK",
            204: "No Content",
            400: "Bad Request",
            404: "Not Found",
            500: "Internal Server Error",
        }.get(status, "OK")
        lines = [
            f"HTTP/1.1 {status} {reason}",
            f"Content-Type: {content_type}",
            f"Content-Length: {content_length}",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            "",
        ]
        return "\r\n".join(lines).encode("utf-8")

from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class Settings:
    udp_host: str = "127.0.0.1"
    udp_port: int = 4444
    lua_udp_host: str = "127.0.0.1"
    lua_udp_port: int = 4445
    ws_host: str = "127.0.0.1"
    ws_port: int = 8765
    api_host: str = "127.0.0.1"
    api_port: int = 8766
    log_dir: str = "logs"
    enable_logging: bool = True
    auto_start_logging: bool = False

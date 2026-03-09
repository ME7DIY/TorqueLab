from __future__ import annotations

import argparse
import asyncio

from torquelab_backend.config import Settings
from torquelab_backend.server import TelemetryBridgeServer


def parse_args() -> Settings:
    parser = argparse.ArgumentParser(description="TORQUELAB telemetry bridge")
    parser.add_argument("--udp-host", default="127.0.0.1")
    parser.add_argument("--udp-port", type=int, default=4444)
    parser.add_argument("--lua-udp-host", default="127.0.0.1")
    parser.add_argument("--lua-udp-port", type=int, default=4445)
    parser.add_argument("--ws-host", default="127.0.0.1")
    parser.add_argument("--ws-port", type=int, default=8765)
    parser.add_argument("--api-host", default="127.0.0.1")
    parser.add_argument("--api-port", type=int, default=8766)
    parser.add_argument("--log-dir", default="logs")
    parser.add_argument("--disable-logging", action="store_true")
    parser.add_argument("--auto-start-logging", action="store_true")
    args = parser.parse_args()
    return Settings(
        udp_host=args.udp_host,
        udp_port=args.udp_port,
        lua_udp_host=args.lua_udp_host,
        lua_udp_port=args.lua_udp_port,
        ws_host=args.ws_host,
        ws_port=args.ws_port,
        api_host=args.api_host,
        api_port=args.api_port,
        log_dir=args.log_dir,
        enable_logging=not args.disable_logging,
        auto_start_logging=args.auto_start_logging,
    )


async def main() -> None:
    settings = parse_args()
    server = TelemetryBridgeServer(settings)
    await server.run()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

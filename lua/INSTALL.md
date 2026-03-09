# Installing The Phase 2 Lua Bridge

## Vehicle Lua extension path

Put [torquelabPhase2.lua](/C:/Users/kitza/Documents/TORQUELAB/lua/vehicle/extensions/torquelabPhase2.lua) into BeamNG's vehicle extension path:

```text
BeamNG.drive/lua/vehicle/extensions/torquelabPhase2.lua
```

## Load it manually first

BeamNG's extension docs show vehicle extensions are loaded explicitly and can be placed under `lua/vehicle/extensions/`. The docs also show the usual extension hooks like `onExtensionLoaded` and `onUpdate` / `onPhysicsStep`. Source: https://documentation.beamng.com/modding/programming/extensions/

Open the `VE Lua` console for the active vehicle and run:

```lua
extensions.load("torquelabPhase2")
```

If you are in `GE Lua` instead, queue the command into the player vehicle:

```lua
be:getPlayerVehicle(0):queueLuaCommand('extensions.load("torquelabPhase2")')
```

`extensions.load("torquelabPhase2")` by itself will fail in `GE Lua` because BeamNG will look for a game-engine extension, not a vehicle extension.

If you edit the file while testing, reload the active vehicle Lua VM with `Ctrl+R`.

## What it sends

The script sends UDP JSON to:

```text
127.0.0.1:4445
```

The backend then merges that data into the WebSocket payload under `extended`.

## Important notes

- The UDP socket import uses BeamNG's bundled LuaSocket path:

```lua
local socket = require("libs/luasocket/socket.socket")
```

This import path is based on BeamNG staff guidance here: https://www.beamng.com/threads/how-to-get-game-variables-out-beamng-drive-into-a-programming-environment.69096/

- Wheel access is intentionally defensive. BeamNG forum guidance indicates wheel data is exposed through `wheels.wheels`, but exact per-wheel fields vary and may need inspection with `dump(wheels)` for a given vehicle. Source: https://www.beamng.com/threads/control-brakes-parameters-from-vehicle-lua.100211/

- This first pass is a bridge scaffold. If a given vehicle exposes different field names for wheel speed, suspension, torque, or boost target, update the candidate fields inside [torquelabPhase2.lua](/C:/Users/kitza/Documents/TORQUELAB/lua/vehicle/extensions/torquelabPhase2.lua).

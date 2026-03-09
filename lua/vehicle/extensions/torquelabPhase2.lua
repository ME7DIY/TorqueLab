local M = {}

local socket = require("libs/luasocket/socket.socket")

local TARGET_HOST = "127.0.0.1"
local TARGET_PORT = 4445
local SEND_INTERVAL_SECONDS = 0.05

local udpClient = nil
local elapsedSinceSend = 0
local sendCount = 0
local suspensionBaseline = {}
local getWheelDataByCorner

local CORNER_KEYS = {
  fl = "FL",
  fr = "FR",
  rl = "RL",
  rr = "RR",
}

local function safeNumber(value)
  if type(value) ~= "number" then
    return nil
  end

  if value ~= value or value == math.huge or value == -math.huge then
    return nil
  end

  return value
end

local function round(value, decimals)
  local factor = 10 ^ (decimals or 3)
  return math.floor(value * factor + 0.5) / factor
end

local function normalizeNumber(value, decimals, epsilon)
  local numeric = safeNumber(value)
  if numeric == nil then
    return nil
  end

  if math.abs(numeric) < (epsilon or 0.0001) then
    numeric = 0
  end

  return round(numeric, decimals)
end

local function getNestedNumber(root, path)
  local current = root
  for _, key in ipairs(path) do
    if type(current) ~= "table" then
      return nil
    end
    current = current[key]
  end

  return safeNumber(current)
end

local function firstNumber(...)
  local candidates = { ... }
  for _, value in ipairs(candidates) do
    local numeric = safeNumber(value)
    if numeric ~= nil then
      return numeric
    end
  end

  return nil
end

local function computeWheelSpeedKph(wheelData)
  local angularVelocity = firstNumber(
    wheelData.angularVelocity,
    wheelData.wheelAV,
    wheelData.av,
    wheelData.wheelAngularVelocity
  )
  local radius = firstNumber(wheelData.radius, wheelData.wheelRadius, wheelData.tireRadius)
  local directSpeed = firstNumber(
    wheelData.wheelSpeed,
    wheelData.wheelspeed,
    wheelData.speed,
    wheelData.wheelSpeedMPS
  )

  local speedMps = directSpeed
  if speedMps == nil and angularVelocity ~= nil and radius ~= nil then
    speedMps = angularVelocity * radius
  end

  if speedMps == nil then
    return nil
  end

  return round(math.abs(speedMps) * 3.6, 3)
end

local function computeSuspensionTravel(wheelData)
  return round(firstNumber(
    wheelData.suspensionLength,
    wheelData.springLength,
    wheelData.compression,
    wheelData.suspensionCompression,
    wheelData.springCompression,
    wheelData.suspensionDisplacement,
    wheelData.rayLen
  ) or 0, 5)
end

local function getCurrentBodyFrame()
  if not obj or not obj.getNodePosition or not v or not v.data or not v.data.refNodes or not v.data.refNodes[0] then
    return nil
  end

  local refNodes = v.data.refNodes[0]
  local refPos = obj:getNodePosition(refNodes.ref)
  local backPos = obj:getNodePosition(refNodes.back)
  local upPos = obj:getNodePosition(refNodes.up)
  if not refPos or not backPos or not upPos then
    return nil
  end

  local upVector = upPos - refPos
  if upVector.length and upVector:length() > 0 then
    upVector = upVector:normalized()
  end

  return {
    refPos = refPos,
    upVector = upVector,
  }
end

local function getInitialBodyUpVector()
  if not v or not v.data or not v.data.refNodes or not v.data.refNodes[0] or not v.data.nodes then
    return nil
  end

  local refNodes = v.data.refNodes[0]
  local refPos = vec3(v.data.nodes[refNodes.ref].pos)
  local upPos = vec3(v.data.nodes[refNodes.up].pos)
  local upVector = upPos - refPos
  if upVector:length() <= 0 then
    return nil
  end

  return upVector:normalized()
end

local function initializeSuspensionBaseline()
  suspensionBaseline = {}

  if not v or not v.data or not v.data.nodes or not v.data.refNodes or not v.data.refNodes[0] then
    return
  end

  local refNodeId = v.data.refNodes[0].ref
  local refPos = vec3(v.data.nodes[refNodeId].pos)
  local upVector = getInitialBodyUpVector()
  if upVector == nil then
    return
  end

  for cornerKey, _ in pairs(CORNER_KEYS) do
    local wheelData = getWheelDataByCorner(cornerKey)
    if wheelData and wheelData.node1 and v.data.nodes[wheelData.node1] then
      local wheelPos = vec3(v.data.nodes[wheelData.node1].pos)
      suspensionBaseline[cornerKey] = (wheelPos - refPos):dot(upVector)
    end
  end
end

local function computeSuspensionProxy(cornerKey, wheelData)
  local baseline = suspensionBaseline[cornerKey]
  if baseline == nil or not wheelData or not wheelData.node1 or not obj or not obj.getNodePosition then
    return nil
  end

  local bodyFrame = getCurrentBodyFrame()
  if bodyFrame == nil or bodyFrame.upVector == nil then
    return nil
  end

  local wheelPos = obj:getNodePosition(wheelData.node1)
  if not wheelPos then
    return nil
  end

  local currentHeight = (wheelPos - bodyFrame.refPos):dot(bodyFrame.upVector)
  return round(baseline - currentHeight, 5)
end

getWheelDataByCorner = function(cornerKey)
  if type(wheels) ~= "table" or type(wheels.wheelIDs) ~= "table" or type(wheels.wheels) ~= "table" then
    return nil
  end

  local wheelName = CORNER_KEYS[cornerKey]
  local wheelId = wheelName and wheels.wheelIDs[wheelName] or nil
  if wheelId == nil then
    return nil
  end

  local wheelData = wheels.wheels[wheelId]
  if type(wheelData) ~= "table" then
    return nil
  end

  return wheelData
end

local function collectWheelData()
  local wheelSpeeds = { fl = nil, fr = nil, rl = nil, rr = nil }
  local suspensionTravel = { fl = nil, fr = nil, rl = nil, rr = nil }
  local vehicleSpeedKph = obj and obj.getVelocity and round(obj:getVelocity():length() * 3.6, 3) or nil

  if type(wheels) ~= "table" then
    return wheelSpeeds, suspensionTravel
  end

  if next(suspensionBaseline) == nil then
    initializeSuspensionBaseline()
  end

  for cornerKey, _ in pairs(CORNER_KEYS) do
    local wheelData = getWheelDataByCorner(cornerKey)
    if wheelData ~= nil then
      wheelSpeeds[cornerKey] = computeWheelSpeedKph(wheelData) or vehicleSpeedKph
      suspensionTravel[cornerKey] = computeSuspensionProxy(cornerKey, wheelData) or computeSuspensionTravel(wheelData)
    end
  end

  return wheelSpeeds, suspensionTravel
end

local function collectPowertrainData()
  local electricsValues = electrics and electrics.values or {}
  local gearbox = powertrain and powertrain.getDevice and powertrain.getDevice("gearbox") or nil
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  local propulsionDevices = powertrain and powertrain.getAllWheelPropulsionDevices and powertrain.getAllWheelPropulsionDevices() or {}
  local activeGearIndex = firstNumber(
    getNestedNumber(controller, { "mainController", "currentGearIndex" }),
    electricsValues.gearIndex,
    gearbox and gearbox.gearIndex or nil
  )
  local propulsionTorque = 0

  for _, propulsionDevice in ipairs(propulsionDevices) do
    if type(propulsionDevice) == "table" then
      local deviceTorque = firstNumber(
        propulsionDevice.combustionTorque,
        propulsionDevice.outputTorque1
      )
      if deviceTorque ~= nil then
        propulsionTorque = propulsionTorque + deviceTorque
      end
    end
  end

  local resolvedTorque = firstNumber(
    propulsionTorque ~= 0 and propulsionTorque or nil,
    getNestedNumber(controller, { "mainController", "engineTorque" }),
    engine and firstNumber(engine.combustionTorque, engine.outputTorque1) or nil,
    gearbox and gearbox.outputTorque1 or nil,
    electricsValues.torque,
    electricsValues.engineTorque,
    electricsValues.flywheelTorque
  )

  local resolvedGearRatio = firstNumber(
    gearbox and gearbox.gearRatio or nil,
    gearbox and gearbox.gearRatios and activeGearIndex and gearbox.gearRatios[activeGearIndex] or nil,
    getNestedNumber(controller, { "mainController", "gearRatio" }),
    electricsValues.gearRatio,
    electricsValues.currentGearRatio,
    electricsValues.finalGearRatio
  )

  return {
    torqueNm = normalizeNumber(resolvedTorque or 0, 3, 0.001) or 0,
    gearRatio = normalizeNumber(resolvedGearRatio or 0, 5, 0.00001) or 0,
    boostCurve = {
      actualBar = normalizeNumber(firstNumber(
        electricsValues.boost,
        electricsValues.turboBoost,
        electricsValues.boost,
        electricsValues.boostPressure,
        electricsValues.manifoldPressure
      ) or 0, 4, 0.0001) or 0,
      targetBar = normalizeNumber(firstNumber(
        electricsValues.boostMax,
        electricsValues.boostTarget,
        electricsValues.requestedBoost,
        electricsValues.turboBoostTarget,
        electricsValues.turboBoostMax
      ) or 0, 4, 0.0001) or 0,
    },
  }
end

local function buildDebugData()
  local electricsValues = electrics and electrics.values or {}
  local gearbox = powertrain and powertrain.getDevice and powertrain.getDevice("gearbox") or nil
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  local wheelIds = wheels and wheels.wheelIDs or {}
  local controllerGearIndex = firstNumber(
    getNestedNumber(controller, { "mainController", "currentGearIndex" }),
    electricsValues.gearIndex,
    gearbox and gearbox.gearIndex or nil
  )

  local flWheel = getWheelDataByCorner("fl")

  return {
    wheelIdMap = {
      FL = wheelIds and wheelIds.FL or nil,
      FR = wheelIds and wheelIds.FR or nil,
      RL = wheelIds and wheelIds.RL or nil,
      RR = wheelIds and wheelIds.RR or nil,
    },
    wheelCount = wheels and wheels.wheels and #wheels.wheels or 0,
    engineFound = engine ~= nil,
    gearboxFound = gearbox ~= nil,
    gearboxGearIndex = normalizeNumber(gearbox and gearbox.gearIndex or nil, 0, 0.00001),
    gearboxGearRatio = normalizeNumber(gearbox and gearbox.gearRatio or nil, 5, 0.00001),
    gearboxIndexedRatio = normalizeNumber(gearbox and gearbox.gearRatios and controllerGearIndex and gearbox.gearRatios[controllerGearIndex] or nil, 5, 0.00001),
    controllerGearIndex = normalizeNumber(controllerGearIndex, 0, 0.00001),
    objectSpeed = normalizeNumber(obj and obj.getVelocity and obj:getVelocity():length() * 3.6 or nil, 3, 0.001),
    engineTorque = normalizeNumber(engine and engine.combustionTorque or nil, 3, 0.001),
    engineOutputTorque = normalizeNumber(engine and engine.outputTorque1 or nil, 3, 0.001),
    frontLeftWheel = flWheel and {
      name = flWheel.name,
      wheelSpeed = normalizeNumber(flWheel.wheelSpeed, 3, 0.001),
      angularVelocity = normalizeNumber(flWheel.angularVelocity, 3, 0.001),
      suspensionLength = normalizeNumber(flWheel.suspensionLength, 5, 0.00001),
      springLength = normalizeNumber(flWheel.springLength, 5, 0.00001),
      compression = normalizeNumber(flWheel.compression, 5, 0.00001),
      suspensionCompression = normalizeNumber(flWheel.suspensionCompression, 5, 0.00001),
      springCompression = normalizeNumber(flWheel.springCompression, 5, 0.00001),
      rayLen = normalizeNumber(flWheel.rayLen, 5, 0.00001),
    } or nil,
    electrics = {
      rpm = normalizeNumber(electricsValues.rpm, 1, 0.001),
      wheelspeed = normalizeNumber(electricsValues.wheelspeed, 3, 0.001),
      gearIndex = normalizeNumber(electricsValues.gearIndex, 0, 0.00001),
      boost = normalizeNumber(electricsValues.boost, 4, 0.0001),
      boostMax = normalizeNumber(electricsValues.boostMax, 4, 0.0001),
      turboBoost = normalizeNumber(electricsValues.turboBoost, 4, 0.0001),
      throttle = normalizeNumber(electricsValues.throttle, 4, 0.0001),
    },
  }
end

local function escapeString(value)
  return value
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
end

local function isArray(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" then
      return false
    end
    count = count + 1
  end

  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end

  return true
end

local function encodeJson(value)
  local valueType = type(value)

  if valueType == "nil" then
    return "null"
  end

  if valueType == "number" then
    return tostring(value)
  end

  if valueType == "boolean" then
    return value and "true" or "false"
  end

  if valueType == "string" then
    return "\"" .. escapeString(value) .. "\""
  end

  if valueType ~= "table" then
    return "null"
  end

  if isArray(value) then
    local encodedItems = {}
    for index = 1, #value do
      encodedItems[#encodedItems + 1] = encodeJson(value[index])
    end
    return "[" .. table.concat(encodedItems, ",") .. "]"
  end

  local encodedPairs = {}
  for key, nestedValue in pairs(value) do
    encodedPairs[#encodedPairs + 1] = encodeJson(tostring(key)) .. ":" .. encodeJson(nestedValue)
  end
  table.sort(encodedPairs)

  return "{" .. table.concat(encodedPairs, ",") .. "}"
end

local function buildPayload()
  local wheelSpeeds, suspensionTravel = collectWheelData()
  local powertrainData = collectPowertrainData()

  return {
    source = "vehicleLua",
    vehicleId = obj and obj:getID() or nil,
    wheelSpeeds = wheelSpeeds,
    suspensionTravel = suspensionTravel,
    torqueNm = powertrainData.torqueNm,
    gearRatio = powertrainData.gearRatio,
    boostCurve = powertrainData.boostCurve,
    debug = buildDebugData(),
  }
end

local function ensureSocket()
  if udpClient ~= nil then
    return true
  end

  udpClient = socket.udp()
  if udpClient == nil then
    return false
  end

  udpClient:settimeout(0)
  return true
end

local function sendPayload()
  if not ensureSocket() then
    log("E", "torquelabPhase2", "TORQUELAB Phase 2 failed to create UDP socket")
    return
  end

  local payload = buildPayload()
  local encoded = encodeJson(payload)
  local ok, err = udpClient:sendto(encoded, TARGET_HOST, TARGET_PORT)
  if not ok then
    log("E", "torquelabPhase2", "TORQUELAB Phase 2 UDP send failed: " .. tostring(err))
    return
  end
  sendCount = sendCount + 1
  if sendCount == 1 then
    log("I", "torquelabPhase2", "TORQUELAB Phase 2 sent first UDP payload to 127.0.0.1:4445")
  end
end

local function onExtensionLoaded()
  elapsedSinceSend = 0
  sendCount = 0
  initializeSuspensionBaseline()
  ensureSocket()
  log("I", "torquelabPhase2", "TORQUELAB Phase 2 vehicle telemetry bridge loaded")
  sendPayload()
end

local function onReset()
  elapsedSinceSend = 0
  sendCount = 0
  initializeSuspensionBaseline()
end

local function onPhysicsStep(dtSim)
  elapsedSinceSend = elapsedSinceSend + (dtSim or 0)
  if elapsedSinceSend < SEND_INTERVAL_SECONDS then
    return
  end

  elapsedSinceSend = 0
  sendPayload()
end

local function updateGFX(dt)
  elapsedSinceSend = elapsedSinceSend + (dt or 0)
  if elapsedSinceSend < SEND_INTERVAL_SECONDS then
    return
  end

  elapsedSinceSend = 0
  sendPayload()
end

local function onExtensionUnloaded()
  if udpClient ~= nil then
    udpClient:close()
    udpClient = nil
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onReset = onReset
M.updateGFX = updateGFX

return M

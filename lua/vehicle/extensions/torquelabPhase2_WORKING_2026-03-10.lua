local M = {}

local socket = require("libs/luasocket/socket.socket")

local TARGET_HOST = "127.0.0.1"
local TARGET_PORT = 4445
local CMD_PORT = 4446
local SEND_INTERVAL_SECONDS = 0.05

local udpClient = nil
local cmdSocket = nil
local elapsedSinceSend = 0
local sendCount = 0
local suspensionBaseline = {}
local getWheelDataByCorner
local torqueScalar = 1.0
local baseMaxTorque = nil
local revLimiter = nil
local baseMaxRPM = nil
local baseMaxAvailableRPM = nil
local lastTuneStatus = nil
local baseTorqueScale = nil
local ignitionCutTimer = 0
local baseIgnitionCutTime = nil
local baseAfterFireCoef = nil
local boostTarget = nil
local boostOffsetPsi = 0
local desiredBoostTarget = nil
local boostDebugDumped = false
local boostCeiling = nil
local boostPid = {
  p = 0.6,
  i = 0.04,
  d = 0.05,
  integral = 0,
  lastError = 0,
}
local popDebug = nil
local exhaustNodesInitialized = false
local exhaustNodesAttempted = false
local exhaustNodesSet = false
local lastExhaustStart = nil
local lastExhaustFinish = nil
local forcePop = false
local safeAfterfireMode = false
local popStrengthScale = 0.5
local requireTuneForPops = true
local pendingPopStrength = 0
local pendingPopActive = false

local CORNER_KEYS = {
  fl = "FL",
  fr = "FR",
  rl = "RL",
  rr = "RR",
}

local PSI_TO_BAR = 1 / 14.5038
local PSI_PER_BAR = 14.5038

local function safeNumber(value)
  if type(value) ~= "number" then
    return nil
  end

  if value ~= value or value == math.huge or value == -math.huge then
    return nil
  end

  return value
end

local RPM_BINS = { 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 5000, 6000, 7000, 8000 }
local LOAD_BINS = { 100, 90, 80, 70, 60, 50, 40, 30 }
local fuelTrimMap = {}
local ignTrimMap = {}

local function buildDefaultMap()
  local map = {}
  for row = 1, #LOAD_BINS do
    map[row] = {}
    for col = 1, #RPM_BINS do
      map[row][col] = 0
    end
  end
  return map
end

local function ensureTrimMaps()
  if type(fuelTrimMap) ~= "table" or next(fuelTrimMap) == nil then
    fuelTrimMap = buildDefaultMap()
  end
  if type(ignTrimMap) ~= "table" or next(ignTrimMap) == nil then
    ignTrimMap = buildDefaultMap()
  end
end

local function clampCell(value, minValue, maxValue)
  local numeric = safeNumber(value)
  if numeric == nil then
    return nil
  end
  return clamp(numeric, minValue, maxValue)
end

local function findClosestIndex(value, bins)
  if type(value) ~= "number" then
    return 1
  end
  local closestIndex = 1
  local closestDiff = math.huge
  for index, bin in ipairs(bins) do
    local diff = math.abs(bin - value)
    if diff < closestDiff then
      closestDiff = diff
      closestIndex = index
    end
  end
  return closestIndex
end

local function getBinRange(bins, index)
  if type(bins) ~= "table" or type(index) ~= "number" then
    return -math.huge, math.huge
  end
  local value = bins[index]
  if type(value) ~= "number" then
    return -math.huge, math.huge
  end
  local prev = bins[index - 1]
  local nxt = bins[index + 1]
  local midPrev = (type(prev) == "number") and ((prev + value) / 2) or nil
  local midNext = (type(nxt) == "number") and ((nxt + value) / 2) or nil

  if midPrev ~= nil and midNext ~= nil then
    local lower = math.min(midPrev, midNext)
    local upper = math.max(midPrev, midNext)
    return lower, upper
  end

  if midPrev ~= nil then
    if prev < value then
      return midPrev, math.huge
    end
    return -math.huge, midPrev
  end

  if midNext ~= nil then
    if nxt < value then
      return midNext, math.huge
    end
    return -math.huge, midNext
  end

  return -math.huge, math.huge
end

local function getTrimAt(map, rpmValue, loadValue)
  if type(map) ~= "table" then
    return 0
  end
  local row = findClosestIndex(loadValue, LOAD_BINS)
  local col = findClosestIndex(rpmValue, RPM_BINS)
  local rowData = map[row]
  if type(rowData) ~= "table" then
    return 0
  end
  return safeNumber(rowData[col]) or 0
end

local function setTrimCell(map, row, col, value)
  if type(map) ~= "table" then
    return false
  end
  if type(row) ~= "number" or type(col) ~= "number" then
    return false
  end
  if row < 1 or row > #LOAD_BINS or col < 1 or col > #RPM_BINS then
    return false
  end
  map[row] = map[row] or {}
  map[row][col] = value
  return true
end

local function clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

local function firstTable(...)
  local candidates = { ... }
  for _, value in ipairs(candidates) do
    if type(value) == "table" then
      return value
    end
  end
  return nil
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

local function firstNumberFromTable(root, keys)
  if type(root) ~= "table" or type(keys) ~= "table" then
    return nil
  end
  for _, key in ipairs(keys) do
    local numeric = safeNumber(root[key])
    if numeric ~= nil then
      return numeric
    end
  end
  return nil
end

local function getNodeIdByName(nodeName)
  if type(nodeName) ~= "string" then
    return nil
  end
  if v and v.data and type(v.data.nodeMap) == "table" then
    local mapped = v.data.nodeMap[nodeName]
    if type(mapped) == "number" then
      return mapped
    end
  end
  if v and v.data and type(v.data.nodes) == "table" then
    for id, node in pairs(v.data.nodes) do
      if type(node) == "table" and node.name == nodeName then
        return id
      end
    end
  end
  return nil
end

local function ensureExhaustSoundNodes(engine)
  if exhaustNodesInitialized or type(engine) ~= "table" then
    return
  end

  exhaustNodesAttempted = true
  local startId = getNodeIdByName("ex1") or getNodeIdByName("ex2") or getNodeIdByName("ex3")
  local finishId = getNodeIdByName("ex5") or getNodeIdByName("ex4") or getNodeIdByName("ex6")
  lastExhaustStart = startId
  lastExhaustFinish = finishId
  if type(startId) ~= "number" or type(finishId) ~= "number" or startId == finishId then
    return
  end

  local endNodes = {
    {
      start = startId,
      finish = finishId,
      exhaustAudioOpennessCoef = 1,
      exhaustAudioGainChange = 6,
    },
  }
  engine.exhaustEndNodes = endNodes
  if type(engine.exhaustEndNodesChanged) == "function" then
    engine:exhaustEndNodesChanged(endNodes)
  end
  local thermals = engine.thermals
  if type(thermals) == "table" then
    thermals.exhaustEndNodes = endNodes
  end
  exhaustNodesSet = true
  exhaustNodesInitialized = true
end

local function normalizeField(value, decimals, epsilon)
  local numeric = safeNumber(value)
  if numeric == nil then
    return nil
  end
  return normalizeNumber(numeric, decimals, epsilon)
end

local function resolveBoostValue(...)
  local candidate = firstNumber(...)
  if candidate == nil then
    return 0
  end

  local numeric = safeNumber(candidate)
  if numeric == nil then
    return 0
  end

  local absValue = math.abs(numeric)
  if absValue > 5 then
    if absValue > 200 then
      -- likely kPa (100 kPa = 1 bar)
      numeric = numeric * 0.01
    else
      -- likely psi
      numeric = numeric * PSI_TO_BAR
    end
  end

  return normalizeNumber(numeric, 4, 0.0001) or 0
end

local function getBoostOffsetClampPsi()
  if boostCeiling ~= nil then
    return clamp((boostCeiling * PSI_PER_BAR) - 5, 5, 40)
  end
  return 20
end

local function getActualBoostBar()
  local electricsValues = electrics and electrics.values or {}
  return resolveBoostValue(
    electricsValues.boost,
    electricsValues.turboBoost,
    electricsValues.boostPressure,
    electricsValues.manifoldPressure
  )
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
      actualBar = resolveBoostValue(
        electricsValues.boost,
        electricsValues.turboBoost,
        electricsValues.boostPressure,
        electricsValues.manifoldPressure
      ),
      targetBar = resolveBoostValue(
        electricsValues.boostMax,
        electricsValues.boostTarget,
        electricsValues.requestedBoost,
        electricsValues.turboBoostTarget,
        electricsValues.turboBoostMax
      ),
    },
  }
end

local function collectHealthData()
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  local gearbox = powertrain and powertrain.getDevice and powertrain.getDevice("gearbox") or nil
  local clutch = powertrain and powertrain.getDevice and powertrain.getDevice("clutch") or nil
  local differentialR = powertrain and powertrain.getDevice and powertrain.getDevice("differential_R") or nil

  local tires = {}
  local brakes = {}

  for cornerKey, _ in pairs(CORNER_KEYS) do
    local wheelData = getWheelDataByCorner(cornerKey)
    if type(wheelData) == "table" then
      local brakeTemp = firstNumberFromTable(wheelData, { "brakeCoreTemperature", "brakeSurfaceTemperature" })
      local brakeGlaze = firstNumberFromTable(wheelData, { "padGlazingFactor", "squealCoefGlazing" })
      if brakeTemp or brakeGlaze then
        brakes[cornerKey] = {
          temp = normalizeField(brakeTemp, 2, 0.001),
          glaze = normalizeField(brakeGlaze, 4, 0.0001),
        }
      end
    end
  end

  local health = {
    tires = next(tires) and tires or nil,
    brakes = next(brakes) and brakes or nil,
    engine = engine and {
      damageFriction = normalizeField(firstNumberFromTable(engine, { "damageFrictionCoef", "damageDynamicFrictionCoef" }), 4, 0.0001),
      wearFriction = normalizeField(firstNumberFromTable(engine, { "wearDynamicFrictionCoef" }), 4, 0.0001),
      overRevDamage = normalizeField(firstNumberFromTable(engine, { "overRevDamage", "maxOverRevDamage" }), 4, 0.0001),
      overTorqueDamage = normalizeField(firstNumberFromTable(engine, { "overTorqueDamage", "maxOverTorqueDamage" }), 4, 0.0001),
      tempRevLimiterActive = engine.isTempRevLimiterActive and true or false,
      thermalsEnabled = engine.thermalsEnabled and true or false,
    } or nil,
    drivetrain = gearbox and {
      damageFriction = normalizeField(firstNumberFromTable(gearbox, { "damageFrictionCoef" }), 4, 0.0001),
      wearFriction = normalizeField(firstNumberFromTable(gearbox, { "wearFrictionCoef" }), 4, 0.0001),
      gearDamageThreshold = normalizeField(firstNumberFromTable(gearbox, { "gearDamageThreshold" }), 4, 0.0001),
      isBroken = gearbox.isBroken and true or false,
    } or nil,
    differential = differentialR and {
      damageFriction = normalizeField(firstNumberFromTable(differentialR, { "damageFrictionCoef" }), 4, 0.0001),
      wearFriction = normalizeField(firstNumberFromTable(differentialR, { "wearFrictionCoef" }), 4, 0.0001),
    } or nil,
    clutch = clutch and {
      temp = normalizeField(firstNumberFromTable(clutch, { "clutchTemperature" }), 2, 0.001),
      maxSafeTemp = normalizeField(firstNumberFromTable(clutch, { "clutchMaxSafeTemp", "clutchWarningTemp" }), 2, 0.001),
      permanentDamage = clutch.clutchPermanentlyDamaged and true or false,
      wearLockTorque = normalizeField(firstNumberFromTable(clutch, { "wearLockTorqueCoef" }), 4, 0.0001),
      wearFreePlay = normalizeField(firstNumberFromTable(clutch, { "wearClutchFreePlayCoef" }), 4, 0.0001),
      damageLockTorque = normalizeField(firstNumberFromTable(clutch, { "damageLockTorqueCoef" }), 4, 0.0001),
      damageFreePlay = normalizeField(firstNumberFromTable(clutch, { "damageClutchFreePlayCoef" }), 4, 0.0001),
    } or nil,
  }

  if not health.tires and not health.brakes and not health.engine and not health.drivetrain and not health.differential and not health.clutch then
    return nil
  end

  return health
end


local BOOST_FIELDS = {
  "boostTarget",
  "targetBoost",
  "boostPressureTarget",
  "wastegateTarget",
  "wgTarget",
  "boostMax",
  "maxBoost",
}

local function getPowertrainDevices()
  if not powertrain then
    return {}
  end
  if type(powertrain.getDevices) == "function" then
    local devices = powertrain.getDevices()
    if type(devices) == "table" then
      return devices
    end
  end
  return {}
end

local function findBoostDevices()
  local devices = {}
  local named = {
    "turbocharger",
    "turbocharger1",
    "supercharger",
    "supercharger1",
  }

  if powertrain and powertrain.getDevice then
    for _, name in ipairs(named) do
      local device = powertrain.getDevice(name)
      if type(device) == "table" then
        devices[#devices + 1] = device
      end
    end
  end

  for _, device in pairs(getPowertrainDevices()) do
    if type(device) == "table" then
      devices[#devices + 1] = device
      if type(device.turbocharger) == "table" then
        devices[#devices + 1] = device.turbocharger
      end
      if type(device.supercharger) == "table" then
        devices[#devices + 1] = device.supercharger
      end
    end
  end

  return devices
end

local function findBoostDevice()
  return firstTable(unpack(findBoostDevices()))
end

local function findBoostModule(device)
  if device == nil then
    return nil
  end
  if type(device.turbocharger) == "table" then
    return device.turbocharger
  end
  if type(device.turbocharger) == "string" and powertrain and type(powertrain.getDevice) == "function" then
    local resolved = powertrain.getDevice(device.turbocharger)
    if type(resolved) == "table" then
      return resolved
    end
  end
  return device
end

local function getUpvalue(func, name)
  if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
    return nil, nil
  end
  local index = 1
  while true do
    local upName, upValue = debug.getupvalue(func, index)
    if not upName then
      return nil, nil
    end
    if upName == name then
      return upValue, index
    end
    index = index + 1
  end
end

local function setUpvalue(func, name, value)
  if type(debug) ~= "table" or type(debug.setupvalue) ~= "function" then
    return false
  end
  local _, index = getUpvalue(func, name)
  if not index then
    return false
  end
  debug.setupvalue(func, index, value)
  return true
end

local function overwriteTableValues(tbl, value)
  for key, _ in pairs(tbl) do
    tbl[key] = value
  end
end

local function hasBoostSupport()
  local device = findBoostDevice()
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  local mainController = controller and controller.mainController or nil
  local deviceCandidates = { device }
  if device and type(device.turbocharger) == "table" then
    deviceCandidates[#deviceCandidates + 1] = device.turbocharger
  end
  if device and type(device.supercharger) == "table" then
    deviceCandidates[#deviceCandidates + 1] = device.supercharger
  end
  for _, field in ipairs(BOOST_FIELDS) do
    for _, dev in ipairs(deviceCandidates) do
      if dev and dev[field] ~= nil then
        return true
      end
    end
    if engine and engine[field] ~= nil then
      return true
    end
    if mainController and mainController[field] ~= nil then
      return true
    end
  end

  for _, dev in ipairs(deviceCandidates) do
    if dev and type(dev.setWastegateOffset) == "function" then
      return true
    end
  end
  return false
end

local function hasRevLimiterSupport()
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  if engine == nil then
    return false
  end
  return engine.maxRPM ~= nil or engine.maxAvailableRPM ~= nil
end

local function hasBoostCeilingSupport()
  local device = findBoostDevice()
  local module = findBoostModule(device)
  if module and (type(module.setWastegateLimit) == "function" or type(module.setWastegateStart) == "function") then
    return true
  end
  if module and (type(module.wastegateLimit) == "number" or type(module.wastegateLimit) == "table") then
    return true
  end
  if module and type(module.updateGFX) == "function" then
    local limit = getUpvalue(module.updateGFX, "wastegateLimit")
    return limit ~= nil
  end
  return false
end

local function applyBoostTarget(value)
  local numeric = safeNumber(value)
  if numeric == nil then
    return false, "invalid_value"
  end

  local target = clamp(numeric, 0, 2.5)
  local previousTarget = desiredBoostTarget or boostTarget
  local loweringTarget = previousTarget ~= nil and target < previousTarget
  local device = findBoostDevice()
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  local mainController = controller and controller.mainController or nil
  local applied = false
  local deviceCandidates = { device }
  if device and type(device.turbocharger) == "table" then
    deviceCandidates[#deviceCandidates + 1] = device.turbocharger
  end
  if device and type(device.supercharger) == "table" then
    deviceCandidates[#deviceCandidates + 1] = device.supercharger
  end

  for _, field in ipairs(BOOST_FIELDS) do
    for _, dev in ipairs(deviceCandidates) do
      if dev and dev[field] ~= nil then
        dev[field] = target
        applied = true
        break
      end
    end
    if applied then
      break
    end
  end

  if not applied then
    for _, dev in ipairs(deviceCandidates) do
      if dev and type(dev.setWastegateOffset) == "function" then
        desiredBoostTarget = target
        local actual = getActualBoostBar()
        local errorBar = target - actual
        boostPid.integral = clamp(boostPid.integral + errorBar, -5, 5)
        local derivative = errorBar - boostPid.lastError
        boostPid.lastError = errorBar
        local offsetDeltaPsi = (errorBar * boostPid.p + boostPid.integral * boostPid.i + derivative * boostPid.d) * PSI_PER_BAR
        local maxOffsetPsi = getBoostOffsetClampPsi()
        boostOffsetPsi = clamp((boostOffsetPsi or 0) + offsetDeltaPsi, -maxOffsetPsi, maxOffsetPsi)
        local ok = pcall(dev.setWastegateOffset, boostOffsetPsi)
        if not ok then ok = pcall(dev.setWastegateOffset, dev, boostOffsetPsi) end
        if not ok then ok = pcall(dev.setWastegateOffset, { offset = boostOffsetPsi }) end
        if not ok then ok = pcall(dev.setWastegateOffset, dev, { offset = boostOffsetPsi }) end
        if not ok then ok = pcall(dev.setWastegateOffset, { value = boostOffsetPsi }) end
        if not ok then ok = pcall(dev.setWastegateOffset, dev, { value = boostOffsetPsi }) end
        if ok then
          applied = true
          break
        end
      end
    end
  end

  if not applied then
    for _, field in ipairs(BOOST_FIELDS) do
      if engine and engine[field] ~= nil then
        engine[field] = target
        applied = true
        break
      end
    end
  end

  if not applied then
    for _, field in ipairs(BOOST_FIELDS) do
      if mainController and mainController[field] ~= nil then
        mainController[field] = target
        applied = true
        break
      end
    end
  end

  if not applied then
    if not boostDebugDumped then
      boostDebugDumped = true
      local devices = findBoostDevices()
      log("I", "torquelabPhase2", "TORQUELAB boost debug: scanning powertrain devices")
      for index, device in ipairs(devices) do
        local name = device.name or device.uiName or device.type or "unknown"
        local keys = {}
        for key, _ in pairs(device) do
          if type(key) == "string" then
            keys[#keys + 1] = key
          end
        end
        table.sort(keys)
        log("I", "torquelabPhase2", "Device[" .. index .. "] name=" .. tostring(name))
        log("I", "torquelabPhase2", "Device[" .. index .. "] keys=" .. table.concat(keys, ","))
        local boostKeys = {}
        for _, key in ipairs(keys) do
          local lower = string.lower(key)
          if string.find(lower, "boost") or string.find(lower, "turbo") or string.find(lower, "wg") or string.find(lower, "wastegate") or string.find(lower, "pressure") then
            boostKeys[#boostKeys + 1] = key
          end
        end
        if #boostKeys > 0 then
          log("I", "torquelabPhase2", "Device[" .. index .. "] boost-related keys=" .. table.concat(boostKeys, ","))
        end
        if type(device.turbocharger) == "table" then
          local turboKeys = {}
          for key, _ in pairs(device.turbocharger) do
            if type(key) == "string" then
              turboKeys[#turboKeys + 1] = key
            end
          end
          table.sort(turboKeys)
          if #turboKeys > 0 then
            log("I", "torquelabPhase2", "Device[" .. index .. "] turbocharger keys=" .. table.concat(turboKeys, ","))
          end
        end
      end
      if controller and controller.mainController then
        local keys = {}
        for key, _ in pairs(controller.mainController) do
          if type(key) == "string" then
            keys[#keys + 1] = key
          end
        end
        table.sort(keys)
        log("I", "torquelabPhase2", "MainController keys=" .. table.concat(keys, ","))
      end
      if electrics and electrics.values then
        local keys = {}
        for key, _ in pairs(electrics.values) do
          if type(key) == "string" then
            local lower = string.lower(key)
            if string.find(lower, "boost") or string.find(lower, "turbo") or string.find(lower, "pressure") or string.find(lower, "wg") or string.find(lower, "wastegate") then
              keys[#keys + 1] = key
            end
          end
        end
        table.sort(keys)
        log("I", "torquelabPhase2", "Electrics boost keys=" .. table.concat(keys, ","))
      end
    end
    return false, "unsupported"
  end

  if loweringTarget then
    boostOffsetPsi = 0
    boostPid.integral = 0
    boostPid.lastError = 0
    desiredBoostTarget = nil
    log("I", "torquelabPhase2", "TORQUELAB boostTarget lowered; reset boost offset/PID")
  end

  boostTarget = target
  return true, "applied"
end

local function applyBoostCeiling(value)
  local numeric = safeNumber(value)
  if numeric == nil then
    return false, "invalid_value"
  end

  local targetBar = clamp(numeric, 0.5, 3.0)
  local loweringCeiling = boostCeiling ~= nil and targetBar < boostCeiling
  local targetPsi = targetBar * PSI_PER_BAR
  local device = findBoostDevice()
  local module = findBoostModule(device)
  local applied = false

  if module and type(module.setWastegateLimit) == "function" then
    local ok = pcall(module.setWastegateLimit, module, targetPsi)
    if not ok then ok = pcall(module.setWastegateLimit, targetPsi) end
    if ok then
      log("I", "torquelabPhase2", "TORQUELAB boostCeiling used setWastegateLimit psi=" .. tostring(targetPsi))
      applied = true
    end
  end

  if not applied and module and type(module.setWastegateStart) == "function" then
    local ok = pcall(module.setWastegateStart, module, targetPsi * 0.85)
    if not ok then ok = pcall(module.setWastegateStart, targetPsi * 0.85) end
    if ok then
      log("I", "torquelabPhase2", "TORQUELAB boostCeiling used setWastegateStart psi=" .. tostring(targetPsi * 0.85))
      applied = true
    end
  end

  if not applied and module and type(module.wastegateLimit) == "number" then
    module.wastegateLimit = targetPsi
    log("I", "torquelabPhase2", "TORQUELAB boostCeiling set wastegateLimit field psi=" .. tostring(targetPsi))
    applied = true
  elseif not applied and module and type(module.wastegateLimit) == "table" then
    overwriteTableValues(module.wastegateLimit, targetPsi)
    log("I", "torquelabPhase2", "TORQUELAB boostCeiling set wastegateLimit table psi=" .. tostring(targetPsi))
    applied = true
  end

  if not applied and module and type(module.wastegateStart) == "number" then
    module.wastegateStart = targetPsi * 0.85
    log("I", "torquelabPhase2", "TORQUELAB boostCeiling set wastegateStart field psi=" .. tostring(targetPsi * 0.85))
    applied = true
  elseif not applied and module and type(module.wastegateStart) == "table" then
    overwriteTableValues(module.wastegateStart, targetPsi * 0.85)
    log("I", "torquelabPhase2", "TORQUELAB boostCeiling set wastegateStart table psi=" .. tostring(targetPsi * 0.85))
    applied = true
  end

  -- Note: debug.setupvalue is blocked by BeamNG's sandbox, so we cannot modify upvalues here.

  if not applied then
    return false, "unsupported"
  end

  if loweringCeiling then
    boostOffsetPsi = 0
    boostPid.integral = 0
    boostPid.lastError = 0
    desiredBoostTarget = nil
    log("I", "torquelabPhase2", "TORQUELAB boostCeiling lowered; reset boost offset/PID")
  end

  boostCeiling = targetBar
  return true, "applied"
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

local function collectDeviceKeyScan()
  if not powertrain or type(powertrain.getDevices) ~= "function" then
    return nil
  end

  local devices = powertrain.getDevices()
  if type(devices) ~= "table" then
    return nil
  end

  local patterns = { "cyl", "piston", "combust", "therm", "temp", "wear", "damage", "health" }
  local scan = {}

  for deviceName, device in pairs(devices) do
    if type(device) == "table" then
      local matches = {}
      for key, value in pairs(device) do
        if type(value) ~= "table" then
          local lowerKey = tostring(key):lower()
          for _, pat in ipairs(patterns) do
            if lowerKey:find(pat, 1, true) then
              matches[#matches + 1] = tostring(key)
              break
            end
          end
        end
      end
      if #matches > 0 then
        table.sort(matches)
        scan[tostring(deviceName)] = matches
      end
    end
  end

  if next(scan) == nil then
    return nil
  end

  return scan
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

local function decodeJson(value)
  if type(value) ~= "string" then
    return nil
  end

  if type(jsonDecode) == "function" then
    local ok, decoded = pcall(jsonDecode, value)
    if ok and type(decoded) == "table" then
      return decoded
    end
  end

  if type(json) == "table" and type(json.decode) == "function" then
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == "table" then
      return decoded
    end
  end

  return nil
end

local function applyTorqueScalar(value)
  local numeric = safeNumber(value)
  if numeric == nil then
    return false, "invalid_value"
  end

  local scalar = clamp(numeric, 0.5, 1.5)
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  if engine == nil then
    return false, "engine_missing"
  end

  if engine.torqueCurveScale ~= nil then
    engine.torqueCurveScale = scalar
  elseif engine.maxTorque ~= nil then
    baseMaxTorque = baseMaxTorque or engine.maxTorque
    engine.maxTorque = baseMaxTorque * scalar
  elseif engine.torqueMultiplier ~= nil then
    engine.torqueMultiplier = scalar
  else
    return false, "unsupported"
  end

  torqueScalar = scalar
  return true, "applied"
end

local function applyFuelTrimCell(value)
  ensureTrimMaps()
  if type(value) ~= "table" then
    return false, "invalid_value"
  end
  local row = value.row
  local col = value.col
  local cellValue = clampCell(value.value, -20, 20)
  if cellValue == nil then
    return false, "invalid_value"
  end
  if not setTrimCell(fuelTrimMap, row, col, cellValue) then
    return false, "out_of_range"
  end
  return true, "applied"
end

local function applyIgnTrimCell(value)
  ensureTrimMaps()
  if type(value) ~= "table" then
    return false, "invalid_value"
  end
  local row = value.row
  local col = value.col
  local cellValue = clampCell(value.value, -10, 10)
  if cellValue == nil then
    return false, "invalid_value"
  end
  if not setTrimCell(ignTrimMap, row, col, cellValue) then
    return false, "out_of_range"
  end
  return true, "applied"
end

local function applyFuelTrimBatch(value)
  ensureTrimMaps()
  if type(value) ~= "table" or type(value.cells) ~= "table" then
    return false, "invalid_value"
  end
  for _, cell in ipairs(value.cells) do
    local row = cell.row
    local col = cell.col
    local cellValue = clampCell(cell.value, -20, 20)
    if cellValue ~= nil then
      setTrimCell(fuelTrimMap, row, col, cellValue)
    end
  end
  return true, "applied"
end

local function applyIgnTrimBatch(value)
  ensureTrimMaps()
  if type(value) ~= "table" or type(value.cells) ~= "table" then
    return false, "invalid_value"
  end
  for _, cell in ipairs(value.cells) do
    local row = cell.row
    local col = cell.col
    local cellValue = clampCell(cell.value, -10, 10)
    if cellValue ~= nil then
      setTrimCell(ignTrimMap, row, col, cellValue)
    end
  end
  return true, "applied"
end

local function resetFuelTrim()
  fuelTrimMap = buildDefaultMap()
end

local function resetIgnTrim()
  ignTrimMap = buildDefaultMap()
end

local function applyRevLimiter(value)
  local numeric = safeNumber(value)
  if numeric == nil then
    return false, "invalid_value"
  end

  local target = clamp(numeric, 1000, 12000)
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  if engine == nil then
    return false, "engine_missing"
  end
  local applied = false
  local targetAV = target * 0.104719755

  if engine.maxRPM ~= nil then
    baseMaxRPM = baseMaxRPM or engine.maxRPM
    engine.maxRPM = target
    applied = true
  end

  if engine.maxAvailableRPM ~= nil then
    baseMaxAvailableRPM = baseMaxAvailableRPM or engine.maxAvailableRPM
    engine.maxAvailableRPM = target
    applied = true
  end

  if engine.revLimiterRPM ~= nil then
    engine.revLimiterRPM = target
    applied = true
  end

  if engine.revLimiter ~= nil then
    engine.revLimiter = target
    applied = true
  end

  if engine.tempRevLimiterAV ~= nil then
    engine.tempRevLimiterAV = targetAV
    applied = true
  end

  if type(engine.setTempRevLimiter) == "function" then
    local ok = pcall(engine.setTempRevLimiter, engine, targetAV)
    if not ok then
      ok = pcall(engine.setTempRevLimiter, targetAV)
    end
    if ok then
      applied = true
    end
  end

  local mainController = controller and controller.mainController or nil
  if type(mainController) == "table" then
    if mainController.maxRPM ~= nil then
      mainController.maxRPM = target
      applied = true
    end
    if mainController.revLimiterRPM ~= nil then
      mainController.revLimiterRPM = target
      applied = true
    end
    if mainController.revLimiter ~= nil then
      mainController.revLimiter = target
      applied = true
    end
  end

  if not applied then
    return false, "unsupported"
  end

  revLimiter = target
  return true, "applied"
end

local function buildPayload()
  local wheelSpeeds, suspensionTravel = collectWheelData()
  local powertrainData = collectPowertrainData()
  local health = collectHealthData()
  local deviceKeyScan = collectDeviceKeyScan()

  return {
    source = "vehicleLua",
    vehicleId = obj and obj:getID() or nil,
    wheelSpeeds = wheelSpeeds,
    suspensionTravel = suspensionTravel,
    torqueNm = powertrainData.torqueNm,
    gearRatio = powertrainData.gearRatio,
    boostCurve = powertrainData.boostCurve,
    health = health,
    deviceKeyScan = deviceKeyScan,
    tunables = {
      torqueScalar = true,
      boostTarget = hasBoostSupport(),
      boostCeiling = hasBoostSupport(),
      revLimiter = hasRevLimiterSupport(),
    },
    tune = {
      torqueScalar = torqueScalar,
      boostTarget = boostTarget,
      boostOffsetPsi = boostOffsetPsi,
      boostCeiling = boostCeiling,
      revLimiter = revLimiter,
      fuelTrimMap = fuelTrimMap,
      ignTrimMap = ignTrimMap,
      popDebug = popDebug,
      boostPid = {
        p = boostPid.p,
        i = boostPid.i,
        d = boostPid.d,
        integral = boostPid.integral,
        lastError = boostPid.lastError,
      },
      lastStatus = lastTuneStatus,
    },
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

local function ensureCommandSocket()
  if cmdSocket ~= nil then
    return true
  end

  cmdSocket = socket.udp()
  if cmdSocket == nil then
    return false
  end

  cmdSocket:settimeout(0)
  local ok, err = cmdSocket:setsockname(TARGET_HOST, CMD_PORT)
  if not ok then
    log("E", "torquelabPhase2", "TORQUELAB Phase 2 failed to bind tune socket: " .. tostring(err))
    return false
  end
  return true
end

local function pollTuneCommands(maxReads)
  if not ensureCommandSocket() then
    return
  end

  local reads = 0
  while reads < (maxReads or 4) do
    local payload = cmdSocket:receive()
    if not payload then
      return
    end
    reads = reads + 1

    local command = decodeJson(payload)
    if type(command) ~= "table" then
      lastTuneStatus = "bad_json"
    elseif command.type == "tune" then
      if command.param == "torqueScalar" then
        local ok, status = applyTorqueScalar(command.value)
        lastTuneStatus = ok and status or status
        if ok then
          log("I", "torquelabPhase2", "TORQUELAB tune torqueScalar=" .. tostring(torqueScalar))
        else
          log("W", "torquelabPhase2", "TORQUELAB tune rejected: " .. tostring(status))
        end
      elseif command.param == "boostTarget" then
        local ok, status = applyBoostTarget(command.value)
        lastTuneStatus = ok and status or status
        if ok then
          log("I", "torquelabPhase2", "TORQUELAB tune boostTarget=" .. tostring(boostTarget))
        else
          log("W", "torquelabPhase2", "TORQUELAB tune rejected: " .. tostring(status))
        end
      elseif command.param == "boostCeiling" then
        local ok, status = applyBoostCeiling(command.value)
        lastTuneStatus = ok and status or status
        if ok then
          log("I", "torquelabPhase2", "TORQUELAB tune boostCeiling=" .. tostring(boostCeiling))
        else
          log("W", "torquelabPhase2", "TORQUELAB tune rejected: " .. tostring(status))
        end
      elseif command.param == "revLimiter" then
        local ok, status = applyRevLimiter(command.value)
        lastTuneStatus = ok and status or status
        if ok then
          log("I", "torquelabPhase2", "TORQUELAB tune revLimiter=" .. tostring(revLimiter))
        else
          log("W", "torquelabPhase2", "TORQUELAB tune rejected: " .. tostring(status))
        end
      elseif command.param == "fuelTrimCell" then
        local ok, status = applyFuelTrimCell(command.value)
        lastTuneStatus = ok and status or status
      elseif command.param == "ignTrimCell" then
        local ok, status = applyIgnTrimCell(command.value)
        lastTuneStatus = ok and status or status
      elseif command.param == "fuelTrimBatch" then
        local ok, status = applyFuelTrimBatch(command.value)
        lastTuneStatus = ok and status or status
      elseif command.param == "ignTrimBatch" then
        local ok, status = applyIgnTrimBatch(command.value)
        lastTuneStatus = ok and status or status
      elseif command.param == "fuelTrimReset" then
        resetFuelTrim()
        lastTuneStatus = "applied"
      elseif command.param == "ignTrimReset" then
        resetIgnTrim()
        lastTuneStatus = "applied"
      end
    end
  end
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
  ensureCommandSocket()
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
  if pendingPopActive and not safeAfterfireMode then
    local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
    if engine then
      if engine.sustainedAfterFireTimer ~= nil then
        engine.sustainedAfterFireTimer = engine.sustainedAfterFireTime
      end
      if engine.instantAfterFireFuel ~= nil then
        engine.instantAfterFireFuel = math.max(engine.instantAfterFireFuel or 0, 12 * pendingPopStrength)
      end
      if engine.sustainedAfterFireFuel ~= nil then
        engine.sustainedAfterFireFuel = math.max(engine.sustainedAfterFireFuel or 0, 8 * pendingPopStrength)
      end
      if engine.shiftAfterFireFuel ~= nil then
        engine.shiftAfterFireFuel = math.max(engine.shiftAfterFireFuel or 0, 6 * pendingPopStrength)
      end
      if engine.continuousAfterFireFuel ~= nil then
        engine.continuousAfterFireFuel = math.max(engine.continuousAfterFireFuel or 0, 4 * pendingPopStrength)
      end
    end
  end
  sendPayload()
end

local function updateGFX(dt)
  elapsedSinceSend = elapsedSinceSend + (dt or 0)
  pollTuneCommands(6)
  ensureTrimMaps()
  local engine = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine") or nil
  local electricsValues = electrics and electrics.values or {}
  local rpmValue = firstNumber(
    electricsValues.rpm,
    electricsValues.engineRPM,
    electricsValues.rpmTacho,
    engine and engine.outputRPM or nil,
    engine and engine.outputAV1 and (engine.outputAV1 * 9.5493) or nil,
    engine and engine.outputAV and (engine.outputAV * 9.5493) or nil,
    engine and engine.inputAV and (engine.inputAV * 9.5493) or nil,
    electricsValues.avgWheelAV and (electricsValues.avgWheelAV * 9.5493) or nil
  ) or 0
  local throttleValue = firstNumber(
    electricsValues.throttle_input,
    electricsValues.throttle,
    electricsValues.engineThrottle
  ) or 0
  local engineLoadValue = safeNumber(electricsValues.engineLoad)
  local loadValue = engineLoadValue ~= nil and engineLoadValue or throttleValue
  if loadValue <= 1 then
    loadValue = loadValue * 100
  end
  loadValue = clamp(loadValue, 0, 100)
  local throttlePct = throttleValue
  if throttlePct <= 1 then
    throttlePct = throttlePct * 100
  end
  throttlePct = clamp(throttlePct, 0, 100)
  local trimRow = findClosestIndex(loadValue, LOAD_BINS)
  local trimCol = findClosestIndex(rpmValue, RPM_BINS)
  local fuelTrim = getTrimAt(fuelTrimMap, rpmValue, loadValue)
  local ignTrim = getTrimAt(ignTrimMap, rpmValue, loadValue)
  if engine and type(engine.torqueCurveScale) == "number" and not safeAfterfireMode then
    baseTorqueScale = baseTorqueScale or engine.torqueCurveScale
    local trimScalar = 1 + (fuelTrim or 0) * 0.005 + (ignTrim or 0) * 0.002
    trimScalar = clamp(trimScalar, 0.5, 1.5)
    engine.torqueCurveScale = baseTorqueScale * (torqueScalar or 1.0) * trimScalar
  end
  if engine then
    baseIgnitionCutTime = baseIgnitionCutTime or (engine.ignitionCutTime or 0)
    baseAfterFireCoef = baseAfterFireCoef or {
      instant = engine.instantAfterFireCoef or 0,
      sustained = engine.sustainedAfterFireCoef or 0,
      time = engine.sustainedAfterFireTime or 1.5,
      instantVol = engine.instantAfterFireVolumeCoef or 0,
      sustainedVol = engine.sustainedAfterFireVolumeCoef or 0,
      shiftVol = engine.shiftAfterFireVolumeCoef or 0,
      particulates = engine.particulates or 0,
      muffling = engine.exhaustAudioMufflingCoefRange or 1,
      gainDb = engine.exhaustAudioGainChange or 0,
    }
    local rpmMin, rpmMax = getBinRange(RPM_BINS, trimCol)
    local loadMin, loadMax = getBinRange(LOAD_BINS, trimRow)
    local inCellRange = (rpmValue >= rpmMin and rpmValue <= rpmMax) and (loadValue >= loadMin and loadValue <= loadMax)
    local hasPopTune = (ignTrim <= -2) or (fuelTrim >= 2)
    local forcePopActive = forcePop and (rpmValue > 1500)
    local tuneGate = (not requireTuneForPops) or hasPopTune
    local shouldPop = forcePopActive or (tuneGate
      and inCellRange
      and (loadValue < 25)
      and (rpmValue > 1500)
      and (throttlePct < 5))
    popDebug = {
      rpm = normalizeNumber(rpmValue, 0, 0.01),
      load = normalizeNumber(loadValue, 1, 0.01),
      rpmBin = RPM_BINS[trimCol],
      loadBin = LOAD_BINS[trimRow],
      inCellRange = inCellRange and true or false,
      ignTrim = normalizeNumber(ignTrim, 2, 0.001),
      fuelTrim = normalizeNumber(fuelTrim, 2, 0.001),
      throttle = normalizeNumber(throttlePct, 2, 0.001),
      engineLoad = normalizeNumber(firstNumber(electricsValues.engineLoad) or 0, 3, 0.001),
      exhaustNodesAttempted = exhaustNodesAttempted and true or false,
      exhaustNodesSet = exhaustNodesSet and true or false,
      exhaustStart = lastExhaustStart,
      exhaustFinish = lastExhaustFinish,
      forcePop = forcePopActive and true or false,
      popScale = popStrengthScale,
      instFuel = engine and engine.instantAfterFireFuel or nil,
      sustFuel = engine and engine.sustainedAfterFireFuel or nil,
      requireTune = requireTuneForPops and true or false,
      shouldPop = shouldPop and true or false,
    }
    M.popDebug = popDebug
    ensureExhaustSoundNodes(engine)
    local ignStrength = clamp((-ignTrim) / 10, 0, 1)
    local fuelStrength = clamp((fuelTrim) / 20, 0, 1)
    local tunedStrength = clamp(ignStrength * 0.55 + fuelStrength * 0.45, 0, 1)
    local tuneStrength = hasPopTune and tunedStrength or 0
    local strength = forcePopActive and 1 or tuneStrength
    strength = clamp(strength * popStrengthScale, 0, 1)
    local popStrength = shouldPop and strength or 0
    popDebug.appliedStrength = popStrength
    if baseAfterFireCoef then
      if requireTuneForPops and not hasPopTune then
        engine.instantAfterFireCoef = 0
        engine.sustainedAfterFireCoef = 0
        engine.instantAfterFireVolumeCoef = 0
        engine.sustainedAfterFireVolumeCoef = 0
        engine.shiftAfterFireVolumeCoef = 0
      elseif shouldPop then
        engine.instantAfterFireCoef = 60 * popStrength
        engine.sustainedAfterFireCoef = 40 * popStrength
        engine.instantAfterFireVolumeCoef = 60 * popStrength
        engine.sustainedAfterFireVolumeCoef = 50 * popStrength
        engine.shiftAfterFireVolumeCoef = 40 * popStrength
      else
        engine.instantAfterFireCoef = (baseAfterFireCoef.instant or 0)
        engine.sustainedAfterFireCoef = (baseAfterFireCoef.sustained or 0)
        engine.instantAfterFireVolumeCoef = math.max(baseAfterFireCoef.instantVol or 0, 10)
        engine.sustainedAfterFireVolumeCoef = math.max(baseAfterFireCoef.sustainedVol or 0, 10)
        engine.shiftAfterFireVolumeCoef = (baseAfterFireCoef.shiftVol or 0)
      end
      engine.sustainedAfterFireTime = math.max(baseAfterFireCoef.time or 1.5, 1.2)
      engine.particulates = math.max(baseAfterFireCoef.particulates or 0, (baseAfterFireCoef.particulates or 0) * (1 + 2.0 * popStrength))
      engine.exhaustAudioMufflingCoefRange = clamp((baseAfterFireCoef.muffling or 1) * (1 - 0.55 * popStrength), 0.05, 1)
      engine.exhaustAudioGainChange = clamp((baseAfterFireCoef.gainDb or 0) + 6 * popStrength, -12, 12)
    end
    if engine.antiLagCoefDesired ~= nil and not safeAfterfireMode then
      engine.antiLagCoefDesired = shouldPop and strength or 0
    end
    pendingPopActive = shouldPop
    pendingPopStrength = popStrength
    local device = findBoostDevice()
    local module = findBoostModule(device)
    popDebug.hasTurbo = module ~= nil
    if module and type(module.setAntilagCoef) == "function" then
      if shouldPop then
        local strength = clamp(math.abs(ignTrim) / 10, 0, 1)
        pcall(module.setAntilagCoef, strength)
        popDebug.antilag = strength
      else
        pcall(module.setAntilagCoef, 0)
        popDebug.antilag = 0
      end
    end
  end
  if desiredBoostTarget then
    local actual = getActualBoostBar()
    local error = desiredBoostTarget - actual
    boostPid.integral = clamp(boostPid.integral + error * 0.15, -5, 5)
    local derivative = error - boostPid.lastError
    boostPid.lastError = error
    local offsetDeltaPsi = (error * boostPid.p + boostPid.integral * boostPid.i + derivative * boostPid.d) * PSI_PER_BAR
    boostOffsetPsi = clamp((boostOffsetPsi or 0) + offsetDeltaPsi, -50, 50)
    local device = findBoostDevice()
    if device and type(device.turbocharger) == "table" then
      pcall(device.turbocharger.setWastegateOffset, device.turbocharger, boostOffsetPsi)
    elseif device and type(device.setWastegateOffset) == "function" then
      pcall(device.setWastegateOffset, device, boostOffsetPsi)
    end
  end
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
  if cmdSocket ~= nil then
    cmdSocket:close()
    cmdSocket = nil
  end
end

local function getPopDebug()
  return popDebug
end

local function setForcePop(value)
  forcePop = value == true
end

local function setSafeAfterfireMode(value)
  safeAfterfireMode = value == true
end

local function setPopStrengthScale(value)
  local numeric = safeNumber(value)
  if numeric == nil then
    return
  end
  popStrengthScale = clamp(numeric, 0, 1)
end

local function setRequireTuneForPops(value)
  requireTuneForPops = value ~= false
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onReset = onReset
M.updateGFX = updateGFX
M.getPopDebug = getPopDebug
M.setForcePop = setForcePop
M.setSafeAfterfireMode = setSafeAfterfireMode
M.setPopStrengthScale = setPopStrengthScale
M.setRequireTuneForPops = setRequireTuneForPops

return M

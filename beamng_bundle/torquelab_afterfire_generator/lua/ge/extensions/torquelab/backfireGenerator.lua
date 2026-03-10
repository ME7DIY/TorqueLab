local M = {}

local template = nil
local templateVersion = -1
local exhaustPatchVersion = 1
local afterfireNodeDefaults = {
  afterFireAudioCoef = 2.5,
  afterFireVolumeCoef = 2.5,
  afterFireMufflingCoef = 0.15,
  afterFireVisualCoef = 2.0,
  exhaustAudioMufflingCoef = 0.2,
  exhaustAudioGainChange = 4,
}

local function isEmptyOrWhitespace(str)
    return str == nil or str:match("^%s*$") ~= nil
end

local function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

local function isDictRow(row)
  if type(row) ~= "table" then
    return false
  end
  if row[1] ~= nil or row[2] ~= nil then
    return false
  end
  for k, _ in pairs(row) do
    if type(k) == "string" then
      return true
    end
  end
  return false
end

local function getGeneratedPath(originalPath)
  if isEmptyOrWhitespace(originalPath) then
    return nil
  end
  local relative = originalPath:gsub("^/vehicles/", "")
  if relative == originalPath then
    return nil
  end
  return "/mods/unpacked/torquelab_afterfire_generated/vehicles/" .. relative
end

local function ensureDirectory(path)
  if isEmptyOrWhitespace(path) then
    return
  end
  local dir = path:match("(.+)/[^/]+$")
  if dir and not FS:directoryExists(dir) then
    FS:directoryCreate(dir)
  end
end

local function readJsonFile(path)
    if isEmptyOrWhitespace(path) then
        log('E', 'readJsonFile', "path is empty")
        return nil
    end
    return jsonReadFile(path)
end

local function writeJsonFile(path, data, nice)
    return jsonWriteFile(path, data, nice)
end

local function getAllVehicles()
  local vehicles = {}
  for _, v in ipairs(FS:findFiles('/vehicles', '*', 0, false, true)) do
    if v ~= '/vehicles/common' then
      table.insert(vehicles, string.match(v, '/vehicles/(.*)'))
    end
  end
  return vehicles
end

local function getAfterfireJbeamPath(vehicleDir)
  local path = "/mods/unpacked/torquelab_afterfire_generated/vehicles/" .. vehicleDir .. "/torquelab_afterfire/" .. vehicleDir .. "_torquelab_afterfire.jbeam"
  return path
end

local function loadExistingAfterfireData(vehicleDir)
  return readJsonFile(getAfterfireJbeamPath(vehicleDir))
end

local function makeAndSaveNewTemplate(vehicleDir, slotName)
  local templateCopy = deepcopy(template)

  local mainPart = {}
  templateCopy.slotType = slotName
  mainPart[vehicleDir .. "_torquelab_afterfire"] = templateCopy

  local savePath = getAfterfireJbeamPath(vehicleDir)
  writeJsonFile(savePath, mainPart, true)
end

local function findMainPart(vehicleJbeam)
  if type(vehicleJbeam) ~= 'table' then return nil end

  for partKey, part in pairs(vehicleJbeam) do
    if part.slotType == "main" then
      return partKey
    end
  end
  return nil
end

local function loadMainSlot(vehicleDir)
  local vehJbeamPath = "/vehicles/" .. vehicleDir .. "/" .. vehicleDir .. ".jbeam"
  local vehicleJbeam = nil

  if FS:fileExists(vehJbeamPath) then
    vehicleJbeam = readJsonFile(vehJbeamPath)

    local mainPartKey = findMainPart(vehicleJbeam)
    if mainPartKey ~= nil then
      return vehicleJbeam[mainPartKey]
    end
  end

  local files = FS:findFiles("/vehicles/" .. vehicleDir, "*.jbeam", -1, true, false)
  for _, file in ipairs(files) do
    vehicleJbeam = readJsonFile(file)

    local mainPartKey = findMainPart(vehicleJbeam)
    if mainPartKey ~= nil then
      return vehicleJbeam[mainPartKey]
    end
  end

  return nil
end

local function getSlotTypes(slotTable)
  local slotTypes = {}
  for i, slot in pairs(slotTable) do
    if i > 1 then
      local slotType = slot[1]
      table.insert(slotTypes, slotType)
    end
  end
  return slotTypes
end

local function collectExhaustNodes(part)
  local exhaustNodes = {}
  if type(part) ~= "table" or type(part.beams) ~= "table" then
    return exhaustNodes
  end

  local beamDefaults = nil
  for _, row in ipairs(part.beams) do
    if isDictRow(row) then
      beamDefaults = row
    elseif type(row) == "table" and type(row[1]) == "string" and type(row[2]) == "string" then
      local options = type(row[3]) == "table" and row[3] or nil
      local isExhaust = (options and options.isExhaust) or (beamDefaults and beamDefaults.isExhaust)
      if isExhaust then
        exhaustNodes[row[1]] = true
        exhaustNodes[row[2]] = true
      end
    end
  end

  return exhaustNodes
end

local function applyAfterfireDefaults(nodeRow)
  if type(nodeRow) ~= "table" then
    return false
  end
  local props = nil
  if type(nodeRow[#nodeRow]) == "table" then
    props = nodeRow[#nodeRow]
  else
    props = {}
    table.insert(nodeRow, props)
  end

  local changed = false
  for key, value in pairs(afterfireNodeDefaults) do
    if props[key] == nil then
      props[key] = value
      changed = true
    end
  end
  return changed
end

local function patchExhaustNodes(part)
  if type(part) ~= "table" or type(part.nodes) ~= "table" then
    return false
  end
  local exhaustNodes = collectExhaustNodes(part)
  if next(exhaustNodes) == nil then
    return false
  end

  local changed = false
  for _, row in ipairs(part.nodes) do
    if type(row) == "table" and type(row[1]) == "string" and exhaustNodes[row[1]] then
      if applyAfterfireDefaults(row) then
        changed = true
      end
    end
  end

  return changed
end

local function patchJbeamFile(path)
  local data = readJsonFile(path)
  if type(data) ~= "table" then
    return false
  end

  if type(data.torquelabAfterfirePatch) == "table" and data.torquelabAfterfirePatch.version == exhaustPatchVersion then
    return false
  end

  local modified = false
  for _, part in pairs(data) do
    if type(part) == "table" then
      if patchExhaustNodes(part) then
        modified = true
      end
    end
  end

  if not modified then
    return false
  end

  data.torquelabAfterfirePatch = { version = exhaustPatchVersion }
  local outputPath = getGeneratedPath(path)
  if outputPath == nil then
    return false
  end
  ensureDirectory(outputPath)
  writeJsonFile(outputPath, data, true)
  return true
end

local function generateExhaustPatches(vehicleDir)
  local files = FS:findFiles("/vehicles/" .. vehicleDir, "*.jbeam", -1, true, false)
  for _, file in ipairs(files) do
    if not file:find("/torquelab_afterfire/") then
      patchJbeamFile(file)
    end
  end
end

local function generate(vehicleDir)
  local existingData = loadExistingAfterfireData(vehicleDir)
  if existingData ~= nil and existingData.version == templateVersion then
    log('D', 'generate', vehicleDir .. " up to date")
    return
  else
    log('D', 'generate', vehicleDir .. " NOT up to date, updating")
  end

  local mainSlotData = loadMainSlot(vehicleDir)
  if mainSlotData ~= nil and mainSlotData.slots ~= nil and type(mainSlotData.slots) == 'table' then
    for _,slotType in pairs(getSlotTypes(mainSlotData.slots)) do
      if ends_with(slotType, "_mod") then
        log('D', 'generate', "found mod slot: " .. slotType)
        makeAndSaveNewTemplate(vehicleDir, slotType)
      end
    end
  end
  if mainSlotData ~= nil and mainSlotData.slots2 ~= nil and type(mainSlotData.slots2) == 'table' then
    for _,slotType in pairs(getSlotTypes(mainSlotData.slots2)) do
      if ends_with(slotType, "_mod") then
        log('D', 'generate', "found mod slot: " .. slotType)
        makeAndSaveNewTemplate(vehicleDir, slotType)
      end
    end
  end
end

local function generateAll()
  log('D', 'generateAll', "running generateAll()")
  for _,veh in pairs(getAllVehicles()) do
    generate(veh)
    generateExhaustPatches(veh)
  end
  log('D', 'generateAll', "done")
end

local function loadTemplate()
  template = readJsonFile("/modslotgenerator/Afterfire.json")
  if template ~= nil then
    templateVersion = template.version
  end
end

local function onExtensionLoaded()
  log('D', 'GELua.torquelabAfterfireGenerator.onExtensionLoaded', "TORQUELAB Afterfire Generator Loaded")
  if template == nil then loadTemplate() end
  if template == nil then
    print("ERROR: Can't make TORQUELAB Afterfire mod. Template missing/invalid/failed to load!")
    return
  end
  generateAll()
end

local function deleteTempFiles()
  local files = FS:findFiles("/mods/unpacked/torquelab_afterfire_generated", "*", -1, true, false)
  for _, file in ipairs(files) do
    FS:removeFile(file)
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onModDeactivated = onExtensionLoaded
M.onModActivated = onExtensionLoaded
M.onExit = deleteTempFiles

return M

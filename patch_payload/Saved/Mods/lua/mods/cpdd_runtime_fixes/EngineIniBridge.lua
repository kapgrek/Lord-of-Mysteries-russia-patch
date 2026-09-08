local Loader = assert(LOMModLoader, "LOMModLoader is required")

local M = {}
local BEGIN_MARKER = "; BEGIN CPDD VISUAL CLARITY PATCH"
local END_MARKER = "; END CPDD VISUAL CLARITY PATCH"
local ALLOWED_SECTIONS = {
    ["/Script/Engine.RendererSettings"] = true,
    ["ConsoleVariables"] = true,
}
local ALLOWED_CVARS = {
    ["r.DynamicGlobalIlluminationMethod"] = true,
    ["r.ReflectionMethod"] = true,
    ["r.MotionBlurQuality"] = true,
    ["r.DefaultFeature.MotionBlur"] = true,
    ["r.LensFlareQuality"] = true,
    ["r.DefaultFeature.LensFlare"] = true,
    ["r.BloomQuality"] = true,
    ["r.DefaultFeature.Bloom"] = true,
    ["r.LightShaftQuality"] = true,
    ["r.RefractionQuality"] = true,
    ["r.Refraction.OffsetQuality"] = true,
    ["r.DistanceFieldAO"] = true,
    ["r.AOQuality"] = true,
    ["r.AmbientOcclusionLevels"] = true,
    ["r.AmbientOcclusionMaxQuality"] = true,
    ["r.Fog"] = true,
    ["r.VolumetricFog"] = true,
    ["r.VolumetricCloud"] = true,
}

local applied = false

local function report(message)
    local logger = Log or LaunchLog
    if logger and logger.Info then
        logger.Info("[CPDDVisualClarity] " .. tostring(message))
    end
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function engineIniPath()
    local root = tostring(Loader.Root or ""):gsub("\\", "/"):gsub("/+$", "")
    local savedRoot, replacements = root:gsub("/Mods$", "")
    if replacements ~= 1 then
        return nil
    end
    return savedRoot .. "/Config/Windows/Engine.ini"
end

local function managedBlock(source)
    local startAt = source:find(BEGIN_MARKER, 1, true)
    if startAt == nil then
        return nil
    end
    local endAt = source:find(END_MARKER, startAt + #BEGIN_MARKER, true)
    if endAt == nil then
        return nil
    end
    return source:sub(startAt, endAt + #END_MARKER - 1)
end

local function parseManagedCVars(source)
    local block = managedBlock(source)
    if block == nil then
        return {}, {}
    end
    local section = nil
    local values = {}
    local order = {}
    for rawLine in block:gmatch("[^\r\n]+") do
        local line = trim(rawLine)
        local first = line:sub(1, 1)
        if first == "[" then
            section = line:match("^%[([^%]]+)%]$")
        elseif line ~= "" and first ~= ";" and ALLOWED_SECTIONS[section] then
            local name, rawValue = line:match("^([%w%._]+)%s*=%s*([^;%s]+)")
            if name and ALLOWED_CVARS[name] then
                local value = tonumber(rawValue)
                if value ~= nil then
                    if values[name] == nil then
                        order[#order + 1] = name
                    end
                    values[name] = value
                end
            end
        end
    end
    return order, values
end

function M.Apply()
    if applied then
        return true, 0, 0, "already applied"
    end
    local path = engineIniPath()
    if path == nil then
        return false, 0, 0, "Saved directory could not be resolved"
    end
    local imported, library = pcall(import, "LuaFunctionLibrary")
    if not imported or library == nil then
        return false, 0, 0, "LuaFunctionLibrary is unavailable"
    end
    local loaded, source = pcall(function()
        return library.LoadFile(path)
    end)
    if not loaded or type(source) ~= "string" or source == "" then
        return false, 0, 0, "Visual Clarity block is not enabled"
    end
    local order, values = parseManagedCVars(source)
    if #order == 0 then
        return false, 0, 0, "Visual Clarity block is not enabled"
    end
    local intSetter = library.ChangeConsoleVariableOfIntWithCurrentPriority
        or library.ChangeConsoleVariableOfInt
    local floatSetter = library.ChangeConsoleVariableOfFloatWithCurrentPriority
        or library.ChangeConsoleVariableOfFloat
    if intSetter == nil or floatSetter == nil then
        return false, 0, 0, "console-variable setters are unavailable"
    end
    local changed = 0
    local failed = 0
    for _, name in ipairs(order) do
        local value = values[name]
        local setter = value == math.floor(value) and intSetter or floatSetter
        if pcall(function() setter(name, value) end) then
            changed = changed + 1
        else
            failed = failed + 1
        end
    end
    applied = true
    report("submitted " .. tostring(changed)
        .. " managed Engine.ini CVars (failed=" .. tostring(failed) .. ")")
    return failed == 0, changed, failed, path
end

Loader.On("after_main", function()
    local ok, changed, failed, detail = M.Apply()
    if not ok and detail ~= "Visual Clarity block is not enabled" then
        report(tostring(detail) .. " (changed=" .. tostring(changed)
            .. ", failed=" .. tostring(failed) .. ")")
    end
end, 1600, "cpdd.visual-clarity.engine-ini")

return M

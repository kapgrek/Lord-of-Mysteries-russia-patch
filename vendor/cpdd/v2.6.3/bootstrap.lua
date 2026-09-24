local File = import("LuaFunctionLibrary")
local Paths = import("BlueprintPathsLibrary")
local root = File.GetFilePath(Paths.ProjectSavedDir()) .. "/Mods/"

local Loader = {
    Version = "0.4.5",
    Root = root,
    Aliases = {},
    Overlays = {},
    OverlayApplied = {},
    OverlayTargets = {},
    ExternalLoaded = {},
    ExternalLoading = {},
    Hooks = {},
    Phases = {},
    Applied = {},
    Features = {
        PerformanceMode = true,
        DiagnosticsMode = false,
                RuntimeRowRepair = true,
        RuntimeUIRepair = true,
        StatisticsEverywhere = true,
        AdvancedDpsMeter = true,
        ExternalDpsMeter = false,
        DesktopChatUI = false,
    },
    Telemetry = {
        BootStartedMs = 0,
        BootStartedMemoryKb = 0,
        PhaseMillis = {},
        PhaseMemoryKb = {},
        OverlayReads = 0,
        OverlayReadHits = 0,
        OverlayExecutes = 0,
        OverlayMerges = 0,
        OverlaySkipped = 0,
    },
}
_G.LOMModLoader = Loader

local function now_ms()
    if os and type(os.clock) == "function" then
        return os.clock() * 1000
    end
    return 0
end

local function memory_kb()
    if type(collectgarbage) == "function" then
        local ok, value = pcall(collectgarbage, "count")
        if ok then return tonumber(value) or 0 end
    end
    return 0
end

Loader.Telemetry.BootStartedMs = now_ms()
Loader.Telemetry.BootStartedMemoryKb = memory_kb()

local function report(message)
    local logger = Log or LaunchLog
    if logger and logger.Error then logger.Error("[LOMModLoader] " .. tostring(message)) end
end

local function read_chunk(relative, chunk_name)
    local path = root .. relative
    if type(loadfile) == "function" then
        local chunk, message = loadfile(path)
        if chunk then return chunk, path end
    end
    local source = File.LoadFile(path)
    if source == nil or source == "" then
        return nil, "missing " .. path
    end
    local chunk, message = load(source, "@" .. (chunk_name or path))
    if not chunk then return nil, message end
    return chunk, path
end

local function apply_feature_settings(settings)
    if type(settings.PerformanceMode) == "boolean" then
        Loader.Features.PerformanceMode = settings.PerformanceMode
    end
    if type(settings.DiagnosticsMode) == "boolean" then
        Loader.Features.DiagnosticsMode = settings.DiagnosticsMode
    end
    if type(settings.RuntimeRowRepair) == "boolean" then
        Loader.Features.RuntimeRowRepair = settings.RuntimeRowRepair
    end
    if type(settings.RuntimeUIRepair) == "boolean" then
        Loader.Features.RuntimeUIRepair = settings.RuntimeUIRepair
    end
    if type(settings.StatisticsEverywhere) == "boolean" then
        Loader.Features.StatisticsEverywhere = settings.StatisticsEverywhere
    end
    if type(settings.AdvancedDpsMeter) == "boolean" then
        Loader.Features.AdvancedDpsMeter = settings.AdvancedDpsMeter
    end
    if type(settings.ExternalDpsMeter) == "boolean" then
        Loader.Features.ExternalDpsMeter = settings.ExternalDpsMeter
    end
    if type(settings.DesktopChatUI) == "boolean" then
        Loader.Features.DesktopChatUI = settings.DesktopChatUI
    end
    if settings.DpsMeterMode == "advanced" then
        Loader.Features.StatisticsEverywhere = true
        Loader.Features.AdvancedDpsMeter = true
        Loader.Features.ExternalDpsMeter = false
    elseif settings.DpsMeterMode == "native" then
        Loader.Features.StatisticsEverywhere = true
        Loader.Features.AdvancedDpsMeter = false
        Loader.Features.ExternalDpsMeter = false
    elseif settings.DpsMeterMode == "external" then
        Loader.Features.StatisticsEverywhere = false
        Loader.Features.AdvancedDpsMeter = false
        Loader.Features.ExternalDpsMeter = true
    elseif settings.DpsMeterMode == "off" then
        Loader.Features.StatisticsEverywhere = false
        Loader.Features.AdvancedDpsMeter = false
        Loader.Features.ExternalDpsMeter = false
    end
end

-- This optional file contains personal module and feature overrides. Missing
-- values keep their defaults above.
local user_settings = {}
local user_settings_chunk = read_chunk("lua/cpdd_user_settings.lua", "LOM user settings")
if user_settings_chunk then
    setfenv(user_settings_chunk, _G)
    local ok, settings = xpcall(user_settings_chunk, debug.traceback)
    if ok and type(settings) == "table" then
        user_settings = settings
        apply_feature_settings(settings)
    elseif not ok then
        report("user settings failed: " .. tostring(settings))
    end
end
Loader.UserSettings = user_settings

-- The patcher keeps its DPS choice separate so it never overwrites personal
-- modules or personal feature settings.
local patcher_settings = {}
local patcher_settings_chunk = read_chunk(
    "lua/cpdd_patcher_settings.lua",
    "LOM patcher settings"
)
if patcher_settings_chunk then
    setfenv(patcher_settings_chunk, _G)
    local ok, settings = xpcall(patcher_settings_chunk, debug.traceback)
    if ok and type(settings) == "table" then
        patcher_settings = settings
        apply_feature_settings(settings)
    elseif not ok then
        report("patcher settings failed: " .. tostring(settings))
    end
end
Loader.PatcherSettings = patcher_settings

local function module_relative(name)
    if type(name) ~= "string" or name:find("[^%w_%.]") or name:find("..", 1, true) then
        return nil
    end
    return "lua/" .. name:gsub("%.", "/") .. ".lua"
end

function Loader.LoadExternal(name)
    if Loader.ExternalLoaded[name] ~= nil then return Loader.ExternalLoaded[name] end
    if Loader.ExternalLoading[name] then return nil, "cyclic external load " .. tostring(name) end
    local relative = module_relative(name)
    if not relative then return nil, "invalid external module name " .. tostring(name) end
    local chunk, message = read_chunk(relative, name)
    if not chunk then return nil, message end
    Loader.ExternalLoading[name] = true
    setfenv(chunk, _G)
    local ok, value = xpcall(function() return chunk(name) end, debug.traceback)
    Loader.ExternalLoading[name] = nil
    if not ok then
        report("external data load " .. tostring(name) .. " failed: " .. tostring(value))
        return nil, value
    end
    if value == nil then value = true end
    Loader.ExternalLoaded[name] = value
    return value
end

local function sort_hooks(hooks)
    table.sort(hooks, function(a, b)
        if a.Priority == b.Priority then return a.Order < b.Order end
        return a.Priority < b.Priority
    end)
end

local registration_order = 0

function Loader.Apply(name, value, environment)
    local hooks = Loader.Hooks[name]
    if not hooks then return value end
    for _, hook in ipairs(hooks) do
        local ok, replacement = xpcall(function()
            return hook.Callback(value, environment, name)
        end, function(message)
            report("post-load hook " .. hook.Id .. " failed: " .. tostring(message))
            return message
        end)
        if ok and replacement ~= nil then value = replacement end
    end
    Loader.Applied[name] = (Loader.Applied[name] or 0) + 1
    return value
end

function Loader.Reapply(name)
    local game_loaded = Game and Game.loaded and Game.loaded[name]
    if game_loaded then
        local value = game_loaded.Ret ~= nil and game_loaded.Ret or game_loaded.ENV
        local replacement = Loader.Apply(name, value, game_loaded.ENV)
        if game_loaded.Ret ~= nil then game_loaded.Ret = replacement end
        return true
    elseif package.loaded[name] ~= nil then
        package.loaded[name] = Loader.Apply(name, package.loaded[name], _G)
        return true
    end
    return false
end

function Loader.ReapplyAll()
    local names = {}
    for name in pairs(Loader.Hooks) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do Loader.Reapply(name) end
end

function Loader.AfterLoad(name, callback, priority, id)
    assert(type(name) == "string" and type(callback) == "function")
    registration_order = registration_order + 1
    local hooks = Loader.Hooks[name] or {}
    Loader.Hooks[name] = hooks
    hooks[#hooks + 1] = {
        Callback = callback,
        Priority = tonumber(priority) or 0,
        Id = id or (name .. "#" .. registration_order),
        Order = registration_order,
    }
    sort_hooks(hooks)

    Loader.Reapply(name)
end

function Loader.On(phase, callback, priority, id)
    assert(type(phase) == "string" and type(callback) == "function")
    registration_order = registration_order + 1
    local hooks = Loader.Phases[phase] or {}
    Loader.Phases[phase] = hooks
    hooks[#hooks + 1] = {
        Callback = callback,
        Priority = tonumber(priority) or 0,
        Id = id or (phase .. "#" .. registration_order),
        Order = registration_order,
    }
    sort_hooks(hooks)
end

function Loader.RunPhase(phase, ...)
    local hooks = Loader.Phases[phase]
    if not hooks then return end
    local started = now_ms()
    local memoryBefore = memory_kb()
    local arguments = { ... }
    for _, hook in ipairs(hooks) do
        xpcall(function()
            hook.Callback(unpack(arguments))
        end, function(message)
            report("phase hook " .. hook.Id .. " failed: " .. tostring(message))
        end)
    end
    local elapsed = now_ms() - started
    local memoryDelta = memory_kb() - memoryBefore
    Loader.Telemetry.PhaseMillis[phase] = elapsed
    Loader.Telemetry.PhaseMemoryKb[phase] = memoryDelta
    local logger = Log or LaunchLog
    if logger and logger.Info then
        logger.Info("[LOMPerf] phase=" .. tostring(phase)
            .. " ms=" .. string.format("%.2f", elapsed)
            .. " memory_kb=" .. string.format("%.1f", memoryDelta))
    end
end

Loader.SetStatisticsEverywhere = function(enabled)
    Loader.Features.StatisticsEverywhere = enabled == true
    local ok, runtime = pcall(require, "mods.cpdd_runtime_fixes.Init")
    if ok and type(runtime) == "table" and type(runtime.SetStatisticsEverywhere) == "function" then
        return runtime.SetStatisticsEverywhere(enabled)
    end
    return Loader.Features.StatisticsEverywhere
end
Loader.SetRuntimeRowRepair = function(enabled)
    Loader.Features.RuntimeRowRepair = enabled == true
    local ok, runtime = pcall(require, "mods.cpdd_runtime_fixes.Init")
    if ok and type(runtime) == "table" and type(runtime.SetRuntimeRowRepair) == "function" then
        return runtime.SetRuntimeRowRepair(enabled)
    end
    return Loader.Features.RuntimeRowRepair
end
Loader.SetRuntimeUIRepair = function(enabled)
    Loader.Features.RuntimeUIRepair = enabled == true
    local ok, runtime = pcall(require, "mods.cpdd_runtime_fixes.Init")
    if ok and type(runtime) == "table" and type(runtime.SetRuntimeUIRepair) == "function" then
        return runtime.SetRuntimeUIRepair(enabled)
    end
    return Loader.Features.RuntimeUIRepair
end

local manifest_chunk, manifest_error = read_chunk("manifest.lua", "LOM Mods manifest")
local manifest = {}
if manifest_chunk then
    local ok, value = xpcall(manifest_chunk, function(message)
        report("manifest failed: " .. tostring(message))
        return message
    end)
    if ok and type(value) == "table" then manifest = value end
else
    report(manifest_error)
end
Loader.Manifest = manifest
for name, external in pairs(manifest.Overrides or {}) do Loader.Aliases[name] = external end
for name, external in pairs(manifest.Overlays or {}) do Loader.Overlays[name] = external end
for name, external in pairs(user_settings.PersonalOverrides or {}) do
    if type(name) == "string" and type(external) == "string"
        and module_relative(external) ~= nil then
        Loader.Aliases[name] = external
    end
end

local local_overrides_chunk = read_chunk("translation-overrides.lua", "local translation overrides")
if local_overrides_chunk then
    local ok, value = xpcall(local_overrides_chunk, function(message)
        report("local translation overrides failed: " .. tostring(message))
        return message
    end)
    if ok and type(value) == "table" then
        local overrides = value.Overrides or value
        for name, external in pairs(overrides) do
            if type(name) == "string" and type(external) == "string" then Loader.Aliases[name] = external end
        end
        for name, external in pairs(value.Overlays or {}) do
            if type(name) == "string" and type(external) == "string" then Loader.Overlays[name] = external end
        end
    end
end

local original_loaders = {}
for index, searcher in ipairs(package.loaders) do original_loaders[index] = searcher end

local function find_original_chunk(name)
    for _, searcher in ipairs(original_loaders) do
        local chunk = searcher(name)
        if type(chunk) == "function" then return chunk end
    end
    return nil
end

local overlay_chunks = {}

local function read_overlay_chunk(name)
    local cached = overlay_chunks[name]
    if cached ~= nil then
        Loader.Telemetry.OverlayReadHits = Loader.Telemetry.OverlayReadHits + 1
        return cached.Chunk, cached.Message
    end
    local overlay = Loader.Overlays[name]
    local relative = overlay and module_relative(overlay)
    if not relative then return nil, "invalid external overlay name " .. tostring(overlay) end
    Loader.Telemetry.OverlayReads = Loader.Telemetry.OverlayReads + 1
    local chunk, message = read_chunk(relative, overlay)
    overlay_chunks[name] = { Chunk = chunk, Message = message }
    return chunk, message
end

local function overlay_target(name, originalValue)
    local originalData = type(originalValue) == "table" and originalValue.data or nil
    return type(originalData) == "table" and Loader.OverlayTargets[name] == originalData
end

local function merge_overlay(name, originalValue, environment, translatedChunk, force)
    local originalData = type(originalValue) == "table" and originalValue.data or nil
    if type(originalData) ~= "table" then
        report("translation overlay " .. name .. " has an invalid original module shape")
        return originalValue
    end
    if Loader.OverlayTargets[name] == originalData and not force then return originalValue end

    setfenv(translatedChunk, environment or _G)
    Loader.Telemetry.OverlayExecutes = Loader.Telemetry.OverlayExecutes + 1
    local ok, translatedValue = xpcall(function() return translatedChunk(name) end, debug.traceback)
    local translatedData = ok and type(translatedValue) == "table" and translatedValue.data or nil
    if type(translatedData) ~= "table" then
        report("translation overlay " .. name .. " has an invalid translated module shape: " .. tostring(translatedValue))
        return originalValue
    end
    local external = Loader.Overlays[name]
    if external then Loader.ExternalLoaded[external] = translatedValue end

    local count = 0
    for key, value in pairs(translatedData) do
        originalData[key] = value
        count = count + 1
    end
    Loader.OverlayTargets[name] = originalData
    Loader.OverlayApplied[name] = count
    Loader.Telemetry.OverlayMerges = Loader.Telemetry.OverlayMerges + 1
    return originalValue
end

function Loader.ReapplyOverlay(name, force)
    local overlay = Loader.Overlays[name]
    if not overlay then return false end
    local originalValue, environment, loaded
    if Game and Game.loaded and Game.loaded[name] then
        loaded = Game.loaded[name]
        originalValue = loaded.Ret ~= nil and loaded.Ret or loaded.ENV
        environment = loaded.ENV
    elseif package.loaded[name] ~= nil then
        originalValue = package.loaded[name]
        environment = _G
    else
        return false
    end
    if overlay_target(name, originalValue) and not force then
        Loader.Telemetry.OverlaySkipped = Loader.Telemetry.OverlaySkipped + 1
        return true
    end
    local translatedChunk, message = read_overlay_chunk(name)
    if not translatedChunk then
        report("translation overlay " .. name .. " -> " .. overlay .. " failed: " .. tostring(message))
        return false
    end
    local merged = merge_overlay(name, originalValue, environment, translatedChunk, force)
    if loaded and loaded.Ret ~= nil then loaded.Ret = merged end
    if package.loaded[name] ~= nil then package.loaded[name] = merged end
    return Loader.OverlayTargets[name] ~= nil
end

function Loader.ReapplyOverlays(force)
    local applied = 0
    for name in pairs(Loader.Overlays) do
        if Loader.ReapplyOverlay(name, force) then applied = applied + 1 end
    end
    return applied
end

local function external_searcher(name)
    local overlay = Loader.Overlays[name]
    if overlay then
        local translatedChunk, message = read_overlay_chunk(name)
        local originalChunk = find_original_chunk(name)
        if translatedChunk and originalChunk then
            return function(...)
                local environment = getfenv(1)
                setfenv(originalChunk, environment)
                local originalValue = originalChunk(...)
                originalValue = merge_overlay(name, originalValue, environment, translatedChunk)
                if Loader.Hooks[name] then return Loader.Apply(name, originalValue, environment) end
                return originalValue
            end
        end
        report("translation overlay " .. name .. " -> " .. overlay .. " failed: " .. tostring(message))
        return "\n\ttranslation overlay unavailable for " .. tostring(name)
    end

    local mapped = Loader.Aliases[name]
    if mapped == nil and name:sub(1, 5) == "mods." then mapped = name end
    if mapped then
        local relative = module_relative(mapped)
        if not relative then return "\n\tinvalid external module name " .. tostring(mapped) end
        local chunk, message = read_chunk(relative, mapped)
        if chunk then
            if Loader.Hooks[name] then
                return function(...)
                    local environment = getfenv(1)
                    setfenv(chunk, environment)
                    return Loader.Apply(name, chunk(...), environment)
                end
            end
            return chunk
        end
        report("external mapping " .. name .. " -> " .. mapped .. " failed: " .. tostring(message))
        return "\n\t" .. tostring(message)
    end

    if Loader.Hooks[name] then
        local chunk = find_original_chunk(name)
        if chunk then
            return function(...)
                setfenv(chunk, getfenv(1))
                return Loader.Apply(name, chunk(...), getfenv(1))
            end
        end
    end
    return "\n\tno Lord of Mysteries external mapping for " .. name
end

table.insert(package.loaders, 1, external_searcher)
Loader.Searcher = external_searcher
Loader.ReapplyOverlays()
Loader.On("after_prepare", function() Loader.ReapplyOverlays() end, -1000000, "loader.translation_overlays.prepare")
Loader.On("after_main", function()
    Loader.ReapplyOverlays()
    local moduleCount, entryCount = 0, 0
    for _, count in pairs(Loader.OverlayApplied) do
        moduleCount = moduleCount + 1
        entryCount = entryCount + (tonumber(count) or 0)
    end
    if Loader.Diagnostics then
        Loader.Diagnostics:Gauge("translation_data", "overlay_modules", moduleCount)
        Loader.Diagnostics:Gauge("translation_data", "overlay_entries", entryCount)
    end
    local activeLogger = Log or LaunchLog
    if activeLogger and activeLogger.Info then
        activeLogger.Info("[LOMModLoader] translation overlays applied modules=" .. tostring(moduleCount) .. " entries=" .. tostring(entryCount))
        activeLogger.Info("[LOMPerf] overlays reads=" .. tostring(Loader.Telemetry.OverlayReads)
            .. " read_hits=" .. tostring(Loader.Telemetry.OverlayReadHits)
            .. " executes=" .. tostring(Loader.Telemetry.OverlayExecutes)
            .. " merges=" .. tostring(Loader.Telemetry.OverlayMerges)
            .. " skipped=" .. tostring(Loader.Telemetry.OverlaySkipped))
    end
end, 1000000, "loader.translation_overlays.main")

Loader.AfterLoad("Gameplay.GameInit.Main", function(value)
    if not Loader.MainWrapped then
        Loader.MainWrapped = true
        local prepare = MainPrepare
        MainPrepare = function(...)
            local result = { prepare(...) }
            Loader.RunPhase("after_prepare")
            return unpack(result)
        end
        local main = Main
        Main = function(...)
            local result = { main(...) }
            Loader.RunPhase("after_main")
            return unpack(result)
        end
    end
    return value
end, 1000000, "loader.lifecycle.main")

for _, name in ipairs(manifest.Load or {}) do
    local enabled = true
    if name == "mods.cpdd_runtime_fixes.DpsMeter" then
        enabled = Loader.Features.StatisticsEverywhere ~= false
            and Loader.Features.AdvancedDpsMeter ~= false
    elseif name == "mods.cpdd_runtime_fixes.DpsTelemetry" then
        enabled = Loader.Features.ExternalDpsMeter == true
    elseif name == "mods.cpdd_runtime_fixes.DesktopChat" then
        enabled = Loader.Features.DesktopChatUI == true
    end
    if enabled then
        local ok, message = xpcall(function() require(name) end, debug.traceback)
        if not ok then report("entry module " .. tostring(name) .. " failed: " .. tostring(message)) end
    end
end
for _, name in ipairs(user_settings.PersonalLoad or {}) do
    local enabled = name ~= "mods.personal_cjk_logger.Init"
        or Loader.Features.DiagnosticsMode == true
    if enabled and type(name) == "string" and module_relative(name) ~= nil then
        local ok, message = xpcall(function() require(name) end, debug.traceback)
        if not ok then report("personal module " .. tostring(name) .. " failed: " .. tostring(message)) end
    end
end

local logger = Log or LaunchLog
if logger and logger.Info then
    local overlayCount = 0
    for _ in pairs(Loader.Overlays) do overlayCount = overlayCount + 1 end
    logger.Info("[LOMModLoader] external bootstrap loaded v" .. Loader.Version .. " overlays=" .. tostring(overlayCount))
    logger.Info("[LOMPerf] bootstrap ms="
        .. string.format("%.2f", now_ms() - Loader.Telemetry.BootStartedMs)
        .. " memory_kb="
        .. string.format("%.1f", memory_kb() - Loader.Telemetry.BootStartedMemoryKb))
end

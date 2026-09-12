-- ============================================================================
-- Lord of the Mysteries (C7 / UE5 / Slua) — Text & Localization Diagnostics
-- File: TextDiagnostics.lua
-- Purpose: Deeply trace text rendering, language settings, and translation
--          pipeline to diagnose why English text is not replaced with Russian.
-- ============================================================================

local MODULE_TAG = "[TextDiagnostics]"
local Loader = rawget(_G, "LOMModLoader")

local function safe_import(name)
    local ok, lib = pcall(import, name)
    if ok and lib ~= nil then return lib end
    return nil
end

local FileLib = safe_import("LuaFunctionLibrary")
local PathsLib = safe_import("BlueprintPathsLibrary")
local KismetSys = safe_import("KismetSystemLibrary")

-- Resolve log directory and file
local function resolveLogPath()
    local savedDir = ""
    if PathsLib and type(PathsLib.ProjectSavedDir) == "function" then
        pcall(function()
            local raw = PathsLib.ProjectSavedDir()
            if FileLib and type(FileLib.GetFilePath) == "function" then
                savedDir = FileLib.GetFilePath(raw)
            else
                savedDir = tostring(raw)
            end
        end)
    end
    if savedDir == "" then savedDir = "Saved" end
    savedDir = savedDir:gsub("\\", "/")
    if savedDir:sub(-1) == "/" then savedDir = savedDir:sub(1, -2) end

    local logDir = savedDir .. "/Mods/Logs"
    pcall(function()
        if FileLib and type(FileLib.CreateDirectory) == "function" then
            FileLib.CreateDirectory(logDir)
        elseif FileLib and type(FileLib.MakeDirectory) == "function" then
            FileLib.MakeDirectory(logDir)
        end
        if os and type(os.execute) == "function" then
            os.execute('mkdir "' .. logDir:gsub("/", "\\") .. '" 2>nul')
        end
    end)

    return logDir .. "/lom_diagnostics.log"
end

local LOG_FILE_PATH = resolveLogPath()
local logHandle = nil

pcall(function()
    logHandle = io.open(LOG_FILE_PATH, "a")
end)

local function getTimestamp()
    if os and type(os.date) == "function" then
        return os.date("%Y-%m-%d %H:%M:%S")
    end
    return "0000-00-00 00:00:00"
end

local function raw_log(tag, message)
    local line = string.format("[%s] [%s] %s\n", getTimestamp(), tag, tostring(message))
    if logHandle then
        pcall(function()
            logHandle:write(line)
            logHandle:flush()
        end)
    end

    local logger = rawget(_G, "Log") or rawget(_G, "LaunchLog")
    if logger and type(logger.Info) == "function" then
        pcall(logger.Info, "[LOMDiag] " .. line)
    end
end

-- Export global diagnostic logger
_G.__LOM_DiagLog = raw_log

raw_log("INIT", "============================================================")
raw_log("INIT", "Lord of the Mysteries — Russian Localization Diagnostics Init")
raw_log("INIT", "Version: 2.6-RU Diagnostics | Log: " .. LOG_FILE_PATH)
raw_log("INIT", "Lua version: " .. tostring(_VERSION))

-- Probe game language and environment
local function probeEnvironment()
    local info = {}
    table.insert(info, "Lua Engine: Slua/LuaJIT")

    -- Check Culture / Language settings in UE5
    pcall(function()
        local KismetText = safe_import("KismetTextLibrary")
        if KismetText then
            table.insert(info, "KismetTextLibrary: available")
        end
    end)

    -- Probe Game globals
    local gameObj = rawget(_G, "Game")
    if gameObj then
        table.insert(info, "Global Game object: present")
        if gameObj.Language then
            table.insert(info, "Game.Language = " .. tostring(gameObj.Language))
        end
        if gameObj.Culture then
            table.insert(info, "Game.Culture = " .. tostring(gameObj.Culture))
        end
    else
        table.insert(info, "Global Game object: not yet loaded")
    end

    -- Probe Loader features
    if Loader then
        table.insert(info, "LOMModLoader version: " .. tostring(Loader.Version))
        table.insert(info, "LOMModLoader Russian: " .. tostring(Loader.RussianLocalization))
        if Loader.Features then
            table.insert(info, string.format("Features: PerfMode=%s, DiagMode=%s, RowRepair=%s, UIRepair=%s",
                tostring(Loader.Features.PerformanceMode),
                tostring(Loader.Features.DiagnosticsMode),
                tostring(Loader.Features.RuntimeRowRepair),
                tostring(Loader.Features.RuntimeUIRepair)
            ))
        end
    else
        table.insert(info, "WARNING: LOMModLoader global is NIL!")
    end

    -- Check Loaded translation overlays
    local overlayCount = 0
    if Loader and Loader.OverlayApplied then
        for mod, count in pairs(Loader.OverlayApplied) do
            overlayCount = overlayCount + 1
            table.insert(info, string.format("Overlay loaded: %s (entries=%s)", mod, tostring(count)))
        end
    end
    table.insert(info, "Total overlay modules applied: " .. overlayCount)

    for _, line in ipairs(info) do
        raw_log("ENV", line)
    end
end

probeEnvironment()

-- ----------------------------------------------------------------------------
-- String Analysis and Interception Tracing
-- ----------------------------------------------------------------------------
local Stats = {
    TotalIntercepted = 0,
    CjkCount = 0,
    EnglishCount = 0,
    CyrillicCount = 0,
    GeminiHits = 0,
    GeminiMisses = 0,
    UniqueEnglishSeen = {},
    UniqueEnglishList = {},
    UniqueEnglishCount = 0,
}

local function hasCjk(str)
    return type(str) == "string" and str:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function hasCyrillic(str)
    -- Cyrillic UTF-8 range: D0 80 to D1 BF
    return type(str) == "string" and str:find("[\208-\209][\128-\191]") ~= nil
end

local function isAsciiEnglish(str)
    return type(str) == "string" and str:find("[%a]") ~= nil and not hasCjk(str) and not hasCyrillic(str)
end

local function recordStringEncounter(context, originalText, translatedText)
    if type(originalText) ~= "string" or originalText == "" then return end
    Stats.TotalIntercepted = Stats.TotalIntercepted + 1

    local cjk = hasCjk(originalText)
    local cyr = hasCyrillic(originalText)
    local eng = isAsciiEnglish(originalText)

    if cjk then Stats.CjkCount = Stats.CjkCount + 1 end
    if cyr then Stats.CyrillicCount = Stats.CyrillicCount + 1 end
    if eng then
        Stats.EnglishCount = Stats.EnglishCount + 1

        -- Record unique English string
        if not Stats.UniqueEnglishSeen[originalText] then
            Stats.UniqueEnglishSeen[originalText] = {
                count = 1,
                context = context or "Unknown",
                sample = originalText:sub(1, 120),
                translated = (translatedText ~= originalText) and tostring(translatedText):sub(1, 120) or nil
            }
            Stats.UniqueEnglishCount = Stats.UniqueEnglishCount + 1
            if Stats.UniqueEnglishCount <= 200 then
                table.insert(Stats.UniqueEnglishList, originalText)
                raw_log("ENGLISH_RAW", string.format("[ctx=%s] %s%s",
                    context or "UI",
                    originalText:sub(1, 100),
                    (#originalText > 100 and "..." or "")
                ))
            end
        else
            Stats.UniqueEnglishSeen[originalText].count = Stats.UniqueEnglishSeen[originalText].count + 1
        end
    end
end

-- ----------------------------------------------------------------------------
-- Hooking into Init.lua runtime functions if available
-- ----------------------------------------------------------------------------
local function hookRuntimeFixes()
    raw_log("HOOK", "Setting up translation diagnostics hooks...")

    -- 1. Check if Init module is loaded
    local runtimeMod = package.loaded["mods.cpdd_runtime_fixes.Init"]
    if runtimeMod then
        raw_log("HOOK", "cpdd_runtime_fixes.Init is loaded.")
    end

    -- 2. Hook global Text widget SetText if accessible
    pcall(function()
        local KGUILib = safe_import("UIFunctionLibrary")
        if KGUILib then
            raw_log("HOOK", "UIFunctionLibrary found")
        end
    end)
end

hookRuntimeFixes()

-- ----------------------------------------------------------------------------
-- Periodic stats logging
-- ----------------------------------------------------------------------------
local function logPeriodicSummary()
    raw_log("SUMMARY", string.format(
        "Stats: Total=%d | CJK=%d | English=%d | Cyrillic=%d | UniqueEnglish=%d",
        Stats.TotalIntercepted,
        Stats.CjkCount,
        Stats.EnglishCount,
        Stats.CyrillicCount,
        Stats.UniqueEnglishCount
    ))

    -- Check if Gemini runtime text shards are loadable
    pcall(function()
        local testShard = "000"
        local ok, shard = pcall(require, "mods.cpdd_runtime_fixes.RuntimeTextGemini_" .. testShard)
        if ok and type(shard) == "table" then
            local count = 0
            for _ in pairs(shard) do count = count + 1 end
            raw_log("SHARD_TEST", string.format("RuntimeTextGemini_%s OK (contains %d keys)", testShard, count))
        else
            raw_log("SHARD_TEST", string.format("ERROR: RuntimeTextGemini_%s FAILED to load: %s", testShard, tostring(shard)))
        end
    end)
end

-- Hook after_main for periodic summary
if Loader and type(Loader.On) == "function" then
    Loader.On("after_main", function()
        raw_log("LIFECYCLE", "Phase: after_main triggered!")
        probeEnvironment()
        logPeriodicSummary()

        pcall(function()
            local GameObj = rawget(_G, "Game")
            if GameObj and GameObj.NewUIManager and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
                GameObj.NewUIManager:AddTimerWithFunction(10.0, -1, function()
                    pcall(logPeriodicSummary)
                end)
                raw_log("HOOK", "Diagnostic 10s timer registered in NewUIManager")
            end
        end)
    end, -100, "cpdd.text_diagnostics.lifecycle")
end

-- Hook UIComponent to trace texts in panels
if Loader and type(Loader.AfterLoad) == "function" then
    Loader.AfterLoad("Framework.KGFramework.KGUI.Core.UIComponent", function(mod)
        raw_log("HOOK", "Framework.KGFramework.KGUI.Core.UIComponent loaded, attaching text inspection...")
        if type(mod) == "table" then
            for _, method in ipairs({ "Open", "Refresh" }) do
                local orig = rawget(mod, method) or mod[method]
                if type(orig) == "function" then
                    mod[method] = function(self, ...)
                        local res = { orig(self, ...) }
                        pcall(function()
                            local name = tostring(self.uid or self.UID or self.__cname or "Panel")
                            -- Inspect root widget texts
                            local w = self.userWidget or self.widget or self.panel
                            if w then
                                local function scanWidget(item)
                                    if item == nil then return end
                                    if type(item.GetText) == "function" then
                                        local txt = item:GetText()
                                        if txt ~= nil then
                                            recordStringEncounter(name .. ":" .. tostring(item:GetName()), tostring(txt), nil)
                                        end
                                    end
                                    local cnt = tonumber(type(item.GetChildrenCount) == "function" and item:GetChildrenCount()) or 0
                                    for i = 0, cnt - 1 do
                                        pcall(function() scanWidget(item:GetChildAt(i)) end)
                                    end
                                end
                                scanWidget(w)
                            end
                        end)
                        return unpack(res)
                    end
                end
            end
        end
        return mod
    end, 150, "cpdd.text_diagnostics.uicomp")
end

raw_log("INIT", "TextDiagnostics module successfully registered!")
return {
    Stats = Stats,
    Log = raw_log,
    RecordString = recordStringEncounter
}

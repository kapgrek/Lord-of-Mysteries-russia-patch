-- AbsoluteRU asset export from game memory (TASK-018, docs/tasks/TASK-018-godway-export.md).
--
-- Dev-only. Init.lua loads this module only when Saved/Mods/lua/absoluteru_dev.lua
-- returns Enabled = true and a non-empty AssetExport table, after
-- AbsruDiagnostics has started (its JSON encoder and panel walk are reused).
-- Everything goes to Saved/Mods/logs/godway/; every engine call is protected.
-- Modes (AssetExport.Probe):
--   true        step 0: once per session, 3 s after one of AssetExport.Panels
--               opens, one probe stage per timer tick checks KismetRenderingLibrary
--               on one Texture2D, one KGSprite and one material -> probe.json
--               (rewritten before and after every stage, so a crash shows the
--               stage it happened in), PNG files and one "[AbsruExport] probe" line.
--   "retainer"  step 3.0 (probe 4): a RetainerBox renders an Image with the
--               control icon, the Img_Bg01 material and one liudong04 material;
--               its render target is copied out -> probe_retainer.json and one
--               "[AbsruExport] retainer" line.
--   false / nil full export (steps 1-3): textures, atlases and sprites,
--               materials, layout snapshots, the parameter timeline and
--               RetainerBox reference frames; one "[AbsruExport] done" line.

local E = {}

local PROBE_DELAY = 3.0
local STEP_SECONDS = 0.05
local WALK_BUDGET_MS = 4
local WALK_TICKS_MAX = 200
local SECOND_DRAW_MS = 1000
local RT_SIZE = 512
local ERRORS_LOGGED = 3
local ERRORS_MAX = 200
local TEXT_MAX = 300
local KEYS_MAX = 200

-- Constants live in one table (the field lists below are added to it): the
-- main chunk stays well under LuaJIT's 200 local variables (VerifyPatch.ps1).
-- Times are ms from the panel opening unless noted.
local K = {
    FULL_DELAY_MS = 3000,       -- second walk, first layout snapshot, first exports
    MIP_WAIT_MS = 2000,         -- SetForceMipLevelsToBeResident -> export
    POLL_MS = 1000,             -- selected-path signature
    SIGNATURE_NOISE_MS = 15000, -- panel fields changing before this are not a path change
    SAVE_MS = 5000,
    OPEN_WINDOW_MS = 10000,
    PATH_WINDOW_MS = 5000,
    PATH_SNAPSHOT_MS = 2000,
    IDLE_DONE_MS = 30000,
    FILES_MAX = 3000,
    MB_MAX = 600,
    EVENTS_MAX = 150000,
    CALIB_PARALLEL = 2,
    CALIB_POOL_MB = 256,
    CALIB_SIDE_MAX = 1024,
    CALIB_OPEN_MS = 2000,
    CALIB_OPEN_FRAMES = 40,
    CALIB_MOMENTS = {
        { tick = 0 }, { tick = 1 }, { tick = 2 }, { tick = 3 },
        { ms = 250 }, { ms = 500 }, { ms = 1000 }, { ms = 2000 }, { ms = 4000 },
    },
    -- Reference frames stop at this share of the ceiling, so textures always fit.
    CALIB_SHARE = 0.75,
    RT_WAIT_TICKS = 20,
    W3D_PATH = "/Engine/EngineMaterials/Widget3DPassThrough.Widget3DPassThrough",
    FIELD_KIND = {
        ScalarParameterValues = "scalar", VectorParameterValues = "vector", TextureParameterValues = "texture",
    },
    SAVE_ORDER = { "state", "textures", "sprites", "materials", "timeline" },
}

K.API_NAMES = {
    "CreateRenderTarget2D", "DrawMaterialToRenderTarget", "BeginDrawCanvasToRenderTarget",
    "EndDrawCanvasToRenderTarget", "ExportRenderTarget", "ExportTexture2D", "ReadRenderTargetPixel",
    "ReadRenderTargetRawPixel", "ClearRenderTarget2D", "ReleaseRenderTarget2D",
}
-- The C7.log line lists only the calls the export depends on.
K.API_LOGGED = {
    "CreateRenderTarget2D", "DrawMaterialToRenderTarget", "BeginDrawCanvasToRenderTarget",
    "EndDrawCanvasToRenderTarget", "ExportRenderTarget", "ExportTexture2D", "ReadRenderTargetPixel",
}
-- slua metatables do not list UPROPERTYs (probe 2026-09-26_1616: only __index
-- and friends), so KGSprite / KGSpriteAtlas fields are probed by name.
K.SPRITE_FIELDS = {
    "BakedSourceTexture", "SourceTexture", "AtlasTexture", "Atlas", "SpriteAtlas", "Texture",
    "BakedSourceUV", "BakedSourceDimension", "SourceUV", "SourceDimension", "SourceTextureDimension",
    "SourceSize", "Size", "ImageSize", "TextureSize", "UV", "StartUV", "SizeUV", "bRotated", "Rotated",
    "bTrimmed", "TrimRect", "Pivot", "CustomPivotPoint", "PixelsPerUnrealUnit", "Margin",
    "SpriteName", "AtlasData", "SlateAtlasData", "SpriteInfo", "SpriteData",
    "Rect", "SourceRect", "UVRect", "UVs", "TextureRect", "SpriteRect", "Region", "Frame", "Offset",
    "Position", "X", "Y", "Width", "Height", "W", "H", "Index", "AtlasIndex", "PageIndex",
    "TextureIndex", "OriginalSize", "SpriteSize", "RawSize", "bRotate", "Rotate", "Border", "Info", "Data",
}
K.SPRITE_METHODS = {
    "GetSlateAtlasData", "GetBakedTexture", "GetSourceTexture", "GetAtlasTexture", "GetTexture",
    "GetSourceSize", "GetImageSize", "GetSourceUV", "GetSize", "GetAtlas", "GetRect", "GetUV",
    "GetSpriteInfo", "GetSpriteData", "GetResourceObject", "GetSpriteTexture",
}
K.ATLAS_FIELDS = {
    "Texture", "Textures", "AtlasTexture", "AtlasTextures", "Pages", "PageTextures", "Sprites",
    "SpriteList", "SpriteArray", "SpriteInfos", "SpriteInfoList", "SpriteMap", "SpriteInfoMap",
    "SpriteDataMap", "SpriteDatas", "SpriteNames", "Frames", "Size", "Width", "Height", "TextureSize",
    "AtlasSize", "Padding", "bSRGB", "Name", "AtlasName",
}
-- Called with the sprite name as the only argument.
K.ATLAS_METHODS_BY_NAME = { "GetSprite", "FindSprite", "GetSpriteByName", "GetSpriteInfo", "GetSpriteData" }
K.ATLAS_METHODS = { "GetTexture", "GetTextures", "GetAtlasTexture", "GetSprites", "GetSpriteNames", "GetSize" }
K.MATERIAL_ARRAYS = { "ScalarParameterValues", "VectorParameterValues", "TextureParameterValues" }
K.TEXTURE_PROPS = { "SRGB", "CompressionSettings", "AddressX", "AddressY", "Filter", "LODGroup" }
K.MATERIAL_PROPS = {
    "BlendMode", "MaterialDomain", "TwoSided", "ShadingModel", "OpacityMaskClipValue", "bUsedWithUI",
    "bIsMasked", "TranslucencyLightingMode", "bDisableDepthTest", "bUseMaterialAttributes",
}
K.RETAINER_METHODS = {
    "SetEffectMaterial", "GetEffectMaterial", "SetTextureParameter", "SetRetainRendering",
    "SetRenderingPhase", "RequestRender", "SetContent", "AddChild", "GetRenderTarget",
    "GetRetainerRenderTarget", "RemoveFromParent",
}
K.RETAINER_FIELDS = {
    "bRetainRender", "RenderOnInvalidation", "RenderOnPhase", "Phase", "PhaseCount", "EffectMaterial",
    "TextureParameter", "RenderTarget",
}
-- Lua fields of the panel component that may hold the selected path.
K.SIGNATURE_WORDS = { "select", "index", "cur", "way", "path", "tab", "page", "id" }

local cfg = { Panels = {}, PanelSet = {}, Mode = "full", Calib = true }
local S = {
    started = false,
    disabled = false,
    errors = {},
    errorTotal = 0,
    probe = nil,
    job = nil,   -- the job the render-target helpers work for (probe or full export)
    full = nil,
    flat = false,
    own = setmetatable({}, { __mode = "k" }),   -- RetainerBox / Image created here
}

local clock = os.clock

local function nowMs()
    return clock() * 1000
end

local function stamp(format)
    local ok, value = pcall(os.date, format)
    return ok and type(value) == "string" and value or nil
end

-- Same channel as AbsruDiagnostics: Log.Info reaches C7.log as "LuaLog: ReleaseLog:".
local function warn(message)
    local text = tostring(message)
    local okLog, gameLog = pcall(function() return Log or LaunchLog end)
    if okLog and gameLog ~= nil and type(gameLog.Info) == "function" and pcall(gameLog.Info, text) then
        return
    end
    local ok, logger = pcall(function() return LuaCLogger end)
    if ok and logger ~= nil and type(logger.Warning) == "function" then
        pcall(logger.Warning, text)
    end
end

local function disable(reason)
    S.disabled = true
    warn("[AbsruExport] disabled: " .. tostring(reason))
    return false
end

local function noteError(stage, err)
    S.errors[stage] = (S.errors[stage] or 0) + 1
    S.errorTotal = S.errorTotal + 1
    if S.errors[stage] <= ERRORS_LOGGED then
        warn("[AbsruExport] error stage=" .. tostring(stage) .. ": " .. tostring(err))
    end
    if S.errorTotal >= ERRORS_MAX and not S.disabled then
        disable("too many errors (" .. tostring(S.errorTotal) .. ")")
    end
end

local function clip(text)
    text = tostring(text)
    if #text > TEXT_MAX then
        return text:sub(1, TEXT_MAX) .. "..."
    end
    return text
end

local function importSafe(name)
    if type(import) ~= "function" then
        return nil
    end
    local ok, result = pcall(import, name)
    return ok and result or nil
end

local function get(owner, key)
    if owner == nil then
        return nil
    end
    local ok, value = pcall(function() return owner[key] end)
    if ok then
        return value
    end
    return nil
end

-- Returns ok, result, err: ok=false when the method is missing or raised.
local function callMethod(owner, name, ...)
    local method = get(owner, name)
    if type(method) ~= "function" then
        return false, nil, "missing"
    end
    local ok, result = pcall(method, owner, ...)
    if not ok then
        return false, nil, clip(result)
    end
    return true, result
end

local function objectPath(object)
    local ok, result = callMethod(object, "GetPathName")
    return ok and result ~= nil and tostring(result) or nil
end

local function objectName(object)
    local ok, result = callMethod(object, "GetName")
    return ok and result ~= nil and tostring(result) or nil
end

local function className(object)
    local ok, class = callMethod(object, "GetClass")
    if not ok or class == nil then
        return nil
    end
    return objectName(class)
end

local function componentUid(component)
    local uid = nil
    pcall(function() uid = component.uid or component.UID or component.__cname end)
    return tostring(uid or "?")
end

local function vector2(x, y)
    local ok, value = pcall(function() return FVector2D(x, y) end)
    if ok and value ~= nil then
        return value
    end
    return { X = x, Y = y }
end

local function linearColor(r, g, b, a)
    local ok, value = pcall(function() return FLinearColor(r, g, b, a) end)
    if ok and value ~= nil then
        return value
    end
    return { R = r, G = g, B = b, A = a }
end

-- slua TArray (0-based Num/Get) or a plain Lua table (same helpers as Init.lua).
local function count(array)
    if type(array) == "table" then
        return #array
    end
    local ok, value = pcall(function() return array:Num() end)
    return ok and tonumber(value) or 0
end

local function item(array, index)
    if type(array) == "table" then
        return array[index + 1]
    end
    local ok, value = pcall(function() return array:Get(index) end)
    return ok and value or nil
end

-- A JSON-friendly view of an engine value: UObject -> path/class, struct -> X/Y/R/G/B/A.
local function describe(value)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" then
        return value
    elseif valueType == "string" then
        return clip(value)
    elseif valueType == "function" then
        return "<function>"
    end
    local path = objectPath(value)
    if path ~= nil then
        return { path = path, class = className(value) }
    end
    local out, any = {}, false
    for _, key in ipairs({ "X", "Y", "Z", "W", "R", "G", "B", "A", "Left", "Top", "Right", "Bottom" }) do
        local field = get(value, key)
        if type(field) == "number" then
            out[key] = field
            any = true
        end
    end
    if any then
        return out
    end
    return "<" .. valueType .. " " .. clip(tostring(value)) .. ">"
end

-- slua keeps readable properties in metatable[".get"] (docs/LESSONS.md, TASK-008).
local function metaKeys(value)
    local keys, seen = {}, {}
    local function add(tableValue, prefix)
        if type(tableValue) ~= "table" then
            return
        end
        for key in pairs(tableValue) do
            if type(key) == "string" and not seen[prefix .. key] and #keys < KEYS_MAX then
                seen[prefix .. key] = true
                keys[#keys + 1] = prefix .. key
            end
        end
    end
    local ok, meta = pcall(getmetatable, value)
    local depth = 0
    while ok and type(meta) == "table" and depth < 6 do
        add(meta, "")
        add(rawget(meta, ".get"), "get:")
        local index = rawget(meta, "__index")
        if type(index) == "table" and index ~= meta then
            add(index, "")
        end
        depth = depth + 1
        meta = rawget(meta, "__parent") or rawget(meta, "__base") or rawget(meta, "__super")
    end
    table.sort(keys)
    return keys
end

-- Iterates a UObject / container through its slua __pairs (LuaJIT's pairs()
-- ignores __pairs without 5.2 compat, so the metamethod is called directly).
-- visit(key, value) returning true stops; returns an error text or nil.
local function eachPair(value, limit, visit)
    local ok, result = pcall(function()
        local meta = getmetatable(value)
        local iterate = type(meta) == "table" and rawget(meta, "__pairs") or nil
        local fn, state, key
        if type(iterate) == "function" then
            fn, state, key = iterate(value)
        else
            fn, state, key = pairs(value)
        end
        local steps = 0
        while steps < limit do
            local nextKey, nextValue = fn(state, key)
            if nextKey == nil or visit(nextKey, nextValue) == true then
                break
            end
            key = nextKey
            steps = steps + 1
        end
    end)
    return not ok and clip(result) or nil
end

local function pairsDump(value, limit)
    local entries = {}
    local err = eachPair(value, limit, function(key, item)
        entries[#entries + 1] = { key = describe(key), value = describe(item) }
    end)
    return { count = #entries, entries = entries, error = err }
end

-- describe() plus the first items of a TArray / TMap.
local function expand(value)
    local valueType = type(value)
    if valueType ~= "userdata" and valueType ~= "table" then
        return describe(value)
    end
    local out = { value = describe(value) }
    local n = count(value)
    if n > 0 then
        out.count = n
        out.items = {}
        for index = 0, math.min(n, 5) - 1 do
            out.items[#out.items + 1] = describe(item(value, index))
        end
    end
    if objectPath(value) == nil then
        local dump = pairsDump(value, 5)
        if dump.count > 0 then
            out.pairs = dump.entries
        end
    end
    return out
end

local function probeFields(object, fields, out, found)
    for _, field in ipairs(fields) do
        local value = get(object, field)
        if value ~= nil and type(value) ~= "function" then
            out[field] = expand(value)
            found[#found + 1] = field
        end
    end
end

local function probeMethods(object, methods, out, found, ...)
    for _, method in ipairs(methods) do
        local ok, result, err = callMethod(object, method, ...)
        if ok then
            local view = { value = expand(result) }
            for _, key in ipairs({ "AtlasTexture", "StartUV", "SizeUV" }) do
                local field = get(result, key)
                if field ~= nil then
                    view[key] = describe(field)
                end
            end
            out[method] = view
            found[#found + 1] = method .. "()"
        elseif err ~= "missing" then
            out[method] = { error = err }
        end
    end
end

local function jsonArray(values)
    values = values or {}
    local mark = S.diag and S.diag.JsonArray
    if type(mark) == "function" then
        return mark(values)
    end
    return values
end

local function shortName(path)
    if path == nil then
        return nil
    end
    return tostring(path):match("([^/%.:]+)$") or tostring(path)
end

local function safeName(name)
    return (tostring(name):gsub("[^%w%-%._]", "_"))
end

local function toBool(value)
    if type(value) == "boolean" then
        return value
    elseif type(value) == "number" then
        return value ~= 0
    end
    return nil
end

local function mb(bytes)
    return math.floor(bytes / 104857.6 + 0.5) / 10
end

-- Files -------------------------------------------------------------------------

-- ExportRenderTarget / SaveStringContentToFile create sub-folders; if they do
-- not (first texture export checks it), "textures/x.png" becomes "textures+x.png"
-- and tools/GodWayExport.ps1 restores the folders.
local function outName(name)
    if S.flat then
        return (name:gsub("/", "+"))
    end
    return name
end

local function writeText(name, content)
    local ok, result = pcall(S.save, content, S.dir .. S.prefix .. outName(name))
    if not ok or result == false then
        noteError("io", ok and "write returned false" or result)
        return false
    end
    return true
end

local function writeJson(name, value)
    local ok, content = pcall(S.encode, value)
    if not ok then
        noteError("encode", content)
        return false
    end
    return writeText(name, content)
end

local function fileExists(path)
    local paths = S.paths
    if paths == nil or type(paths.FileExists) ~= "function" then
        return nil
    end
    local ok, result = pcall(paths.FileExists, path)
    if not ok then
        return nil
    end
    return result == true
end

-- Render targets (shared by the probes and the full export) ---------------------

local function createTarget(w, h, format)
    local J = S.job
    local lib = J.lib
    format = format or J.format
    local ok, rt = pcall(lib.CreateRenderTarget2D, J.ctx, w, h, format, linearColor(0, 0, 0, 0), false)
    local first = ok and rt ~= nil and "full" or clip(rt)
    if not ok or rt == nil then
        ok, rt = pcall(lib.CreateRenderTarget2D, J.ctx, w, h, format)
    end
    if ok and rt ~= nil then
        J.targets[#J.targets + 1] = rt
        return rt, first == "full" and "full" or "short"
    end
    return nil, "full: " .. tostring(first) .. "; short: " .. clip(rt)
end

local function releaseTarget(rt)
    local J = S.job
    local targets = J.targets
    for index = #targets, 1, -1 do
        if targets[index] == rt then
            table.remove(targets, index)
            break
        end
    end
    local release = get(J.lib, "ReleaseRenderTarget2D")
    if type(release) == "function" then
        pcall(release, rt)
    end
end

local function exportTarget(rt, fileName)
    local J = S.job
    local name = S.prefix .. outName(fileName)
    local ok, result = pcall(J.lib.ExportRenderTarget, J.ctx, rt, S.dir, name)
    return {
        call = ok and "ok" or clip(result), returned = ok and describe(result) or nil,
        file = S.dir .. name, exists = fileExists(S.dir .. name),
    }
end

local function readPixels(rt, w, h, grid)
    local J = S.job
    local samples, distinct, seen, nonBlack, readOk = {}, 0, {}, 0, false
    for gy = 1, grid do
        for gx = 1, grid do
            local x = math.floor(w * (gx - 0.5) / grid)
            local y = math.floor(h * (gy - 0.5) / grid)
            local ok, color = pcall(J.lib.ReadRenderTargetPixel, J.ctx, rt, x, y)
            local r, g, b, a = get(color, "R"), get(color, "G"), get(color, "B"), get(color, "A")
            if ok and type(r) == "number" then
                readOk = true
                local key = string.format("%d,%d,%d,%d", r, g or 0, b or 0, a or 0)
                if not seen[key] then
                    seen[key] = true
                    distinct = distinct + 1
                end
                if r + (g or 0) + (b or 0) > 0 then
                    nonBlack = nonBlack + 1
                end
                samples[#samples + 1] = { x = x, y = y, r = r, g = g, b = b, a = a }
            else
                samples[#samples + 1] = { x = x, y = y, error = ok and describe(color) or clip(color) }
            end
        end
    end
    return { read = readOk, distinct = distinct, non_black = nonBlack, samples = samples }
end

local function textureSize(texture)
    for _, pair in ipairs({
        { "Blueprint_GetSizeX", "Blueprint_GetSizeY" }, { "GetSizeX", "GetSizeY" },
        { "GetSurfaceWidth", "GetSurfaceHeight" },
    }) do
        local okX, x = callMethod(texture, pair[1])
        local okY, y = callMethod(texture, pair[2])
        if okX and okY and tonumber(x) and tonumber(y) and tonumber(x) > 0 then
            return math.floor(tonumber(x)), math.floor(tonumber(y)), pair[1]
        end
    end
    return nil, nil, "none"
end

-- onValue(field, name, value) sees the raw parameter value (texture objects).
local function materialParams(material, onValue)
    local out = {}
    for _, field in ipairs(K.MATERIAL_ARRAYS) do
        local array = get(material, field)
        local list = {}
        for index = 0, count(array) - 1 do
            local entry = item(array, index)
            local info = get(entry, "ParameterInfo")
            local name = get(info, "Name") or get(entry, "ParameterName")
            local value = get(entry, "ParameterValue")
            local paramName = name ~= nil and tostring(name) or "?"
            list[#list + 1] = { name = paramName, value = describe(value) }
            if onValue ~= nil then
                onValue(field, paramName, value)
            end
        end
        out[field] = { type = type(array), count = count(array), values = list }
    end
    return out
end

-- slua wants the out parameters (Canvas, Size, Context) as arguments:
-- (ctx, rt) fails with "expect userdata at arg 4" (probe 2026-09-26_1616).
-- Probe 2 passed the imported struct type itself ("expect struct but got
-- nil"); an instance is needed. FVector2D is a callable table here, so the
-- imported struct type is called the same way (probe 3: works).
local function newDrawContext()
    local J = S.job
    if J.contextStruct == nil then
        J.contextStruct = importSafe("DrawToRenderTargetContext") or false
    end
    local struct = J.contextStruct or nil
    local drawContext, contextVia = nil, "none"
    local tried = {}
    local function tryMake(label, make)
        if drawContext ~= nil then
            return
        end
        local ok, value = pcall(make)
        tried[#tried + 1] = label .. ": " .. (ok and (value ~= nil and ("ok " .. type(value)) or "nil") or clip(value))
        if ok and value ~= nil then
            drawContext, contextVia = value, label
        end
    end
    tryMake("DrawToRenderTargetContext()", function() return struct() end)
    tryMake("DrawToRenderTargetContext.new()", function() return struct.new() end)
    tryMake("FDrawToRenderTargetContext()", function() return FDrawToRenderTargetContext() end)
    tryMake("import F()", function() return import("FDrawToRenderTargetContext")() end)
    return drawContext, contextVia, tried, type(struct)
end

-- Opens a Canvas on rt. Returns canvas, context, info (the probe records info;
-- info.begin_returns is nil when BeginDrawCanvasToRenderTarget failed).
local function beginCanvas(rt)
    local J = S.job
    local drawContext, contextVia, tried, structType = newDrawContext()
    local info = { context_type = structType, context_tried = tried, context_via = contextVia, begin = {} }
    local attempts = {
        { "ctx,rt,nil,size,context", function() return J.lib.BeginDrawCanvasToRenderTarget(J.ctx, rt, nil, vector2(0, 0), drawContext) end },
        { "ctx,rt,size,context", function() return J.lib.BeginDrawCanvasToRenderTarget(J.ctx, rt, vector2(0, 0), drawContext) end },
        { "ctx,rt", function() return J.lib.BeginDrawCanvasToRenderTarget(J.ctx, rt) end },
    }
    if J.canvasSig ~= nil then
        table.insert(attempts, 1, attempts[J.canvasSig])
    end
    local returns = nil
    for index, attempt in ipairs(attempts) do
        local result = { pcall(attempt[2]) }
        info.begin[#info.begin + 1] = attempt[1] .. ": " .. (result[1] and "ok" or clip(result[2]))
        if result[1] then
            returns = result
            if J.canvasSig == nil then
                J.canvasSig = index
            end
            break
        end
    end
    if returns == nil then
        return nil, nil, info
    end
    info.begin_returns = { describe(returns[2]), describe(returns[3]), describe(returns[4]), describe(returns[5]) }
    local canvas, context = nil, nil
    for index = 2, 5 do
        local value = returns[index]
        if canvas == nil and type(get(value, "K2_DrawTexture")) == "function" then
            canvas = value
        elseif canvas ~= nil and context == nil and value ~= nil and get(value, "X") == nil then
            context = value
        end
    end
    return canvas, context or drawContext, info
end

local function endCanvas(context)
    local J = S.job
    return pcall(J.lib.EndDrawCanvasToRenderTarget, J.ctx, context)
end

-- Copies source (Texture2D or a render target) into rt with Canvas K2_DrawTexture.
-- BLEND_Opaque keeps straight alpha and the RGB of transparent pixels (probe 3).
local function canvasCopy(source, rt, w, h)
    local J = S.job
    local canvas, context, info = beginCanvas(rt)
    if canvas == nil then
        if info.begin_returns ~= nil then
            endCanvas(context)
        end
        return false, "no canvas: " .. table.concat(info.begin, "; ")
    end
    local okDraw, _, drawErr = callMethod(canvas, "K2_DrawTexture", source, vector2(0, 0), vector2(w, h),
        vector2(0, 0), vector2(1, 1), linearColor(1, 1, 1, 1), J.blendOpaque, 0, vector2(0.5, 0.5))
    local okEnd, endErr = endCanvas(context)
    if not okDraw then
        return false, "draw: " .. tostring(drawErr)
    end
    if not okEnd then
        return false, "end: " .. clip(endErr)
    end
    return true
end

local function clearTarget(rt)
    local J = S.job
    pcall(J.lib.ClearRenderTarget2D, J.ctx, rt, linearColor(0, 0, 0, 0))
end

local function realSeconds(J)
    if J.statics == nil then
        J.statics = importSafe("GameplayStatics") or false
    end
    if not J.statics then
        return nil
    end
    local ok, value = pcall(J.statics.GetRealTimeSeconds, J.ctx)
    return ok and tonumber(value) or nil
end

local function loadObject(path)
    local tried = {}
    for _, loader in ipairs({
        { "slua.loadObject", function() return slua.loadObject(path) end },
        { "LoadObject", function() return LoadObject(path) end },
        { "UE4.LoadObject", function() return UE4.LoadObject(path) end },
    }) do
        local ok, value = pcall(loader[2])
        if ok and value ~= nil then
            return value, loader[1]
        end
        tried[#tried + 1] = loader[1] .. ": " .. (ok and "nil" or clip(value))
    end
    return nil, table.concat(tried, "; ")
end

-- Mean / max channel difference of two readPixels results on the same grid.
local function pixelDiff(a, b)
    local total, maxDiff, n = 0, 0, 0
    for index = 1, math.min(#a.samples, #b.samples) do
        local p, q = a.samples[index], b.samples[index]
        if type(p.r) == "number" and type(q.r) == "number" then
            for _, key in ipairs({ "r", "g", "b", "a" }) do
                local d = math.abs((p[key] or 0) - (q[key] or 0))
                total = total + d
                if d > maxDiff then
                    maxDiff = d
                end
            end
            n = n + 4
        end
    end
    if n == 0 then
        return nil
    end
    return { mean = total / n, max = maxDiff, channels = n }
end

-- ref: the icon through Canvas Opaque (straight alpha); got: the same icon from
-- the retainer. Semi-transparent samples tell straight from premultiplied RGB.
local function classifyAlpha(ref, got)
    local straight, premultiplied, alphaDiff, used = 0, 0, 0, 0
    for index = 1, math.min(#ref.samples, #got.samples) do
        local p, q = ref.samples[index], got.samples[index]
        if type(p.r) == "number" and type(q.r) == "number" and p.a > 0 then
            used = used + 1
            alphaDiff = alphaDiff + math.abs(p.a - q.a)
            for _, key in ipairs({ "r", "g", "b" }) do
                straight = straight + math.abs(p[key] - q[key])
                premultiplied = premultiplied + math.abs(p[key] * p.a / 255 - q[key])
            end
        end
    end
    if used == 0 then
        return { result = "unknown", samples = 0 }
    end
    local result = "unknown"
    if straight <= premultiplied and straight / (used * 3) <= 8 then
        result = "straight"
    elseif premultiplied < straight and premultiplied / (used * 3) <= 8 then
        result = "premultiplied"
    end
    return {
        result = result, samples = used, straight_mean = straight / (used * 3),
        premultiplied_mean = premultiplied / (used * 3), alpha_mean = alphaDiff / used,
    }
end

-- RetainerBox (shared by probe 4 and the reference frames) ---------------------

local function newWidget(name, tree, outer)
    local class = importSafe(name) or importSafe("U" .. name)
    if class == nil then
        return nil, "class " .. name .. " unavailable"
    end
    local ok, widget = callMethod(tree, "ConstructWidget", class)
    if ok and widget ~= nil then
        return widget, "ConstructWidget"
    end
    local manager = nil
    pcall(function() manager = Game and Game.ObjectActorManager end)
    ok, widget = callMethod(manager, "KGNewObject", class, outer or tree, true)
    if ok and widget ~= nil then
        return widget, "KGNewObject"
    end
    local globalNew = rawget(_G, "NewObject")
    if type(globalNew) == "function" then
        local okNew, result = pcall(globalNew, class, outer or tree)
        if okNew and result ~= nil then
            return result, "NewObject"
        end
    end
    local ue = rawget(_G, "UE")
    local ueNew = type(ue) == "table" and ue.NewObject or nil
    if type(ueNew) == "function" then
        local okNew, result = pcall(ueNew, class, outer or tree)
        if okNew and result ~= nil then
            return result, "UE.NewObject"
        end
    end
    return nil, "no factory created " .. name
end

-- RetainerBox + Image under the panel's root CanvasPanel, below everything.
-- Returns a handle or nil; out records which calls worked.
local function createRetainer(J, out)
    local tree = get(J.userWidget, "WidgetTree")
    local root = get(tree, "RootWidget")
    out.root = className(root)
    local box, boxVia = newWidget("RetainerBox", tree, J.userWidget)
    local image, imageVia = newWidget("Image", tree, J.userWidget)
    out.box = box ~= nil and boxVia or ("fail: " .. tostring(boxVia))
    out.image = image ~= nil and imageVia or ("fail: " .. tostring(imageVia))
    if box == nil or image == nil or root == nil then
        out.create = "fail"
        return nil
    end
    local handle = { box = box, image = image }
    -- The full export's walk skips these (not part of the panel's layout).
    S.own[box], S.own[image] = true, true
    out.content_tried = {}
    for _, method in ipairs({ "SetContent", "AddChild" }) do
        local ok, _, err = callMethod(box, method, image)
        out.content_tried[#out.content_tried + 1] = method .. ": " .. (ok and "ok" or tostring(err))
        if ok then
            out.content = method
            break
        end
    end
    local okCanvas, slot, errCanvas = callMethod(root, "AddChildToCanvas", box)
    if okCanvas then
        out.add = "AddChildToCanvas"
    else
        local okAdd, slotAdd, errAdd = callMethod(root, "AddChild", box)
        if okAdd then
            out.add, slot = "AddChild", slotAdd
        else
            out.add = "fail: " .. tostring(errCanvas) .. "; " .. tostring(errAdd)
            out.create = "fail"
            return nil
        end
    end
    handle.slot = slot or get(box, "Slot")
    out.slot = className(handle.slot)
    local okZ = callMethod(handle.slot, "SetZOrder", -1000)
    callMethod(handle.slot, "SetAutoSize", false)
    local okPos = callMethod(handle.slot, "SetPosition", vector2(0, 0))
    out.slot_calls = (okZ and "zorder " or "") .. (okPos and "position" or "")
    out.create = tostring(boxVia) .. "+" .. tostring(out.content) .. "+" .. out.add
    return handle
end

-- Effect material = MID of Widget3DPassThrough, texture parameter SlateUI:
-- SRetainerWidget passes its render target to it every paint.
local function setupRetainer(J, handle, out)
    local box = handle.box
    local base, via = loadObject(K.W3D_PATH)
    out.material = base ~= nil and via or ("fail: " .. tostring(via))
    local materialLibrary = importSafe("KismetMaterialLibrary")
    if base ~= nil and materialLibrary ~= nil then
        local ok, mid = pcall(materialLibrary.CreateDynamicMaterialInstance, J.ctx, base)
        out.mid = ok and mid ~= nil and "ok" or clip(mid)
        if ok then
            handle.effect = mid
        end
    end
    local calls = {}
    local function note(label, ok, err)
        calls[#calls + 1] = label .. ": " .. (ok and "ok" or tostring(err))
        return ok
    end
    local effect = handle.effect or base
    if effect ~= nil then
        local ok, _, err = callMethod(box, "SetEffectMaterial", effect)
        note("SetEffectMaterial", ok, err)
    end
    local okTex, _, errTex = callMethod(box, "SetTextureParameter", "SlateUI")
    note("SetTextureParameter", okTex, errTex)
    local okRetain, _, errRetain = callMethod(box, "SetRetainRendering", true)
    if not note("SetRetainRendering", okRetain, errRetain) then
        local okField, errField = pcall(function() box.bRetainRender = true end)
        note("bRetainRender=true", okField, errField)
    end
    local okPhase, _, errPhase = callMethod(box, "SetRenderingPhase", 0, 1)
    note("SetRenderingPhase", okPhase, errPhase)
    out.calls = calls
    out.methods = {}
    for _, name in ipairs(K.RETAINER_METHODS) do
        out.methods[#out.methods + 1] = name .. ":" .. (type(get(box, name)) == "function" and "ok" or "missing")
    end
    out.fields = {}
    for _, name in ipairs(K.RETAINER_FIELDS) do
        local value = get(box, name)
        if value ~= nil and type(value) ~= "function" then
            out.fields[name] = describe(value)
        end
    end
    out.meta_keys = metaKeys(box)
end

-- w, h are frame pixels; the slot is sized in Slate units (viewport scale).
local function setRetainerBrush(J, handle, kind, object, w, h)
    local scale = J.viewportScale or 1
    local out = { kind = kind, size = { w, h }, scale = scale }
    local ok, _, err
    if kind == "texture" then
        ok, _, err = callMethod(handle.image, "SetBrushFromTexture", object, false)
    else
        ok, _, err = callMethod(handle.image, "SetBrushFromMaterial", object)
    end
    out.brush = ok and "ok" or tostring(err)
    local okSize = callMethod(handle.image, "SetBrushSize", vector2(w / scale, h / scale))
    out.brush_size = okSize and "ok" or "missing"
    local okSlot, _, errSlot = callMethod(handle.slot, "SetSize", vector2(w / scale, h / scale))
    out.slot_size = okSlot and "ok" or tostring(errSlot)
    return out
end

local function isTarget(value)
    local class = className(value)
    return class ~= nil and class:find("RenderTarget", 1, true) ~= nil
end

-- The retainer's render target: the effect MID's SlateUI texture parameter
-- (a Texture2D there means the default value, i.e. nothing rendered yet).
local function retainerTarget(handle)
    local tried = {}
    local function accept(label, value)
        tried[#tried + 1] = label .. ": " .. tostring(className(value) or type(value))
        return isTarget(value)
    end
    local okE, effect = callMethod(handle.box, "GetEffectMaterial")
    if okE and effect ~= nil then
        local ok, rt = callMethod(effect, "K2_GetTextureParameterValue", "SlateUI")
        if ok and accept("GetEffectMaterial():SlateUI", rt) then
            return rt, "GetEffectMaterial", tried
        end
    else
        tried[#tried + 1] = "GetEffectMaterial: " .. tostring(effect)
    end
    if handle.effect ~= nil then
        local ok, rt = callMethod(handle.effect, "K2_GetTextureParameterValue", "SlateUI")
        if ok and accept("mid:SlateUI", rt) then
            return rt, "mid", tried
        end
    end
    for _, field in ipairs({ "RenderTarget", "RetainerRenderTarget" }) do
        local value = get(handle.box, field)
        if value ~= nil and type(value) ~= "function" and accept(field, value) then
            return value, field, tried
        end
    end
    for _, method in ipairs({ "GetRenderTarget", "GetRetainerRenderTarget" }) do
        local ok, value = callMethod(handle.box, method)
        if ok and accept(method .. "()", value) then
            return value, method, tried
        end
    end
    return nil, nil, tried
end

local function targetInfo(rt)
    local w, h = tonumber(get(rt, "SizeX")), tonumber(get(rt, "SizeY"))
    if w == nil or w <= 0 then
        w, h = textureSize(rt)
    end
    return {
        class = className(rt), path = objectPath(rt), w = w, h = h,
        format = describe(get(rt, "RenderTargetFormat")), linear_gamma = describe(get(rt, "bForceLinearGamma")),
    }
end

local function removeRetainer(handle)
    if handle == nil or handle.removed then
        return
    end
    handle.removed = true
    callMethod(handle.image, "RemoveFromParent")
    callMethod(handle.box, "RemoveFromParent")
end

-- Canvas copies keep bytes when the target has the source's colour space.
local function copyFormatFor(J, info)
    if info ~= nil and info.format == J.formatLinear then
        return J.formatLinear, "linear"
    end
    return J.formatSrgb, "srgb"
end

-- Probe -------------------------------------------------------------------------

local function writeProbe()
    local P = S.probe
    local ok, content = pcall(S.encode, P.result)
    if ok then
        writeText(P.jsonName, content)
    else
        noteError("encode", content)
    end
end

local STAGES = {}

STAGES[#STAGES + 1] = { "api", function(P, R)
    local lib = importSafe("KismetRenderingLibrary")
    P.lib = lib
    R.api = { KismetRenderingLibrary = lib ~= nil }
    for _, name in ipairs(K.API_NAMES) do
        local value = get(lib, name)
        R.api[name] = type(value) == "function" and "ok" or ("missing:" .. type(value))
    end
    local paths = S.paths
    R.api.BlueprintPathsLibrary_FileExists = paths ~= nil and type(get(paths, "FileExists")) == "function"
    R.api.FVector2D = type(FVector2D)
    R.api.FLinearColor = type(FLinearColor)
    R.api.GetContextObject = type(GetContextObject)
    local formats = importSafe("ETextureRenderTargetFormat")
    local srgb, rgba8 = get(formats, "RTF_RGBA8_SRGB"), get(formats, "RTF_RGBA8")
    R.api.RTF_RGBA8_SRGB = describe(srgb)
    R.api.RTF_RGBA8 = describe(rgba8)
    -- Probe 1: RTF_RGBA8 = 2, RTF_RGBA8_SRGB = 3.
    P.formatSrgb, P.formatLinear = srgb or 3, rgba8 or 2
    if srgb ~= nil then
        P.format, R.rt_format = srgb, "RTF_RGBA8_SRGB"
    elseif rgba8 ~= nil then
        P.format, R.rt_format = rgba8, "RTF_RGBA8"
    else
        P.format, R.rt_format = 2, "RTF_RGBA8 (literal 2)"
    end
    local blend = importSafe("EBlendMode")
    P.blendOpaque = get(blend, "BLEND_Opaque") or 0
    P.blendTranslucent = get(blend, "BLEND_Translucent") or 2
    R.api.EBlendMode = blend ~= nil
    return true
end }

STAGES[#STAGES + 1] = { "context", function(P, R)
    local widget = get(P.component, "userWidget") or get(P.component, "widget")
    local contextObject = nil
    if type(GetContextObject) == "function" then
        local ok, value = pcall(GetContextObject)
        contextObject = ok and value or nil
    end
    local _, widgetWorld = callMethod(widget, "GetWorld")
    local _, contextWorld = callMethod(contextObject, "GetWorld")
    local game = nil
    pcall(function() game = Game end)
    R.context = {
        userWidget = describe(widget), userWidget_world = describe(widgetWorld),
        GetContextObject = describe(contextObject), GetContextObject_world = describe(contextWorld),
        Game_GameInstance = describe(get(game, "GameInstance")), Game_World = describe(get(game, "World")),
    }
    if contextObject ~= nil and contextWorld ~= nil then
        P.ctx, R.context.used = contextObject, "GetContextObject"
    elseif widget ~= nil then
        P.ctx, R.context.used = widget, "userWidget"
    else
        P.ctx, R.context.used = contextObject, "GetContextObject (no world)"
    end
    P.userWidget = widget
    local layout = importSafe("WidgetLayoutLibrary")
    local okSize, viewport = pcall(function() return layout.GetViewportSize(P.ctx) end)
    R.context.viewport = okSize and describe(viewport) or clip(viewport)
    local okScale, scale = pcall(function() return layout.GetViewportScale(P.ctx) end)
    scale = okScale and tonumber(scale) or nil
    P.viewportScale = scale and scale > 0 and scale or 1
    R.context.viewport_scale = okScale and scale or clip(scale)
    return true
end }

-- ExportRenderTarget on its own: a 64x64 target cleared to opaque red.
STAGES[#STAGES + 1] = { "rt_clear", function(P, R)
    local out = {}
    R.rt_clear = out
    local rt, how = createTarget(64, 64)
    out.create = how
    if rt == nil then
        return true
    end
    local ok, err = pcall(P.lib.ClearRenderTarget2D, P.ctx, rt, linearColor(1, 0, 0, 1))
    out.clear = ok and "ok" or clip(err)
    out.export = exportTarget(rt, "probe_rt_clear.png")
    out.pixels = readPixels(rt, 64, 64, 2)
    return true
end }

-- Finds one Texture2D icon, one KGSprite and the Img_Bg01 material (fallbacks: any).
-- Probe 4 (P.wantSmall) also needs one liudong04 material (Img_Lev3Bg02).
STAGES[#STAGES + 1] = { "find", function(P, R)
    if P.walk == nil then
        P.walk = S.diag.NewPanelWalk(P.component)
        P.walkTicks, P.walkNodes, P.found = 0, 0, {}
    end
    local F = P.found
    local function visit(widget)
        P.walkNodes = P.walkNodes + 1
        local resource = get(get(widget, "Brush"), "ResourceObject")
        if resource == nil then
            return false
        end
        local class = className(resource) or "?"
        local path = objectPath(resource) or ""
        local name = objectName(widget)
        if class == "Texture2D" then
            if F.icon == nil and path:find("UI_GodWay_Icon_Class", 1, true) then
                F.icon = resource
            elseif F.anyTexture == nil then
                F.anyTexture = resource
            end
        elseif class == "KGSprite" then
            if F.sprite == nil and path:find("UI_GodWay_Img_TextBg1_Sprite", 1, true) then
                F.sprite = resource
            elseif F.anySprite == nil then
                F.anySprite = resource
            end
        elseif class:find("MaterialInstance", 1, true) then
            if P.wantSmall and path:find("liudong04", 1, true)
                and (F.small == nil or (name == "Img_Lev3Bg02" and F.smallName ~= "Img_Lev3Bg02")) then
                F.small, F.smallWidget, F.smallName = resource, widget, name
            end
            if F.mid == nil and name == "Img_Bg01" then
                F.mid, F.midWidget = resource, widget
            elseif F.anyMid == nil then
                F.anyMid, F.anyMidWidget = resource, widget
            end
        end
        return F.icon ~= nil and F.sprite ~= nil and F.mid ~= nil
            and (not P.wantSmall or F.smallName == "Img_Lev3Bg02")
    end
    P.walkTicks = P.walkTicks + 1
    local done = P.walk(nowMs() + WALK_BUDGET_MS, visit)
    if not done and P.walkTicks < WALK_TICKS_MAX then
        return false
    end
    P.texture = F.icon or F.anyTexture
    P.sprite = F.sprite or F.anySprite
    P.mid, P.midWidget = F.mid or F.anyMid, F.midWidget or F.anyMidWidget
    P.small, P.smallWidget = F.small, F.smallWidget
    R.find = {
        nodes = P.walkNodes, ticks = P.walkTicks, complete = done,
        texture = objectPath(P.texture), texture_fallback = F.icon == nil and P.texture ~= nil,
        sprite = objectPath(P.sprite), sprite_fallback = F.sprite == nil and P.sprite ~= nil,
        material = objectPath(P.mid), material_class = className(P.mid),
        material_widget = objectName(P.midWidget), material_fallback = F.mid == nil and P.mid ~= nil,
        small = P.wantSmall and objectPath(P.small) or nil, small_widget = P.wantSmall and F.smallName or nil,
    }
    return true
end }

local function canvasDraw(P, R, key, blend, fileName)
    local out = { blend = describe(blend) }
    R.texture[key] = out
    local rt, how = createTarget(P.texW, P.texH)
    out.create = how
    if rt == nil then
        return
    end
    local canvas, context, info = beginCanvas(rt)
    for field, value in pairs(info) do
        out[field] = value
    end
    if info.begin_returns == nil then
        return
    end
    out.canvas = canvas ~= nil
    if canvas == nil then
        local okEnd, endErr = endCanvas(context)
        out["end"] = okEnd and "ok (no canvas)" or clip(endErr)
        return
    end
    local okDraw, _, drawErr = callMethod(canvas, "K2_DrawTexture", P.texture, vector2(0, 0),
        vector2(P.texW, P.texH), vector2(0, 0), vector2(1, 1), linearColor(1, 1, 1, 1), blend, 0, vector2(0.5, 0.5))
    out.draw = okDraw and "ok" or drawErr
    local okEnd, endErr = endCanvas(context)
    out["end"] = okEnd and (context ~= nil and "ok" or "ok (nil context)") or clip(endErr)
    out.export = exportTarget(rt, fileName)
    out.pixels = readPixels(rt, P.texW, P.texH, 3)
end

STAGES[#STAGES + 1] = { "texture_canvas", function(P, R)
    local w, h, via = textureSize(P.texture)
    P.texW, P.texH = w or 176, h or 176
    R.texture = { path = objectPath(P.texture), size = w and { w, h } or nil, size_via = via }
    if P.texture == nil then
        R.texture.canvas_opaque = { call = "no texture" }
        return true
    end
    canvasDraw(P, R, "canvas_opaque", P.blendOpaque, "probe_icon_rt_opaque.png")
    canvasDraw(P, R, "canvas_translucent", P.blendTranslucent, "probe_icon_rt_translucent.png")
    return true
end }

STAGES[#STAGES + 1] = { "sprite", function(P, R)
    local sprite = P.sprite
    local out = { path = objectPath(sprite), class = className(sprite), fields = {}, methods = {}, found = {} }
    R.sprite = out
    if sprite == nil then
        return true
    end
    probeFields(sprite, K.SPRITE_FIELDS, out.fields, out.found)
    probeMethods(sprite, K.SPRITE_METHODS, out.methods, out.found)
    out.meta_keys = metaKeys(sprite)
    out.pairs = pairsDump(sprite, 100)
    local atlas = get(sprite, "Atlas")
    if atlas ~= nil then
        local spriteName = get(sprite, "SpriteName")
        local view = { path = objectPath(atlas), class = className(atlas), fields = {}, methods = {}, found = {} }
        out.atlas = view
        probeFields(atlas, K.ATLAS_FIELDS, view.fields, view.found)
        probeMethods(atlas, K.ATLAS_METHODS, view.methods, view.found)
        if spriteName ~= nil then
            probeMethods(atlas, K.ATLAS_METHODS_BY_NAME, view.methods, view.found, spriteName)
        end
        view.pairs = pairsDump(atlas, 100)
        -- Probe 2: Sprites is a TMap name -> struct; dump this sprite's struct.
        local sprites = get(atlas, "Sprites")
        if sprites ~= nil and spriteName ~= nil then
            local entry = nil
            view.sprites_error = eachPair(sprites, 1000, function(key, value)
                if tostring(key) == tostring(spriteName) then
                    entry = value
                    return true
                end
            end)
            if entry ~= nil then
                view.entry = pairsDump(entry, 40)
                view.entry_nested = {}
                eachPair(entry, 40, function(key, value)
                    if type(value) == "userdata" and objectPath(value) == nil then
                        view.entry_nested[tostring(key)] = pairsDump(value, 20)
                    end
                end)
            end
        end
        local w, h, via = textureSize(get(atlas, "AtlasTexture"))
        view.atlas_texture_size = w and { w, h, via } or nil
        for _, name in ipairs(view.found) do
            out.found[#out.found + 1] = "atlas." .. name
        end
    end
    return true
end }

STAGES[#STAGES + 1] = { "mid_params", function(P, R)
    local out = { path = objectPath(P.mid), class = className(P.mid), chain = {} }
    R.mid = out
    local brush = get(P.midWidget, "Brush")
    out.brush_size = describe(get(brush, "ImageSize"))
    local material, depth = P.mid, 0
    while material ~= nil and depth < 6 do
        local level = { path = objectPath(material), class = className(material) }
        local params = materialParams(material)
        for key, value in pairs(params) do
            level[key] = value
        end
        out.chain[#out.chain + 1] = level
        material = get(material, "Parent")
        depth = depth + 1
    end
    out.meta_keys = metaKeys(P.mid)
    return true
end }

local function drawMaterial(P, fileName)
    local out = {}
    local rt, how = createTarget(RT_SIZE, RT_SIZE)
    out.create = how
    if rt == nil then
        out.result = "fail"
        return out
    end
    local ok, err = pcall(P.lib.DrawMaterialToRenderTarget, P.ctx, rt, P.mid)
    out.draw = ok and "ok" or clip(err)
    out.export = exportTarget(rt, fileName)
    out.pixels = readPixels(rt, RT_SIZE, RT_SIZE, 4)
    if not ok then
        out.result = "fail"
    elseif not out.pixels.read then
        out.result = "unread"
    elseif out.pixels.non_black == 0 then
        out.result = "black"
    else
        out.result = "ok"
    end
    out.t_ms = math.floor(nowMs() - P.openedMs)
    return out
end

STAGES[#STAGES + 1] = { "mid_draw", function(P, R)
    R.mid = R.mid or {}
    if P.mid == nil then
        R.mid.draw = { result = "fail", reason = "no material" }
        return true
    end
    R.mid.draw = drawMaterial(P, "probe_mid.png")
    P.firstDrawMs = nowMs()
    return true
end }

-- A second frame a second later: do the samples change with game time?
STAGES[#STAGES + 1] = { "mid_draw_2", function(P, R)
    if P.mid == nil or R.mid.draw == nil or R.mid.draw.result == "fail" then
        return true
    end
    if nowMs() - P.firstDrawMs < SECOND_DRAW_MS then
        return false
    end
    local second = drawMaterial(P, "probe_mid_t2.png")
    R.mid.draw_2 = second
    local a, b = R.mid.draw.pixels.samples, second.pixels.samples
    local changed = 0
    for index = 1, math.min(#a, #b) do
        if a[index].r ~= b[index].r or a[index].g ~= b[index].g or a[index].b ~= b[index].b or a[index].a ~= b[index].a then
            changed = changed + 1
        end
    end
    R.mid.animated_samples = changed
    return true
end }

-- Probe 2: the UI material drew a fully transparent frame (all 0,0,0,0).
-- Does DrawMaterialToRenderTarget draw anything? Engine surface materials,
-- and Widget3DPassThrough* with SlateUI = the icon as a Canvas replacement.
K.ENGINE_MATERIALS = {
    { "Widget3DPassThrough_Translucent", true }, { "Widget3DPassThrough_Masked", true },
    { "Widget3DPassThrough_Opaque", true }, { "Widget3DPassThrough", true },
    { "DefaultMaterial", false }, { "WorldGridMaterial", false },
}

local function drawProbe(P, material, w, h, format, fileName)
    local out = {}
    local rt, how = createTarget(w, h, format)
    out.create = how
    if rt == nil then
        return out
    end
    local ok, err = pcall(P.lib.DrawMaterialToRenderTarget, P.ctx, rt, material)
    out.draw = ok and "ok" or clip(err)
    if fileName ~= nil then
        out.export = exportTarget(rt, fileName)
    end
    out.pixels = readPixels(rt, w, h, 3)
    return out
end

STAGES[#STAGES + 1] = { "engine_material", function(P, R)
    local out = { materials = {} }
    R.engine_material = out
    local materialLibrary = importSafe("KismetMaterialLibrary")
    out.KismetMaterialLibrary = materialLibrary ~= nil
    for _, entry in ipairs(K.ENGINE_MATERIALS) do
        local name = entry[1]
        local path = "/Engine/EngineMaterials/" .. name .. "." .. name
        local material, via = loadObject(path)
        local view = { loaded = material ~= nil, via = via }
        out.materials[name] = view
        if material ~= nil then
            view.plain = drawProbe(P, material, 64, 64, nil, nil)
            if entry[2] and P.texture ~= nil and materialLibrary ~= nil then
                local okMid, mid = pcall(materialLibrary.CreateDynamicMaterialInstance, P.ctx, material)
                view.mid = okMid and mid ~= nil and "ok" or clip(mid)
                if okMid and mid ~= nil then
                    P.keepMids = P.keepMids or {}
                    P.keepMids[#P.keepMids + 1] = mid
                    local okSet, _, setErr = callMethod(mid, "SetTextureParameterValue", "SlateUI", P.texture)
                    view.set_slateui = okSet and "ok" or setErr
                    view.icon = drawProbe(P, mid, P.texW or 176, P.texH or 176, nil, "probe_icon_" .. name .. ".png")
                end
            end
        end
    end
    -- The UI material again, into a float target (RTF_RGBA16f).
    if P.mid ~= nil then
        local formats = importSafe("ETextureRenderTargetFormat")
        out.ui_float = drawProbe(P, P.mid, 64, 64, get(formats, "RTF_RGBA16f") or 6, nil)
    end
    return true
end }

-- Last on purpose: ExportTexture2D reads CPU mip data, which a cooked texture
-- may not keep; the other results are already in probe.json if this fails hard.
STAGES[#STAGES + 1] = { "texture_direct", function(P, R)
    R.texture = R.texture or {}
    if P.texture == nil then
        R.texture.direct = { call = "no texture" }
        return true
    end
    local name = S.prefix .. "probe_icon_direct.png"
    local ok, result = pcall(P.lib.ExportTexture2D, P.ctx, P.texture, S.dir, name)
    R.texture.direct = {
        call = ok and "ok" or clip(result), returned = ok and describe(result) or nil,
        file = S.dir .. name, exists = fileExists(S.dir .. name),
    }
    return true
end }

local STAGE_BY_NAME = {}
for _, stage in ipairs(STAGES) do
    STAGE_BY_NAME[stage[1]] = stage
end

local function probeLine(R)
    local api = {}
    for _, name in ipairs(K.API_LOGGED) do
        api[#api + 1] = name .. ":" .. ((R.api and R.api[name] == "ok") and "ok" or "missing")
    end
    local file = "none"
    local texture = R.texture or {}
    -- ExportTexture2D last: it wrote a 0-byte file in probe 2026-09-26_1616.
    for _, entry in ipairs({ R.rt_clear and R.rt_clear.export, texture.canvas_opaque and texture.canvas_opaque.export,
        R.mid and R.mid.draw and R.mid.draw.export, texture.direct }) do
        if type(entry) == "table" and entry.exists == true then
            file = entry.file
            break
        elseif file == "none" and type(entry) == "table" and entry.call == "ok" then
            file = tostring(entry.file) .. "(unverified)"
        end
    end
    local sprite = R.sprite and #R.sprite.found > 0 and table.concat(R.sprite.found, ",") or "none"
    local midDraw = R.mid and R.mid.draw and R.mid.draw.result or "fail"
    local canvas = texture.canvas_opaque and texture.canvas_opaque.draw or "fail"
    local engine = {}
    for name, view in pairs(R.engine_material and R.engine_material.materials or {}) do
        local icon = view.icon and view.icon.pixels
        local plain = view.plain and view.plain.pixels
        local result = not view.loaded and "noload"
            or icon and (icon.non_black > 0 and "icon_ok" or "icon_black")
            or plain and (plain.non_black > 0 and "ok" or "black") or "fail"
        engine[#engine + 1] = name:gsub("Widget3DPassThrough", "W3D") .. ":" .. result
    end
    table.sort(engine)
    return "[AbsruExport] probe api=" .. table.concat(api, ",") .. " file=" .. file
        .. " canvas=" .. tostring(canvas) .. " component=" .. tostring(R.component)
        .. " engine=" .. (#engine > 0 and table.concat(engine, ",") or "none")
        .. " sprite=" .. sprite .. " mid_draw=" .. midDraw
        .. " animated=" .. tostring(R.mid and R.mid.animated_samples or "?")
        .. " ctx=" .. tostring(R.context and R.context.used or "?")
        .. " json=" .. S.dir .. S.prefix .. "probe.json"
end

-- Probe 4 (step 3.0): RetainerBox ----------------------------------------------

local RETAINER_STAGES = { STAGE_BY_NAME.api, STAGE_BY_NAME.context, STAGE_BY_NAME.find }

RETAINER_STAGES[#RETAINER_STAGES + 1] = { "cvar", function(P, R)
    local system = importSafe("KismetSystemLibrary")
    local out = { KismetSystemLibrary = system ~= nil }
    R.cvar = out
    for _, getter in ipairs({ "GetConsoleVariableIntValue", "GetConsoleVariableBoolValue" }) do
        local ok, value = pcall(function() return system[getter]("Slate.EnableRetainedRendering") end)
        out[getter] = ok and describe(value) or clip(value)
        if ok and out.value == nil and value ~= nil then
            out.value = describe(value)
        end
    end
    return true
end }

RETAINER_STAGES[#RETAINER_STAGES + 1] = { "create", function(P, R)
    local out = {}
    R.create = out
    P.retainer = createRetainer(P, out)
    return true
end }

RETAINER_STAGES[#RETAINER_STAGES + 1] = { "setup", function(P, R)
    local out = {}
    R.setup = out
    if P.retainer == nil then
        out.result = "no retainer"
        return true
    end
    setupRetainer(P, P.retainer, out)
    return true
end }

local function waitTarget(P, state)
    if state.wait > 0 then
        state.wait = state.wait - 1
        return nil
    end
    local rt, via, tried = retainerTarget(P.retainer)
    state.tried = tried
    if rt == nil then
        state.tries = state.tries + 1
        return nil
    end
    return rt, via
end

-- The control icon: RT class/size/format, direct export, copies in both colour
-- spaces and the icon itself through Canvas Opaque (alpha / gamma of Slate).
RETAINER_STAGES[#RETAINER_STAGES + 1] = { "icon", function(P, R)
    local out = R.icon or {}
    R.icon = out
    if P.retainer == nil or P.texture == nil then
        out.result, out.reason = "fail", P.retainer == nil and "no retainer" or "no texture"
        return true
    end
    local state = P.iconState
    if state == nil then
        local w, h = textureSize(P.texture)
        P.iconW, P.iconH = w or 176, h or 176
        out.texture = objectPath(P.texture)
        out.brush = setRetainerBrush(P, P.retainer, "texture", P.texture, P.iconW, P.iconH)
        P.iconState = { wait = 2, tries = 0 }
        return false
    end
    local rt, via = waitTarget(P, state)
    if rt == nil then
        if state.tries < K.RT_WAIT_TICKS then
            return false
        end
        out.rt_tried, out.result = state.tried, "fail"
        return true
    end
    local info = targetInfo(rt)
    out.rt_via, out.rt = via, info
    P.retainerRt, P.rtInfo = rt, info
    local rw, rh = info.w or P.iconW, info.h or P.iconH
    out.direct = exportTarget(rt, "probe_retainer_icon_direct.png")
    out.direct_pixels = readPixels(rt, rw, rh, 3)
    out.direct_grid = readPixels(rt, rw, rh, 6)
    out.copy = {}
    for _, variant in ipairs({ { "srgb", P.formatSrgb, "probe_retainer_icon.png" },
        { "linear", P.formatLinear, "probe_retainer_icon_linear.png" } }) do
        local view = {}
        out.copy[variant[1]] = view
        local target, how = createTarget(P.iconW, P.iconH, variant[2])
        view.create = how
        if target ~= nil then
            clearTarget(target)
            local ok, err = canvasCopy(rt, target, P.iconW, P.iconH)
            view.copy = ok and "ok" or err
            view.export = exportTarget(target, variant[3])
            view.pixels = readPixels(target, P.iconW, P.iconH, 3)
            view.grid = readPixels(target, P.iconW, P.iconH, 6)
            view.diff_direct = pixelDiff(view.grid, out.direct_grid)
        end
    end
    local reference, how = createTarget(P.iconW, P.iconH, P.formatSrgb)
    out.reference = { create = how }
    if reference ~= nil then
        clearTarget(reference)
        local ok, err = canvasCopy(P.texture, reference, P.iconW, P.iconH)
        out.reference.copy = ok and "ok" or err
        out.reference.pixels = readPixels(reference, P.iconW, P.iconH, 3)
        out.reference.grid = readPixels(reference, P.iconW, P.iconH, 6)
        out.alpha = classifyAlpha(out.reference.grid, out.direct_grid)
        out.alpha_copy = out.copy.srgb.grid and classifyAlpha(out.reference.grid, out.copy.srgb.grid) or nil
    end
    local srgbDiff = out.copy.srgb.diff_direct
    local linearDiff = out.copy.linear.diff_direct
    if srgbDiff ~= nil and (linearDiff == nil or srgbDiff.mean <= linearDiff.mean) then
        P.copyFormat, out.copy_format = P.formatSrgb, "srgb"
    elseif linearDiff ~= nil then
        P.copyFormat, out.copy_format = P.formatLinear, "linear"
    else
        P.copyFormat, out.copy_format = copyFormatFor(P, info)
    end
    local seen = out.direct_grid.non_black > 0 or (out.copy.srgb.grid and out.copy.srgb.grid.non_black > 0)
    out.result = (not out.direct_grid.read) and "unread" or (seen and "ok" or "black")
    return true
end }

-- One material in the retainer: two frames 0.5 s apart, copy and export times.
local function retainerFrame(P, rt, w, h, fileName)
    local frame = { rt_s = realSeconds(P), t = math.floor(nowMs() - P.openedMs) }
    local target, how = createTarget(w, h, P.copyFormat)
    frame.create = how
    if target == nil then
        return frame
    end
    local started = nowMs()
    local ok, err = canvasCopy(rt, target, w, h)
    frame.copy = ok and "ok" or err
    frame.copy_ms = nowMs() - started
    started = nowMs()
    frame.export = exportTarget(target, fileName)
    frame.export_ms = nowMs() - started
    frame.pixels = readPixels(target, w, h, 4)
    releaseTarget(target)
    return frame
end

local function retainerMaterialStage(P, R, key, material, w, h, baseName)
    local out = R[key] or {}
    R[key] = out
    if P.retainer == nil or material == nil then
        out.result, out.reason = "fail", P.retainer == nil and "no retainer" or "no material"
        return true
    end
    local state = P[key .. "State"]
    if state == nil then
        out.material, out.size = objectPath(material), { w, h }
        out.brush = setRetainerBrush(P, P.retainer, "material", material, w, h)
        P[key .. "State"] = { wait = 3, tries = 0 }
        return false
    end
    if state.t0 == nil then
        local rt = waitTarget(P, state)
        if rt == nil then
            if state.tries < K.RT_WAIT_TICKS then
                return false
            end
            out.rt_tried, out.result = state.tried, "fail"
            return true
        end
        state.rt = rt
        out.rt = targetInfo(rt)
        if key == "mid" then
            local started = nowMs()
            out.direct = exportTarget(rt, baseName .. "_t0_direct.png")
            out.direct_ms = nowMs() - started
        end
        out.t0 = retainerFrame(P, rt, w, h, baseName .. "_t0.png")
        state.t0 = nowMs()
        return false
    end
    if nowMs() - state.t0 < 500 then
        return false
    end
    out.t1 = retainerFrame(P, state.rt, w, h, baseName .. "_t1.png")
    local a, b = out.t0.pixels, out.t1.pixels
    local changed = 0
    if a ~= nil and b ~= nil then
        for index = 1, math.min(#a.samples, #b.samples) do
            local p, q = a.samples[index], b.samples[index]
            if p.r ~= q.r or p.g ~= q.g or p.b ~= q.b or p.a ~= q.a then
                changed = changed + 1
            end
        end
    end
    out.changed_samples = changed
    out.animated = changed > 0
    local nonBlack = (a and a.non_black or 0) + (b and b.non_black or 0)
    out.result = (a == nil or not a.read) and "unread" or (nonBlack > 0 and "ok" or "black")
    return true
end

local function frameSize(w, h)
    local scale = math.min(1, K.CALIB_SIDE_MAX / math.max(w, h))
    return math.max(1, math.floor(w * scale + 0.5)), math.max(1, math.floor(h * scale + 0.5)), scale
end

RETAINER_STAGES[#RETAINER_STAGES + 1] = { "mid", function(P, R)
    -- Img_Bg01 is 2048x2024: half resolution, as the reference frames will be.
    return retainerMaterialStage(P, R, "mid", P.mid, 1024, 1012, "probe_retainer_bg")
end }

RETAINER_STAGES[#RETAINER_STAGES + 1] = { "mid_small", function(P, R)
    local size = get(get(P.smallWidget, "Brush"), "ImageSize")
    local w, h = tonumber(get(size, "X")), tonumber(get(size, "Y"))
    if w == nil or w <= 0 or h == nil or h <= 0 then
        w, h = 256, 256
    end
    w, h = frameSize(w, h)
    return retainerMaterialStage(P, R, "mid_small", P.small, w, h, "probe_retainer_small")
end }

RETAINER_STAGES[#RETAINER_STAGES + 1] = { "cleanup", function(P, R)
    removeRetainer(P.retainer)
    R.cleanup = P.retainer ~= nil and "removed" or "nothing"
    return true
end }

local function retainerLine(R)
    local icon, mid, small = R.icon or {}, R.mid or {}, R.mid_small or {}
    local rt = icon.rt or mid.rt
    local rtText = rt and (tostring(rt.class) .. " " .. tostring(rt.w) .. "x" .. tostring(rt.h)
        .. " fmt=" .. tostring(rt.format)) or "nil"
    local exportMs = mid.t0 and mid.t0.export_ms or nil
    local copyMs = mid.t0 and mid.t0.copy_ms or nil
    local function ms(value)
        return value ~= nil and tostring(math.floor(value + 0.5)) or "?"
    end
    return "[AbsruExport] retainer cvar=" .. tostring(R.cvar and R.cvar.value or "?")
        .. " create=" .. tostring(R.create and R.create.create or "fail")
        .. " rt=" .. rtText .. " icon=" .. tostring(icon.result or "fail")
        .. " copy=" .. tostring(icon.copy_format or "?")
        .. " alpha=" .. tostring(icon.alpha and icon.alpha.result or "?")
        .. " mid=" .. tostring(mid.result or "fail")
        .. " animated=" .. (mid.animated == true and "yes" or "no")
        .. " small=" .. tostring(small.result or "fail") .. "/" .. (small.animated == true and "yes" or "no")
        .. " export_ms=" .. ms(exportMs) .. " copy_ms=" .. ms(copyMs)
        .. " json=" .. S.dir .. S.prefix .. "probe_retainer.json"
end

local function finishProbe(P, R, status)
    R.status = status
    R.finished = stamp("%Y-%m-%d %H:%M:%S")
    R.errors = S.errors
    removeRetainer(P.retainer)
    local release = get(P.lib, "ReleaseRenderTarget2D")
    if type(release) == "function" then
        for _, rt in ipairs(P.targets) do
            pcall(release, rt)
        end
    end
    P.targets = {}
    P.done = true
    writeProbe()
    warn(P.line(R))
end

-- Timer -------------------------------------------------------------------------

local function schedule(delay, step, onFail)
    local manager = nil
    pcall(function() manager = Game and Game.NewUIManager end)
    local addTimer = get(manager, "AddTimerWithFunction")
    local ok, result = false, "AddTimerWithFunction unavailable"
    if type(addTimer) == "function" then
        ok, result = pcall(addTimer, manager, delay, 1, function()
            local stepOk, err = pcall(step)
            if not stepOk then
                noteError("tick", err)
            end
        end)
    end
    if not ok or result == false then
        noteError("timer", result)
        if onFail ~= nil then
            pcall(onFail)
        end
        return false
    end
    return true
end

local stepProbe

local function probeTimerFailed()
    local P = S.probe
    if P ~= nil and not P.done then
        finishProbe(P, P.result, "timer failed")
    end
end

stepProbe = function()
    local P = S.probe
    if P == nil or P.done or S.disabled then
        return
    end
    S.job = P
    local R = P.result
    if get(P.component, "isDestroyed") == true then
        finishProbe(P, R, "panel closed at stage " .. tostring(R.stage))
        return
    end
    local stage = P.stages[P.index]
    if stage == nil then
        finishProbe(P, R, "done")
        return
    end
    local name = stage[1]
    if R.stages[name] == nil then
        R.stage = name
        R.stages[name] = "running"
        writeProbe()
    end
    local ok, done = pcall(stage[2], P, R)
    if not ok then
        noteError(name, done)
        R.stages[name] = "error: " .. clip(done)
        done = true
    elseif done == true then
        R.stages[name] = "ok"
    elseif done ~= false then
        R.stages[name] = "failed"
        done = true
    end
    if done then
        writeProbe()
        P.index = P.index + 1
        if name == "api" and P.lib == nil then
            finishProbe(P, R, "KismetRenderingLibrary unavailable")
            return
        end
        if name == "context" and P.ctx == nil then
            finishProbe(P, R, "no world context")
            return
        end
    end
    schedule(STEP_SECONDS, stepProbe, probeTimerFailed)
end

-- Full export (steps 1-3) --------------------------------------------------------

local function newFullJob()
    return {
        mode = "full", targets = {}, opens = 0, ready = false, closed = true,
        result = { version = S.version, started = stamp("%Y-%m-%d %H:%M:%S"), status = "running", stages = {} },
        widgets = {}, widgetIndex = {}, tracks = {}, trackCursor = 1, active = {}, activeList = {},
        iconWidgets = {}, textWidgets = {}, animationsSeen = {}, animations = {}, walkSerial = 0,
        textures = {}, textureOrder = {}, textureObjects = {}, unknown = {}, unknownSeen = {},
        atlases = {}, atlasOrder = {}, sprites = {}, spriteAssets = {},
        materials = {}, materialObjects = {}, baseMaterials = {}, baseNames = {}, bases = {}, mids = {},
        effectiveQueue = {}, effectiveQueued = {},
        texQueue = {}, calibQueue = {}, fileNames = {},
        files = 0, bytes = 0, limited = false,
        pendingWalks = {}, snapshots = {}, snapshotCount = 0,
        events = {}, eventsDropped = 0, windows = {}, windowEnd = 0,
        rates = { samples = 0, active_samples = 0, sweeps = 0, ms = 0, ticks = 0, mid_samples = 0 },
        calib = { enabled = cfg.Calib, reps = {}, dirs = {}, queue = {}, active = {}, poolBytes = 0, frames = 0, series = {} },
        dirty = {}, lastSave = 0, pathKeys = {}, pathCount = 0, sigNoise = {}, sigLast = {},
    }
end

local function tMs(J, now)
    return math.floor((now or nowMs()) - J.openedMs)
end

local function markDirty(J, name)
    J.dirty[name] = true
end

local function noteUnknown(J, object, source, class)
    local path = objectPath(object) or tostring(object)
    if J.unknownSeen[path] then
        return
    end
    J.unknownSeen[path] = true
    J.unknown[#J.unknown + 1] = { path = path, class = class or className(object), source = source }
    markDirty(J, "textures")
end

local function uniqueFile(J, dir, name, ext)
    local base = dir .. safeName(name)
    local file = base .. ext
    local n = 1
    while J.fileNames[file] do
        n = n + 1
        file = base .. "_" .. n .. ext
    end
    J.fileNames[file] = true
    return file
end

-- Texture props, forced mips and the export items (one per colour space).
local function prepareTexture(J, texture, rec, dir, kind)
    for _, prop in ipairs(K.TEXTURE_PROPS) do
        local value = get(texture, prop)
        if value ~= nil and type(value) ~= "function" then
            rec[prop] = describe(value)
        end
    end
    local srgb = toBool(get(texture, "SRGB"))
    rec.SRGB = srgb
    local ok, _, err = callMethod(texture, "SetForceMipLevelsToBeResident", 30, 0)
    rec.force_mips = ok and "ok" or err
    local due = math.max(nowMs() + K.MIP_WAIT_MS, J.openedMs + K.FULL_DELAY_MS)
    local variants
    if srgb == true then
        variants = { { "file", ".png", J.formatSrgb, "RTF_RGBA8_SRGB" } }
    elseif srgb == false then
        variants = { { "file", ".png", J.formatLinear, "RTF_RGBA8" } }
    else
        -- SRGB unreadable: both variants, the demo picks one.
        variants = { { "file", ".srgb.png", J.formatSrgb, "RTF_RGBA8_SRGB" },
            { "file_linear", ".linear.png", J.formatLinear, "RTF_RGBA8" } }
    end
    for _, variant in ipairs(variants) do
        local file = uniqueFile(J, dir, rec.name, variant[2])
        rec[variant[1]] = file
        J.texQueue[#J.texQueue + 1] = {
            kind = kind, rec = rec, object = texture, field = variant[1], file = file,
            format = variant[3], format_name = variant[4], due = due,
        }
    end
    rec.rt_format = srgb == nil and "both" or variants[1][4]
end

local function noteTexture(J, texture, source)
    local path = objectPath(texture)
    if path == nil then
        return nil
    end
    local rec = J.textures[path]
    if rec ~= nil then
        return rec
    end
    local class = className(texture)
    if class ~= "Texture2D" then
        noteUnknown(J, texture, source, class)
        return nil
    end
    rec = { path = path, name = objectName(texture) or shortName(path), source = source, status = "pending" }
    J.textures[path] = rec
    J.textureOrder[#J.textureOrder + 1] = rec
    J.textureObjects[path] = texture
    prepareTexture(J, texture, rec, "textures/", "texture")
    markDirty(J, "textures")
    return rec
end

local function noteAtlas(J, atlas)
    local path = objectPath(atlas)
    if path == nil then
        return nil
    end
    local rec = J.atlases[path]
    if rec ~= nil then
        return rec
    end
    rec = {
        path = path, name = objectName(atlas) or shortName(path), status = "pending",
        AtlasWidth = get(atlas, "AtlasWidth"), AtlasHeight = get(atlas, "AtlasHeight"),
        AtlasFilter = describe(get(atlas, "Filter")), BatchAtlasIndex = get(atlas, "BatchAtlasIndex"),
    }
    J.atlases[path] = rec
    J.atlasOrder[#J.atlasOrder + 1] = rec
    local sprites = 0
    rec.sprites_error = eachPair(get(atlas, "Sprites"), 5000, function(key, entry)
        local start, size = get(entry, "StartUV"), get(entry, "Size")
        J.sprites[#J.sprites + 1] = {
            sprite = tostring(get(entry, "Name") or key), key = tostring(key), atlas = rec.name, atlas_path = path,
            x = get(start, "X"), y = get(start, "Y"), w = get(size, "X"), h = get(size, "Y"),
        }
        sprites = sprites + 1
    end)
    rec.count = sprites
    local texture = get(atlas, "AtlasTexture")
    rec.texture = objectPath(texture)
    if texture ~= nil then
        rec.texture_w, rec.texture_h = textureSize(texture)
        prepareTexture(J, texture, rec, "atlases/", "atlas")
    else
        rec.status = "fail"
        rec.error = "no AtlasTexture"
    end
    markDirty(J, "sprites")
    return rec
end

local function addName(set, name, J, base)
    if name ~= nil and name ~= "?" and not set[name] then
        set[name] = true
        J.baseNames[base].version = J.baseNames[base].version + 1
    end
end

local function baseNamesFor(J, base)
    local names = J.baseNames[base]
    if names == nil then
        names = { scalar = {}, vector = {}, texture = {}, version = 0 }
        J.baseNames[base] = names
    end
    return names
end

local function eachItem(array, limit, visit)
    local n = count(array)
    if n > 0 then
        for index = 0, math.min(n, limit) - 1 do
            visit(index, item(array, index))
        end
        return
    end
    local index = 0
    eachPair(array, limit, function(_, value)
        visit(index, value)
        index = index + 1
    end)
end

-- Material properties, fields and whatever the cooked data keeps about
-- parameter defaults and textures (TextureStreamingData, CachedExpressionData).
local function noteBaseMaterial(J, material, path)
    if J.baseMaterials[path] ~= nil then
        return
    end
    local out = { class = className(material), props = {} }
    J.baseMaterials[path] = out
    for _, prop in ipairs(K.MATERIAL_PROPS) do
        local value = get(material, prop)
        if value ~= nil and type(value) ~= "function" then
            out.props[prop] = describe(value)
        end
    end
    local fields = pairsDump(material, KEYS_MAX)
    out.fields = jsonArray(fields.entries)
    out.fields_error = fields.error
    local names = baseNamesFor(J, path)
    local streaming = jsonArray()
    eachItem(get(material, "TextureStreamingData"), 200, function(_, entry)
        local textureName = get(entry, "TextureName")
        local view = {
            TextureName = textureName ~= nil and tostring(textureName) or nil,
            SamplingScale = get(entry, "SamplingScale"), UVChannelIndex = get(entry, "UVChannelIndex"),
            TextureIndex = get(entry, "TextureIndex"),
        }
        if view.TextureName ~= nil and view.TextureName:find("/", 1, true) then
            local texture = loadObject(view.TextureName)
            view.loaded = texture ~= nil
            if texture ~= nil then
                noteTexture(J, texture, "material_streaming")
            end
        end
        streaming[#streaming + 1] = view
    end)
    out.texture_streaming = streaming
    local cached = get(material, "CachedExpressionData")
    if cached ~= nil then
        out.cached = pairsDump(cached, 50)
        local referenced = jsonArray()
        eachItem(get(cached, "ReferencedTextures"), 200, function(_, texture)
            referenced[#referenced + 1] = objectPath(texture)
            if texture ~= nil then
                noteTexture(J, texture, "material_cached")
            end
        end)
        out.referenced_textures = referenced
        local parameters = get(cached, "Parameters")
        if parameters ~= nil then
            out.parameters = pairsDump(parameters, 50)
            -- RuntimeEntries[type]: 0 scalar, 1 vector, 2 texture (EMaterialParameterType).
            local sets = { names.scalar, names.vector, names.texture }
            out.parameter_names = jsonArray()
            eachItem(get(parameters, "RuntimeEntries"), 8, function(typeIndex, entry)
                local list = jsonArray()
                local infos = get(entry, "ParameterInfos") or get(entry, "ParameterInfoSet")
                eachItem(infos, 500, function(_, info)
                    local name = get(info, "Name")
                    if name ~= nil then
                        list[#list + 1] = tostring(name)
                        if sets[typeIndex + 1] ~= nil then
                            addName(sets[typeIndex + 1], tostring(name), J, path)
                        end
                    end
                end)
                out.parameter_names[#out.parameter_names + 1] = { type_index = typeIndex, names = list }
            end)
            for _, field in ipairs({ "ScalarValues", "VectorValues", "TextureValues" }) do
                local values = jsonArray()
                eachItem(get(parameters, field), 300, function(_, value)
                    values[#values + 1] = describe(value)
                end)
                out[field] = values
            end
        end
    end
    markDirty(J, "materials")
end

local function queueEffective(J, path)
    if not J.effectiveQueued[path] then
        J.effectiveQueued[path] = true
        J.effectiveQueue[#J.effectiveQueue + 1] = path
    end
end

local noteCalib

local function noteMaterial(J, material, widgetRec, brushSize)
    local path = objectPath(material)
    if path == nil then
        return nil
    end
    local rec = J.materials[path]
    if rec ~= nil then
        rec.widgets = rec.widgets + 1
        if rec.base ~= nil and J.bases[rec.base] ~= nil then
            J.bases[rec.base].widgets = J.bases[rec.base].widgets + 1
        end
        return rec
    end
    rec = { path = path, name = objectName(material) or shortName(path), class = className(material), widgets = 1, chain = jsonArray() }
    J.materials[path] = rec
    local levels = {}
    local level, depth = material, 0
    while level ~= nil and depth < 8 do
        local entry = { path = objectPath(level), class = className(level) }
        local params = materialParams(level, function(field, _, value)
            if field == "TextureParameterValues" and value ~= nil and objectPath(value) ~= nil then
                noteTexture(J, value, "material")
            end
        end)
        for field, kind in pairs(K.FIELD_KIND) do
            entry[kind] = jsonArray(params[field].values)
        end
        rec.chain[#rec.chain + 1] = entry
        levels[#levels + 1] = entry
        local parent = get(level, "Parent")
        if entry.class == "Material" or parent == nil then
            rec.base = entry.path
            if entry.path ~= nil then
                noteBaseMaterial(J, level, entry.path)
            end
        end
        level = parent
        depth = depth + 1
    end
    rec.parent = rec.chain[2] and rec.chain[2].path or nil
    rec.mi = rec.class == "MaterialInstanceDynamic" and rec.parent or path
    rec.mi_name = shortName(rec.mi)
    if rec.base ~= nil then
        local names = baseNamesFor(J, rec.base)
        for _, entry in ipairs(levels) do
            for _, kind in ipairs({ "scalar", "vector", "texture" }) do
                for _, param in ipairs(entry[kind]) do
                    addName(names[kind], param.name, J, rec.base)
                end
            end
        end
        local base = J.bases[rec.base]
        if base == nil then
            base = { instances = {}, mids = 0, widgets = 0 }
            J.bases[rec.base] = base
        end
        base.instances[rec.mi or path] = true
        base.widgets = base.widgets + 1
        if rec.class == "MaterialInstanceDynamic" then
            base.mids = base.mids + 1
        end
    end
    if rec.class == "MaterialInstanceDynamic" then
        J.materialObjects[path] = material
        J.mids[#J.mids + 1] = rec
        J.tracks[#J.tracks + 1] = { material = rec }
        queueEffective(J, path)
        if noteCalib ~= nil then
            noteCalib(J, rec, material, brushSize, widgetRec)
        end
    end
    markDirty(J, "materials")
    return rec
end

-- Current scalar/vector (and texture) values of a MID for every parameter name
-- any instance of its base material uses.
local function midValues(J, rec, mid, withTextures)
    local names = rec.base and J.baseNames[rec.base]
    local out = { scalar = {}, vector = {} }
    if names == nil then
        return out, 0
    end
    local calls = 0
    for name in pairs(names.scalar) do
        local ok, value = callMethod(mid, "K2_GetScalarParameterValue", name)
        if ok then
            out.scalar[name] = value
        end
        calls = calls + 1
    end
    for name in pairs(names.vector) do
        local ok, value = callMethod(mid, "K2_GetVectorParameterValue", name)
        if ok then
            out.vector[name] = describe(value)
        end
        calls = calls + 1
    end
    if withTextures then
        out.texture = {}
        for name in pairs(names.texture) do
            local ok, value = callMethod(mid, "K2_GetTextureParameterValue", name)
            if ok and value ~= nil then
                out.texture[name] = objectPath(value)
                noteTexture(J, value, "material")
            end
            calls = calls + 1
        end
    end
    return out, calls
end

local function stepEffective(J, deadline)
    while #J.effectiveQueue > 0 and nowMs() < deadline do
        local path = table.remove(J.effectiveQueue, 1)
        J.effectiveQueued[path] = nil
        local rec, mid = J.materials[path], J.materialObjects[path]
        if rec ~= nil and mid ~= nil then
            local names = rec.base and J.baseNames[rec.base]
            rec.effective = midValues(J, rec, mid, true)
            rec.effective_version = names and names.version or 0
            markDirty(J, "materials")
        end
    end
end

-- Layout views ------------------------------------------------------------------

local function colorView(value)
    if value == nil then
        return nil
    end
    local specified = get(value, "SpecifiedColor")
    if specified ~= nil then
        return { color = describe(specified), rule = describe(get(value, "ColorUseRule")) }
    end
    return describe(value)
end

local function transformView(value)
    if value == nil then
        return nil
    end
    return {
        translation = describe(get(value, "Translation")), scale = describe(get(value, "Scale")),
        shear = describe(get(value, "Shear")), angle = get(value, "Angle"),
    }
end

local function methodValue(object, name)
    local ok, value = callMethod(object, name)
    return ok and describe(value) or nil
end

local function slotView(slot)
    local anchors = nil
    local okA, value = callMethod(slot, "GetAnchors")
    if okA and value ~= nil then
        anchors = { min = describe(get(value, "Minimum")), max = describe(get(value, "Maximum")) }
    end
    local size = get(slot, "Size")
    return {
        class = className(slot), position = methodValue(slot, "GetPosition"), size = methodValue(slot, "GetSize"),
        anchors = anchors, alignment = methodValue(slot, "GetAlignment"), autosize = methodValue(slot, "GetAutoSize"),
        zorder = methodValue(slot, "GetZOrder"), padding = describe(get(slot, "Padding")),
        halign = describe(get(slot, "HorizontalAlignment")), valign = describe(get(slot, "VerticalAlignment")),
        size_rule = size ~= nil and type(size) ~= "function" and {
            rule = describe(get(size, "SizeRule")), value = describe(get(size, "Value")),
        } or nil,
    }
end

-- Out parameters are instances (as for BeginDrawCanvasToRenderTarget); the
-- signature that worked is kept in export_state.json.
local function localToViewport(J, geometry, point)
    local slate = J.slate
    local attempts = {
        { "ctx,geom,local,out,out", function()
            return slate.LocalToViewport(J.ctx, geometry, point, vector2(0, 0), vector2(0, 0))
        end },
        { "ctx,geom,local", function() return slate.LocalToViewport(J.ctx, geometry, point) end },
    }
    if J.viewportSig ~= nil then
        attempts = { attempts[J.viewportSig] }
    end
    for index, attempt in ipairs(attempts) do
        local ok, pixel, viewport = pcall(attempt[2])
        if ok and type(get(pixel, "X")) == "number" then
            if J.viewportSig == nil then
                J.viewportSig = index
                J.result.local_to_viewport = attempt[1]
            end
            return pixel, viewport
        end
    end
    return nil, nil
end

local function geometryView(J, widget)
    if J.slate == nil then
        return nil
    end
    local okG, geometry = callMethod(widget, "GetCachedGeometry")
    if not okG or geometry == nil then
        return nil
    end
    local out = {}
    local slate = J.slate
    local okL, localSize = pcall(slate.GetLocalSize, geometry)
    out.local_size = okL and describe(localSize) or nil
    local okS, absSize = pcall(slate.GetAbsoluteSize, geometry)
    out.abs_size = okS and describe(absSize) or nil
    local okA, absolute = pcall(slate.LocalToAbsolute, geometry, vector2(0, 0))
    out.abs = okA and describe(absolute) or nil
    local pixel, viewport = localToViewport(J, geometry, vector2(0, 0))
    out.px, out.vp = describe(pixel), describe(viewport)
    local w, h = out.local_size and out.local_size.X, out.local_size and out.local_size.Y
    if pixel ~= nil and type(w) == "number" and type(h) == "number" then
        local pixelEnd = localToViewport(J, geometry, vector2(w, h))
        out.px_end = describe(pixelEnd)
    end
    return out
end

local function brushView(brush, resource)
    if brush == nil then
        return nil
    end
    local uv = get(brush, "UVRegion")
    return {
        draw_as = describe(get(brush, "DrawAs")), tiling = describe(get(brush, "Tiling")),
        mirroring = describe(get(brush, "Mirroring")), margin = describe(get(brush, "Margin")),
        tint = colorView(get(brush, "TintColor")), image_size = describe(get(brush, "ImageSize")),
        uv_region = uv ~= nil and type(uv) ~= "function" and {
            min = describe(get(uv, "Min")), max = describe(get(uv, "Max")), valid = describe(get(uv, "bIsValid")),
        } or nil,
        resource = resource,
    }
end

local function textView(widget)
    local ok, text = callMethod(widget, "GetText")
    local font = get(widget, "Font")
    return {
        text = ok and text ~= nil and clip(tostring(text)) or nil,
        font = font ~= nil and type(font) ~= "function" and {
            object = objectPath(get(font, "FontObject")), typeface = get(font, "TypefaceFontName") ~= nil
                and tostring(get(font, "TypefaceFontName")) or nil,
            size = get(font, "Size"), outline = get(get(font, "OutlineSettings"), "OutlineSize"),
        } or nil,
        color = colorView(get(widget, "ColorAndOpacity")), justification = describe(get(widget, "Justification")),
    }
end

local function layoutEntry(J, rec)
    local widget = rec.obj
    if objectName(widget) == nil then
        return nil
    end
    local entry = { id = rec.id, name = rec.name, class = rec.class, parent = rec.parent }
    local okP, parent = callMethod(widget, "GetParent")
    if okP and parent ~= nil then
        local okI, index = callMethod(parent, "GetChildIndex", widget)
        entry.index = okI and index or nil
        local parentRec = J.widgetIndex[parent]
        entry.panel = parentRec and parentRec.id or nil
    end
    local slot = get(widget, "Slot")
    if slot ~= nil and type(slot) ~= "function" then
        entry.slot = slotView(slot)
    end
    entry.geom = geometryView(J, widget)
    entry.opacity = get(widget, "RenderOpacity")
    entry.transform = transformView(get(widget, "RenderTransform"))
    entry.pivot = describe(get(widget, "RenderTransformPivot"))
    entry.visibility = describe(get(widget, "Visibility"))
    entry.clipping = describe(get(widget, "Clipping"))
    local isText = type(get(widget, "GetText")) == "function"
    if isText then
        entry.text = textView(widget)
    else
        entry.color = colorView(get(widget, "ColorAndOpacity"))
    end
    if rec.hasBrush then
        entry.brush = brushView(get(widget, "Brush"), rec.resource)
    end
    return entry
end

-- Walk --------------------------------------------------------------------------

local function noteAnimations(J, widget, rec)
    if J.animationsSeen[rec.class] then
        return
    end
    J.animationsSeen[rec.class] = true
    eachPair(widget, 1000, function(key, value)
        if type(value) ~= "function" and className(value) == "WidgetAnimation" then
            local okEnd, endTime = callMethod(value, "GetEndTime")
            local okStart, startTime = callMethod(value, "GetStartTime")
            J.animations[#J.animations + 1] = {
                owner = rec.class, field = tostring(key), name = objectName(value),
                start = okStart and startTime or nil, ["end"] = okEnd and endTime or nil,
            }
        end
    end)
    markDirty(J, "timeline")
end

local function noteResource(J, rec, resource, size)
    local class = className(resource) or "?"
    local path = objectPath(resource)
    if class == "Texture2D" then
        noteTexture(J, resource, "brush")
        if path ~= nil and path:find("Icon_Class", 1, true) then
            J.iconWidgets[rec.id] = rec
            if J.calib.control == nil and noteCalib ~= nil then
                noteCalib(J, nil, resource, size, rec)
            end
        end
        return { kind = "texture", path = path }
    elseif class == "KGSprite" then
        local atlas = get(resource, "Atlas")
        local atlasRec = atlas ~= nil and noteAtlas(J, atlas) or nil
        local spriteName = get(resource, "SpriteName")
        local ref = { kind = "sprite", path = path, atlas = atlasRec and atlasRec.name or nil,
            sprite = spriteName ~= nil and tostring(spriteName) or nil }
        if path ~= nil and J.spriteAssets[path] == nil then
            J.spriteAssets[path] = { atlas = ref.atlas, sprite = ref.sprite }
            markDirty(J, "sprites")
        end
        return ref
    elseif class:find("Material", 1, true) then
        noteMaterial(J, resource, rec, size)
        return { kind = "material", path = path }
    end
    noteUnknown(J, resource, "brush", class)
    return { kind = "unknown", class = class, path = path }
end

local function visitFull(J, widget, parent)
    if S.own[widget] then
        return false
    end
    local rec = J.widgetIndex[widget]
    if rec == nil then
        rec = { id = #J.widgets + 1, obj = widget, name = objectName(widget) or "?", class = className(widget) or "?" }
        J.widgets[rec.id] = rec
        J.widgetIndex[widget] = rec
        J.tracks[#J.tracks + 1] = { widget = rec }
    end
    rec.seen = J.walkSerial
    local parentRec = parent ~= nil and J.widgetIndex[parent] or nil
    if parentRec ~= nil then
        rec.parent = parentRec.id
    end
    local brush = get(widget, "Brush")
    if brush ~= nil and type(brush) ~= "function" then
        rec.hasBrush = true
        local resource = get(brush, "ResourceObject")
        local path = resource ~= nil and objectPath(resource) or nil
        -- A re-walk counts a widget's material once; a new resource is noted again.
        if resource ~= nil and path ~= rec.resourcePath then
            rec.resourcePath = path
            rec.resource = noteResource(J, rec, resource, get(brush, "ImageSize"))
        end
    elseif not rec.textNoted and #J.textWidgets < 30 and type(get(widget, "GetText")) == "function" then
        -- The first texts of the panel (title, path name) join the path signature.
        rec.textNoted = true
        J.textWidgets[#J.textWidgets + 1] = rec
    end
    if rec.class:sub(-2) == "_C" then
        noteAnimations(J, widget, rec)
    end
    return false
end

local function stepWalks(J, now)
    if J.walk == nil then
        local nextWalk = J.pendingWalks[1]
        if nextWalk == nil or nextWalk.at > now then
            return
        end
        table.remove(J.pendingWalks, 1)
        J.walkSerial = J.walkSerial + 1
        J.walk, J.walkInfo = S.diag.NewPanelWalk(J.component), nextWalk
        J.walkInfo.started, J.walkInfo.ticks, J.walkInfo.before = now, 0, #J.widgets
    end
    local info = J.walkInfo
    info.ticks = info.ticks + 1
    local done = J.walk(nowMs() + J.budget, function(widget, parent) return visitFull(J, widget, parent) end)
    if not done and info.ticks < WALK_TICKS_MAX * 5 then
        return
    end
    J.walk = nil
    J.result.walks = J.result.walks or jsonArray()
    J.result.walks[#J.result.walks + 1] = {
        reason = info.reason, t = tMs(J, info.started), ticks = info.ticks, complete = done,
        widgets = #J.widgets, new = #J.widgets - info.before,
    }
    if info.reason == "open" then
        J.initialWalk = false
    end
    -- New parameter names: effective values of the MIDs of that base again.
    for _, rec in ipairs(J.mids) do
        local names = rec.base and J.baseNames[rec.base]
        if names ~= nil and rec.effective_version ~= names.version then
            queueEffective(J, rec.path)
        end
    end
    if info.snapshot then
        J.snapDue = math.max(now, info.snapshotAt or now)
        J.snapReason = info.reason
    end
    markDirty(J, "state")
end

-- Layout snapshots ----------------------------------------------------------------

local function viewportInfo(J)
    local layout = importSafe("WidgetLayoutLibrary")
    local okSize, size = pcall(function() return layout.GetViewportSize(J.ctx) end)
    local okScale, scale = pcall(function() return layout.GetViewportScale(J.ctx) end)
    return okSize and describe(size) or nil, okScale and tonumber(scale) or nil
end

local function writeLayoutIndex(J)
    local viewport, scale = viewportInfo(J)
    return writeJson("layout.json", {
        version = S.version, viewport = viewport, viewport_scale = scale,
        local_to_viewport = J.result.local_to_viewport, snapshots = jsonArray(J.snapshots),
    })
end

local function stepSnapshot(J, now)
    local snap = J.snap
    if snap == nil then
        if J.snapDue == nil or J.snapDue > now or J.walk ~= nil then
            return
        end
        J.snapDue = nil
        J.snapshotCount = J.snapshotCount + 1
        local viewport, scale = viewportInfo(J)
        snap = {
            index = J.snapshotCount, t = tMs(J, now), open = J.opens, reason = J.snapReason,
            path_index = J.pathIndex or 0, path_key = J.pathSig, viewport = viewport, viewport_scale = scale,
            root = J.userWidget ~= nil and geometryView(J, J.userWidget) or nil,
            widgets = jsonArray(), cursor = 1, started = now, serial = J.walkSerial,
        }
        J.snap = snap
    end
    local deadline = nowMs() + J.snapshotBudget
    while snap.cursor <= #J.widgets and nowMs() < deadline do
        -- Only widgets the latest walk reached: the tree as it is now.
        local rec = J.widgets[snap.cursor]
        if rec.seen == snap.serial then
            local ok, entry = pcall(layoutEntry, J, rec)
            if ok and entry ~= nil then
                snap.widgets[#snap.widgets + 1] = entry
            elseif not ok then
                noteError("layout", entry)
            end
        end
        snap.cursor = snap.cursor + 1
    end
    if snap.cursor <= #J.widgets then
        return
    end
    J.snap = nil
    local file = string.format("layout_%03d.json", snap.index)
    local cursor, started = snap.cursor, snap.started
    snap.cursor, snap.started = nil, nil
    snap.ms = math.floor(nowMs() - started)
    writeJson(file, snap)
    J.snapshots[#J.snapshots + 1] = {
        index = snap.index, file = file, t = snap.t, open = snap.open, reason = snap.reason,
        path_index = snap.path_index, path_key = snap.path_key, widgets = #snap.widgets, ms = snap.ms,
        interrupted = snap.interrupted,
    }
    writeLayoutIndex(J)
    warn("[AbsruExport] snapshot index=" .. snap.index .. " path=" .. tostring(snap.path_index)
        .. " widgets=" .. #snap.widgets .. " ms=" .. snap.ms .. " scanned=" .. (cursor - 1))
end

-- Timeline ----------------------------------------------------------------------

local function valueKey(value)
    if type(value) == "table" then
        local ok, text = pcall(S.encode, value)
        return ok and text or tostring(value)
    end
    return tostring(value)
end

local function addEvent(J, t, rt, kind, id, prop, value)
    if #J.events >= K.EVENTS_MAX then
        J.eventsDropped = J.eventsDropped + 1
        return
    end
    J.events[#J.events + 1] = { t = t, rt = rt, o = J.opens, k = kind, id = id, p = prop, v = value }
end

local function sampleTrack(J, track, t, rt)
    local last, state, kind, id
    if track.widget ~= nil then
        local rec = track.widget
        local widget = rec.obj
        state = {
            opacity = get(widget, "RenderOpacity"), transform = transformView(get(widget, "RenderTransform")),
            visibility = describe(get(widget, "Visibility")), color = colorView(get(widget, "ColorAndOpacity")),
        }
        if rec.hasBrush then
            state.tint = colorView(get(get(widget, "Brush"), "TintColor"))
        end
        kind, id = "w", rec.id
    else
        local rec = track.material
        local mid = J.materialObjects[rec.path]
        local values = midValues(J, rec, mid, false)
        state = {}
        for name, value in pairs(values.scalar) do
            state["s:" .. name] = value
        end
        for name, value in pairs(values.vector) do
            state["v:" .. name] = value
        end
        kind, id = "m", rec.path
        J.rates.mid_samples = J.rates.mid_samples + 1
    end
    last = track.last or {}
    local changed = false
    for prop, value in pairs(state) do
        local key = valueKey(value)
        if last[prop] ~= key then
            last[prop] = key
            addEvent(J, t, rt, kind, id, prop, value)
            changed = true
        end
    end
    track.last = last
    if changed and track.sampled and not track.active then
        track.active = true
        J.activeList[#J.activeList + 1] = track
    end
    track.sampled = true
    J.rates.samples = J.rates.samples + 1
end

-- Active tracks (changed at least once) every tick, the rest round-robin.
local function stepTimeline(J, now)
    if now > J.windowEnd then
        if J.windowOpen then
            J.windowOpen = false
            markDirty(J, "timeline")
        end
        return
    end
    J.windowOpen = true
    local started = nowMs()
    local deadline = started + J.timelineBudget
    local t, rt = tMs(J, now), realSeconds(J)
    for _, track in ipairs(J.activeList) do
        if nowMs() >= deadline then
            break
        end
        sampleTrack(J, track, t, rt)
        J.rates.active_samples = J.rates.active_samples + 1
    end
    local tracks = J.tracks
    local visited = 0
    while #tracks > 0 and nowMs() < deadline and visited < #tracks do
        if J.trackCursor > #tracks then
            J.trackCursor = 1
            J.rates.sweeps = J.rates.sweeps + 1
        end
        local track = tracks[J.trackCursor]
        J.trackCursor = J.trackCursor + 1
        visited = visited + 1
        if not track.active then
            sampleTrack(J, track, t, rt)
        end
    end
    J.rates.ticks = J.rates.ticks + 1
    J.rates.ms = J.rates.ms + (nowMs() - started)
    J.rates.window_ms = (J.rates.window_ms or 0) + STEP_SECONDS * 1000
end

local function openWindow(J, now, length, reason)
    J.windowEnd = math.max(J.windowEnd, now + length)
    J.windows[#J.windows + 1] = {
        start = tMs(J, now), ["end"] = tMs(J, now + length), reason = reason, open = J.opens,
        path_index = J.pathIndex or 0,
    }
end

-- Reference frames (step 3.2) ---------------------------------------------------

local function calibStop(J, reason)
    local C = J.calib
    if not C.enabled then
        return
    end
    C.enabled, C.stopped = false, reason
    C.queue = {}
    for _, series in ipairs(C.active) do
        removeRetainer(series.handle)
        if series.state ~= "export" then
            series.state, series.status = "done", "cancelled: " .. tostring(reason)
            for _, rt in ipairs(series.pool or {}) do
                releaseTarget(rt)
            end
        end
    end
    markDirty(J, "state")
end

noteCalib = function(J, rec, object, size, widgetRec)
    local C = J.calib
    if not C.enabled then
        return
    end
    local w, h = tonumber(get(size, "X")), tonumber(get(size, "Y"))
    if rec == nil then
        -- The control icon: its own texture size.
        w, h = textureSize(object)
        if w == nil then
            return
        end
        C.control = { kind = "control", object = object, w = w, h = h, image = { w, h }, scale = 1,
            dir = "calib/_control/", name = "_control", widget = widgetRec and widgetRec.name, state = "create" }
        C.active[#C.active + 1] = C.control
        C.series[#C.series + 1] = C.control
        return
    end
    if w == nil or w <= 0 or h == nil or h <= 0 then
        return
    end
    local key = tostring(rec.mi) .. "|" .. math.floor(w) .. "x" .. math.floor(h)
    if C.reps[key] then
        return
    end
    C.reps[key] = true
    local fw, fh, scale = frameSize(w, h)
    local name = safeName(rec.mi_name or rec.name)
    if C.dirs[name] then
        name = name .. "_" .. fw .. "x" .. fh
    end
    C.dirs[name] = true
    local base = {
        rec = rec, object = object, w = fw, h = fh, image = { w, h }, scale = scale,
        widget = widgetRec and widgetRec.name,
    }
    local function series(kind, dir)
        local entry = { kind = kind, dir = dir, name = name, state = "create" }
        for field, value in pairs(base) do
            entry[field] = value
        end
        return entry
    end
    C.queue[#C.queue + 1] = series("regular", "calib/" .. name .. "/")
    if J.initialWalk and tostring(rec.mi_name):find("_Animated", 1, true) then
        local opening = series("open", "calib/" .. name .. "_open/")
        C.active[#C.active + 1] = opening
        C.series[#C.series + 1] = opening
    end
end

local function seriesView(J, series)
    local rec = series.rec
    return {
        kind = series.kind, mi = rec and rec.mi or nil, mid = rec and rec.path or nil,
        texture = series.kind == "control" and objectPath(series.object) or nil, widget = series.widget,
        size = { series.w, series.h }, image_size = series.image, scale = series.scale, rt = series.rtInfo,
        copy_format = series.copyName, alpha = J.calib.alpha, status = series.status,
        created = series.info, frames = jsonArray(series.frames),
        control = series.control,
    }
end

local function finishSeries(J, series, status)
    series.status = series.status or status
    removeRetainer(series.handle)
    local pending = 0
    for index, frame in ipairs(series.frames or {}) do
        if frame.captured then
            pending = pending + 1
            J.calibQueue[#J.calibQueue + 1] = { series = series, index = index }
        end
    end
    series.pending = pending
    series.state = "export"
    if pending == 0 then
        for _, rt in ipairs(series.pool or {}) do
            releaseTarget(rt)
        end
        J.calib.poolBytes = J.calib.poolBytes - (series.poolBytes or 0)
        series.poolBytes = 0
        writeJson(series.dir .. "frames.json", seriesView(J, series))
        series.state = "done"
    end
end

local function planFrames(J, series)
    local bytes = series.w * series.h * 4
    local wanted = series.kind == "regular" and #K.CALIB_MOMENTS or (series.kind == "open" and K.CALIB_OPEN_FRAMES or 2)
    local room = math.floor((K.CALIB_POOL_MB * 1048576 - J.calib.poolBytes) / bytes)
    return math.min(wanted, room), bytes
end

local function captureFrame(J, series, now)
    local index = #series.frames + 1
    local rt = series.pool[index]
    local frame = { file = series.dir .. string.format("%03d.png", index - 1), t = tMs(J, now), rt_s = realSeconds(J) }
    local ok, err = canvasCopy(series.rt, rt, series.w, series.h)
    frame.copy = ok and "ok" or err
    frame.captured = ok
    if series.rec ~= nil then
        local mid = J.materialObjects[series.rec.path]
        if mid ~= nil then
            frame.params = midValues(J, series.rec, mid, false)
        end
    end
    series.frames[index] = frame
    return frame
end

local reserve, exportCounted   -- Exports section

-- The control icon: direct export, both copies, alpha / colour-space decision.
local function controlCapture(J, series, now)
    local C = J.calib
    local out = {}
    series.control = out
    local rw, rh = series.rtInfo.w or series.w, series.rtInfo.h or series.h
    if reserve(J, rw * rh * 4, true) then
        out.direct = exportCounted(J, series.rt, series.dir .. "icon_direct.png", rw * rh * 4)
        if out.direct.call == "ok" then
            C.frames = C.frames + 1
        end
    end
    local direct = readPixels(series.rt, rw, rh, 6)
    out.direct_grid = direct
    local grids = {}
    for index, name in ipairs({ "srgb", "linear" }) do
        clearTarget(series.pool[index])
        local ok, err = canvasCopy(series.rt, series.pool[index], series.w, series.h)
        local frame = {
            file = series.dir .. string.format("%03d.png", index - 1), t = tMs(J, now), rt_s = realSeconds(J),
            copy = ok and "ok" or err, captured = ok, format = name,
        }
        series.frames[index] = frame
        grids[name] = readPixels(series.pool[index], series.w, series.h, 6)
        out[name .. "_diff"] = pixelDiff(grids[name], direct)
    end
    local reference, how = createTarget(series.w, series.h, J.formatSrgb)
    out.reference = how
    if reference ~= nil then
        clearTarget(reference)
        canvasCopy(series.object, reference, series.w, series.h)
        local refGrid = readPixels(reference, series.w, series.h, 6)
        releaseTarget(reference)
        out.alpha = classifyAlpha(refGrid, direct)
        C.alpha = out.alpha.result
    end
    local srgbDiff, linearDiff = out.srgb_diff, out.linear_diff
    if srgbDiff ~= nil and (linearDiff == nil or srgbDiff.mean <= linearDiff.mean) then
        C.copyFormat, C.copyName = J.formatSrgb, "srgb"
    elseif linearDiff ~= nil then
        C.copyFormat, C.copyName = J.formatLinear, "linear"
    end
    series.copyName = "srgb+linear"
    C.available = direct.read and direct.non_black > 0
    out.result = C.available and "ok" or (direct.read and "black" or "unread")
end

local function stepSeries(J, series, now)
    local C = J.calib
    if series.state == "create" then
        local info = {}
        series.info = info
        series.handle = createRetainer(J, info)
        if series.handle == nil then
            finishSeries(J, series, "create failed")
            return
        end
        setupRetainer(J, series.handle, info)
        info.meta_keys = nil
        local kind = series.kind == "control" and "texture" or "material"
        info.brush = setRetainerBrush(J, series.handle, kind, series.object, series.w, series.h)
        series.state, series.wait, series.tries = "rt", 2, 0
        return
    end
    if series.state == "rt" then
        if series.wait > 0 then
            series.wait = series.wait - 1
            return
        end
        local rt = retainerTarget(series.handle)
        if rt == nil then
            series.tries = series.tries + 1
            if series.tries >= K.RT_WAIT_TICKS then
                finishSeries(J, series, "rt=nil")
                if series.kind == "control" then
                    C.available = false
                    calibStop(J, "control: no retainer render target")
                end
            end
            return
        end
        series.rt, series.rtInfo = rt, targetInfo(rt)
        local n, bytes = planFrames(J, series)
        if n < 1 then
            finishSeries(J, series, "pool budget")
            return
        end
        local format, formatName
        if series.kind == "control" then
            format, formatName = nil, "srgb+linear"
        elseif C.copyFormat ~= nil then
            format, formatName = C.copyFormat, C.copyName
        else
            format, formatName = copyFormatFor(J, series.rtInfo)
        end
        series.copyName = formatName
        series.pool, series.frames = {}, {}
        for index = 1, n do
            local poolFormat = format
            if series.kind == "control" then
                poolFormat = index == 1 and J.formatSrgb or J.formatLinear
            end
            local target = createTarget(series.w, series.h, poolFormat)
            if target == nil then
                break
            end
            series.pool[index] = target
        end
        series.poolBytes = #series.pool * bytes
        C.poolBytes = C.poolBytes + series.poolBytes
        if #series.pool == 0 then
            finishSeries(J, series, "no pool target")
            return
        end
        series.state, series.start, series.ticks, series.moment = "capture", now, 0, 1
    end
    if series.state ~= "capture" then
        return
    end
    if series.kind == "control" then
        controlCapture(J, series, now)
        finishSeries(J, series, "ok")
        return
    end
    if series.kind == "open" then
        if #series.frames < #series.pool and (now - J.openedMs <= K.CALIB_OPEN_MS or #series.frames == 0) then
            captureFrame(J, series, now)
        end
        if #series.frames >= #series.pool or now - J.openedMs > K.CALIB_OPEN_MS then
            finishSeries(J, series, "ok")
        end
        series.ticks = series.ticks + 1
        return
    end
    local moment = K.CALIB_MOMENTS[series.moment]
    if moment ~= nil and #series.frames < #series.pool
        and ((moment.tick ~= nil and series.ticks >= moment.tick) or (moment.ms ~= nil and now - series.start >= moment.ms)) then
        captureFrame(J, series, now)
        series.moment = series.moment + 1
    end
    series.ticks = series.ticks + 1
    if K.CALIB_MOMENTS[series.moment] == nil or #series.frames >= #series.pool then
        finishSeries(J, series, "ok")
    end
end

local function stepCalib(J, now)
    local C = J.calib
    if not C.enabled and #C.active == 0 then
        return
    end
    local regular = 0
    for _, series in ipairs(C.active) do
        if series.kind == "regular" and series.state ~= "export" and series.state ~= "done" then
            regular = regular + 1
        end
    end
    while C.enabled and #C.queue > 0 and regular < K.CALIB_PARALLEL and now - J.openedMs >= K.FULL_DELAY_MS do
        local series = table.remove(C.queue, 1)
        C.active[#C.active + 1] = series
        C.series[#C.series + 1] = series
        regular = regular + 1
    end
    local keep = {}
    for _, series in ipairs(C.active) do
        if series.state ~= "export" and series.state ~= "done" then
            local ok, err = pcall(stepSeries, J, series, now)
            if not ok then
                noteError("calib", err)
                finishSeries(J, series, "error: " .. clip(err))
            end
        end
        if series.state ~= "done" and series.state ~= "export" then
            keep[#keep + 1] = series
        end
    end
    C.active = keep
end

-- Exports -----------------------------------------------------------------------

local function dropCalib(J)
    calibStop(J, "limit")
    for _, entry in ipairs(J.calibQueue) do
        entry.series.frames[entry.index].skipped = "limit"
    end
    local seriesDone = {}
    for _, entry in ipairs(J.calibQueue) do
        seriesDone[entry.series] = true
    end
    J.calibQueue = {}
    for series in pairs(seriesDone) do
        series.pending = 0
        for _, rt in ipairs(series.pool or {}) do
            releaseTarget(rt)
        end
        writeJson(series.dir .. "frames.json", seriesView(J, series))
        series.state = "done"
        J.calib.poolBytes = J.calib.poolBytes - (series.poolBytes or 0)
        series.poolBytes = 0
    end
    markDirty(J, "state")
end

local function limitLine(J, part)
    warn("[AbsruExport] limit part=" .. part .. " files=" .. J.files .. " mb=" .. mb(J.bytes)
        .. " max_files=" .. cfg.MaxFiles .. " max_mb=" .. cfg.MaxMB)
end

-- bytes: uncompressed RGBA (an upper bound; the PNG on disk is smaller).
reserve = function(J, bytes, calib)
    if J.limited or (calib and J.calibLimited) then
        return false
    end
    local share = calib and K.CALIB_SHARE or 1
    if J.files + 1 <= cfg.MaxFiles * share and (J.bytes + bytes) / 1048576 <= cfg.MaxMB * share then
        return true
    end
    J.calibLimited = true
    if calib then
        limitLine(J, "calib")
    else
        J.limited = true
        limitLine(J, "all")
        for _, entry in ipairs(J.texQueue) do
            entry.rec.status = "skipped: limit"
        end
        J.texQueue = {}
        markDirty(J, "textures")
        markDirty(J, "sprites")
    end
    dropCalib(J)
    return false
end

-- Exports rt; the first one checks that ExportRenderTarget created the
-- sub-folder and switches to flat names ("textures+x.png") if it did not.
exportCounted = function(J, rt, fileName, bytes)
    local result = exportTarget(rt, fileName)
    if J.folderChecked == nil and result.call == "ok" and result.exists ~= nil then
        J.folderChecked = true
        if result.exists == false and not S.flat then
            S.flat = true
            J.result.flat = true
            result = exportTarget(rt, fileName)
        end
    end
    if result.call == "ok" then
        J.files = J.files + 1
        J.bytes = J.bytes + bytes
    end
    return result
end

local function exportTextureItem(J, entry)
    local rec = entry.rec
    local texture = entry.object
    local w, h = textureSize(texture)
    rec.w, rec.h = w, h
    if w == nil then
        rec.status, rec.error = "fail", "no size"
        return
    end
    if not reserve(J, w * h * 4) then
        return
    end
    local okStream, streamed = callMethod(texture, "IsFullyStreamedIn")
    rec.streamed = okStream and streamed == true or (okStream and false or "unknown")
    local rt, how = createTarget(w, h, entry.format)
    if rt == nil then
        rec.status, rec.error = "fail", "create: " .. tostring(how)
        return
    end
    clearTarget(rt)
    local ok, err = canvasCopy(texture, rt, w, h)
    if not ok then
        releaseTarget(rt)
        rec.status, rec.error = "fail", err
        return
    end
    local result = exportCounted(J, rt, entry.file, w * h * 4)
    releaseTarget(rt)
    if result.call ~= "ok" then
        rec.status, rec.error = "fail", result.call
    elseif rec.status ~= "fail" then
        rec.status = "ok"
    end
    rec.exists = result.exists
    if entry.kind == "texture" then
        markDirty(J, "textures")
    else
        markDirty(J, "sprites")
    end
end

local function exportCalibItem(J, entry)
    local series = entry.series
    if series.state == "done" then
        return
    end
    local frame = series.frames[entry.index]
    if reserve(J, series.w * series.h * 4, true) then
        local result = exportCounted(J, series.pool[entry.index], frame.file, series.w * series.h * 4)
        frame.export = result.call
        frame.exists = result.exists
        if result.call == "ok" then
            J.calib.frames = J.calib.frames + 1
        end
    else
        frame.skipped = "limit"
    end
    if series.state == "done" then
        return
    end
    series.pending = J.calibLimited and 0 or series.pending - 1
    if series.pending <= 0 then
        for _, rt in ipairs(series.pool or {}) do
            releaseTarget(rt)
        end
        J.calib.poolBytes = J.calib.poolBytes - (series.poolBytes or 0)
        series.poolBytes = 0
        writeJson(series.dir .. "frames.json", seriesView(J, series))
        series.state = "done"
        markDirty(J, "state")
    end
end

-- One export per tick: reference frames first (they hold pool targets).
local function stepExport(J, now)
    if J.limited then
        return
    end
    local entry = table.remove(J.calibQueue, 1)
    if entry ~= nil then
        exportCalibItem(J, entry)
        return
    end
    for index, item in ipairs(J.texQueue) do
        if item.due <= now then
            table.remove(J.texQueue, index)
            exportTextureItem(J, item)
            return
        end
    end
end

-- Selected path -------------------------------------------------------------------

local function signatureParts(J)
    local parts = {}
    pcall(function()
        for key, value in pairs(J.component) do
            local kind = type(value)
            if type(key) == "string" and (kind == "number" or kind == "string" or kind == "boolean") then
                local lower = key:lower()
                for _, word in ipairs(K.SIGNATURE_WORDS) do
                    if lower:find(word, 1, true) then
                        parts[key] = tostring(value)
                        break
                    end
                end
            end
        end
    end)
    for id, rec in pairs(J.iconWidgets) do
        local brush = get(rec.obj, "Brush")
        parts["icon" .. id] = tostring(objectPath(get(brush, "ResourceObject"))) .. "/" .. tostring(get(rec.obj, "Visibility"))
    end
    for _, rec in ipairs(J.textWidgets) do
        local ok, text = callMethod(rec.obj, "GetText")
        parts["text" .. rec.id] = ok and clip(tostring(text)) or "?"
    end
    return parts
end

local function componentFields(J)
    local fields = {}
    pcall(function()
        for key, value in pairs(J.component) do
            local kind = type(value)
            if type(key) == "string" and (kind == "number" or kind == "string" or kind == "boolean") and #fields < KEYS_MAX then
                fields[#fields + 1] = key .. "=" .. clip(tostring(value))
            end
        end
    end)
    table.sort(fields)
    return jsonArray(fields)
end

local function onPathChange(J, now, signature)
    local index = J.pathKeys[signature]
    if index == nil then
        J.pathCount = J.pathCount + 1
        index = J.pathCount
        J.pathKeys[signature] = index
    end
    J.pathIndex, J.pathSig = index, signature
    J.lastActivity = now
    J.doneLogged = false
    openWindow(J, now, K.PATH_WINDOW_MS, "path")
    if J.snap ~= nil then
        J.snap.interrupted = true
    end
    J.pendingWalks[#J.pendingWalks + 1] = { reason = "path", at = now, snapshot = true, snapshotAt = now + K.PATH_SNAPSHOT_MS }
    J.result.paths = J.result.paths or jsonArray()
    J.result.paths[#J.result.paths + 1] = { t = tMs(J, now), open = J.opens, path_index = index, key = signature }
    markDirty(J, "state")
end

local function stepPoll(J, now)
    if now - (J.lastPoll or 0) < K.POLL_MS then
        return
    end
    J.lastPoll = now
    local parts = signatureParts(J)
    if J.result.component_fields == nil then
        J.result.component_fields = componentFields(J)
    end
    -- Keys changing on their own in the first 15 s (timers, counters) are noise;
    -- keys appearing later (widgets of a new path) are ignored.
    local early = now - J.openedMs < K.SIGNATURE_NOISE_MS
    for key, value in pairs(parts) do
        if early then
            if J.sigLast[key] ~= nil and J.sigLast[key] ~= value then
                J.sigNoise[key] = true
            end
            J.sigKeys[key] = true
        end
        J.sigLast[key] = value
    end
    local list = {}
    for key, value in pairs(parts) do
        if J.sigKeys[key] and not J.sigNoise[key] then
            list[#list + 1] = key .. "=" .. value
        end
    end
    table.sort(list)
    local signature = table.concat(list, ";")
    if J.pathSig == nil or early then
        if J.pathSig ~= signature then
            J.pathSig = signature
            J.pathIndex = J.pathIndex or 0
        end
        return
    end
    if signature ~= J.pathSig then
        onPathChange(J, now, signature)
    end
end

-- Saving --------------------------------------------------------------------------

local function setView(set)
    local list = {}
    for key in pairs(set) do
        list[#list + 1] = key
    end
    table.sort(list)
    return jsonArray(list)
end

local function materialsView(J)
    local bases, names = {}, {}
    for path, base in pairs(J.bases) do
        bases[path] = { instances = setView(base.instances), mids = base.mids, widgets = base.widgets }
    end
    for path, set in pairs(J.baseNames) do
        names[path] = { scalar = setView(set.scalar), vector = setView(set.vector), texture = setView(set.texture) }
    end
    return { version = S.version, materials = J.materials, bases = bases, base_materials = J.baseMaterials, names = names }
end

local function stateView(J, status)
    local R = J.result
    R.status = status or R.status
    R.updated = stamp("%Y-%m-%d %H:%M:%S")
    R.errors = S.errors
    R.files, R.mb, R.limited, R.opens = J.files, mb(J.bytes), J.limited, J.opens
    R.widgets, R.textures, R.atlases, R.sprites = #J.widgets, #J.textureOrder, #J.atlasOrder, #J.sprites
    local materials = 0
    for _ in pairs(J.materials) do
        materials = materials + 1
    end
    R.materials, R.events, R.events_dropped = materials, #J.events, J.eventsDropped
    R.queue = { textures = #J.texQueue, calib = #J.calibQueue, effective = #J.effectiveQueue }
    local C = J.calib
    local series = jsonArray()
    for _, entry in ipairs(C.series) do
        series[#series + 1] = { kind = entry.kind, dir = entry.dir, state = entry.state, status = entry.status,
            frames = entry.frames and #entry.frames or 0 }
    end
    R.calib = {
        enabled = C.enabled, stopped = C.stopped, available = C.available, alpha = C.alpha, copy_format = C.copyName,
        frames = C.frames, queued = #C.queue, pool_mb = mb(C.poolBytes), series = series,
    }
    return R
end

local function saveOne(J, name)
    J.dirty[name] = nil
    if name == "state" then
        return writeJson("export_state.json", stateView(J))
    elseif name == "textures" then
        return writeJson("textures.json", {
            version = S.version, textures = jsonArray(J.textureOrder), unknown_resources = jsonArray(J.unknown),
        })
    elseif name == "sprites" then
        return writeJson("sprites.json", {
            version = S.version, atlases = jsonArray(J.atlasOrder), sprites = jsonArray(J.sprites),
            sprite_assets = J.spriteAssets,
        })
    elseif name == "materials" then
        return writeJson("materials.json", materialsView(J))
    elseif name == "timeline" then
        local rates = {}
        for key, value in pairs(J.rates) do
            rates[key] = value
        end
        local seconds = (J.rates.window_ms or 0) / 1000
        if seconds > 0 then
            rates.samples_per_s = J.rates.samples / seconds
            rates.sweeps_per_s = J.rates.sweeps / seconds
        end
        rates.tracks, rates.active = #J.tracks, #J.activeList
        return writeJson("timeline.json", {
            version = S.version, windows = jsonArray(J.windows), rates = rates, animations = jsonArray(J.animations),
            events = jsonArray(J.events), dropped = J.eventsDropped, budget_ms = J.timelineBudget,
        })
    end
end

local function stepSave(J, now)
    if now - J.lastSave < K.SAVE_MS then
        return
    end
    for _, name in ipairs(K.SAVE_ORDER) do
        if J.dirty[name] then
            saveOne(J, name)
            return
        end
    end
    J.lastSave = now
end

local function saveAll(J)
    J.dirty.state = true
    for _, name in ipairs(K.SAVE_ORDER) do
        if J.dirty[name] then
            saveOne(J, name)
        end
    end
    J.lastSave = nowMs()
end

local function doneLine(J, reason)
    local textures = 0
    for _, rec in ipairs(J.textureOrder) do
        if rec.status == "ok" then
            textures = textures + 1
        end
    end
    local materials = 0
    for _ in pairs(J.materials) do
        materials = materials + 1
    end
    return "[AbsruExport] done files=" .. J.files .. " mb=" .. mb(J.bytes) .. " textures=" .. textures
        .. " sprites=" .. #J.sprites .. " materials=" .. materials .. " calib=" .. J.calib.frames
        .. " timeline=" .. #J.events .. " snapshots=" .. #J.snapshots .. " paths=" .. J.pathCount
        .. " reason=" .. tostring(reason) .. " limit=" .. (J.limited and "yes" or "no")
        .. " json=" .. S.dir .. S.prefix .. "export_state.json"
end

local function finishFull(J, reason)
    stateView(J, reason)
    saveAll(J)
    warn(doneLine(J, reason))
    J.doneLogged = true
end

local function isIdle(J)
    return J.walk == nil and #J.pendingWalks == 0 and J.snap == nil and J.snapDue == nil
        and #J.calibQueue == 0 and #J.calib.active == 0 and (#J.calib.queue == 0 or not J.calib.enabled)
        and #J.effectiveQueue == 0 and (#J.texQueue == 0 or J.limited)
end

local function initFull(J)
    J.ready = true
    local R = J.result
    for _, name in ipairs({ "api", "context" }) do
        local ok, err = pcall(STAGE_BY_NAME[name][2], J, R)
        R.stages[name] = ok and "ok" or ("error: " .. clip(err))
        if not ok then
            noteError(name, err)
        end
    end
    J.slate = importSafe("SlateBlueprintLibrary")
    if J.lib == nil or J.ctx == nil then
        R.status = J.lib == nil and "KismetRenderingLibrary unavailable" or "no world context"
        return false
    end
    return true
end

local stepFull

local function closeFull(J, now)
    J.closed = true
    J.closedAt = now
    J.result.closes = (J.result.closes or 0) + 1
    -- The world context was the panel's userWidget: whatever is still queued
    -- cannot be drawn any more. The checklist says to wait for the done line.
    local C = J.calib
    for _, series in ipairs(C.series) do
        if series.state ~= "done" then
            removeRetainer(series.handle)
            series.state, series.status = "done", "cancelled: panel closed"
            for _, rt in ipairs(series.pool or {}) do
                releaseTarget(rt)
            end
            C.poolBytes = C.poolBytes - (series.poolBytes or 0)
            series.poolBytes = 0
            if series.frames ~= nil then
                writeJson(series.dir .. "frames.json", seriesView(J, series))
            end
        end
    end
    C.active, C.queue, J.calibQueue = {}, {}, {}
    for _, entry in ipairs(J.texQueue) do
        entry.rec.status = "skipped: panel closed"
    end
    J.texQueue = {}
    J.walk, J.pendingWalks, J.snap, J.snapDue = nil, {}, nil, nil
    J.windowEnd = 0
    markDirty(J, "timeline")
    markDirty(J, "textures")
    markDirty(J, "sprites")
end

stepFull = function()
    local J = S.full
    if J == nil then
        return
    end
    J.timerPending = false
    if S.disabled then
        return
    end
    S.job = J
    local now = nowMs()
    if not J.ready and not initFull(J) then
        finishFull(J, J.result.status)
        J.failed = true
        return
    end
    if get(J.component, "isDestroyed") == true then
        closeFull(J, now)
        finishFull(J, "panel closed")
        return
    end
    stepCalib(J, now)
    stepTimeline(J, now)
    stepWalks(J, now)
    stepSnapshot(J, now)
    stepPoll(J, now)
    stepExport(J, now)
    stepEffective(J, nowMs() + J.budget)
    stepSave(J, now)
    if not J.doneLogged and isIdle(J) and now - (J.lastActivity or now) >= K.IDLE_DONE_MS then
        finishFull(J, "idle")
    end
    J.timerPending = schedule(STEP_SECONDS, stepFull)
end

-- Every root open of the panel (a reopening keeps what was collected).
local function openFull(component)
    local J = S.full
    if J == nil then
        J = newFullJob()
        J.budget = cfg.FrameBudgetMs
        J.timelineBudget = cfg.TimelineBudgetMs
        J.snapshotBudget = cfg.SnapshotBudgetMs
        S.full = J
    elseif not J.closed or J.failed then
        return
    end
    local now = nowMs()
    J.component, J.userWidget = component, get(component, "userWidget")
    J.openedMs, J.closed, J.opens = now, false, J.opens + 1
    J.lastActivity, J.doneLogged, J.initialWalk = now, false, true
    J.pathSig, J.pathIndex, J.sigNoise, J.sigLast, J.sigKeys, J.lastPoll = nil, nil, {}, {}, {}, now
    J.iconWidgets, J.textWidgets = {}, {}
    -- The world context (userWidget) belongs to this opening.
    J.ready, J.lib, J.ctx = false, nil, nil
    J.calib.enabled = cfg.Calib and not J.limited and J.calib.available ~= false
    J.result.panel = componentUid(component)
    J.result.component = objectName(J.userWidget)
    J.pendingWalks = {
        { reason = "open", at = now },
        { reason = "full", at = now + K.FULL_DELAY_MS, snapshot = true, snapshotAt = now + K.FULL_DELAY_MS },
    }
    openWindow(J, now, K.OPEN_WINDOW_MS, "open")
    warn("[AbsruExport] full open=" .. J.opens .. " panel=" .. tostring(J.result.panel)
        .. " calib=" .. tostring(J.calib.enabled) .. " budget_ms=" .. J.budget)
    if not J.timerPending then
        J.timerPending = schedule(STEP_SECONDS, stepFull)
    end
end

-- Child components (WBP_ComBackTitle...) open first and share the panel uid
-- (probe 2026-09-26_1616): the panel itself is the one whose userWidget is named uid.
local function isPanelRoot(component, uid)
    return objectName(get(component, "userWidget") or get(component, "widget")) == uid
end

function E.OnPanelOpen(component)
    if S.disabled or component == nil then
        return
    end
    local uid = componentUid(component)
    if not cfg.PanelSet[uid] then
        return
    end
    if cfg.Mode == "full" then
        if isPanelRoot(component, uid) then
            openFull(component)
        end
        return
    end
    local P = S.probe
    if P ~= nil then
        if P.index == 1 and P.result.stage == nil and not P.rootFound and isPanelRoot(component, uid) then
            P.component, P.rootFound = component, true
            P.result.component = objectName(get(component, "userWidget"))
        end
        return
    end
    local root = isPanelRoot(component, uid)
    local retainer = cfg.Mode == "retainer"
    S.probe = {
        component = component, uid = uid, index = 1, targets = {}, openedMs = nowMs(), rootFound = root,
        stages = retainer and RETAINER_STAGES or STAGES, wantSmall = retainer,
        jsonName = retainer and "probe_retainer.json" or "probe.json", line = retainer and retainerLine or probeLine,
        result = {
            version = S.version, started = stamp("%Y-%m-%d %H:%M:%S"), panel = uid, mode = cfg.Mode,
            root = S.root, dir = S.dir, prefix = S.prefix, status = "running", stages = {},
            component = objectName(get(component, "userWidget") or get(component, "widget")),
        },
    }
    schedule(PROBE_DELAY, stepProbe, probeTimerFailed)
end

-- diag: the started AbsruDiagnostics module (EncodeJson, NewPanelWalk).
function E.Start(loader, runtimeFixes, version, diag)
    if S.started then
        return not S.disabled
    end
    S.started = true
    S.version = tostring(version)
    if type(diag) ~= "table" or type(diag.EncodeJson) ~= "function" or type(diag.NewPanelWalk) ~= "function" then
        return disable("AbsruDiagnostics is not running")
    end
    S.diag, S.encode = diag, diag.EncodeJson
    local flags = type(loader) == "table" and type(loader.DevFlags) == "table" and loader.DevFlags.AssetExport
    if type(flags) ~= "table" then
        return disable("DevFlags.AssetExport is not a table")
    end
    if flags.Probe == true then
        cfg.Mode = "probe"
    elseif flags.Probe == "retainer" then
        cfg.Mode = "retainer"
    else
        cfg.Mode = "full"
    end
    cfg.Calib = flags.Calib ~= false
    cfg.FrameBudgetMs = tonumber(flags.FrameBudgetMs) or 4
    cfg.TimelineBudgetMs = tonumber(flags.TimelineBudgetMs) or 4
    cfg.SnapshotBudgetMs = tonumber(flags.SnapshotBudgetMs) or 12
    cfg.MaxFiles = tonumber(flags.MaxFiles) or K.FILES_MAX
    cfg.MaxMB = tonumber(flags.MaxMB) or K.MB_MAX
    if type(flags.Panels) == "table" then
        for _, name in ipairs(flags.Panels) do
            cfg.Panels[#cfg.Panels + 1] = tostring(name)
            cfg.PanelSet[tostring(name)] = true
        end
    end

    local library = importSafe("LuaFunctionLibrary")
    if library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return disable("LuaFunctionLibrary.SaveStringContentToFile unavailable")
    end
    S.save = library.SaveStringContentToFile
    S.paths = importSafe("BlueprintPathsLibrary")
    local root = type(loader) == "table" and loader.Root or nil
    if type(root) ~= "string" or root == "" then
        return disable("Loader.Root unavailable")
    end
    -- Root is "<Saved>//Mods/": collapse doubled slashes for the export API.
    S.root = root
    local base = (root:gsub("(.)//+", "%1/"))
    local token = "export " .. tostring(stamp("%Y%m%d-%H%M%S") or nowMs()) .. "\n"
    local function tryDirectory(directory, prefix)
        local okSave, result = pcall(S.save, token, directory .. prefix .. "export-state.txt")
        if not okSave or result == false then
            return false
        end
        local load = library.LoadFile
        if type(load) ~= "function" then
            return true
        end
        local okLoad, back = pcall(load, directory .. prefix .. "export-state.txt")
        return okLoad and type(back) == "string" and back:find(token, 1, true) ~= nil
    end
    if tryDirectory(base .. "logs/godway/", "") then
        S.dir, S.prefix = base .. "logs/godway/", ""
    elseif tryDirectory(base .. "logs/", "godway-") then
        S.dir, S.prefix = base .. "logs/", "godway-"
    else
        return disable("cannot write to " .. base .. "logs/godway/")
    end
    warn("[AbsruExport] ready dir=" .. S.dir .. S.prefix .. " mode=" .. cfg.Mode
        .. " panels=" .. table.concat(cfg.Panels, ","))
    return true
end

E.State = S
E.Config = cfg

return E

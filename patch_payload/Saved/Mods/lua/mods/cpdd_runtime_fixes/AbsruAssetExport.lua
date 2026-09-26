-- AbsoluteRU asset export from game memory (TASK-018, docs/tasks/TASK-018-godway-export.md).
--
-- Dev-only. Init.lua loads this module only when Saved/Mods/lua/absoluteru_dev.lua
-- returns Enabled = true and a non-empty AssetExport table, after
-- AbsruDiagnostics has started (its JSON encoder and panel walk are reused).
-- Step 0 (AssetExport.Probe = true): once per session, 3 s after one of
-- AssetExport.Panels opens, one probe stage runs per timer tick and checks
-- KismetRenderingLibrary on one Texture2D, one KGSprite and one material.
-- Results go to Saved/Mods/logs/godway/probe.json (rewritten before and after
-- every stage, so a crash shows the stage it happened in), PNG files next to
-- it, and one "[AbsruExport] probe" line to C7.log. Every engine call is
-- protected; nothing is written outside Saved/Mods/logs/.

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

local API_NAMES = {
    "CreateRenderTarget2D", "DrawMaterialToRenderTarget", "BeginDrawCanvasToRenderTarget",
    "EndDrawCanvasToRenderTarget", "ExportRenderTarget", "ExportTexture2D", "ReadRenderTargetPixel",
    "ReadRenderTargetRawPixel", "ClearRenderTarget2D", "ReleaseRenderTarget2D",
}
-- The C7.log line lists only the calls the export depends on.
local API_LOGGED = {
    "CreateRenderTarget2D", "DrawMaterialToRenderTarget", "BeginDrawCanvasToRenderTarget",
    "EndDrawCanvasToRenderTarget", "ExportRenderTarget", "ExportTexture2D", "ReadRenderTargetPixel",
}
local SPRITE_FIELDS = {
    "BakedSourceTexture", "SourceTexture", "AtlasTexture", "Atlas", "SpriteAtlas", "Texture",
    "BakedSourceUV", "BakedSourceDimension", "SourceUV", "SourceDimension", "SourceTextureDimension",
    "SourceSize", "Size", "ImageSize", "TextureSize", "UV", "StartUV", "SizeUV", "bRotated", "Rotated",
    "bTrimmed", "TrimRect", "Pivot", "CustomPivotPoint", "PixelsPerUnrealUnit", "Margin",
    "SpriteName", "AtlasData", "SlateAtlasData", "SpriteInfo", "SpriteData",
}
local SPRITE_METHODS = {
    "GetSlateAtlasData", "GetBakedTexture", "GetSourceTexture", "GetAtlasTexture", "GetTexture",
    "GetSourceSize", "GetImageSize", "GetSourceUV", "GetSize",
}
local MATERIAL_ARRAYS = { "ScalarParameterValues", "VectorParameterValues", "TextureParameterValues" }

local cfg = { Panels = {}, PanelSet = {}, Probe = false }
local S = {
    started = false,
    disabled = false,
    errors = {},
    errorTotal = 0,
    probe = nil,
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

-- Files -------------------------------------------------------------------------

local function writeText(name, content)
    local ok, result = pcall(S.save, content, S.dir .. S.prefix .. name)
    if not ok or result == false then
        noteError("io", ok and "write returned false" or result)
        return false
    end
    return true
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

-- Probe --------------------------------------------------------------------------

local function writeProbe()
    local P = S.probe
    local ok, content = pcall(S.encode, P.result)
    if ok then
        writeText("probe.json", content)
    else
        noteError("encode", content)
    end
end

local function createTarget(w, h)
    local P = S.probe
    local lib = P.lib
    local ok, rt = pcall(lib.CreateRenderTarget2D, P.ctx, w, h, P.format, linearColor(0, 0, 0, 0), false)
    local first = ok and rt ~= nil and "full" or clip(rt)
    if not ok or rt == nil then
        ok, rt = pcall(lib.CreateRenderTarget2D, P.ctx, w, h, P.format)
    end
    if ok and rt ~= nil then
        P.targets[#P.targets + 1] = rt
        return rt, first == "full" and "full" or "short"
    end
    return nil, "full: " .. tostring(first) .. "; short: " .. clip(rt)
end

local function exportTarget(rt, fileName)
    local P = S.probe
    local name = S.prefix .. fileName
    local ok, result = pcall(P.lib.ExportRenderTarget, P.ctx, rt, S.dir, name)
    return {
        call = ok and "ok" or clip(result), returned = ok and describe(result) or nil,
        file = S.dir .. name, exists = fileExists(S.dir .. name),
    }
end

local function readPixels(rt, w, h, grid)
    local P = S.probe
    local samples, distinct, seen, nonBlack, readOk = {}, 0, {}, 0, false
    for gy = 1, grid do
        for gx = 1, grid do
            local x = math.floor(w * (gx - 0.5) / grid)
            local y = math.floor(h * (gy - 0.5) / grid)
            local ok, color = pcall(P.lib.ReadRenderTargetPixel, P.ctx, rt, x, y)
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

local function materialParams(material)
    local out = {}
    for _, field in ipairs(MATERIAL_ARRAYS) do
        local array = get(material, field)
        local list = {}
        for index = 0, count(array) - 1 do
            local entry = item(array, index)
            local info = get(entry, "ParameterInfo")
            local name = get(info, "Name") or get(entry, "ParameterName")
            list[#list + 1] = { name = name ~= nil and tostring(name) or "?", value = describe(get(entry, "ParameterValue")) }
        end
        out[field] = { type = type(array), count = count(array), values = list }
    end
    return out
end

local STAGES = {}

STAGES[#STAGES + 1] = { "api", function(P, R)
    local lib = importSafe("KismetRenderingLibrary")
    P.lib = lib
    R.api = { KismetRenderingLibrary = lib ~= nil }
    for _, name in ipairs(API_NAMES) do
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
    local okSize, viewport = pcall(function()
        return importSafe("WidgetLayoutLibrary").GetViewportSize(P.ctx)
    end)
    R.context.viewport = okSize and describe(viewport) or clip(viewport)
    return true
end }

-- Finds one Texture2D icon, one KGSprite and the Img_Bg01 material (fallbacks: any).
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
            if F.mid == nil and name == "Img_Bg01" then
                F.mid, F.midWidget = resource, widget
            elseif F.anyMid == nil then
                F.anyMid, F.anyMidWidget = resource, widget
            end
        end
        return F.icon ~= nil and F.sprite ~= nil and F.mid ~= nil
    end
    P.walkTicks = P.walkTicks + 1
    local done = P.walk(nowMs() + WALK_BUDGET_MS, visit)
    if not done and P.walkTicks < WALK_TICKS_MAX then
        return false
    end
    P.texture = F.icon or F.anyTexture
    P.sprite = F.sprite or F.anySprite
    P.mid, P.midWidget = F.mid or F.anyMid, F.midWidget or F.anyMidWidget
    R.find = {
        nodes = P.walkNodes, ticks = P.walkTicks, complete = done,
        texture = objectPath(P.texture), texture_fallback = F.icon == nil and P.texture ~= nil,
        sprite = objectPath(P.sprite), sprite_fallback = F.sprite == nil and P.sprite ~= nil,
        material = objectPath(P.mid), material_class = className(P.mid),
        material_widget = objectName(P.midWidget), material_fallback = F.mid == nil and P.mid ~= nil,
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
    local returns = { pcall(P.lib.BeginDrawCanvasToRenderTarget, P.ctx, rt) }
    out.begin = returns[1] and "ok" or clip(returns[2])
    out.begin_returns = { describe(returns[2]), describe(returns[3]), describe(returns[4]) }
    local canvas, context = returns[2], returns[4]
    if not returns[1] or canvas == nil then
        return
    end
    local okDraw, _, drawErr = callMethod(canvas, "K2_DrawTexture", P.texture, vector2(0, 0),
        vector2(P.texW, P.texH), vector2(0, 0), vector2(1, 1), linearColor(1, 1, 1, 1), blend, 0, vector2(0.5, 0.5))
    out.draw = okDraw and "ok" or drawErr
    local okEnd, endErr = pcall(P.lib.EndDrawCanvasToRenderTarget, P.ctx, context)
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
    for _, field in ipairs(SPRITE_FIELDS) do
        local value = get(sprite, field)
        if value ~= nil and type(value) ~= "function" then
            out.fields[field] = describe(value)
            out.found[#out.found + 1] = field
        end
    end
    for _, method in ipairs(SPRITE_METHODS) do
        local ok, result, err = callMethod(sprite, method)
        if ok then
            local view = { value = describe(result) }
            for _, key in ipairs({ "AtlasTexture", "StartUV", "SizeUV" }) do
                local field = get(result, key)
                if field ~= nil then
                    view[key] = describe(field)
                end
            end
            out.methods[method] = view
            out.found[#out.found + 1] = method .. "()"
        elseif err ~= "missing" then
            out.methods[method] = { error = err }
        end
    end
    out.meta_keys = metaKeys(sprite)
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

local function probeLine(R)
    local api = {}
    for _, name in ipairs(API_LOGGED) do
        api[#api + 1] = name .. ":" .. ((R.api and R.api[name] == "ok") and "ok" or "missing")
    end
    local file = "none"
    local texture = R.texture or {}
    for _, entry in ipairs({ texture.direct, texture.canvas_opaque and texture.canvas_opaque.export,
        R.mid and R.mid.draw and R.mid.draw.export }) do
        if type(entry) == "table" and entry.exists == true then
            file = entry.file
            break
        elseif file == "none" and type(entry) == "table" and entry.call == "ok" then
            file = tostring(entry.file) .. "(unverified)"
        end
    end
    local sprite = R.sprite and #R.sprite.found > 0 and table.concat(R.sprite.found, ",") or "none"
    local midDraw = R.mid and R.mid.draw and R.mid.draw.result or "fail"
    return "[AbsruExport] probe api=" .. table.concat(api, ",") .. " file=" .. file
        .. " sprite=" .. sprite .. " mid_draw=" .. midDraw
        .. " animated=" .. tostring(R.mid and R.mid.animated_samples or "?")
        .. " ctx=" .. tostring(R.context and R.context.used or "?")
        .. " json=" .. S.dir .. S.prefix .. "probe.json"
end

local function finishProbe(P, R, status)
    R.status = status
    R.finished = stamp("%Y-%m-%d %H:%M:%S")
    R.errors = S.errors
    local release = get(P.lib, "ReleaseRenderTarget2D")
    if type(release) == "function" then
        for _, rt in ipairs(P.targets) do
            pcall(release, rt)
        end
    end
    P.targets = {}
    P.done = true
    writeProbe()
    warn(probeLine(R))
end

local schedule

local function stepProbe()
    local P = S.probe
    if P == nil or P.done or S.disabled then
        return
    end
    local R = P.result
    if get(P.component, "isDestroyed") == true then
        finishProbe(P, R, "panel closed at stage " .. tostring(R.stage))
        return
    end
    local stage = STAGES[P.index]
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
    schedule(STEP_SECONDS)
end

schedule = function(delay)
    local manager = nil
    pcall(function() manager = Game and Game.NewUIManager end)
    local addTimer = get(manager, "AddTimerWithFunction")
    local ok, result = false, "AddTimerWithFunction unavailable"
    if type(addTimer) == "function" then
        ok, result = pcall(addTimer, manager, delay, 1, function()
            local stepOk, err = pcall(stepProbe)
            if not stepOk then
                noteError("tick", err)
            end
        end)
    end
    if not ok or result == false then
        noteError("timer", result)
        local P = S.probe
        if P ~= nil and not P.done then
            finishProbe(P, P.result, "timer failed")
        end
    end
end

function E.OnPanelOpen(component)
    if S.disabled or not cfg.Probe or S.probe ~= nil or component == nil then
        return
    end
    local uid = componentUid(component)
    if not cfg.PanelSet[uid] then
        return
    end
    S.probe = {
        component = component, uid = uid, index = 1, targets = {}, openedMs = nowMs(),
        result = {
            version = S.version, started = stamp("%Y-%m-%d %H:%M:%S"), panel = uid,
            root = S.root, dir = S.dir, prefix = S.prefix, status = "running", stages = {},
        },
    }
    schedule(PROBE_DELAY)
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
    cfg.Probe = flags.Probe == true
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
    warn("[AbsruExport] ready dir=" .. S.dir .. S.prefix .. " probe=" .. tostring(cfg.Probe)
        .. " panels=" .. table.concat(cfg.Panels, ","))
    return true
end

E.State = S
E.Config = cfg

return E

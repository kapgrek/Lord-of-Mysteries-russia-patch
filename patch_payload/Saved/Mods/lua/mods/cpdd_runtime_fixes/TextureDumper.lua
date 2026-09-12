-- ============================================================================
-- Lord of the Mysteries (C7 / UE5 / Slua) — Universal UI Texture Dumper
-- File: TextureDumper.lua
-- Purpose: Extract in-game UI textures (UTexture2D) directly from engine memory
--          to disk as clean PNG files without external process injection.
-- ============================================================================

local MODULE_TAG = "[TextureDumper]"
local Loader = rawget(_G, "LOMModLoader")

local function safe_import(name)
    local ok, lib = pcall(import, name)
    if ok and lib ~= nil then return lib end
    return nil
end

local FileLib = safe_import("LuaFunctionLibrary")
local PathsLib = safe_import("BlueprintPathsLibrary")
local RenderLib = safe_import("KismetRenderingLibrary")
local KismetSys = safe_import("KismetSystemLibrary")

-- Resolve output directory
local function resolveOutputDir()
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

    -- Check custom config file if present
    local configPath = savedDir .. "/Mods/cpdd_diagnostic_config.json"
    local customDir = nil
    pcall(function()
        local f = io.open(configPath, "r")
        if f then
            local text = f:read("*a")
            f:close()
            local dir = text:match('"texture_dump_dir"%s*:%s*"([^"]+)"')
            if dir and dir ~= "" then customDir = dir:gsub("\\", "/") end
        end
    end)
    if customDir then return customDir end

    return savedDir .. "/Mods/DumpedTextures"
end

local OUTPUT_DIR = resolveOutputDir()

local function log_msg(msg)
    local line = MODULE_TAG .. " " .. tostring(msg)
    local logger = rawget(_G, "Log") or rawget(_G, "LaunchLog") or rawget(_G, "LuaCLogger")
    if logger ~= nil then
        if type(logger.Info) == "function" then
            pcall(logger.Info, line)
        elseif type(logger.Log) == "function" then
            pcall(logger.Log, line)
        end
    end
    print(line)

    -- Also append to diagnostics log if available
    pcall(function()
        local diagLog = rawget(_G, "__LOM_DiagLog")
        if type(diagLog) == "function" then
            diagLog("TEXTURE", tostring(msg))
        end
    end)
end

-- Ensure output directory exists
pcall(function()
    if FileLib and type(FileLib.CreateDirectory) == "function" then
        FileLib.CreateDirectory(OUTPUT_DIR)
    elseif FileLib and type(FileLib.MakeDirectory) == "function" then
        FileLib.MakeDirectory(OUTPUT_DIR)
    end
    if os and type(os.execute) == "function" then
        os.execute('mkdir "' .. OUTPUT_DIR:gsub("/", "\\") .. '" 2>nul')
    end
end)

local Dumper = {
    OutputDir = OUTPUT_DIR,
    DumpedTextures = {},
    DumpedCount = 0,
    Index = {},
    IsRunning = true
}
_G.__LOMTextureDumper = Dumper

local function getTextureDimensions(tex)
    local w, h = 0, 0
    pcall(function()
        if type(tex.GetSizeX) == "function" then w = tonumber(tex:GetSizeX()) or 0 end
        if type(tex.GetSizeY) == "function" then h = tonumber(tex:GetSizeY()) or 0 end
        if (w == 0 or h == 0) and type(tex.GetSurfaceWidth) == "function" then
            w = tonumber(tex:GetSurfaceWidth()) or 0
            h = tonumber(tex:GetSurfaceHeight()) or 0
        end
    end)
    return w, h
end

local function dumpTexture(tex, sourceWidgetName, panelName)
    if tex == nil then return false end

    local texName = "Tex_Unknown"
    local texPath = ""
    pcall(function()
        if type(tex.GetName) == "function" then texName = tostring(tex:GetName()) end
        if type(tex.GetPathName) == "function" then texPath = tostring(tex:GetPathName()) end
    end)

    -- Filter out engine font/render target/white box noise
    if texName:find("^Font") or texName:find("WhiteSquareTexture") or texName:find("^Default_") then
        return false
    end

    local key = texPath ~= "" and texPath or texName
    if Dumper.DumpedTextures[key] then
        return false -- already dumped
    end
    Dumper.DumpedTextures[key] = true
    Dumper.DumpedCount = Dumper.DumpedCount + 1

    local w, h = getTextureDimensions(tex)
    local cleanPanel = (panelName or "UI"):gsub("[^%w_%-]", "_")
    local cleanTex = texName:gsub("[^%w_%-]", "_")
    local safeFileName = string.format("%04d_%s_%s.png", Dumper.DumpedCount, cleanPanel, cleanTex)

    local exported = false
    if RenderLib and type(RenderLib.ExportTexture2D) == "function" then
        pcall(function()
            exported = RenderLib.ExportTexture2D(nil, tex, Dumper.OutputDir, safeFileName)
        end)
    end

    table.insert(Dumper.Index, {
        index = Dumper.DumpedCount,
        file_name = safeFileName,
        texture_name = texName,
        texture_path = texPath,
        width = w,
        height = h,
        source_widget = sourceWidgetName or "unknown",
        panel = panelName or "unknown",
        exported = exported
    })

    log_msg(string.format("Dumped [%04d] (%dx%d) %s -> %s (Exported=%s)",
        Dumper.DumpedCount, w, h, texName, safeFileName, tostring(exported)))

    return true
end

local function extractTexturesFromWidget(widget, panelName)
    if widget == nil then return end

    local wName = "Widget"
    pcall(function()
        if type(widget.GetName) == "function" then wName = tostring(widget:GetName()) end
    end)

    -- 1. Check UImage Brush
    pcall(function()
        local brush = widget.Brush or (type(widget.GetBrush) == "function" and widget:GetBrush())
        if brush and brush.ResourceObject then
            dumpTexture(brush.ResourceObject, wName, panelName)
        end
    end)

    -- 2. Check UButton WidgetStyle (Normal, Hovered, Pressed, Disabled)
    pcall(function()
        local style = widget.WidgetStyle
        if style then
            if style.Normal and style.Normal.ResourceObject then
                dumpTexture(style.Normal.ResourceObject, wName .. "_Normal", panelName)
            end
            if style.Hovered and style.Hovered.ResourceObject then
                dumpTexture(style.Hovered.ResourceObject, wName .. "_Hovered", panelName)
            end
            if style.Pressed and style.Pressed.ResourceObject then
                dumpTexture(style.Pressed.ResourceObject, wName .. "_Pressed", panelName)
            end
            if style.Disabled and style.Disabled.ResourceObject then
                dumpTexture(style.Disabled.ResourceObject, wName .. "_Disabled", panelName)
            end
        end
    end)

    -- 3. Check direct Texture / Image properties
    pcall(function()
        if widget.Texture then dumpTexture(widget.Texture, wName, panelName) end
        if widget.Image then dumpTexture(widget.Image, wName, panelName) end
        if widget.NormalImage then dumpTexture(widget.NormalImage, wName .. "_Normal", panelName) end
    end)
end

local function walkWidgetTree(owner, visited, panelName)
    if owner == nil or visited[owner] then return end
    visited[owner] = true

    if type(owner) == "table" then
        local rw = owner.userWidget or owner.widget or owner.panel or owner.RootWidget or owner.m_Widget
        if rw ~= nil then walkWidgetTree(rw, visited, panelName) end
        if type(owner.view) == "table" then
            for _, v in pairs(owner.view) do
                if v ~= nil and type(v) ~= "function" then walkWidgetTree(v, visited, panelName) end
            end
        end
        return
    end

    extractTexturesFromWidget(owner, panelName)

    -- Walk children
    local count = nil
    pcall(function()
        if type(owner.GetChildrenCount) == "function" then count = tonumber(owner:GetChildrenCount()) end
    end)
    if count ~= nil and count > 0 then
        for i = 0, count - 1 do
            pcall(function()
                local child = owner:GetChildAt(i)
                if child ~= nil then walkWidgetTree(child, visited, panelName) end
            end)
        end
    end

    -- Check UUserWidget.WidgetTree
    pcall(function()
        local tree = owner.WidgetTree
        if tree ~= nil then
            if tree.RootWidget ~= nil then
                walkWidgetTree(tree.RootWidget, visited, panelName)
            end
            if type(tree.GetAllWidgets) == "function" then
                local widgets = {}
                local ok, result = pcall(tree.GetAllWidgets, tree, widgets)
                local arr = (ok and type(result) == "table" and result) or widgets
                for _, w in pairs(arr) do
                    walkWidgetTree(w, visited, panelName)
                end
            end
        end
    end)

    -- Direct Content slot
    pcall(function()
        if type(owner.GetContent) == "function" then
            local cnt = owner:GetContent()
            if cnt ~= nil then walkWidgetTree(cnt, visited, panelName) end
        end
    end)
end

function Dumper:ScanPanel(component, reason)
    if component == nil then return end
    local uid = "UnknownPanel"
    pcall(function()
        uid = tostring(component.uid or component.UID or component.__cname or "Panel")
    end)

    local visited = setmetatable({}, { __mode = "k" })
    walkWidgetTree(component, visited, uid)

    pcall(function()
        if type(component.view) == "table" then
            for _, v in pairs(component.view) do
                walkWidgetTree(v, visited, uid)
            end
        end
        if type(component.view and component.view._widgetCache) == "table" then
            for _, v in pairs(component.view._widgetCache) do
                walkWidgetTree(v, visited, uid)
            end
        end
    end)

    local root = nil
    pcall(function() root = component.userWidget or component.widget or component.panel end)
    if root then walkWidgetTree(root, visited, uid) end

    self:SaveIndex()
end

function Dumper:SaveIndex()
    pcall(function()
        local indexPath = Dumper.OutputDir .. "/dump_index.json"
        local f = io.open(indexPath, "w")
        if f then
            f:write("[\n")
            for i, item in ipairs(self.Index) do
                local jsonItem = string.format(
                    '  {\n    "index": %d,\n    "file": "%s",\n    "texture": "%s",\n    "path": "%s",\n    "width": %d,\n    "height": %d,\n    "widget": "%s",\n    "panel": "%s",\n    "exported": %s\n  }%s\n',
                    item.index,
                    (item.file_name or ""):gsub('\\', '\\\\'),
                    (item.texture_name or ""):gsub('\\', '\\\\'),
                    (item.texture_path or ""):gsub('\\', '\\\\'),
                    item.width or 0,
                    item.height or 0,
                    (item.source_widget or ""):gsub('\\', '\\\\'),
                    (item.panel or ""):gsub('\\', '\\\\'),
                    tostring(item.exported),
                    (i < #self.Index and "," or "")
                )
                f:write(jsonItem)
            end
            f:write("]\n")
            f:close()
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Hooks into UI Lifecycle
-- ----------------------------------------------------------------------------
local function hookUIComponent(targetClass)
    if type(targetClass) ~= "table" then return end
    if rawget(targetClass, "__lomTextureDumperHooked") then return end

    for _, method in ipairs({ "Open", "Refresh", "InitUIView" }) do
        local orig = rawget(targetClass, method) or targetClass[method]
        if type(orig) == "function" then
            targetClass[method] = function(self, ...)
                local res = { orig(self, ...) }
                pcall(function() Dumper:ScanPanel(self, method) end)
                return unpack(res)
            end
        end
    end
    rawset(targetClass, "__lomTextureDumperHooked", true)
    log_msg("Hooked UIComponent lifecycle methods (Open/Refresh/InitUIView)")
end

-- Try hooking right away if class is already loaded
pcall(function()
    local UIComp = rawget(_G, "UIComponent") or package.loaded["Framework.KGFramework.KGUI.Core.UIComponent"]
    if UIComp then hookUIComponent(UIComp) end
end)

-- Register AfterLoad hook
if Loader and type(Loader.AfterLoad) == "function" then
    Loader.AfterLoad("Framework.KGFramework.KGUI.Core.UIComponent", function(mod)
        hookUIComponent(mod)
        return mod
    end, 200, "cpdd.texture_dumper.uicomp")
end

-- Periodic scanner for active UI panels
local function setupPeriodicScan()
    pcall(function()
        local GameObj = rawget(_G, "Game")
        if GameObj and GameObj.NewUIManager and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
            GameObj.NewUIManager:AddTimerWithFunction(2.0, -1, function()
                pcall(function()
                    if GameObj.NewUIManager.ActivePanels then
                        for _, p in pairs(GameObj.NewUIManager.ActivePanels) do
                            Dumper:ScanPanel(p, "PeriodicActive")
                        end
                    end
                end)
            end)
            log_msg("Periodic UI texture scan timer activated (every 2.0s)")
        end
    end)
end

if Loader and type(Loader.On) == "function" then
    Loader.On("after_main", function()
        setupPeriodicScan()
    end, 1000, "cpdd.texture_dumper.ticker")
end

log_msg("TextureDumper module initialized successfully. Output: " .. OUTPUT_DIR)
return Dumper

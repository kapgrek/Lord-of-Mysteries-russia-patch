local Loader = assert(LOMModLoader, "LOMModLoader is required")

local VERSION = "1.9.1"
local POSITION_FILE = "dps-meter-position-v2.txt"
local SECONDARY_POSITION_FILE = "dps-meter-position-v2-secondary.txt"
local SCALE_FILE = "dps-meter-scale-v1.txt"
local SECONDARY_SCALE_FILE = "dps-meter-scale-v1-secondary.txt"
local HEIGHT_FILE = "dps-meter-height-v1.txt"
local SECONDARY_HEIGHT_FILE = "dps-meter-height-v1-secondary.txt"
local LOCK_FILE = "dps-meter-lock-v1.txt"
local SECONDARY_LOCK_FILE = "dps-meter-lock-v1-secondary.txt"
local VISIBILITY_FILE = "dps-meter-visible-v1.txt"
local DRAG_THRESHOLD = 4
local DEFAULT_POSITION = { X = 58, Y = 296 }
local SECONDARY_Y_OFFSET = 220
local DEFAULT_WIDTH_BONUS = 420
local DEFAULT_METER_SCALE = 1
local MIN_METER_SCALE = 0.65
local MAX_METER_SCALE = 1.45
local DEFAULT_HEIGHT_BONUS = 0
local MIN_HEIGHT_BONUS = 0
local MAX_HEIGHT_BONUS = 520
local HEIGHT_ROW_SIZE = 26
local RESIZE_HANDLE_SIZE = 36
local FOOTER_BOTTOM_INSET = 3
local MIN_ROWS_BEFORE_RESIZE_FOOTER = 5
local ADD_TITLE_HIT_WIDTH = 42
local LOCK_TITLE_HIT_WIDTH = 78
local DETAIL_REQUEST_TIMEOUT = 3
local COLUMN_SEPARATOR = " | "
local DAMAGE_COLUMN_WIDTHS = { 48, 108, 78, 68 }
local HEALING_COLUMN_WIDTHS = { 70, 125, 85 }

local unpack = table.unpack or unpack
local savedPositions = {}
local loadedPositions = {}
local savedScales = {}
local loadedScales = {}
local savedHeightBonuses = {}
local loadedHeightBonuses = {}
local savedLocks = {}
local loadedLocks = {}
local savedVisibility = nil
local visibilityLoaded = false
local cachedCritTagData = nil
local critTagResolved = false
local playerNameRepair = nil
local playerNameRepairResolved = false
local leftJustification = nil
local rightJustification = nil
local justificationResolved = false

local function report(message)
    local logger = Log or LaunchLog
    if logger and logger.Info then
        logger.Info("[CPDDDpsMeter] " .. tostring(message))
    end
end

local function isActionMode(system)
    if system == nil then
        return false
    end
    local ok, method = pcall(function()
        return system.IsActionMode
    end)
    if not ok or type(method) ~= "function" then
        return false
    end
    local called, result = pcall(method, system)
    return called and result == true
end

local function isCursorVisible()
    local manager = Game and Game.CursorManager
    if manager == nil then
        return false
    end
    local ok, method = pcall(function()
        return manager.IsCursorShow
    end)
    if not ok or type(method) ~= "function" then
        return false
    end
    local called, result = pcall(method, manager)
    return called and result == true
end

local function isPointerInteractionAllowed(inputType)
    if inputType ~= "mouse" then
        return true
    end
    local system = Game and Game.OperationModeSystem
    if not isActionMode(system) then
        return true
    end
    local ok, shownForAlt = pcall(function()
        return system.bShownForAlt
    end)
    return ok and shownForAlt == true and isCursorVisible()
end

local function detailRequestClock()
    local gameTime = Game and tonumber(Game.GameTime)
    if gameTime then
        return gameTime
    end
    local timeUtils = Game and Game.TimeUtils
    if timeUtils and type(timeUtils.GetCurTime) == "function" then
        local ok, currentTime = pcall(timeUtils.GetCurTime)
        if ok and tonumber(currentTime) then
            return tonumber(currentTime)
        end
    end
    return 0
end

local function getSymbol(value, environment, name)
    if type(value) == "table" and rawget(value, name) ~= nil then
        return rawget(value, name)
    end
    if type(environment) == "table" and rawget(environment, name) ~= nil then
        return rawget(environment, name)
    end
    return nil
end

local function repairDpsPlayerName(value, data)
    value = tostring(value or "")
    if not playerNameRepairResolved then
        playerNameRepairResolved = true
        local ok, runtimeFixes = pcall(require, "mods.cpdd_runtime_fixes.Init")
        playerNameRepair = ok and type(runtimeFixes) == "table"
            and runtimeFixes.RepairLiveText or nil
    end
    if type(playerNameRepair) ~= "function" then
        return value
    end
    local ok, repaired = pcall(
        playerNameRepair,
        "HUDStats",
        tostring(data and data.id or "player"),
        "Text_PlayerName",
        value
    )
    return ok and type(repaired) == "string" and repaired or value
end

local function instanceIndex(component)
    return component and component.__cpddDpsInstanceId == 2 and 2 or 1
end

local function settingsPath(fileName)
    local root = tostring(Loader.Root or ""):gsub("\\", "/"):gsub("/+$", "")
    if root == "" then
        return nil
    end
    return root .. "/" .. fileName
end

local function positionPath(index)
    return settingsPath(index == 2 and SECONDARY_POSITION_FILE or POSITION_FILE)
end

local function scalePath(index)
    return settingsPath(index == 2 and SECONDARY_SCALE_FILE or SCALE_FILE)
end

local function heightPath(index)
    return settingsPath(index == 2 and SECONDARY_HEIGHT_FILE or HEIGHT_FILE)
end

local function lockPath(index)
    return settingsPath(index == 2 and SECONDARY_LOCK_FILE or LOCK_FILE)
end

local function visibilityPath()
    return settingsPath(VISIBILITY_FILE)
end

local function loadPosition(index)
    index = index == 2 and 2 or 1
    if loadedPositions[index] then
        return savedPositions[index]
    end
    loadedPositions[index] = true

    local path = positionPath(index)
    if path == nil then
        return nil
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.LoadFile) ~= "function" then
        return nil
    end
    local loaded, source = pcall(library.LoadFile, path)
    if not loaded or type(source) ~= "string" then
        return nil
    end
    local rawX, rawY = source:match("^%s*([%-+]?[%d%.]+)%s*,%s*([%-+]?[%d%.]+)%s*$")
    local x, y = tonumber(rawX), tonumber(rawY)
    if x == nil or y == nil or x ~= x or y ~= y
        or math.abs(x) > 100000 or math.abs(y) > 100000 then
        return nil
    end
    savedPositions[index] = { X = x, Y = y }
    return savedPositions[index]
end

local function savePosition(index, x, y)
    index = index == 2 and 2 or 1
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then
        return false
    end
    savedPositions[index] = { X = x, Y = y }
    loadedPositions[index] = true

    local path = positionPath(index)
    if path == nil then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return false
    end
    return pcall(library.SaveStringContentToFile, string.format("%.3f,%.3f\n", x, y), path)
end

local function loadScale(index)
    index = index == 2 and 2 or 1
    if loadedScales[index] then
        return savedScales[index]
    end
    loadedScales[index] = true

    local path = scalePath(index)
    if path == nil then
        return nil
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.LoadFile) ~= "function" then
        return nil
    end
    local loaded, source = pcall(library.LoadFile, path)
    local value = loaded and tonumber(type(source) == "string" and source:match("[%d%.]+") or nil)
    if value == nil or value ~= value then
        return nil
    end
    value = math.max(MIN_METER_SCALE, math.min(MAX_METER_SCALE, value))
    savedScales[index] = value
    return value
end

local function saveScale(index, value)
    index = index == 2 and 2 or 1
    value = math.max(
        MIN_METER_SCALE,
        math.min(MAX_METER_SCALE, tonumber(value) or DEFAULT_METER_SCALE)
    )
    savedScales[index] = value
    loadedScales[index] = true

    local path = scalePath(index)
    if path == nil then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return false
    end
    return pcall(library.SaveStringContentToFile, string.format("%.3f\n", value), path)
end

local function loadHeightBonus(index)
    index = index == 2 and 2 or 1
    if loadedHeightBonuses[index] then
        return savedHeightBonuses[index]
    end
    loadedHeightBonuses[index] = true

    local path = heightPath(index)
    if path == nil then
        return nil
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.LoadFile) ~= "function" then
        return nil
    end
    local loaded, source = pcall(library.LoadFile, path)
    local value = loaded and tonumber(type(source) == "string" and source:match("[%-+]?[%d%.]+") or nil)
    if value == nil or value ~= value then
        return nil
    end
    value = math.max(MIN_HEIGHT_BONUS, math.min(MAX_HEIGHT_BONUS, value))
    savedHeightBonuses[index] = value
    return value
end

local function saveHeightBonus(index, value)
    index = index == 2 and 2 or 1
    value = math.max(
        MIN_HEIGHT_BONUS,
        math.min(MAX_HEIGHT_BONUS, tonumber(value) or DEFAULT_HEIGHT_BONUS)
    )
    savedHeightBonuses[index] = value
    loadedHeightBonuses[index] = true

    local path = heightPath(index)
    if path == nil then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return false
    end
    return pcall(library.SaveStringContentToFile, string.format("%.3f\n", value), path)
end

local function loadLocked(index)
    index = index == 2 and 2 or 1
    if loadedLocks[index] then
        return savedLocks[index] == true
    end
    loadedLocks[index] = true

    local path = lockPath(index)
    if path == nil then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.LoadFile) ~= "function" then
        return false
    end
    local loaded, source = pcall(library.LoadFile, path)
    local normalized = loaded and type(source) == "string"
        and source:lower():match("^%s*(.-)%s*$") or ""
    local locked = normalized == "1" or normalized == "true" or normalized == "locked"
    savedLocks[index] = locked
    return locked
end

local function saveLocked(index, locked)
    index = index == 2 and 2 or 1
    locked = locked and true or false
    savedLocks[index] = locked
    loadedLocks[index] = true

    local path = lockPath(index)
    if path == nil then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return false
    end
    return pcall(library.SaveStringContentToFile, locked and "1\n" or "0\n", path)
end

local function loadVisibilityPreference()
    if visibilityLoaded then
        return savedVisibility
    end
    visibilityLoaded = true

    local path = visibilityPath()
    if path == nil then
        return nil
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.LoadFile) ~= "function" then
        return nil
    end
    local loaded, source = pcall(library.LoadFile, path)
    local normalized = loaded and type(source) == "string"
        and source:lower():match("^%s*(.-)%s*$") or ""
    if normalized == "1" or normalized == "true" or normalized == "on" then
        savedVisibility = true
    elseif normalized == "0" or normalized == "false" or normalized == "off" then
        savedVisibility = false
    end
    return savedVisibility
end

local function saveVisibilityPreference(visible)
    visible = visible and true or false
    savedVisibility = visible
    visibilityLoaded = true

    local path = visibilityPath()
    if path == nil then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return false
    end
    return pcall(library.SaveStringContentToFile, visible and "1\n" or "0\n", path)
end

local function currentMeterLocked(component)
    if component == nil then
        return false
    end
    if component.__cpddDpsLocked == nil then
        component.__cpddDpsLocked = loadLocked(instanceIndex(component))
    end
    return component.__cpddDpsLocked == true
end

local function currentMeterScale(component)
    local index = instanceIndex(component)
    local value = component and component.__cpddDpsScale
    value = tonumber(value) or loadScale(index) or DEFAULT_METER_SCALE
    value = math.max(MIN_METER_SCALE, math.min(MAX_METER_SCALE, value))
    if component then
        component.__cpddDpsScale = value
    end
    return value
end

local function currentMeterHeightBonus(component)
    local index = instanceIndex(component)
    local value = component and component.__cpddDpsHeightBonus
    value = tonumber(value) or loadHeightBonus(index) or DEFAULT_HEIGHT_BONUS
    value = math.max(MIN_HEIGHT_BONUS, math.min(MAX_HEIGHT_BONUS, value))
    if component then
        component.__cpddDpsHeightBonus = value
    end
    return value
end

local function meterVisibleRowFloor(component)
    return MIN_ROWS_BEFORE_RESIZE_FOOTER
        + math.floor(currentMeterHeightBonus(component) / HEIGHT_ROW_SIZE + 0.5)
end

local function applyMeterScale(component, value)
    local widget = component and component.userWidget
    if widget == nil or type(widget.SetRenderScale) ~= "function" then
        return false
    end
    value = math.max(
        MIN_METER_SCALE,
        math.min(MAX_METER_SCALE, tonumber(value) or DEFAULT_METER_SCALE)
    )
    if type(widget.SetRenderTransformPivot) == "function" then
        widget:SetRenderTransformPivot(FVector2D(1, 0))
    end
    widget:SetRenderScale(FVector2D(value, value))
    component.__cpddDpsScale = value
    return true
end

local function meterBaseLayout(component)
    if component and component.__cpddDpsBaseLayout then
        return component.__cpddDpsBaseLayout
    end
    local widget = component and component.userWidget
    local slot = widget and widget.Slot
    if slot == nil
        or type(slot.GetOffsets) ~= "function"
        or type(slot.GetAnchors) ~= "function"
    then
        return nil
    end
    local offsets = slot:GetOffsets()
    local anchors = slot:GetAnchors()
    if offsets == nil or anchors == nil then
        return nil
    end
    local minimum = anchors.Minimum
    local maximum = anchors.Maximum
    component.__cpddDpsBaseLayout = {
        Left = offsets.Left,
        Top = offsets.Top,
        Right = offsets.Right,
        Bottom = offsets.Bottom,
        StretchX = minimum and maximum and minimum.X ~= maximum.X,
        StretchY = minimum and maximum and minimum.Y ~= maximum.Y,
    }
    return component.__cpddDpsBaseLayout
end

local currentMeterPosition

local function applyMeterPosition(component, position)
    local widget = component and component.userWidget
    local slot = widget and widget.Slot
    local base = meterBaseLayout(component)
    if position == nil
        or slot == nil
        or base == nil
        or type(slot.SetOffsets) ~= "function"
    then
        return false
    end
    if type(widget.SetRenderTranslation) == "function" then
        widget:SetRenderTranslation(FVector2D(0, 0))
    end
    local offsets = slot:GetOffsets()
    if offsets == nil then
        return false
    end
    local widthBonus = DEFAULT_WIDTH_BONUS
    offsets.Left = base.Left + position.X - widthBonus
    offsets.Top = base.Top + position.Y
    offsets.Right = base.Right - (base.StretchX and position.X or -widthBonus)
    offsets.Bottom = base.Bottom - (base.StretchY and position.Y or 0)
    slot:SetOffsets(offsets)
    component.__cpddDpsPosition = FVector2D(position.X, position.Y)
    return true
end

local function heightLayout(component, key, widget)
    if component == nil or widget == nil then
        return nil
    end
    component.__cpddDpsHeightLayouts = component.__cpddDpsHeightLayouts or {}
    local cached = component.__cpddDpsHeightLayouts[key]
    if cached and cached.Widget == widget then
        return cached
    end
    local slot = widget.Slot
    if slot == nil or type(slot.GetOffsets) ~= "function"
        or type(slot.SetOffsets) ~= "function" or type(slot.GetAnchors) ~= "function"
    then
        return nil
    end
    local offsets = slot:GetOffsets()
    local anchors = slot:GetAnchors()
    if offsets == nil or anchors == nil then
        return nil
    end
    local minimum = anchors.Minimum
    local maximum = anchors.Maximum
    cached = {
        Widget = widget,
        Top = offsets.Top,
        Bottom = offsets.Bottom,
        StretchY = minimum and maximum and minimum.Y ~= maximum.Y,
    }
    component.__cpddDpsHeightLayouts[key] = cached
    return cached
end

local function applyWidgetHeightBonus(component, key, widget, heightBonus)
    local layout = heightLayout(component, key, widget)
    local slot = widget and widget.Slot
    if layout == nil or slot == nil then
        return false
    end
    local offsets = slot:GetOffsets()
    if offsets == nil then
        return false
    end
    offsets.Top = layout.Top
    offsets.Bottom = layout.Bottom + (layout.StretchY and -heightBonus or heightBonus)
    slot:SetOffsets(offsets)
    return true
end

local function applyMeterHeight(component, value)
    if component == nil then
        return false
    end
    value = math.max(
        MIN_HEIGHT_BONUS,
        math.min(MAX_HEIGHT_BONUS, tonumber(value) or DEFAULT_HEIGHT_BONUS)
    )
    component.__cpddDpsHeightBonus = value
    local positionApplied = applyMeterPosition(component, currentMeterPosition(component))
    local info = component.WBP_HUDStatsInfoCom
    local infoWidget = (component.view and component.view.WBP_HUDStatsInfo)
        or (info and info.userWidget)
    local listWidget = info and info.view and info.view.Listview_SimpleInfo
    local infoApplied = applyWidgetHeightBonus(component, "info", infoWidget, value)
    local listApplied = applyWidgetHeightBonus(component, "list", listWidget, value)
    return positionApplied and (infoApplied or listApplied)
end

currentMeterPosition = function(component)
    local position = component and component.__cpddDpsPosition
    if position then
        return FVector2D(position.X, position.Y)
    end
    local index = instanceIndex(component)
    local saved = loadPosition(index)
    if saved == nil and index == 2 then
        local primary = component and component.__cpddDpsPrimary
        local primaryPosition = primary and currentMeterPosition(primary)
            or loadPosition(1) or DEFAULT_POSITION
        saved = {
            X = primaryPosition.X,
            Y = primaryPosition.Y + SECONDARY_Y_OFFSET,
        }
    end
    saved = saved or DEFAULT_POSITION
    return FVector2D(saved.X, saved.Y)
end

local function applySavedPosition(component)
    local scaled, scaleResult = pcall(
        applyMeterScale,
        component,
        currentMeterScale(component)
    )
    if not scaled or not scaleResult then
        report("could not scale the DPS meter: " .. tostring(scaleResult))
    end
    local ok, applied = pcall(
        applyMeterPosition,
        component,
        currentMeterPosition(component)
    )
    if not ok then
        report("could not place the DPS meter: " .. tostring(applied))
        return false
    end
    local heightOk, heightApplied = pcall(
        applyMeterHeight,
        component,
        currentMeterHeightBonus(component)
    )
    if not heightOk or not heightApplied then
        report("could not apply the DPS meter height: " .. tostring(heightApplied))
    end
    return applied and heightOk and heightApplied
end

local function eventReply(method, widget)
    local ok, library = pcall(import, "WidgetBlueprintLibrary")
    if not ok or library == nil then
        return nil
    end
    local handled = library.Handled()
    if method == "capture" and widget then
        return library.CaptureMouse(handled, widget)
    elseif method == "release" then
        return library.ReleaseMouseCapture(handled)
    end
    return handled
end

local function pointerPosition(pointerEvent)
    local ok, library = pcall(import, "KismetInputLibrary")
    if not ok or library == nil then
        return nil
    end
    return library.PointerEvent_GetScreenSpacePosition(pointerEvent)
end

local function pointerIndex(pointerEvent)
    local ok, library = pcall(import, "KismetInputLibrary")
    if not ok or library == nil or type(library.PointerEvent_GetPointerIndex) ~= "function" then
        return nil
    end
    return library.PointerEvent_GetPointerIndex(pointerEvent)
end

local function viewportScale()
    local ok, library = pcall(import, "WidgetLayoutLibrary")
    if not ok or library == nil then
        return 1
    end
    local scale = tonumber(library.GetViewportScale(_G.GetContextObject())) or 1
    return scale > 0 and scale or 1
end

local function viewportSize()
    local ok, library = pcall(import, "WidgetLayoutLibrary")
    if not ok or library == nil then
        return nil
    end
    return library.GetViewportSize(_G.GetContextObject())
end

local function mousePosition()
    local ok, library = pcall(import, "WidgetLayoutLibrary")
    if not ok or library == nil or type(library.GetMousePositionOnViewport) ~= "function" then
        return nil
    end
    local position = library.GetMousePositionOnViewport(_G.GetContextObject())
    if position == nil then
        return nil
    end
    local scale = viewportScale()
    return FVector2D(position.X * scale, position.Y * scale)
end

local function absoluteWidgetBounds(widget)
    if widget == nil or type(widget.GetCachedGeometry) ~= "function" then
        return nil, nil
    end
    local ok, library = pcall(import, "SlateBlueprintLibrary")
    if not ok or library == nil then
        return nil, nil
    end
    local geometry = widget:GetCachedGeometry()
    if geometry == nil then
        return nil, nil
    end
    local localSize = type(library.GetLocalSize) == "function"
        and library.GetLocalSize(geometry) or nil
    if localSize == nil then
        return library.LocalToAbsolute(geometry, FVector2D(0, 0)), library.GetAbsoluteSize(geometry)
    end
    local topLeft = library.LocalToAbsolute(geometry, FVector2D(0, 0))
    local topRight = library.LocalToAbsolute(geometry, FVector2D(localSize.X, 0))
    local bottomLeft = library.LocalToAbsolute(geometry, FVector2D(0, localSize.Y))
    if topLeft == nil or topRight == nil or bottomLeft == nil then
        return nil, nil
    end
    local origin = FVector2D(
        math.min(topLeft.X, topRight.X, bottomLeft.X),
        math.min(topLeft.Y, topRight.Y, bottomLeft.Y)
    )
    local size = FVector2D(
        math.max(topLeft.X, topRight.X, bottomLeft.X) - origin.X,
        math.max(topLeft.Y, topRight.Y, bottomLeft.Y) - origin.Y
    )
    return origin, size
end

local function pointWithinWidget(widget, point)
    local origin, size = absoluteWidgetBounds(widget)
    return point ~= nil and origin ~= nil and size ~= nil
        and point.X >= origin.X and point.X <= origin.X + size.X
        and point.Y >= origin.Y and point.Y <= origin.Y + size.Y
end

local function resizeFooterBounds(component)
    local item = component and component.__cpddDpsResizeFooterItem
    local origin, size = absoluteWidgetBounds(item and item.userWidget)
    if origin ~= nil and size ~= nil then
        return origin, size
    end
    return absoluteWidgetBounds(component and component.userWidget)
end

local function leftAlignText(widget)
    if widget == nil or type(widget.SetJustification) ~= "function" then
        return false
    end
    if not justificationResolved then
        justificationResolved = true
        local ok, enum = pcall(import, "ETextJustify")
        leftJustification = ok and enum and enum.Left or 0
        rightJustification = ok and enum and enum.Right or 2
    end
    return pcall(widget.SetJustification, widget, leftJustification)
end

local function rightAlignText(widget)
    if widget == nil or type(widget.SetJustification) ~= "function" then
        return false
    end
    if not justificationResolved then
        justificationResolved = true
        local ok, enum = pcall(import, "ETextJustify")
        leftJustification = ok and enum and enum.Left or 0
        rightJustification = ok and enum and enum.Right or 2
    end
    return pcall(widget.SetJustification, widget, rightJustification)
end

local function configureMetricText(widget)
    if widget == nil then
        return false
    end
    if type(widget.SetAutoWrapText) == "function" then
        widget:SetAutoWrapText(false)
    end
    leftAlignText(widget)
    return true
end

local function pointWithinResizeHandle(component, point)
    local origin, size = resizeFooterBounds(component)
    return point ~= nil and origin ~= nil and size ~= nil
        and point.X >= origin.X
        and point.X <= origin.X + RESIZE_HANDLE_SIZE
        and point.Y >= origin.Y + size.Y - RESIZE_HANDLE_SIZE
        and point.Y <= origin.Y + size.Y
end

local function pointWithinHeightHandle(component, point)
    local origin, size = resizeFooterBounds(component)
    return point ~= nil and origin ~= nil and size ~= nil
        and point.X >= origin.X + size.X - RESIZE_HANDLE_SIZE
        and point.X <= origin.X + size.X
        and point.Y >= origin.Y + size.Y - RESIZE_HANDLE_SIZE
        and point.Y <= origin.Y + size.Y
end

local function pointWithinAddTitle(component, point)
    local info = component and component.WBP_HUDStatsInfoCom
    local title = info and info.view and info.view.Text_Type
    local origin, size = absoluteWidgetBounds(title)
    return point ~= nil and origin ~= nil and size ~= nil
        and point.X >= origin.X
        and point.X <= origin.X + math.min(ADD_TITLE_HIT_WIDTH, size.X)
        and point.Y >= origin.Y
        and point.Y <= origin.Y + size.Y
end

local function pointWithinLockTitle(component, point)
    local info = component and component.WBP_HUDStatsInfoCom
    local title = info and info.view and info.view.Text_Type
    local origin, size = absoluteWidgetBounds(title)
    local offset = instanceIndex(component) == 1
        and component.__cpddDpsAddEnabled ~= false and ADD_TITLE_HIT_WIDTH or 0
    return point ~= nil and origin ~= nil and size ~= nil
        and point.X >= origin.X + offset
        and point.X <= origin.X + math.min(offset + LOCK_TITLE_HIT_WIDTH, size.X)
        and point.Y >= origin.Y
        and point.Y <= origin.Y + size.Y
end

local function formatStatNumber(value)
    local system = Game and Game.DungeonBattleStatisticsSystem
    value = tonumber(value) or 0
    if system and type(system.GetFormatNumberString) == "function" then
        return tostring(system:GetFormatNumberString(value))
    end
    return string.format("%.0f", value)
end

local function formatCompactNumber(value)
    value = tonumber(value) or 0
    local absolute = math.abs(value)
    local divisor, suffix, decimals = 1, "", 0
    if absolute >= 1000000000 then
        divisor, suffix, decimals = 1000000000, "B", 2
    elseif absolute >= 1000000 then
        divisor, suffix, decimals = 1000000, "M", 2
    elseif absolute >= 1000 then
        divisor, suffix, decimals = 1000, "K", 1
    end
    local text = string.format("%." .. tostring(decimals) .. "f", value / divisor)
    text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return text .. suffix
end

local function formatStatShare(value)
    value = math.max(0, tonumber(value) or 0)
    return string.format("%.1f%%", value * 100)
end

local function getEngagementDuration(rows, system)
    if type(rows) ~= "table" or system == nil
        or type(system.GetDisplayBattleLength) ~= "function"
    then
        return 0
    end
    local longest = 0
    for _, data in pairs(rows) do
        if type(data) == "table" and not data.__cpddDpsHeader
            and not data.__cpddDpsSpacer and not data.__cpddDpsResizeFooter
        then
            local ok, duration = pcall(system.GetDisplayBattleLength, system, data)
            if ok then
                longest = math.max(longest, tonumber(duration) or 0)
            end
        end
    end
    return math.max(0, longest)
end

local function formatEngagementDuration(duration)
    local totalSeconds = math.max(0, math.floor(tonumber(duration) or 0))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor(totalSeconds % 3600 / 60)
    local seconds = totalSeconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end
    return string.format("%02d:%02d", minutes, seconds)
end

local function resolveCritTagData()
    if critTagResolved then
        return cachedCritTagData
    end
    critTagResolved = true

    local tableData = Game and Game.TableData
    if tableData == nil
        or type(tableData.GetCombatStatsTabDataRow) ~= "function"
        or type(tableData.GetCombatStatsTagDataRow) ~= "function"
    then
        return nil
    end
    local tabData = tableData.GetCombatStatsTabDataRow(1)
    local tagIds = tabData and tabData.DefaultTagID
    if tagIds == nil then
        return nil
    end

    local fallback = nil
    local iterator = rawget(_G, "ksbcipairs") or ipairs
    for _, tagId in iterator(tagIds) do
        local tagData = tableData.GetCombatStatsTagDataRow(tagId)
        local params = tagData and tagData.Params
        if tagData and tagData.Type == 1 and params and params[1] and params[2] then
            fallback = fallback or tagData
            local name = tostring(tagData.Name or ""):lower()
            local param1 = tostring(params[1]):lower()
            if name:find("crit", 1, true)
                or name:find("暴击", 1, true)
                or param1:find("crit", 1, true)
            then
                cachedCritTagData = tagData
                break
            end
        end
    end
    cachedCritTagData = cachedCritTagData or fallback
    if cachedCritTagData and cachedCritTagData.Params then
        report(string.format(
            "crit rate uses combat fields %s/%s",
            tostring(cachedCritTagData.Params[1]),
            tostring(cachedCritTagData.Params[2])
        ))
    end
    return cachedCritTagData
end

local function formatCritRate(data)
    local tagData = resolveCritTagData()
    local params = tagData and tagData.Params
    if data == nil or params == nil then
        return "--"
    end
    local critical = tonumber(data[params[1]])
    local total = tonumber(data[params[2]])
    if critical == nil or total == nil then
        return "--"
    end
    if total <= 0 then
        return "0.0%"
    end
    return formatStatShare(critical / total)
end

local function desiredTextWidth(widget, text)
    if widget == nil or type(widget.SetText) ~= "function"
        or type(widget.GetDesiredSize) ~= "function"
    then
        return nil
    end
    local ok, width = pcall(function()
        widget:SetText(tostring(text or ""))
        if type(widget.ForceLayoutPrepass) == "function" then
            widget:ForceLayoutPrepass()
        end
        local size = widget:GetDesiredSize()
        return size and tonumber(size.X) or nil
    end)
    return ok and width or nil
end

local function metricTableColumn(widget, text, targetWidth)
    text = tostring(text or "")
    local width = desiredTextWidth(widget, text)
    local compactWidth = desiredTextWidth(widget, "00")
    local spacedWidth = desiredTextWidth(widget, "0 0")
    local spaceWidth = compactWidth and spacedWidth and spacedWidth - compactWidth or nil
    if width == nil or spaceWidth == nil or spaceWidth <= 0 then
        return text
    end
    local count = math.max(0, math.floor((targetWidth - width) / spaceWidth + 0.5))
    return text .. string.rep(" ", count)
end

local function metricTableLine(widget, values, widths)
    local columns = {}
    for index, value in ipairs(values) do
        columns[index] = metricTableColumn(widget, value, widths[index] or 0)
    end
    return table.concat(columns, COLUMN_SEPARATOR)
end

local function damageColumnText(widget, data)
    local values
    if data and data.__cpddDpsHeader then
        values = { "DPS", "TOTAL DMG", "DMG %", "CRIT %" }
    else
        values = {
            formatCompactNumber(data and data.DPS),
            formatCompactNumber(data and data.damage),
            formatStatShare(data and data.DamagePercentAll),
            formatCritRate(data),
        }
    end
    return metricTableLine(widget, values, DAMAGE_COLUMN_WIDTHS)
end

local function healingColumnText(widget, data, system)
    if data and data.__cpddDpsHeader then
        return metricTableLine(
            widget,
            { "HPS", "TOTAL HEAL", "HEAL %" },
            HEALING_COLUMN_WIDTHS
        )
    end
    local duration = system and type(system.GetDisplayBattleLength) == "function"
        and tonumber(system:GetDisplayBattleLength(data)) or 0
    local healing = tonumber(data and data.heal) or 0
    local hps = duration and duration > 0 and healing / duration or 0
    local values = {
        formatCompactNumber(hps),
        formatCompactNumber(healing),
        formatStatShare(data and data.HealingPercentAll),
    }
    return metricTableLine(widget, values, HEALING_COLUMN_WIDTHS)
end

local function meterOwnerForItem(item)
    local parent = item and item.parentComponent
    while parent do
        if parent.__cpddDpsOwner then
            return parent.__cpddDpsOwner
        end
        parent = parent.parentComponent
    end
    return nil
end

local function installHUDStatsItemClass(class)
    if type(class) ~= "table" or rawget(class, "__cpddExpandedDpsRowVersion") == VERSION then
        return false
    end
    local originalOnRefresh = rawget(class, "OnRefresh")
    if type(originalOnRefresh) ~= "function" then
        return false
    end

    class.OnRefresh = function(self, currentData, sortType, ...)
        local meterOwner = meterOwnerForItem(self)
        if meterOwner then
            if currentData and currentData.__cpddDpsResizeFooter then
                if meterOwner.__cpddDpsResizeFooterItem ~= self then
                    self.__cpddDpsFooterTranslation = 0
                    if self.userWidget and type(self.userWidget.SetRenderTranslation) == "function" then
                        self.userWidget:SetRenderTranslation(FVector2D(0, 0))
                    end
                end
                meterOwner.__cpddDpsResizeFooterItem = self
                if type(meterOwner.__cpddScheduleFooterPosition) == "function" then
                    meterOwner:__cpddScheduleFooterPosition()
                end
            elseif meterOwner.__cpddDpsResizeFooterItem == self then
                meterOwner.__cpddDpsResizeFooterItem = nil
                self.__cpddDpsFooterTranslation = 0
                if self.userWidget and type(self.userWidget.SetRenderTranslation) == "function" then
                    self.userWidget:SetRenderTranslation(FVector2D(0, 0))
                end
            end
        end
        local system = Game and Game.DungeonBattleStatisticsSystem
        local types = system and system.SortType
        local nameText = self.view and self.view.Text_PlayerName
        local valueText = self.view and self.view.Text_Value
        local progressBar = self.view and self.view.ProgressBar
        if nameText and type(nameText.SetRenderOpacity) == "function" then
            nameText:SetRenderOpacity(1)
        end
        if valueText and type(valueText.SetRenderOpacity) == "function" then
            valueText:SetRenderOpacity(1)
        end
        if currentData and (currentData.__cpddDpsSpacer or currentData.__cpddDpsResizeFooter) then
            if progressBar and type(progressBar.SetPercent) == "function" then
                progressBar:SetPercent(0)
            end
            if nameText and type(nameText.SetText) == "function" then
                nameText:SetText(currentData.__cpddDpsResizeFooter and "◣" or "")
                leftAlignText(nameText)
                if currentData.__cpddDpsResizeFooter
                    and type(nameText.SetRenderOpacity) == "function"
                then
                    nameText:SetRenderOpacity(0.55)
                end
            end
            if valueText and type(valueText.SetText) == "function" then
                valueText:SetText(currentData.__cpddDpsResizeFooter and "▼" or "")
                if currentData.__cpddDpsResizeFooter then
                    rightAlignText(valueText)
                    if type(valueText.SetRenderOpacity) == "function" then
                        valueText:SetRenderOpacity(0.55)
                    end
                end
            end
            return
        end
        if currentData and currentData.__cpddDpsHeader and types then
            if progressBar and type(progressBar.SetPercent) == "function" then
                progressBar:SetPercent(0)
            end
            if nameText and type(nameText.SetText) == "function" then
                nameText:SetText("PLAYER")
            end
            if valueText and type(valueText.SetText) == "function" then
                configureMetricText(valueText)
                if sortType == types.TotalDamage then
                    valueText:SetText(damageColumnText(valueText, currentData))
                elseif sortType == types.Heal then
                    valueText:SetText(healingColumnText(valueText, currentData, system))
                end
            end
            return
        end

        local results = { originalOnRefresh(self, currentData, sortType, ...) }
        if currentData and nameText and type(nameText.SetText) == "function" then
            local currentName = tostring(currentData.name or "")
            if type(nameText.GetText) == "function" then
                local ok, renderedName = pcall(nameText.GetText, nameText)
                if ok and renderedName ~= nil then
                    currentName = tostring(renderedName)
                end
            end
            local repairedName = repairDpsPlayerName(currentName, currentData)
            nameText:SetText(repairedName)
            pcall(function()
                nameText.Text = repairedName
            end)
        end
        if currentData and types and valueText and type(valueText.SetText) == "function" then
            configureMetricText(valueText)
            if sortType == types.TotalDamage then
                valueText:SetText(damageColumnText(valueText, currentData))
            elseif sortType == types.Heal then
                valueText:SetText(healingColumnText(valueText, currentData, system))
            end
        end
        return unpack(results)
    end
    class.__cpddExpandedDpsRowVersion = VERSION
    report("installed aligned player columns with totals, party share, and real crit rate")
    return true
end

local function installHUDStatsInfoClass(class)
    if type(class) ~= "table" or rawget(class, "__cpddDpsHeaderVersion") == VERSION then
        return false
    end
    local originalUpdateSimpleList = rawget(class, "UpdateSimpleList")
    local originalItemClicked = rawget(class, "on_Listview_SimpleInfoCom_ItemClicked")
    if type(originalUpdateSimpleList) ~= "function" then
        return false
    end
    class.UpdateSimpleList = function(self, data, sortType, ...)
        local rows = { { __cpddDpsHeader = true } }
        for _, row in ipairs(data or {}) do
            rows[#rows + 1] = row
        end
        local minimumRows = meterVisibleRowFloor(self.__cpddDpsOwner)
        while #rows < minimumRows do
            rows[#rows + 1] = { __cpddDpsSpacer = true }
        end
        rows[#rows + 1] = { __cpddDpsResizeFooter = true }
        return originalUpdateSimpleList(self, rows, sortType, ...)
    end
    if type(originalItemClicked) == "function" then
        class.on_Listview_SimpleInfoCom_ItemClicked = function(self, index, data, ...)
            if data and (data.__cpddDpsHeader or data.__cpddDpsSpacer
                or data.__cpddDpsResizeFooter)
            then
                return
            end
            return originalItemClicked(self, index, data, ...)
        end
    end
    class.__cpddDpsHeaderVersion = VERSION
    report("added fixed DPS meter column headers")
    return true
end

local function installHUDStatsClass(class)
    if type(class) ~= "table" or rawget(class, "__cpddMovableDpsMeterVersion") == VERSION then
        return false
    end

    local originalInitUIData = rawget(class, "InitUIData")
    local originalInitUIComponent = rawget(class, "InitUIComponent")
    local originalInitUIEvent = rawget(class, "InitUIEvent")
    local originalRefresh = rawget(class, "Refresh")
    local originalOnClose = rawget(class, "OnClose")
    local originalStartStatisticTimer = rawget(class, "StartStatisticTimer")
    local originalTimerGetDirtyCombatStat = rawget(class, "TimerGetDirtyCombatStat")
    local originalSetStatisticData = rawget(class, "SetStatisticData")
    local originalTypeClick = rawget(class, "on_WBP_HUDStatsInfoCom_TypeClickEvent")

    if type(originalInitUIData) == "function" then
        class.InitUIData = function(self, ...)
            local results = { originalInitUIData(self, ...) }
            self.__cpddDpsClosing = nil
            self.__cpddDpsEngagementTimer = nil
            local system = Game and Game.DungeonBattleStatisticsSystem
            local types = system and system.SortType
            if types then
                self.Type = instanceIndex(self) == 2 and types.Heal or types.TotalDamage
                self.TypeDisplayOrder = { types.TotalDamage, types.Heal }
                self.TypeText = self.TypeText or {}
                self.TypeText[types.TotalDamage] = "Damage"
                self.TypeText[types.Heal] = "Healing"
            end
            return unpack(results)
        end
    end

    if type(originalInitUIComponent) == "function" then
        class.InitUIComponent = function(self, ...)
            local results = { originalInitUIComponent(self, ...) }
            if self.WBP_HUDStatsInfoCom then
                self.WBP_HUDStatsInfoCom.__cpddDpsOwner = self
            end
            return unpack(results)
        end
    end

    if type(originalStartStatisticTimer) == "function" then
        class.StartStatisticTimer = function(self, ...)
            if instanceIndex(self) == 2 then
                return
            end
            return originalStartStatisticTimer(self, ...)
        end
    end

    if type(originalTimerGetDirtyCombatStat) == "function" then
        class.TimerGetDirtyCombatStat = function(self, ...)
            local results = { originalTimerGetDirtyCombatStat(self, ...) }
            local system = Game and Game.DungeonBattleStatisticsSystem
            if instanceIndex(self) == 1
                and system and type(system.ReqPlayerCombatStatInfo) == "function"
            then
                system:ReqPlayerCombatStatInfo()
            end
            return unpack(results)
        end
    end

    class.GetTypeDisplayOrder = function()
        local system = Game and Game.DungeonBattleStatisticsSystem
        local types = system and system.SortType
        return types and { types.TotalDamage, types.Heal } or {}
    end

    class.SyncGameplayRankType = function(self)
        local system = Game and Game.DungeonBattleStatisticsSystem
        local types = system and system.SortType
        if not types then
            return
        end
        if self.Type ~= types.TotalDamage and self.Type ~= types.Heal then
            self.Type = types.TotalDamage
        end
        local info = self.WBP_HUDStatsInfoCom
        if info and type(info.SetText) == "function" then
            local title = self.TypeText and self.TypeText[self.Type] or "Damage"
            local duration = getEngagementDuration(self.BattleData, system)
            title = tostring(title) .. "  |  " .. formatEngagementDuration(duration)
            title = (currentMeterLocked(self) and "[UNLOCK] " or "[LOCK] ")
                .. tostring(title)
            if instanceIndex(self) == 1 and self.__cpddDpsAddEnabled ~= false then
                title = "[+] " .. tostring(title)
            end
            info:SetText(title)
        end
    end

    function class:__cpddUpdateEngagementTimer()
        if self.__cpddDpsClosing then
            return
        end
        self:SyncGameplayRankType()
    end

    function class:__cpddStartEngagementTimer()
        if self.__cpddDpsEngagementTimer == nil and type(self.AddTimer) == "function" then
            self.__cpddDpsEngagementTimer = self:AddTimer(
                1,
                -1,
                "__cpddUpdateEngagementTimer"
            )
        end
        self:__cpddUpdateEngagementTimer()
    end

    if type(originalSetStatisticData) == "function" then
        class.SetStatisticData = function(self, ...)
            local results = { originalSetStatisticData(self, ...) }
            self:__cpddUpdateEngagementTimer()
            return unpack(results)
        end
    end

    function class:__cpddSetAddMeterButtonVisible(visible)
        self.__cpddDpsAddEnabled = visible and true or false
        self:SyncGameplayRankType()
    end

    function class:__cpddSetMeterLocked(locked)
        locked = locked and true or false
        self.__cpddDpsLocked = locked
        if locked then
            self.__cpddDpsDrag = nil
            self:__cpddStopGlobalDragTick()
        end
        saveLocked(instanceIndex(self), locked)
        self:SyncGameplayRankType()
    end

    function class:__cpddToggleMeterLock()
        self:__cpddSetMeterLocked(not currentMeterLocked(self))
        report((currentMeterLocked(self) and "locked" or "unlocked")
            .. " DPS meter " .. tostring(instanceIndex(self)))
    end

    function class:__cpddSpawnSecondaryMeter()
        if instanceIndex(self) ~= 1 then
            return
        end
        local existing = self.__cpddDpsSecondary
        if existing and type(existing.IsOpened) == "function" and existing:IsOpened() then
            return
        end
        local owner = self.parentComponent
        local root = self.userWidget and self.userWidget:GetParent()
        if owner == nil or root == nil
            or type(owner.internalCreateScript) ~= "function"
            or type(owner.initComponent) ~= "function"
            or not Game or not Game.NewUIManager
            or type(Game.NewUIManager.InstanceWidget) ~= "function"
            or type(Game.NewUIManager.AddChildToCanvas) ~= "function"
        then
            report("could not create the second DPS meter: HUD owner was not available")
            return
        end
        local ok, widget = pcall(
            Game.NewUIManager.InstanceWidget,
            Game.NewUIManager,
            self.userWidget:GetClass()
        )
        if not ok or widget == nil then
            report("could not instance the second DPS meter: " .. tostring(widget))
            return
        end
        local attached, failure = pcall(Game.NewUIManager.AddChildToCanvas, Game.NewUIManager, widget, root)
        if not attached then
            report("could not attach the second DPS meter: " .. tostring(failure))
            return
        end
        local created, secondary = pcall(owner.internalCreateScript, owner, widget, class)
        if not created or secondary == nil then
            if type(widget.RemoveFromParent) == "function" then
                widget:RemoveFromParent()
            end
            report("could not initialize the second DPS meter: " .. tostring(secondary))
            return
        end
        secondary.__cpddDpsInstanceId = 2
        secondary.__cpddDpsPrimary = self
        self.__cpddDpsSecondary = secondary
        local initialized, initFailure = pcall(owner.initComponent, owner, secondary)
        if not initialized then
            self.__cpddDpsSecondary = nil
            if type(widget.RemoveFromParent) == "function" then
                widget:RemoveFromParent()
            end
            report("could not open the second DPS meter: " .. tostring(initFailure))
            return
        end
        local system = Game and Game.DungeonBattleStatisticsSystem
        local types = system and system.SortType
        if type(secondary.Refresh) == "function" then
            secondary:Refresh(types and types.Heal or nil)
        end
        self:__cpddSetAddMeterButtonVisible(false)
        report("opened a second independent healing meter")
    end

    if type(originalTypeClick) == "function" then
        class.on_WBP_HUDStatsInfoCom_TypeClickEvent = function(self, ...)
            if self.__cpddDpsAddClickPending or self.__cpddDpsLockClickPending then
                self.__cpddDpsAddClickPending = nil
                self.__cpddDpsLockClickPending = nil
                return
            end
            return originalTypeClick(self, ...)
        end
    end

    function class:__cpddCloseSecondaryMeter()
        local secondary = self.__cpddDpsSecondary
        if secondary == nil then
            return
        end
        self.__cpddDpsSecondary = nil
        secondary.__cpddDpsPrimary = nil
        local owner = secondary.parentComponent or self.parentComponent
        if owner and type(owner.RemoveComponent) == "function" then
            local ok, failure = pcall(owner.RemoveComponent, owner, secondary)
            if not ok then
                report("could not close the secondary DPS meter: " .. tostring(failure))
            end
        elseif type(secondary.Close) == "function" then
            pcall(secondary.Close, secondary)
        end
    end

    function class:__cpddPositionFooterHandles()
        self.__cpddDpsFooterPositionTimer = nil
        local item = self.__cpddDpsResizeFooterItem
        local footerWidget = item and item.userWidget
        local panelWidget = self.__cpddDpsDragHandle
            or (self.view and self.view.WBP_HUDStatsInfo)
        if footerWidget == nil or panelWidget == nil
            or type(footerWidget.SetRenderTranslation) ~= "function"
        then
            return
        end
        pcall(function()
            if self.userWidget and type(self.userWidget.ForceLayoutPrepass) == "function" then
                self.userWidget:ForceLayoutPrepass()
            elseif type(panelWidget.ForceLayoutPrepass) == "function" then
                panelWidget:ForceLayoutPrepass()
            end
        end)
        local panelOrigin, panelSize = absoluteWidgetBounds(panelWidget)
        local footerOrigin, footerSize = absoluteWidgetBounds(footerWidget)
        if panelOrigin == nil or panelSize == nil or footerOrigin == nil or footerSize == nil then
            return
        end
        local absoluteDelta = panelOrigin.Y + panelSize.Y - FOOTER_BOTTOM_INSET
            - (footerOrigin.Y + footerSize.Y)
        if math.abs(absoluteDelta) < 0.5 then
            return
        end
        local absoluteScale = currentMeterScale(self) * viewportScale()
        local ok, library = pcall(import, "SlateBlueprintLibrary")
        if ok and library and type(library.GetLocalSize) == "function"
            and type(footerWidget.GetCachedGeometry) == "function"
        then
            local localSize = library.GetLocalSize(footerWidget:GetCachedGeometry())
            if localSize and tonumber(localSize.Y) and localSize.Y > 0 and footerSize.Y > 0 then
                absoluteScale = footerSize.Y / localSize.Y
            end
        end
        absoluteScale = math.max(0.01, tonumber(absoluteScale) or 1)
        local translation = (tonumber(item.__cpddDpsFooterTranslation) or 0)
            + absoluteDelta / absoluteScale
        item.__cpddDpsFooterTranslation = translation
        footerWidget:SetRenderTranslation(FVector2D(0, translation))
    end

    function class:__cpddScheduleFooterPosition()
        if self.__cpddDpsFooterPositionTimer ~= nil and type(self.DelTimer) == "function" then
            self:DelTimer(self.__cpddDpsFooterPositionTimer)
        end
        self.__cpddDpsFooterPositionTimer = nil
        if type(self.AddTimer) == "function" then
            self.__cpddDpsFooterPositionTimer = self:AddTimer(
                0.01,
                1,
                "__cpddPositionFooterHandles"
            )
        else
            self:__cpddPositionFooterHandles()
        end
    end

    function class:__cpddBindMeterDragEvents()
        local info = self.WBP_HUDStatsInfoCom
        local handle = (self.view and self.view.WBP_HUDStatsInfo)
            or (info and info.view and info.view.Listview_SimpleInfo)
        local dropdown = info and info.view and info.view.Btn_TypeSelect
        if handle == nil then
            report("DPS drag surface was not available")
            return
        end
        self.__cpddDpsDragHandle = handle
        self.__cpddDpsDropdownHandle = dropdown

        local inputManager = Game and Game.UIInputProcessorManager
        if inputManager and type(inputManager.BindMouseButtonDownEvent) == "function"
            and type(inputManager.BindMouseButtonUpEvent) == "function"
        then
            inputManager:BindMouseButtonDownEvent(self, "__cpddDpsGlobalMouseDown")
            inputManager:BindMouseButtonUpEvent(self, "__cpddDpsGlobalMouseUp")
            self.__cpddDpsGlobalInputBound = true
            report("bound DPS dragging to the visible statistics body")
        else
            report("global mouse input was not available for DPS dragging")
        end

    end

    function class:__cpddBeginDpsDragAt(pointer, inputType, pointerIndexValue, mode)
        if not isPointerInteractionAllowed(inputType)
            or pointer == nil or self.userWidget == nil or currentMeterLocked(self)
        then
            return false
        end
        local origin, size = absoluteWidgetBounds(self.userWidget)
        self.__cpddDpsDrag = {
            InputType = inputType,
            PointerIndex = pointerIndexValue,
            Pointer = pointer,
            Translation = currentMeterPosition(self),
            Origin = origin,
            Size = size,
            Mode = mode or "move",
            MeterScale = currentMeterScale(self),
            HeightBonus = currentMeterHeightBonus(self),
            Moved = false,
        }
        return true
    end

    function class:__cpddBeginDpsDrag(pointerEvent, inputType)
        local pointer = pointerPosition(pointerEvent)
        if not self:__cpddBeginDpsDragAt(
            pointer,
            inputType,
            inputType == "touch" and pointerIndex(pointerEvent) or nil
        ) then
            return eventReply("handled")
        end
        return eventReply("capture", self.__cpddDpsDragHandle or self.userWidget)
    end

    function class:__cpddUpdateDpsDragAt(pointer, inputType)
        local drag = self.__cpddDpsDrag
        if drag == nil or drag.InputType ~= inputType then
            return eventReply("handled")
        end
        if not isPointerInteractionAllowed(inputType) then
            self.__cpddDpsDrag = nil
            return eventReply("release")
        end
        if pointer == nil then
            return eventReply("handled")
        end
        local dx, dy = pointer.X - drag.Pointer.X, pointer.Y - drag.Pointer.Y
        if math.abs(dx) >= DRAG_THRESHOLD or math.abs(dy) >= DRAG_THRESHOLD then
            drag.Moved = true
        end
        if not drag.Moved then
            return eventReply("handled")
        end

        local scale = viewportScale()
        if drag.Mode == "height" then
            local meterScale = math.max(0.01, tonumber(drag.MeterScale) or 1)
            local heightBonus = math.max(
                MIN_HEIGHT_BONUS,
                math.min(
                    MAX_HEIGHT_BONUS,
                    drag.HeightBonus + dy / scale / meterScale
                )
            )
            local ok, applied = pcall(applyMeterHeight, self, heightBonus)
            if (not ok or not applied) and not self.__cpddDpsHeightFailureReported then
                self.__cpddDpsHeightFailureReported = true
                report("could not resize the DPS meter height: " .. tostring(applied))
            end
            local visibleRows = meterVisibleRowFloor(self)
            if visibleRows ~= self.__cpddDpsVisibleRows then
                self.__cpddDpsVisibleRows = visibleRows
                if type(self.SetStatisticData) == "function" then
                    self:SetStatisticData()
                end
            end
            self:__cpddPositionFooterHandles()
            self:__cpddScheduleFooterPosition()
            return eventReply("handled")
        end
        if drag.Mode == "resize" then
            local size = drag.Size or FVector2D(1, 1)
            local width = math.max(1, tonumber(size.X) or 1)
            local height = math.max(1, tonumber(size.Y) or 1)
            local denominator = width * width + height * height
            local outward = ((-dx * width) + (dy * height)) / denominator
            local meterScale = math.max(
                MIN_METER_SCALE,
                math.min(MAX_METER_SCALE, drag.MeterScale * (1 + outward))
            )
            local ok, applied = pcall(applyMeterScale, self, meterScale)
            if (not ok or not applied) and not self.__cpddDpsScaleFailureReported then
                self.__cpddDpsScaleFailureReported = true
                report("could not scale the DPS meter: " .. tostring(applied))
            end
            return eventReply("handled")
        end

        local size = drag.Size
        local origin = drag.Origin
        local viewport = viewportSize()
        if size and origin and viewport then
            local maxX = math.max(0, viewport.X - size.X)
            local maxY = math.max(0, viewport.Y - size.Y)
            local targetX = math.max(0, math.min(maxX, origin.X + dx))
            local targetY = math.max(0, math.min(maxY, origin.Y + dy))
            dx, dy = targetX - origin.X, targetY - origin.Y
        end

        local x = drag.Translation.X + dx / scale
        local y = drag.Translation.Y + dy / scale
        local ok, applied = pcall(applyMeterPosition, self, FVector2D(x, y))
        if not ok or not applied then
            if not self.__cpddDpsMoveFailureReported then
                self.__cpddDpsMoveFailureReported = true
                report("could not move the DPS meter: " .. tostring(applied))
            end
            self.__cpddDpsDrag = nil
            self:__cpddStopGlobalDragTick()
            return eventReply("handled")
        end
        return eventReply("handled")
    end

    function class:__cpddUpdateDpsDrag(pointerEvent, inputType)
        local drag = self.__cpddDpsDrag
        if drag == nil or drag.InputType ~= inputType then
            return eventReply("handled")
        end
        if inputType == "touch" and drag.PointerIndex ~= pointerIndex(pointerEvent) then
            return eventReply("handled")
        end
        return self:__cpddUpdateDpsDragAt(pointerPosition(pointerEvent), inputType)
    end

    function class:__cpddEndDpsDragAt(pointer, inputType)
        local drag = self.__cpddDpsDrag
        if drag == nil or drag.InputType ~= inputType then
            return eventReply("release")
        end
        self:__cpddUpdateDpsDragAt(pointer, inputType)
        if self.__cpddDpsDrag == nil then
            return eventReply("release")
        end
        if drag.Moved then
            local translation = currentMeterPosition(self)
            savePosition(instanceIndex(self), translation.X, translation.Y)
            if drag.Mode == "resize" then
                saveScale(instanceIndex(self), currentMeterScale(self))
            elseif drag.Mode == "height" then
                saveHeightBonus(instanceIndex(self), currentMeterHeightBonus(self))
            end
            if type(self.SetStatisticData) == "function" then
                self:SetStatisticData()
            end
        end
        self.__cpddDpsDrag = nil
        return eventReply("release")
    end

    function class:__cpddEndDpsDrag(pointerEvent, inputType)
        local drag = self.__cpddDpsDrag
        if drag == nil or drag.InputType ~= inputType then
            return eventReply("release")
        end
        if inputType == "touch" and drag.PointerIndex ~= pointerIndex(pointerEvent) then
            return eventReply("handled")
        end
        return self:__cpddEndDpsDragAt(pointerPosition(pointerEvent), inputType)
    end

    function class:__cpddDpsMouseDown(_, pointerEvent)
        return self:__cpddBeginDpsDrag(pointerEvent, "mouse")
    end

    function class:__cpddDpsMouseMove(_, pointerEvent)
        return self:__cpddUpdateDpsDrag(pointerEvent, "mouse")
    end

    function class:__cpddDpsMouseUp(_, pointerEvent)
        return self:__cpddEndDpsDrag(pointerEvent, "mouse")
    end

    function class:__cpddStopGlobalDragTick()
        if self.__cpddDpsGlobalDragTick ~= nil and type(self.DelTimer) == "function" then
            self:DelTimer(self.__cpddDpsGlobalDragTick)
        end
        self.__cpddDpsGlobalDragTick = nil
    end

    function class:__cpddDpsGlobalDragTickHandler()
        if self.__cpddDpsDrag == nil then
            self:__cpddStopGlobalDragTick()
            return
        end
        if not isPointerInteractionAllowed("mouse") then
            self.__cpddDpsDrag = nil
            self:__cpddStopGlobalDragTick()
            return
        end
        self:__cpddUpdateDpsDragAt(mousePosition(), "mouse")
    end

    function class:__cpddDpsGlobalMouseDown(pointerEvent)
        if not isPointerInteractionAllowed("mouse") then
            self.__cpddDpsAddClickPending = nil
            self.__cpddDpsLockClickPending = nil
            self.__cpddDpsDrag = nil
            self:__cpddStopGlobalDragTick()
            return false
        end
        local pointer = pointerPosition(pointerEvent)
        if instanceIndex(self) == 1
            and self.__cpddDpsAddEnabled ~= false
            and pointWithinAddTitle(self, pointer)
        then
            self.__cpddDpsAddClickPending = true
            self:__cpddSpawnSecondaryMeter()
            return false
        end
        if pointWithinLockTitle(self, pointer) then
            self.__cpddDpsLockClickPending = true
            self:__cpddToggleMeterLock()
            return false
        end
        if currentMeterLocked(self) then
            self.__cpddDpsDrag = nil
            self:__cpddStopGlobalDragTick()
            return false
        end
        local overHeightHandle = pointWithinHeightHandle(self, pointer)
        local overScaleHandle = pointWithinResizeHandle(self, pointer)
        if self.__cpddDpsDrag ~= nil
            or pointWithinWidget(self.__cpddDpsDropdownHandle, pointer)
        then
            return false
        end
        if not overHeightHandle and not overScaleHandle
            and not pointWithinWidget(self.__cpddDpsDragHandle, pointer)
        then
            return false
        end
        local mode = "move"
        if overHeightHandle then
            mode = "height"
        elseif overScaleHandle then
            mode = "resize"
        end
        if self:__cpddBeginDpsDragAt(pointer, "mouse", nil, mode) then
            self:__cpddStopGlobalDragTick()
            if type(self.AddTickTimer) == "function" then
                self.__cpddDpsGlobalDragTick = self:AddTickTimer(
                    -1,
                    "__cpddDpsGlobalDragTickHandler"
                )
            elseif type(self.AddTimer) == "function" then
                self.__cpddDpsGlobalDragTick = self:AddTimer(
                    0.016,
                    -1,
                    "__cpddDpsGlobalDragTickHandler"
                )
            end
        end
        return false
    end

    function class:__cpddDpsGlobalMouseUp(pointerEvent)
        if not isPointerInteractionAllowed("mouse") then
            self.__cpddDpsDrag = nil
            self:__cpddStopGlobalDragTick()
            return false
        end
        if self.__cpddDpsDrag ~= nil and self.__cpddDpsDrag.InputType == "mouse" then
            self:__cpddEndDpsDragAt(pointerPosition(pointerEvent) or mousePosition(), "mouse")
        end
        self:__cpddStopGlobalDragTick()
        return false
    end

    function class:__cpddDpsTouchDown(_, pointerEvent)
        return self:__cpddBeginDpsDrag(pointerEvent, "touch")
    end

    function class:__cpddDpsTouchMove(_, pointerEvent)
        return self:__cpddUpdateDpsDrag(pointerEvent, "touch")
    end

    function class:__cpddDpsTouchUp(_, pointerEvent)
        return self:__cpddEndDpsDrag(pointerEvent, "touch")
    end

    if type(originalInitUIEvent) == "function" then
        class.InitUIEvent = function(self, ...)
            local results = { originalInitUIEvent(self, ...) }
            self:__cpddBindMeterDragEvents()
            return unpack(results)
        end
    end

    if type(originalRefresh) == "function" then
        class.Refresh = function(self, ...)
            local results = { originalRefresh(self, ...) }
            applySavedPosition(self)
            self:__cpddScheduleFooterPosition()
            self:__cpddStartEngagementTimer()
            return unpack(results)
        end
    end

    class.OnClose = function(self, ...)
        self:__cpddStopGlobalDragTick()
        if self.__cpddDpsEngagementTimer ~= nil and type(self.DelTimer) == "function" then
            self:DelTimer(self.__cpddDpsEngagementTimer)
            self.__cpddDpsEngagementTimer = nil
        end
        if self.__cpddDpsFooterPositionTimer ~= nil and type(self.DelTimer) == "function" then
            self:DelTimer(self.__cpddDpsFooterPositionTimer)
            self.__cpddDpsFooterPositionTimer = nil
        end
        if instanceIndex(self) == 1 then
            self.__cpddDpsClosing = true
            self:__cpddCloseSecondaryMeter()
        end
        if instanceIndex(self) == 2 and self.__cpddDpsPrimary then
            self.__cpddDpsPrimary.__cpddDpsSecondary = nil
            if not self.__cpddDpsPrimary.__cpddDpsClosing then
                self.__cpddDpsPrimary:__cpddSetAddMeterButtonVisible(true)
            end
        end
        local inputManager = Game and Game.UIInputProcessorManager
        if self.__cpddDpsGlobalInputBound and inputManager then
            if type(inputManager.UnBindMouseButtonDownEvent) == "function" then
                inputManager:UnBindMouseButtonDownEvent(self)
            end
            if type(inputManager.UnBindMouseButtonUpEvent) == "function" then
                inputManager:UnBindMouseButtonUpEvent(self)
            end
            self.__cpddDpsGlobalInputBound = nil
        end
        if type(originalOnClose) == "function" then
            return originalOnClose(self, ...)
        end
    end

    class.__cpddMovableDpsMeterVersion = VERSION
    report("installed movable dual HUD DPS meters with a shared engagement timer")
    return true
end

local function callDuringVisibilityTransition(system, original, ...)
    system.__cpddDpsVisibilityTransitionDepth =
        (tonumber(system.__cpddDpsVisibilityTransitionDepth) or 0) + 1
    local results = { pcall(original, system, ...) }
    system.__cpddDpsVisibilityTransitionDepth = math.max(
        0,
        (tonumber(system.__cpddDpsVisibilityTransitionDepth) or 1) - 1
    )
    if not results[1] then
        error(results[2])
    end
    return unpack(results, 2)
end

local function closeStatisticsHUD(system)
    if system and system.model then
        system.model.bShowStats = false
    end
    local hudSystem = Game and Game.HUDSystem
    if hudSystem and type(hudSystem.CloseSubHUD) == "function" then
        local statsId = UICellConfig and UICellConfig.HUDStats or "HUDStats"
        hudSystem:CloseSubHUD(statsId)
    end
    local middleMenu = Game and Game.HUDMiddleMenuSystem
    local middleMenuType = Enum and Enum.EHUD_MiddleMenu
        and Enum.EHUD_MiddleMenu.SwitchMapStats
    if middleMenu and middleMenuType
        and type(middleMenu.UpdateMiddleMenuBtn) == "function"
    then
        middleMenu:UpdateMiddleMenuBtn(middleMenuType)
    end
end

local function installDungeonBattleStatisticsSystemClass(class)
    if type(class) ~= "table"
        or rawget(class, "__cpddDpsVisibilityVersion") == VERSION
    then
        return false
    end

    local originalSwitch = rawget(class, "OnSwitchPanelClicked")
    local originalShow = rawget(class, "ShowHUDStatistics")
    local originalHide = rawget(class, "HideHUDStatistics")
    local originalMapLoaded = rawget(class, "OnWorldMapLoadComplete")
    local originalClearOnSwitch = rawget(class, "ClearDungeonStatisticsOnSwitch")
    local originalLeaveDungeon = rawget(class, "OnLeaveDungeon")
    local originalSetNextState = rawget(class, "SetSwitchToStatAsNextState")
    local originalReqPlayerDetail = rawget(class, "ReqPlayerCombatStatInfo")
    local originalPlayerDetailLoaded = rawget(class, "OnSelfPlayerDetailLoaded")
    local originalResetSelfDetailState = rawget(class, "ResetSelfDetailState")

    if type(originalSwitch) ~= "function"
        or type(originalShow) ~= "function"
        or type(originalHide) ~= "function"
    then
        return false
    end

    local function restoreSavedVisibility(system)
        local visible = loadVisibilityPreference()
        if visible == true then
            originalShow(system)
        elseif visible == false then
            closeStatisticsHUD(system)
        end
    end

    class.ShowHUDStatistics = function(self, ...)
        if loadVisibilityPreference() == false
            and (tonumber(self.__cpddDpsVisibilityTransitionDepth) or 0) == 0
        then
            return
        end
        return originalShow(self, ...)
    end

    class.HideHUDStatistics = function(self, ...)
        if loadVisibilityPreference() == true
            and (tonumber(self.__cpddDpsVisibilityTransitionDepth) or 0) == 0
        then
            return
        end
        return originalHide(self, ...)
    end

    class.OnSwitchPanelClicked = function(self, ...)
        local results = { originalSwitch(self, ...) }
        local visible = self.model and self.model.bShowStats == true
        saveVisibilityPreference(visible)
        report("saved DPS meter visibility: " .. (visible and "on" or "off"))
        return unpack(results)
    end

    if type(originalMapLoaded) == "function" then
        class.OnWorldMapLoadComplete = function(self, ...)
            local results = {
                callDuringVisibilityTransition(self, originalMapLoaded, ...)
            }
            restoreSavedVisibility(self)
            return unpack(results)
        end
    end

    if type(originalClearOnSwitch) == "function" then
        class.ClearDungeonStatisticsOnSwitch = function(self, ...)
            return callDuringVisibilityTransition(self, originalClearOnSwitch, ...)
        end
    end

    if type(originalLeaveDungeon) == "function" then
        class.OnLeaveDungeon = function(self, ...)
            return callDuringVisibilityTransition(self, originalLeaveDungeon, ...)
        end
    end

    if type(originalSetNextState) == "function" then
        class.SetSwitchToStatAsNextState = function(self, ...)
            local results = { originalSetNextState(self, ...) }
            if loadVisibilityPreference() == true
                and (tonumber(self.__cpddDpsVisibilityTransitionDepth) or 0) == 0
            then
                originalShow(self)
            end
            return unpack(results)
        end
    end

    if type(originalReqPlayerDetail) == "function" then
        class.ReqPlayerCombatStatInfo = function(self, ...)
            local now = detailRequestClock()
            if self.bPlayerDetailRequestPending then
                local requestedAt = tonumber(self.__cpddPlayerDetailRequestedAt)
                if requestedAt == nil then
                    self.__cpddPlayerDetailRequestedAt = now
                elseif now < requestedAt
                    or now - requestedAt >= DETAIL_REQUEST_TIMEOUT
                then
                    self.bPlayerDetailRequestPending = false
                    self.__cpddPlayerDetailRequestedAt = nil
                    report("retrying a timed-out detailed statistics request")
                end
            end

            local wasPending = self.bPlayerDetailRequestPending == true
            local results = { originalReqPlayerDetail(self, ...) }
            if not wasPending and self.bPlayerDetailRequestPending then
                self.__cpddPlayerDetailRequestedAt = now
            end
            return unpack(results)
        end
    end

    if type(originalPlayerDetailLoaded) == "function" then
        class.OnSelfPlayerDetailLoaded = function(self, ...)
            self.__cpddPlayerDetailRequestedAt = nil
            return originalPlayerDetailLoaded(self, ...)
        end
    end

    if type(originalResetSelfDetailState) == "function" then
        class.ResetSelfDetailState = function(self, ...)
            self.__cpddPlayerDetailRequestedAt = nil
            return originalResetSelfDetailState(self, ...)
        end
    end

    class.__cpddDpsVisibilityVersion = VERSION
    report("installed persistent DPS visibility and detailed-stat request recovery")
    return true
end

local function installStatisticsPanelClass(class)
    if type(class) ~= "table"
        or rawget(class, "__cpddLiveDetailRefreshVersion") == VERSION
    then
        return false
    end

    local detailEvent = EEventTypesV2 and EEventTypesV2.ON_RECV_PLAYER_DETAIL_STAT
    if detailEvent == nil then
        return false
    end

    class.eventBindMap = class.eventBindMap or {}
    class.eventBindMap[detailEvent] = "__cpddOnRecvPlayerDetailStat"

    local originalOnRefresh = rawget(class, "OnRefresh")
    local originalOnClose = rawget(class, "OnClose")

    function class:__cpddRefreshAfterPlayerDetail()
        self.__cpddPlayerDetailRefreshTimer = nil
        if type(self.RefreshUI) == "function" then
            self:RefreshUI()
        end
    end

    function class:__cpddOnRecvPlayerDetailStat(playerCombatStat)
        local player = Game and Game.me
        if not playerCombatStat or not player
            or playerCombatStat.id ~= player.eid
        then
            return
        end

        -- The native receiver publishes this event immediately before it merges
        -- the full skill maps into CurStat. Refresh on the next UI tick so totals,
        -- crit tags, and skill rows all come from that same completed packet.
        if self.__cpddPlayerDetailRefreshTimer == nil
            and type(self.AddTimer) == "function"
        then
            self.__cpddPlayerDetailRefreshTimer = self:AddTimer(
                0.01,
                1,
                "__cpddRefreshAfterPlayerDetail"
            )
        end
    end

    if type(originalOnRefresh) == "function" then
        class.OnRefresh = function(self, ...)
            local results = { originalOnRefresh(self, ...) }
            local system = Game and Game.DungeonBattleStatisticsSystem
            if system and type(system.ReqPlayerCombatStatInfo) == "function" then
                system:ReqPlayerCombatStatInfo()
            end
            return unpack(results)
        end
    end

    class.OnClose = function(self, ...)
        if self.__cpddPlayerDetailRefreshTimer ~= nil
            and type(self.DelTimer) == "function"
        then
            self:DelTimer(self.__cpddPlayerDetailRefreshTimer)
            self.__cpddPlayerDetailRefreshTimer = nil
        end
        if type(originalOnClose) == "function" then
            return originalOnClose(self, ...)
        end
    end

    class.__cpddLiveDetailRefreshVersion = VERSION
    report("installed response-driven detailed statistics refresh")
    return true
end

local function installHUDStats(value, environment)
    installHUDStatsClass(getSymbol(value, environment, "HUDStats"))
    return value
end

local function installDungeonBattleStatisticsSystem(value, environment)
    installDungeonBattleStatisticsSystemClass(
        getSymbol(value, environment, "DungeonBattleStatisticsSystem")
    )
    return value
end

local function installHUDStatsItem(value, environment)
    installHUDStatsItemClass(getSymbol(value, environment, "HUDStatsItem"))
    return value
end

local function installHUDStatsInfo(value, environment)
    installHUDStatsInfoClass(getSymbol(value, environment, "HUDStatsInfo"))
    return value
end

local function installStatisticsPanel(value, environment)
    installStatisticsPanelClass(getSymbol(value, environment, "Statistics_Panel"))
    return value
end

local function installNonConflictingHUDConfig(value, environment)
    local config = getSymbol(value, environment, "UIHUDConfig")
    local statsId = UICellConfig and UICellConfig.HUDStats or "HUDStats"
    local statsConfig = type(config) == "table" and config[statsId]
    if type(statsConfig) == "table" then
        statsConfig.ConflictNodes = nil
        report("removed the DPS meter/minimap HUD conflict")
    end
    return value
end

local function callMiniMapRuleWithoutStatisticsConflict(original, ...)
    local system = Game and Game.DungeonBattleStatisticsSystem
    if type(system) ~= "table" then
        return original(...)
    end

    local names = { "IsStatWindowExpanded", "CheckStatisticPanelVisible" }
    local rawValues = {}
    for _, name in ipairs(names) do
        rawValues[name] = rawget(system, name)
        rawset(system, name, function()
            return false
        end)
    end
    local results = { pcall(original, ...) }
    for _, name in ipairs(names) do
        rawset(system, name, rawValues[name])
    end
    if not results[1] then
        error(results[2])
    end
    return unpack(results, 2)
end

local function installMiniMapRule(value, environment)
    local rules = getSymbol(value, environment, "HUDShowRules")
    if type(rules) ~= "table" or rawget(rules, "__cpddDpsMeterMiniMapVersion") == VERSION then
        return value
    end
    local original = rawget(rules, "MiniMapRule")
    if type(original) == "function" then
        rules.MiniMapRule = function(...)
            return callMiniMapRuleWithoutStatisticsConflict(original, ...)
        end
        rules.__cpddDpsMeterMiniMapVersion = VERSION
        report("kept the minimap visible while the DPS meter is open")
    end
    return value
end

Loader.AfterLoad(
    "Gameplay.LogicSystem.DungeonBattleStatistics.DungeonBattleStatisticsSystem",
    installDungeonBattleStatisticsSystem,
    1000000,
    "cpdd.dps-meter.persistent-visibility"
)

Loader.AfterLoad(
    "Gameplay.Const.Config.UIConfig.UIHUDConfig",
    installNonConflictingHUDConfig,
    1000000,
    "cpdd.dps-meter.non-conflicting-hud"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.HUD.HUDShowRules",
    installMiniMapRule,
    1000000,
    "cpdd.dps-meter.minimap-rule"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.HUD.HUD_Stats.HUDStats",
    installHUDStats,
    1000000,
    "cpdd.dps-meter.movable"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.HUD.HUD_Stats.HUDStatsItem",
    installHUDStatsItem,
    1000000,
    "cpdd.dps-meter.expanded-rows"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.HUD.HUD_Stats.HUDStatsInfo",
    installHUDStatsInfo,
    1000000,
    "cpdd.dps-meter.column-headers"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.Dungeon.StatisticsDungeon.Statistics_Panel",
    installStatisticsPanel,
    1000000,
    "cpdd.dps-meter.live-detail-refresh"
)

report("registered v" .. VERSION)
return {
    Version = VERSION,
    IsPointerInteractionAllowed = isPointerInteractionAllowed,
    FormatEngagementDuration = formatEngagementDuration,
    GetEngagementDuration = getEngagementDuration,
    ApplySavedPosition = applySavedPosition,
    LoadVisibilityPreference = loadVisibilityPreference,
    SaveVisibilityPreference = saveVisibilityPreference,
    LoadPosition = function()
        return loadPosition(1)
    end,
    SavePosition = function(x, y)
        return savePosition(1, x, y)
    end,
}

-- Opt-in menu unlock. Native DLSS support and the driver's result stay authoritative.
local Loader = assert(LOMModLoader, "LOMModLoader is required")
local Feature = { Version = "1.0.0", LastStatus = "inactive" }
local MODULE = "Gameplay.LogicSystem.Settings.SettingsManager"

local function status(value)
    if Feature.LastStatus == value then return end
    Feature.LastStatus = value
    local logger = Log or LaunchLog
    if logger and logger.Info then logger.Info("[LOMDlss5] " .. value) end
end

local function eligible(manager)
    local vendors = manager.EGPUManufacturer
    local library = manager.KGDLSSNRLibrary
    return Loader.Features.Dlss5Unlock == true and manager.bPCMode == true
        and type(vendors) == "table" and vendors.NVIDIA ~= nil
        and manager.GPUManufacturer == vendors.NVIDIA
        and library ~= nil and type(library.SetEnabled) == "function"
        and type(library.IsEnabled) == "function" and type(library.IsSupported) == "function"
end

function Feature.Install(manager)
    if type(manager) ~= "table" then return false end
    local refresh, command = manager.refreshDLSSNR, manager.__Cmd_DLSS_NR
    if type(refresh) ~= "function" or type(command) ~= "function" then return false end
    if manager.__lomDlss5Refresh == refresh and manager.__lomDlss5Command == command then return true end

    local wrappedRefresh = function(self, srMethod, setSource)
        if not eligible(self) then return refresh(self, srMethod, setSource) end
        local supported = self.bDLSSNRSupported
        self.bDLSSNRSupported = true
        local ok, result = pcall(refresh, self, srMethod, setSource)
        self.bDLSSNRSupported = supported
        if not ok then error(result, 0) end
        -- The native refresh still locks the setting when DLSS is not selected.
        if self.ESuperResolutionMethod and srMethod == self.ESuperResolutionMethod.DLSS then
            local nativeOK, nativeSupported = pcall(self.KGDLSSNRLibrary.IsSupported)
            status(nativeOK and nativeSupported and "menu unlocked; native support available"
                or "menu unlocked experimentally; native support unavailable")
        end
        return result
    end
    local wrappedCommand = function(self, value)
        local result = command(self, value)
        if eligible(self) then
            local ok, enabled = pcall(self.KGDLSSNRLibrary.IsEnabled)
            if not ok then status("native activation status unavailable")
            elseif enabled then status("native neural rendering enabled")
            elseif value == 1 then status("native neural rendering did not activate; GPU, driver or mode unsupported")
            else status("native neural rendering disabled") end
        end
        return result
    end
    manager.refreshDLSSNR, manager.__Cmd_DLSS_NR = wrappedRefresh, wrappedCommand
    manager.__lomDlss5Refresh, manager.__lomDlss5Command = wrappedRefresh, wrappedCommand
    return true
end

Loader.AfterLoad(MODULE, function(value, environment)
    Feature.Install(type(value) == "table" and value or environment and environment.SettingsManager)
    return value
end, 30, "dlss5.menu-unlock")
Loader.On("after_main", function()
    Feature.Install(Game and Game.SettingsManager)
end, 30, "dlss5.current-manager")
Loader.Dlss5 = Feature
return Feature

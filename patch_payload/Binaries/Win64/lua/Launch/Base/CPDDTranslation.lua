local original = require("Launch.Base.LaunchStringExt")

local File = import("LuaFunctionLibrary")
local path = File.GetFilePath(import("BlueprintPathsLibrary").ProjectSavedDir()) .. "/Mods/bootstrap.lua"
local source = File.LoadFile(path)
LaunchLog.Info("[LOMModLoader] bootstrap path=" .. path .. " bytes=" .. tostring(source and #source or 0))
if source and source ~= "" then
    local chunk, message = load(source, "@" .. path)
    if chunk then xpcall(chunk, LaunchLog.Error) else LaunchLog.Error(message) end
end

return original

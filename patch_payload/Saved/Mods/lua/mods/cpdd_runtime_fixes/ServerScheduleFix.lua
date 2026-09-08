local Loader = assert(LOMModLoader, "LOMModLoader is required")

local VERSION = "1.0.0"
local MODULE_NAME = "Gameplay.LogicSystem.SuddenEvent.System.SuddenEventSystem"
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400
local SECONDS_PER_WEEK = 604800
local CHINA_TIME_ZONE = 8

local function report(message)
    local logger = Log or LaunchLog
    if logger and logger.Info then
        logger.Info("[CPDDServerSchedule] " .. tostring(message))
    end
end

local function getServerTimeZoneHours()
    local configured = nil
    pcall(function()
        configured = tonumber(Game.TimeManager.serverTimeZone)
    end)

    -- The production China server reports 8 after Account:onGetControl. During
    -- early startup TimeManager still contains its zero-initialized placeholder.
    if configured == nil or configured == 0 or configured < -12 or configured > 14 then
        return CHINA_TIME_ZONE
    end
    return configured
end

local function getServerClock(timestamp)
    local zoneSeconds = getServerTimeZoneHours() * SECONDS_PER_HOUR
    local shifted = timestamp + zoneSeconds
    local dayIndex = math.floor(shifted / SECONDS_PER_DAY)
    local secondOfDay = shifted - dayIndex * SECONDS_PER_DAY

    -- Unix day zero (1970-01-01) was Thursday. C7 numbers Monday as 1 and
    -- Sunday as 7.
    local weekDay = (dayIndex + 3) % 7 + 1
    local hour = math.floor(secondOfDay / SECONDS_PER_HOUR)
    local minute = math.floor(
        (secondOfDay - hour * SECONDS_PER_HOUR) / 60
    )
    return dayIndex, weekDay, hour, minute, zoneSeconds
end

local function getServerWeekZeroTime(timestamp)
    local dayIndex, weekDay, _, _, zoneSeconds = getServerClock(timestamp)
    local mondayDayIndex = dayIndex - (weekDay - 1)
    return mondayDayIndex * SECONDS_PER_DAY - zoneSeconds
end

local function buildOpenTimeRangeList(self, refreshRuleData, curTime)
    local ruleTimeRangeList = self:_BuildRuleWeekTimeRangeList(
        refreshRuleData and refreshRuleData.RuleTime
    )
    local dailyTimeRangeList = self:_BuildDailyTimeRangeList(
        refreshRuleData and refreshRuleData.DailyRuleTime
    )
    local currentWeekZeroTime = getServerWeekZeroTime(curTime)
    local openTimeRangeList = {}
    local hasDailyRanges = type(dailyTimeRangeList) == "table"
        and next(dailyTimeRangeList) ~= nil

    for weekOffset = 0, 1 do
        local weekStartTime = currentWeekZeroTime
            + weekOffset * SECONDS_PER_WEEK
        for _, ruleTimeRange in ipairs(ruleTimeRangeList or {}) do
            local ruleStartOffset = tonumber(ruleTimeRange.StartOffset)
            local ruleEndOffset = tonumber(ruleTimeRange.EndOffset)
            if ruleStartOffset ~= nil and ruleEndOffset ~= nil then
                local ruleStartDay = math.floor(ruleStartOffset / SECONDS_PER_DAY)
                local ruleEndDay = math.floor(ruleEndOffset / SECONDS_PER_DAY)

                for dayIndex = ruleStartDay, ruleEndDay do
                    local dayStartOffset = dayIndex * SECONDS_PER_DAY
                    local dayEndOffset = dayStartOffset + SECONDS_PER_DAY - 1
                    local boundedRuleStart = math.max(ruleStartOffset, dayStartOffset)
                    local boundedRuleEnd = math.min(ruleEndOffset, dayEndOffset)

                    if not hasDailyRanges then
                        if boundedRuleStart <= boundedRuleEnd then
                            table.insert(openTimeRangeList, {
                                StartTime = weekStartTime + boundedRuleStart,
                                EndTime = weekStartTime + boundedRuleEnd,
                            })
                        end
                    else
                        for _, dailyTimeRange in ipairs(dailyTimeRangeList) do
                            local dailyStartOffset = dayStartOffset
                                + (tonumber(dailyTimeRange.StartOffset) or 0)
                            local dailyEndOffset = dayStartOffset
                                + (tonumber(dailyTimeRange.EndOffset) or -1)
                            local finalStartOffset = math.max(
                                boundedRuleStart,
                                dailyStartOffset
                            )
                            local finalEndOffset = math.min(
                                boundedRuleEnd,
                                dailyEndOffset
                            )
                            if finalStartOffset <= finalEndOffset then
                                table.insert(openTimeRangeList, {
                                    StartTime = weekStartTime + finalStartOffset,
                                    EndTime = weekStartTime + finalEndOffset,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(openTimeRangeList, function(a, b)
        return a.StartTime < b.StartTime
    end)
    return openTimeRangeList
end

local function installTarget(target)
    if type(target) ~= "table" then
        return false
    end
    if target.__cpddServerScheduleVersion == VERSION then
        return true
    end

    local nativeBuild = target._BuildOpenTimeRangeList
    local nativeFormat = target._FormatNextOpenText
    if type(nativeBuild) ~= "function" or type(nativeFormat) ~= "function" then
        return false
    end

    target._BuildOpenTimeRangeList = buildOpenTimeRangeList
    target._FormatNextOpenText = function(self, nextOpenTime, curTime)
        if type(nextOpenTime) ~= "number" or type(curTime) ~= "number" then
            return nativeFormat(self, nextOpenTime, curTime)
        end

        local currentDay = getServerClock(curTime)
        local nextDay, nextWeekDay, hour, minute = getServerClock(nextOpenTime)
        local textTypes = self.OpenStateTextType or target.OpenStateTextType
        local weekDayNames = self.WeekDayName or target.WeekDayName
        local tableData = Game and Game.TableData
        if type(textTypes) ~= "table" or type(tableData) ~= "table" then
            return nativeFormat(self, nextOpenTime, curTime)
        end

        local rowGetter = tableData.GetSuddenEventConstDataRow
        if type(rowGetter) ~= "function" then
            return nativeFormat(self, nextOpenTime, curTime)
        end

        local template, argument, textType
        if currentDay == nextDay then
            template = rowGetter("SUDDEN_DETAIL_TIME_OPEN")
            argument = { hour, minute }
            textType = textTypes.TodayTime or 2
        else
            template = rowGetter("SUDDEN_DETAIL_WEEK_OPEN")
            argument = { type(weekDayNames) == "table"
                and weekDayNames[nextWeekDay] or tostring(nextWeekDay) }
            textType = textTypes.WeekDay or 1
        end

        local ok, text = pcall(string.format, template, unpack(argument))
        if not ok then
            return nativeFormat(self, nextOpenTime, curTime)
        end
        return textType, text
    end
    target.__cpddServerScheduleVersion = VERSION
    report("installed China-server event calendar fix")
    return true
end

local function findAndInstall(value, environment)
    if type(value) == "table" and installTarget(value.SuddenEventSystem) then
        return true
    end
    if type(environment) == "table"
        and installTarget(environment.SuddenEventSystem) then
        return true
    end
    return installTarget(value)
end

Loader.AfterLoad(MODULE_NAME, function(value, environment)
    findAndInstall(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.server-schedule")

Loader.On("after_main", function()
    findAndInstall(Game and Game.SuddenEventSystem, nil)
end, 1000000, "cpdd.runtime-fix.server-schedule-main")

findAndInstall(package.loaded[MODULE_NAME], nil)

return {
    Version = VERSION,
    GetServerClock = getServerClock,
    GetServerWeekZeroTime = getServerWeekZeroTime,
    Install = findAndInstall,
}

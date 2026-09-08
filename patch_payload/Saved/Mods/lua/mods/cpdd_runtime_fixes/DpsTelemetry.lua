local Loader = assert(LOMModLoader, "LOMModLoader is required")

local VERSION = "1.7.1"
local OUTPUT_FILE = "dps-meter-live.json"
local UPDATE_SECONDS = 1
local DETAIL_REQUEST_TIMEOUT = 3
local unpackValues = table.unpack or unpack
local sequence = 0
local metricFieldsResolved = false
local metricFields = {}
local professionNames = {}
local PROFESSION_FALLBACKS = {
    [1] = "Bard",
    [2] = "Spectator",
    [3] = "Seer",
    [5] = "Apprentice",
    [6] = "Warrior",
    [7] = "Mystery Pryer",
}
local lastTargetId = ""
local lastTargetName = ""
local lastTargetLevel = nil
local pvpState = {
    active = false,
    duration = 0,
    key = "",
    label = "PvP Match",
    latest = nil,
    startedAt = nil,
    details = {},
    detailCursor = 0,
    detailRequestedAt = nil,
}

local function report(message)
    local logger = Log or LaunchLog
    if logger and logger.Info then
        logger.Info("[CPDDDpsTelemetry] " .. tostring(message))
    end
end

local function finiteNumber(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then
        return 0
    end
    return value
end

local function detailRequestClock()
    if TimeUtils and type(TimeUtils.GetServerTime) == "function" then
        local ok, value = pcall(TimeUtils.GetServerTime)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return os and type(os.clock) == "function" and os.clock() or 0
end

local function jsonNumber(value)
    return string.format("%.6f", finiteNumber(value)):gsub("%.?0+$", "")
end

local function jsonString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub('"', '\\"')
    value = value:gsub("\b", "\\b"):gsub("\f", "\\f")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    value = value:gsub("[%z\1-\31]", function(character)
        return string.format("\\u%04x", string.byte(character))
    end)
    return '"' .. value .. '"'
end

local function getOutputPath()
    local root = tostring(Loader.Root or ""):gsub("\\", "/"):gsub("/+$", "")
    if root == "" then
        return nil
    end
    return root .. "/" .. OUTPUT_FILE
end

local function displayDuration(system, playerData)
    if system and type(system.GetDisplayBattleLength) == "function" then
        local ok, value = pcall(system.GetDisplayBattleLength, system, playerData)
        if ok then
            return finiteNumber(value)
        end
    end
    return finiteNumber(playerData and playerData.battleLength)
end

local function firstValue(data, keys)
    for _, key in ipairs(keys or {}) do
        if data and data[key] ~= nil then
            return finiteNumber(data[key])
        end
    end
    return 0
end

local function resolveMetricFields()
    if metricFieldsResolved then
        return metricFields
    end
    metricFieldsResolved = true
    local tableData = Game and Game.TableData
    if not tableData or type(tableData.GetCombatStatsTabDataRow) ~= "function"
        or type(tableData.GetCombatStatsTagDataRow) ~= "function"
    then
        return metricFields
    end
    local iterator = rawget(_G, "ksbcipairs") or ipairs
    for tabId = 1, 4 do
        local tab = tableData.GetCombatStatsTabDataRow(tabId)
        for _, tagId in iterator(tab and tab.DefaultTagID or {}) do
            local tag = tableData.GetCombatStatsTagDataRow(tagId)
            local params = tag and tag.Params
            if tag and tag.Type == 1 and params and params[1] and params[2] then
                local text = (tostring(tag.Name or "") .. " "
                    .. tostring(params[1] or "")):lower()
                if not metricFields.crit and (text:find("crit", 1, true)
                    or text:find("暴击", 1, true))
                then
                    metricFields.crit = { params[1], params[2], tag.bInverse == true }
                elseif not metricFields.pierce and (text:find("pierc", 1, true)
                    or text:find("penetr", 1, true)
                    or text:find("穿透", 1, true))
                then
                    metricFields.pierce = { params[1], params[2], tag.bInverse == true }
                end
            end
        end
    end
    for name, params in pairs(metricFields) do
        report(string.format(
            "%s rate uses combat fields %s/%s",
            tostring(name), tostring(params[1]), tostring(params[2])
        ))
    end
    return metricFields
end

local function metricPair(data, metric, numeratorFallbacks, denominatorFallbacks)
    local params = resolveMetricFields()[metric]
    local numerator = params and firstValue(data, { params[1] })
        or firstValue(data, numeratorFallbacks)
    local denominator = params and firstValue(data, { params[2] })
        or firstValue(data, denominatorFallbacks)
    if params and params[3] and denominator > 0 then
        numerator = math.max(0, denominator - numerator)
    end
    return numerator, denominator
end

local function meaningfulName(value)
    if value == nil then
        return ""
    end
    local text = tostring(value):gsub("[%c]", " "):gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" or text:match("^%d+$") or text:match("^Target%s+%d+$") then
        return ""
    end
    return text
end

local function professionName(profession)
    local id = tonumber(profession) or 0
    if professionNames[id] ~= nil then
        return professionNames[id]
    end
    local name = ""
    local tableData = Game and Game.TableData
    if id > 0 and tableData
        and type(tableData.GetPlayerSocialDisplayDataRow) == "function"
    then
        local ok, rows = pcall(tableData.GetPlayerSocialDisplayDataRow, id)
        if ok and rows then
            local row = rows[0] or rows[id] or rows[1]
            name = meaningfulName(row and (row.ClassEngName or row.ClassName))
        end
    end
    if name == "" then
        name = PROFESSION_FALLBACKS[id % 100] or "Unknown Pathway"
    end
    professionNames[id] = name
    return name
end

local function safeMethodResult(owner, methodName)
    local method = owner and owner[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, owner)
    if ok then return value end
    return nil
end

local function entityDisplayName(entity)
    if not entity then
        return ""
    end
    local config = safeMethodResult(entity, "GetEntityConfigData")
    local candidates = {}
    local function add(value)
        if value ~= nil then
            candidates[#candidates + 1] = value
        end
    end
    add(entity.Name)
    add(entity.ExcelData and entity.ExcelData.ShowName)
    add(safeMethodResult(entity, "GetMonsterName"))
    add(safeMethodResult(entity, "GetDisplayName"))
    add(entity.EntityName)
    add(config and config.Name)
    add(entity.DisplayName)
    add(config and config.DisplayName)
    for _, candidate in ipairs(candidates) do
        local name = meaningfulName(candidate)
        if name ~= "" then
            return name
        end
    end
    return ""
end

local function entityIdentity(entity)
    if not entity then
        return nil, ""
    end
    local id = entity.eid or entity.id or entity.EntityID or entity.IntID
    return id, entityDisplayName(entity)
end

local function currentTarget(system, current)
    local targetId = system and (system.lastLockedStatisticNpcTargetID
        or system.currentStatisticNpcTargetID or system.CurrentTargetID)
    local targetName = meaningfulName(current and (current.targetName or current.TargetName
        or current.bossName or current.BossName))
    local player = Game and Game.me
    local targetEntity = nil
    if targetId == nil or targetId == 0 or targetId == "" then
        targetId = player and (player.LockTargetID or player.lockTargetID
            or player.TargetID or player.targetID)
    end
    if targetId == 0 or targetId == "" then
        targetId = nil
    end
    if player then
        for _, methodName in ipairs({ "GetLockTarget", "GetTarget", "GetCurrentTarget" }) do
            if targetEntity == nil and type(player[methodName]) == "function" then
                local ok, value = pcall(player[methodName], player)
                if ok and value then
                    if type(value) == "table" then
                        local entityId, entityName = entityIdentity(value)
                        targetId = targetId or entityId
                        if tostring(entityId) == tostring(targetId) then
                            targetEntity = value
                            if targetName == "" then targetName = entityName end
                        end
                    else
                        targetId = targetId or value
                    end
                end
            end
        end
    end
    if targetId == nil or targetId == 0 or targetId == "" then
        return lastTargetId, lastTargetName, lastTargetLevel
    end
    local manager = Game and Game.EntityManager
    local entity = targetEntity
    if manager then
        for _, methodName in ipairs({ "getEntity", "getEntityWithBrief", "GetEntityByIntID" }) do
            local method = manager[methodName]
            if type(method) == "function" then
                local ok, value = pcall(method, manager, targetId)
                if ok and value then
                    entity = value
                    break
                end
            end
        end
    end
    local name = targetName
    if entity then
        local entityName = entityDisplayName(entity)
        if entityName ~= "" then
            name = entityName
        end
    end
    local level = entity and tonumber(entity.Level)
    if not level or level ~= level or level <= 0 or level >= 1000000 then level = nil end
    if tostring(targetId) == lastTargetId then
        level = level or lastTargetLevel
        if name == "" then name = lastTargetName end
    end
    lastTargetLevel = level and math.floor(level) or nil
    lastTargetId = tostring(targetId)
    lastTargetName = name
    return lastTargetId, lastTargetName, lastTargetLevel
end

local function playerSort(a, b)
    local aActivity = finiteNumber(a.damage) + finiteNumber(a.heal) + finiteNumber(a.bear)
    local bActivity = finiteNumber(b.damage) + finiteNumber(b.heal) + finiteNumber(b.bear)
    if aActivity == bActivity then
        return tostring(a.name or "") < tostring(b.name or "")
    end
    return aActivity > bActivity
end

local function playerGearScore(data, isSelf)
    local score = data and (data.gearScore or data.ZhanLi or data.zhanLi
        or data.CEScore or data.ceScore)
    if (tonumber(score) or 0) > 0 then
        return score
    end
    if isSelf and Game and Game.me then
        score = Game.me.ZhanLi or Game.me.CEScore or Game.me.ceScore
        if (tonumber(score) or 0) > 0 then
            return score
        end
    end
    local manager = Game and Game.EntityManager
    local playerId = data and data.id
    if manager and playerId ~= nil then
        for _, methodName in ipairs({ "getEntity", "getEntityWithBrief", "GetEntityByIntID" }) do
            local method = manager[methodName]
            if type(method) == "function" then
                local ok, entity = pcall(method, manager, playerId)
                if ok and entity then
                    score = entity.ZhanLi or entity.zhanLi or entity.CEScore or entity.ceScore
                    if (tonumber(score) or 0) > 0 then
                        return score
                    end
                end
            end
        end
    end
    return 0
end

-- Counters cover events received by this client, not server-wide coverage.
local observations, knownPlayers = {}, {}
local observationCount = 0
local healObserverReady, deathObserverReady = false, false
local function optionalCounter(value)
    if value == nil then return "null" end
    return jsonNumber(value)
end
local function pingMs()
    local delay = Game and Game.me and Game.me.__ntpAverageDelay
    if type(delay) == "number" and delay == delay and delay >= 0 and delay < math.huge / 2 then
        return delay * 2 -- NTP stores one-way delay in milliseconds.
    end
end
local function lookupEntity(id)
    if Game and Game.me and tostring(Game.me.eid) == tostring(id) then return Game.me end
    local manager = Game and Game.EntityManager
    for _, method in ipairs({ "getEntity", "getEntityWithBrief", "GetEntityByIntID" }) do
        if manager and type(manager[method]) == "function" then
            local ok, entity = pcall(manager[method], manager, id)
            if ok and entity then return entity end
        end
    end
end
local function deadState(entity)
    if not entity then return nil end
    if type(entity.IsDead) == "boolean" then return entity.IsDead end
    if type(entity.bIsDead) == "boolean" then return entity.bIsDead end
    local value = safeMethodResult(entity, "IsDead")
    if type(value) == "boolean" then return value end
end
local function observedPlayer(id, create)
    if id == nil then return nil end
    local key = tostring(id)
    local row = observations[key]
    if not row and create then
        if observationCount >= 256 then
            local oldestKey, oldest
            for candidate, value in pairs(observations) do
                if not knownPlayers[candidate] and (not oldest or value.seen < oldest) then oldestKey, oldest = candidate, value.seen end
            end
            if not oldestKey then return nil end
            observations[oldestKey] = nil
            observationCount = observationCount - 1
        end
        row = { effective = 0, over = 0, deaths = 0, seen = sequence }
        observations[key] = row
        observationCount = observationCount + 1
    end
    if row then row.seen = sequence end
    return row
end
local function registerPlayers(players)
    knownPlayers = {}
    for _, data in ipairs(players) do knownPlayers[tostring(data.id)] = true end
    for _, data in ipairs(players) do
        local entity = lookupEntity(data.id)
        local row = observedPlayer(data.id, entity ~= nil)
        local dead = deadState(entity)
        if row and dead ~= nil then
            if dead and row.dead == false then row.deaths = row.deaths + 1 end
            -- Keep lethal events latched until death and revival are confirmed.
            if dead then row.sawDead = true end
            if not row.eventDeath or dead or row.sawDead then
                row.dead = dead
                if not dead then row.eventDeath, row.sawDead = false, false end
            end
        end
    end
end
local function eventPlayer(id)
    local isSelf = Game and Game.me and tostring(Game.me.eid) == tostring(id)
    return observedPlayer(id, knownPlayers[tostring(id)] or isSelf)
end
local function observeHeal(attacker, total, real)
    if type(total) ~= "number" or type(real) ~= "number" or total ~= total or real ~= real
        or total < 0 or real < 0 or real > total or total == math.huge then return end
    local row = eventPlayer(attacker)
    if row then row.effective, row.over = row.effective + real, row.over + total - real end
end
local function observeDamage(defender, dead)
    local row = eventPlayer(defender)
    if not row then return end
    if dead == true or dead == 1 then
        if row.dead ~= true then row.deaths = row.deaths + 1 end
        row.dead, row.eventDeath = true, true
    elseif (dead == false or dead == 0) and deadState(lookupEntity(defender)) == false then
        row.dead, row.eventDeath, row.sawDead = false, false, false
    end
end
local function packResults(...) return { n = select("#", ...), ... } end
local function installCombatObservers(value, environment)
    local class = type(value) == "table" and rawget(value, "TakeDamageComponent")
        or type(environment) == "table" and rawget(environment, "TakeDamageComponent")
    if type(class) ~= "table" or rawget(class, "__cpddObservedCombatVersion") == VERSION then return value end
    local heal = class.OnMsgHealSyncV2
    if type(heal) == "function" then
        class.OnMsgHealSyncV2 = function(self, attacker, defender, ability, total, real, ...)
            local result = packResults(heal(self, attacker, defender, ability, total, real, ...))
            if healObserverReady then
                local ok, err = pcall(observeHeal, attacker, total, real)
                if not ok then healObserverReady = false; report("healing observer disabled: " .. tostring(err)) end
            end
            return unpack(result, 1, result.n)
        end
        healObserverReady = true
    end
    local damage = class.OnMsgDamageSyncV2
    if type(damage) == "function" then
        class.OnMsgDamageSyncV2 = function(self, attacker, defender, ability, method, damageType, total, shield, real, dead, ...)
            local result = packResults(damage(self, attacker, defender, ability, method, damageType, total, shield, real, dead, ...))
            if deathObserverReady then
                local ok, err = pcall(observeDamage, defender, dead)
                if not ok then deathObserverReady = false; report("death observer disabled: " .. tostring(err)) end
            end
            return unpack(result, 1, result.n)
        end
        deathObserverReady = true
    end
    class.__cpddObservedCombatVersion = VERSION
    return value
end

local function playerJson(system, data, skillRows, isSelf)
    local damageCrits, damageHits = metricPair(
        data, "crit", { "damageCritTimes", "critTimes" }, { "damageTimes", "hitTimes" }
    )
    local piercing, piercingTotal = metricPair(
        data, "pierce", { "spAtkDamage", "piercingDamage", "penetrationDamage" },
        { "damage", "damageTimes" }
    )
    local gearScore = playerGearScore(data, isSelf)
    local observed = observedPlayer(data and data.id, false)
    return table.concat({
        "{",
        '"id":', jsonString(data and data.id),
        ',"name":', jsonString(data and data.name),
        ',"team":', jsonString(data and data.team),
        ',"level":', jsonNumber(data and (data.level or data.lv)),
        ',"gear_score":', jsonNumber(gearScore),
        ',"profession":', jsonNumber(data and data.profession),
        ',"profession_name":', jsonString(professionName(data and data.profession)),
        ',"is_self":', isSelf and "true" or "false",
        ',"damage":', jsonNumber(data and data.damage),
        ',"healing":', jsonNumber(data and data.heal),
        ',"taken":', jsonNumber(data and data.bear),
        ',"duration":', jsonNumber(displayDuration(system, data)),
        ',"damage_crits":', jsonNumber(damageCrits),
        ',"damage_hits":', jsonNumber(damageHits),
        ',"damage_piercing":', jsonNumber(piercing),
        ',"damage_piercing_total":', jsonNumber(piercingTotal),
        ',"healing_crits":', jsonNumber(data and data.healCritTimes),
        ',"healing_hits":', jsonNumber(data and data.healTimes),
        ',"taken_crits":', jsonNumber(data and data.beDamageCritTimes),
        ',"taken_hits":', jsonNumber(data and data.beDamageTimes),
        ',"blocks":', jsonNumber(data and data.blockTimes),
        ',"hits":', jsonNumber(data and data.hitTimes),
        ',"misses":', jsonNumber(data and data.missTimes),
        ',"kills":', jsonNumber(data and data.killNum),
        ',"deaths":', optionalCounter(deathObserverReady and observed and observed.deaths or nil),
        ',"effective_healing":', optionalCounter(healObserverReady and observed and observed.effective or nil),
        ',"overhealing":', optionalCounter(healObserverReady and observed and observed.over or nil),
        ',"skills":[', table.concat(skillRows or {}, ","), "]",
        "}"
    })
end

local function skillName(system, sourceId)
    if system and type(system.GetCombatStatsSourceDisplayData) == "function" then
        local ok, _, name = pcall(
            system.GetCombatStatsSourceDisplayData,
            system,
            sourceId,
            true
        )
        if ok and name ~= nil and tostring(name) ~= "" then
            return tostring(name)
        end
    end
    return "Skill " .. tostring(sourceId)
end

local function collectSkills(system, playerData)
    if not playerData then
        return {}
    end

    local ids = {}
    local seen = {}
    for _, mapName in ipairs({ "skillDamage", "skillHeal", "skillCount" }) do
        for sourceId in pairs(playerData[mapName] or {}) do
            local key = tostring(sourceId)
            if not seen[key] then
                seen[key] = true
                ids[#ids + 1] = sourceId
            end
        end
    end
    table.sort(ids, function(a, b)
        local aValue = finiteNumber((playerData.skillDamage or {})[a])
            + finiteNumber((playerData.skillHeal or {})[a])
        local bValue = finiteNumber((playerData.skillDamage or {})[b])
            + finiteNumber((playerData.skillHeal or {})[b])
        return aValue > bValue
    end)

    local rows = {}
    for _, sourceId in ipairs(ids) do
        rows[#rows + 1] = table.concat({
            "{",
            '"id":', jsonString(sourceId),
            ',"name":', jsonString(skillName(system, sourceId)),
            ',"damage":', jsonNumber((playerData.skillDamage or {})[sourceId]),
            ',"healing":', jsonNumber((playerData.skillHeal or {})[sourceId]),
            ',"uses":', jsonNumber((playerData.skillCount or {})[sourceId]),
            "}"
        })
    end
    return rows
end

local function isPvpArena()
    local arena = Game and Game.TeamAreanaSystem
    return arena and type(arena.IsInTeamArena) == "function"
        and safeMethodResult(arena, "IsInTeamArena") == true
end

local function pvpModeLabel()
    local pvp = Game and Game.PVPSystem
    local matchType = pvp and type(pvp.GetGameModeType) == "function"
        and safeMethodResult(pvp, "GetGameModeType") or nil
    local matchTypes = Enum and Enum.EMatchTypeData
    if matchTypes and matchType == matchTypes.MATCH_TYPE_3V3 then
        return "3v3 PvP Match"
    elseif matchTypes and matchType == matchTypes.MATCH_TYPE_6V6 then
        return "6v6 PvP Match"
    elseif matchTypes and matchType == matchTypes.MATCH_TYPE_12V12 then
        return "12v12 PvP Match"
    end
    return "PvP Match"
end

local function unpackPvpMap(value)
    if type(value) == "table" then
        return value
    end
    local codec = _script and _script.cmsgpack
    if value ~= nil and codec and type(codec.unpack) == "function" then
        local ok, result = pcall(codec.unpack, value)
        if ok and type(result) == "table" then
            return result
        end
    end
    return {}
end

local function pvpValue(primary, fallback, keys)
    for _, key in ipairs(keys) do
        if primary and primary[key] ~= nil then
            return primary[key]
        end
    end
    for _, key in ipairs(keys) do
        if fallback and fallback[key] ~= nil then
            return fallback[key]
        end
    end
    return nil
end

local function normalizePvpPlayer(playerId, stats, member, duration, detail, team)
    stats = type(stats) == "table" and stats or {}
    member = type(member) == "table" and member or {}
    detail = type(detail) == "table" and detail or {}
    local combined = {}
    for key, value in pairs(member) do
        combined[key] = value
    end
    for key, value in pairs(stats) do
        combined[key] = value
    end
    -- The per-player response contains the authoritative skill, hit, critical,
    -- and piercing maps that are absent from the lightweight PvP scoreboard.
    for key, value in pairs(detail) do
        combined[key] = value
    end
    stats = combined
    member = {}
    local data = {}
    data.id = pvpValue(stats, member, { "ID", "Id", "id" }) or playerId
    data.name = pvpValue(stats, member, { "Name", "name" }) or tostring(data.id or "Player")
    data.team = team or ""
    data.level = pvpValue(stats, member, { "Level", "level", "Lv", "lv" })
    data.profession = pvpValue(stats, member, {
        "ProfessionID", "ProfessionId", "Profession", "profession"
    })
    data.gearScore = pvpValue(stats, member, {
        "ZhanLi", "zhanLi", "zhanli", "CEScore", "CeScore", "ceScore"
    })
    data.damage = pvpValue(stats, member, { "Damage", "damage" })
    data.heal = pvpValue(stats, member, { "Heal", "Healing", "heal" })
    data.bear = pvpValue(stats, member, { "Bear", "Taken", "bear" })
    data.battleLength = pvpValue(stats, member, {
        "BattleLength", "battleLength", "Duration", "duration"
    }) or duration
    data.damageCritTimes = pvpValue(detail, stats, {
        "DamageCritTimes", "damageCritTimes", "CritTimes", "critTimes"
    })
    data.damageTimes = pvpValue(detail, stats, {
        "DamageTimes", "damageTimes", "HitTimes", "hitTimes"
    })
    data.criticalHits = data.damageCritTimes
    data.totalHits = data.damageTimes
    data.critTimes = pvpValue(detail, stats, { "CritTimes", "critTimes" })
    data.hitTimes = pvpValue(detail, stats, { "HitTimes", "hitTimes" })
    data.healCritTimes = pvpValue(detail, stats, { "HealCritTimes", "healCritTimes" })
    data.healTimes = pvpValue(detail, stats, { "HealTimes", "healTimes" })
    data.beDamageCritTimes = pvpValue(detail, stats, {
        "BeDamageCritTimes", "beDamageCritTimes", "BeCritTimes", "beCritTimes"
    })
    data.beDamageTimes = pvpValue(detail, stats, {
        "BeDamageTimes", "beDamageTimes", "BeHitTimes", "beHitTimes"
    })
    data.spAtkDamage = pvpValue(detail, stats, { "SpAtkDamage", "spAtkDamage" })
    data.blockTimes = pvpValue(detail, stats, { "BlockTimes", "blockTimes" })
    data.blockedHits = pvpValue(detail, stats, {
        "blockedHits", "BlockedHits", "spAtkDamage", "SpAtkDamage"
    }) or data.blockTimes
    data.attackHits = pvpValue(detail, stats, {
        "attackHits", "AttackHits", "damageTimes", "DamageTimes"
    }) or data.damageTimes
    data.missTimes = pvpValue(detail, stats, { "MissTimes", "missTimes" })
    data.killNum = pvpValue(stats, member, { "KillNum", "Kills", "killNum" })
    data.skillDamage = unpackPvpMap(pvpValue(detail, stats, {
        "SkillDamage", "skillDamage"
    }))
    data.skillHeal = unpackPvpMap(pvpValue(detail, stats, { "SkillHeal", "skillHeal" }))
    data.skillCount = unpackPvpMap(pvpValue(detail, stats, {
        "SkillCount", "skillCount"
    }))
    return data
end

local function collectPvpPlayers(arena, battleStat, duration)
    local members = arena and arena.model and arena.model.memberMap or {}
    local statsById = {}
    local campById = {}
    local orderedIds = {}
    local seen = {}
    local selfId = Game and Game.me and Game.me.eid
    local selfMember = selfId and (members[selfId] or members[tostring(selfId)])
    local matchInfo = Game and Game.me and Game.me.PvpMatchInfo
    local selfCamp = type(selfMember) == "table"
        and (selfMember.CampID or selfMember.CampId or selfMember.campId)
        or type(matchInfo) == "table" and matchInfo.PvpMatchCampID
        or Game and Game.me and Game.me.occupyArenaGroupID

    local function add(playerId, stats, campId)
        if playerId == nil and type(stats) == "table" then
            playerId = stats.ID or stats.Id or stats.id
        end
        if playerId == nil then
            return
        end
        local key = tostring(playerId)
        if stats ~= nil then
            statsById[key] = stats
        end
        if campId ~= nil then
            campById[key] = campId
        end
        if not seen[key] then
            seen[key] = true
            orderedIds[#orderedIds + 1] = playerId
        end
    end

    for playerId, member in pairs(members or {}) do
        add(playerId, nil, type(member) == "table"
            and (member.CampID or member.CampId or member.campId) or nil)
    end

    local source = battleStat
    if type(source) == "table" and type(source.DetailInfo) == "table" then
        source = source.DetailInfo
    end
    for key, value in pairs(type(source) == "table" and source or {}) do
        local playerList = type(value) == "table" and (value.Members or value.avatarList)
        if type(playerList) == "table" then
            for _, player in pairs(playerList) do
                add(player.ID or player.id, player,
                    player.CampID or player.CampId or player.campId or key)
            end
        elseif type(value) == "table" and key ~= "CampExtraInfo" then
            add(value.ID or value.id or key, value,
                value.CampID or value.CampId or value.campId)
        end
    end

    local players = {}
    for _, playerId in ipairs(orderedIds) do
        local key = tostring(playerId)
        local member = members[playerId] or members[key]
        local campId = campById[key]
            or type(member) == "table" and (member.CampID or member.CampId or member.campId)
        local team = ""
        if selfId ~= nil and tostring(playerId) == tostring(selfId) then
            team = "ally"
        elseif selfCamp ~= nil and campId ~= nil then
            team = tostring(campId) == tostring(selfCamp) and "ally" or "enemy"
        end
        local data = normalizePvpPlayer(
            playerId,
            statsById[key],
            member,
            duration,
            pvpState.details[key],
            team
        )
        if data.id ~= nil then
            players[#players + 1] = data
        end
    end
    table.sort(players, playerSort)
    return players
end

local function beginPvpMatch()
    if pvpState.active then
        return
    end
    pvpState.active = true
    pvpState.duration = 0
    pvpState.startedAt = detailRequestClock()
    pvpState.key = "pvp-" .. tostring(math.floor(pvpState.startedAt * 1000))
    pvpState.label = pvpModeLabel()
    pvpState.latest = nil
    pvpState.details = {}
    pvpState.detailCursor = 0
    pvpState.detailRequestedAt = nil
    report("started " .. pvpState.label)
end

local function requestNextPvpPlayerDetail(arena)
    local sender = Game and Game.DungeonBattleStatisticsSystem
        and Game.DungeonBattleStatisticsSystem.sender
    local request = sender and sender.ReqCommonCombatStatistics
    if type(request) ~= "function" then
        return false
    end
    local now = detailRequestClock()
    if pvpState.detailRequestedAt ~= nil
        and now >= pvpState.detailRequestedAt
        and now - pvpState.detailRequestedAt < DETAIL_REQUEST_TIMEOUT
    then
        return false
    end
    pvpState.detailRequestedAt = nil
    local members = arena and arena.model and arena.model.memberMap or {}
    local playerIds = {}
    for playerId in pairs(members) do
        playerIds[#playerIds + 1] = playerId
    end
    if #playerIds == 0 then
        return false
    end
    table.sort(playerIds, function(a, b)
        return tostring(a) < tostring(b)
    end)
    pvpState.detailCursor = pvpState.detailCursor % #playerIds + 1
    local ok = pcall(request, sender, playerIds[pvpState.detailCursor])
    if ok then
        pvpState.detailRequestedAt = now
    end
    return ok
end

local function updatePvpDuration()
    if pvpState.active and pvpState.startedAt then
        pvpState.duration = math.max(0, detailRequestClock() - pvpState.startedAt)
    end
    return pvpState.duration
end

local function buildPvpSnapshot(arena, battleStat, inCombat)
    local duration = updatePvpDuration()
    local players = collectPvpPlayers(arena, battleStat or pvpState.latest, duration)
    registerPlayers(players)
    local playerRows = {}
    local selfSkillRows = {}
    local selfId = Game and Game.me and Game.me.eid
    local statisticsSystem = Game and Game.DungeonBattleStatisticsSystem
    for _, data in ipairs(players) do
        local skillRows = collectSkills(statisticsSystem, data)
        local isSelf = selfId ~= nil and tostring(data.id) == tostring(selfId)
        playerRows[#playerRows + 1] = playerJson(
            statisticsSystem, data, skillRows, isSelf
        )
        if isSelf then
            selfSkillRows = skillRows
        end
    end
    sequence = sequence + 1
    return table.concat({
        "{",
        '"schema_version":2',
        ',"sequence":', tostring(sequence),
        ',"in_combat":', inCombat and "true" or "false",
        ',"target_id":', jsonString(pvpState.key),
        ',"target_name":', jsonString(pvpState.label),
        ',"target_level":null',
        ',"ping_ms":', optionalCounter(pingMs()),
        ',"players":[', table.concat(playerRows, ","), "]",
        ',"self_skills":[', table.concat(selfSkillRows, ","), "]",
        "}\n"
    })
end

local function buildSnapshot(system)
    local current = type(system.GetCurStat) == "function" and system:GetCurStat() or nil
    local players = {}
    for _, data in pairs(current and current.PlayersData or {}) do
        if type(data) == "table" and data.id ~= nil then
            players[#players + 1] = data
        end
    end
    table.sort(players, playerSort)

    registerPlayers(players)
    local playerRows = {}
    local selfSkillRows = {}
    local selfId = Game and Game.me and Game.me.eid
    for _, data in ipairs(players) do
        local skillRows = collectSkills(system, data)
        local isSelf = selfId ~= nil and data.id == selfId
        playerRows[#playerRows + 1] = playerJson(system, data, skillRows, isSelf)
        if isSelf then
            selfSkillRows = skillRows
        end
    end
    local targetId, targetName, targetLevel = currentTarget(system, current)
    sequence = sequence + 1
    local inCombat = Game and Game.me and Game.me.InBattle == true
    return table.concat({
        "{",
        '"schema_version":2',
        ',"sequence":', tostring(sequence),
        ',"in_combat":', inCombat and "true" or "false",
        ',"target_id":', jsonString(targetId),
        ',"target_name":', jsonString(targetName),
        ',"target_level":', optionalCounter(targetLevel),
        ',"ping_ms":', optionalCounter(pingMs()),
        ',"players":[', table.concat(playerRows, ","), "]",
        ',"self_skills":[', table.concat(selfSkillRows, ","), "]",
        "}\n"
    })
end

local function saveSnapshot(snapshot)
    local path = getOutputPath()
    if not path then
        return false
    end
    local ok, library = pcall(import, "LuaFunctionLibrary")
    if not ok or not library or type(library.SaveStringContentToFile) ~= "function" then
        return false
    end
    local saved, result = pcall(library.SaveStringContentToFile, snapshot, path)
    return saved and result ~= false
end

local function writeSnapshot(system)
    local built, snapshot = pcall(buildSnapshot, system)
    if not built then
        report("snapshot build failed: " .. tostring(snapshot))
        return false
    end
    return saveSnapshot(snapshot)
end

local function writePvpSnapshot(arena, battleStat, inCombat)
    local built, snapshot = pcall(buildPvpSnapshot, arena, battleStat, inCombat)
    if not built then
        report("PvP snapshot build failed: " .. tostring(snapshot))
        return false
    end
    return saveSnapshot(snapshot)
end

local function requestNextPlayerDetail(system, current)
    local sender = system and system.sender
    local request = sender and sender.ReqCommonCombatStatistics
    if type(request) ~= "function" then
        return false
    end

    local now = detailRequestClock()
    if system.bPlayerDetailRequestPending then
        local requestedAt = tonumber(system.__cpddExternalDetailRequestedAt)
        if requestedAt and now >= requestedAt and now - requestedAt < DETAIL_REQUEST_TIMEOUT then
            return false
        end
        system.bPlayerDetailRequestPending = false
        system.__cpddExternalDetailRequestedAt = nil
        report("retrying a timed-out party detail request")
    end

    local playerIds = {}
    for _, data in pairs(current and current.PlayersData or {}) do
        if type(data) == "table" and data.id ~= nil then
            local activity = finiteNumber(data.damage) + finiteNumber(data.heal)
                + finiteNumber(data.bear)
            if activity > 0 then
                playerIds[#playerIds + 1] = data.id
            end
        end
    end
    if #playerIds == 0 then
        return false
    end
    table.sort(playerIds, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local cursor = (tonumber(system.__cpddExternalDetailCursor) or 0) % #playerIds + 1
    system.__cpddExternalDetailCursor = cursor
    system.bPlayerDetailRequestPending = true
    system.__cpddExternalDetailRequestedAt = now
    local ok = pcall(request, sender, playerIds[cursor])
    if not ok then
        system.bPlayerDetailRequestPending = false
        system.__cpddExternalDetailRequestedAt = nil
        return false
    end
    return true
end

local function installSystemClass(class)
    if type(class) ~= "table" or rawget(class, "__cpddExternalTelemetryVersion") == VERSION then
        return false
    end
    local originalAfterPlayerInit = rawget(class, "AfterPlayerInit")
    local originalUnInit = rawget(class, "onUnInit")
    local originalReqPlayerDetail = rawget(class, "ReqPlayerCombatStatInfo")
    local originalPlayerDetailLoaded = rawget(class, "OnSelfPlayerDetailLoaded")
    local originalResetSelfDetailState = rawget(class, "ResetSelfDetailState")

    if type(originalReqPlayerDetail) == "function" then
        class.ReqPlayerCombatStatInfo = function(self, ...)
            local now = detailRequestClock()
            if self.bPlayerDetailRequestPending then
                local requestedAt = tonumber(self.__cpddExternalDetailRequestedAt)
                if requestedAt == nil then
                    self.__cpddExternalDetailRequestedAt = now
                elseif now < requestedAt or now - requestedAt >= DETAIL_REQUEST_TIMEOUT then
                    self.bPlayerDetailRequestPending = false
                    self.__cpddExternalDetailRequestedAt = nil
                    report("retrying a timed-out detailed statistics request")
                end
            end
            local wasPending = self.bPlayerDetailRequestPending == true
            local results = { originalReqPlayerDetail(self, ...) }
            if not wasPending and self.bPlayerDetailRequestPending then
                self.__cpddExternalDetailRequestedAt = now
            end
            return unpackValues(results)
        end
    end

    if type(originalPlayerDetailLoaded) == "function" then
        class.OnSelfPlayerDetailLoaded = function(self, ...)
            self.__cpddExternalDetailRequestedAt = nil
            return originalPlayerDetailLoaded(self, ...)
        end
    end

    if type(originalResetSelfDetailState) == "function" then
        class.ResetSelfDetailState = function(self, ...)
            self.__cpddExternalDetailRequestedAt = nil
            return originalResetSelfDetailState(self, ...)
        end
    end

    function class:__cpddExternalTelemetryTick()
        if isPvpArena() then
            return
        end
        local current = type(self.GetCurStat) == "function" and self:GetCurStat() or nil
        local hasPlayers = current and current.PlayersData and next(current.PlayersData) ~= nil
        if hasPlayers and type(self.ReqDirtyCombatStatInfo) == "function" then
            self:ReqDirtyCombatStatInfo()
        elseif type(self.ReqTeamCombatStatInfo) == "function" then
            self:ReqTeamCombatStatInfo()
        end
        requestNextPlayerDetail(self, current)
        writeSnapshot(self)
    end

    function class:__cpddStartExternalTelemetry(restart)
        if restart and self.__cpddExternalTelemetryTimer ~= nil then
            if type(self.DelTimer) == "function" then self:DelTimer(self.__cpddExternalTelemetryTimer) end
            self.__cpddExternalTelemetryTimer = nil
        end
        if self.__cpddExternalTelemetryTimer == nil and type(self.AddTimer) == "function" then
            self.__cpddExternalTelemetryTimer = self:AddTimer(
                UPDATE_SECONDS,
                -1,
                "__cpddExternalTelemetryTick"
            )
        end
        self:__cpddExternalTelemetryTick()
    end

    if type(originalAfterPlayerInit) == "function" then
        class.AfterPlayerInit = function(self, ...)
            local results = { originalAfterPlayerInit(self, ...) }
            self:__cpddStartExternalTelemetry(true)
            local arena = Game and Game.TeamAreanaSystem
            if arena and type(arena.__cpddStartPvpTelemetry) == "function" then arena:__cpddStartPvpTelemetry(true) end
            return unpackValues(results)
        end
    end

    class.onUnInit = function(self, ...)
        if self.__cpddExternalTelemetryTimer ~= nil and type(self.DelTimer) == "function" then
            self:DelTimer(self.__cpddExternalTelemetryTimer)
            self.__cpddExternalTelemetryTimer = nil
        end
        if type(originalUnInit) == "function" then
            return originalUnInit(self, ...)
        end
    end

    class.__cpddExternalTelemetryVersion = VERSION
    report("installed external combat telemetry exporter v" .. VERSION)
    return true
end

local function installArenaClass(class)
    if type(class) ~= "table" or rawget(class, "__cpddPvpTelemetryVersion") == VERSION then
        return false
    end
    local originalInit = rawget(class, "onInit")
    local originalUnInit = rawget(class, "onUnInit")
    local originalStatusUpdate = rawget(class, "OnUpdateTeamArenaStatus")

    function class:__cpddOnPvpBattleStat(battleStat)
        if not isPvpArena() then
            return
        end
        pvpState.latest = battleStat
    end

    function class:__cpddOnPvpPlayerDetail(playerCombatStat)
        if not isPvpArena() or type(playerCombatStat) ~= "table" then
            return
        end
        local playerId = playerCombatStat.id or playerCombatStat.ID or playerCombatStat.Id
        if playerId == nil then
            return
        end
        pvpState.details[tostring(playerId)] = playerCombatStat
        pvpState.detailRequestedAt = nil
    end

    function class:__cpddPvpTelemetryTick()
        if not isPvpArena() then
            return
        end
        local inBattle = type(self.IsInBattleStatus) == "function"
            and safeMethodResult(self, "IsInBattleStatus") == true
        if inBattle then
            beginPvpMatch()
            local pvp = Game and Game.PVPSystem
            local matchType = pvp and type(pvp.GetGameModeType) == "function"
                and safeMethodResult(pvp, "GetGameModeType") or nil
            local matchTypes = Enum and Enum.EMatchTypeData
            if matchTypes and matchType == matchTypes.MATCH_TYPE_12V12
                and pvp and pvp.sender
                and type(pvp.sender.ReqGetGroupOccupyBattleInfo) == "function"
            then
                pcall(pvp.sender.ReqGetGroupOccupyBattleInfo, pvp.sender)
            elseif self.sender and type(self.sender.GetTeamArenaBattleStat) == "function" then
                pcall(self.sender.GetTeamArenaBattleStat, self.sender)
            end
            requestNextPvpPlayerDetail(self)
        end
        -- CALC may begin before the settlement payload arrives. Keep the match
        -- active until OnTeamArenaRoundCalcMsg supplies the authoritative totals.
        writePvpSnapshot(self, pvpState.latest, pvpState.active)
    end

    function class:__cpddStartPvpTelemetry(restart, deferTick)
        if restart and self.__cpddPvpTelemetryTimer ~= nil then
            if type(self.DelTimer) == "function" then self:DelTimer(self.__cpddPvpTelemetryTimer) end
            self.__cpddPvpTelemetryTimer = nil
        end
        if not self.__cpddPvpTelemetryListening and Game and Game.GlobalEventSystem
            and EEventTypesV2 and EEventTypesV2.TEAM_ARENA_RECEIVE_BATTLE_STAT
        then
            Game.GlobalEventSystem:AddListener(
                EEventTypesV2.TEAM_ARENA_RECEIVE_BATTLE_STAT,
                "__cpddOnPvpBattleStat",
                self
            )
            self.__cpddPvpTelemetryListening = true
        end
        if not self.__cpddPvpDetailListening and Game and Game.GlobalEventSystem
            and EEventTypesV2 and EEventTypesV2.ON_RECV_PLAYER_DETAIL_STAT
        then
            Game.GlobalEventSystem:AddListener(
                EEventTypesV2.ON_RECV_PLAYER_DETAIL_STAT,
                "__cpddOnPvpPlayerDetail",
                self
            )
            self.__cpddPvpDetailListening = true
        end
        if self.__cpddPvpTelemetryTimer == nil and type(self.AddTimer) == "function" then
            self.__cpddPvpTelemetryTimer = self:AddTimer(
                UPDATE_SECONDS,
                -1,
                "__cpddPvpTelemetryTick"
            )
        end
        if not deferTick then self:__cpddPvpTelemetryTick() end
    end

    if type(originalInit) == "function" then
        class.onInit = function(self, ...)
            local results = { originalInit(self, ...) }
            self:__cpddStartPvpTelemetry(true)
            return unpackValues(results)
        end
    end

    if type(originalStatusUpdate) == "function" then
        class.OnUpdateTeamArenaStatus = function(self, ...)
            local results = { originalStatusUpdate(self, ...) }
            self:__cpddStartPvpTelemetry(true, true)
            if type(self.IsInBattleStatus) == "function"
                and safeMethodResult(self, "IsInBattleStatus") == true
            then
                beginPvpMatch()
                writePvpSnapshot(self, pvpState.latest, true)
            end
            return unpackValues(results)
        end
    end

    class.onUnInit = function(self, ...)
        if self.__cpddPvpTelemetryTimer ~= nil and type(self.DelTimer) == "function" then
            self:DelTimer(self.__cpddPvpTelemetryTimer)
            self.__cpddPvpTelemetryTimer = nil
        end
        if isPvpArena() and (pvpState.active or pvpState.latest) then
            updatePvpDuration()
            pvpState.active = false
            writePvpSnapshot(self, pvpState.latest, false)
        end
        if type(originalUnInit) == "function" then
            return originalUnInit(self, ...)
        end
    end

    class.__cpddPvpTelemetryVersion = VERSION
    report("installed PvP match telemetry exporter v" .. VERSION)
    return true
end

local function installPvpSystemClass(class)
    if type(class) ~= "table" or rawget(class, "__cpddPvpSettlementVersion") == VERSION then
        return false
    end
    local originalRoundCalc = rawget(class, "OnTeamArenaRoundCalcMsg")
    if type(originalRoundCalc) == "function" then
        class.OnTeamArenaRoundCalcMsg = function(self, battleResult, ...)
            if isPvpArena() then
                if not pvpState.active then
                    beginPvpMatch()
                end
                updatePvpDuration()
                pvpState.latest = battleResult
            end
            local results = { originalRoundCalc(self, battleResult, ...) }
            if isPvpArena() and pvpState.latest then
                pvpState.active = false
                writePvpSnapshot(Game.TeamAreanaSystem, battleResult, false)
                report("finished " .. pvpState.label)
            end
            return unpackValues(results)
        end
    end
    class.__cpddPvpSettlementVersion = VERSION
    return true
end

local function installSystem(value, environment)
    installSystemClass(
        type(value) == "table" and rawget(value, "DungeonBattleStatisticsSystem")
            or type(environment) == "table" and rawget(environment, "DungeonBattleStatisticsSystem")
    )
    local system = Game and Game.DungeonBattleStatisticsSystem
    if system and type(system.__cpddStartExternalTelemetry) == "function" then
        system:__cpddStartExternalTelemetry()
    end
    return value
end

local function installArenaSystem(value, environment)
    installArenaClass(
        type(value) == "table" and rawget(value, "TeamAreanaSystem")
            or type(environment) == "table" and rawget(environment, "TeamAreanaSystem")
    )
    local arena = Game and Game.TeamAreanaSystem
    if arena and type(arena.__cpddStartPvpTelemetry) == "function" then
        arena:__cpddStartPvpTelemetry()
    end
    return value
end

local function installPvpSystem(value, environment)
    installPvpSystemClass(
        type(value) == "table" and rawget(value, "PVPSystem")
            or type(environment) == "table" and rawget(environment, "PVPSystem")
    )
    return value
end

Loader.AfterLoad(
    "Gameplay.LogicSystem.DungeonBattleStatistics.DungeonBattleStatisticsSystem",
    installSystem,
    1000000,
    "cpdd.external-dps.telemetry"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.TeamArena.TeamAreanaSystem",
    installArenaSystem,
    1000000,
    "cpdd.external-dps.pvp-arena"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.PVP.PVPSystem",
    installPvpSystem,
    1000000,
    "cpdd.external-dps.pvp-settlement"
)

Loader.AfterLoad("Gameplay.NetEntities.Comps.TakeDamageComponent", installCombatObservers, 1000000, "cpdd.external-dps.observed-combat")

Loader.On("after_main", function()
    local system = Game and Game.DungeonBattleStatisticsSystem
    if system and type(system.__cpddStartExternalTelemetry) == "function" then
        system:__cpddStartExternalTelemetry()
    end
    local arena = Game and Game.TeamAreanaSystem
    if arena and type(arena.__cpddStartPvpTelemetry) == "function" then
        arena:__cpddStartPvpTelemetry()
    end
end, 1000000, "cpdd.external-dps.after-main")

report("registered v" .. VERSION)
return {
    Version = VERSION,
    BuildSnapshot = buildSnapshot,
    BuildPvpSnapshot = buildPvpSnapshot,
    OutputFile = OUTPUT_FILE,
}

-- exact-current-source-v1: generated from a pinned baseline; no ID-based translation.
local Loader = assert(LOMModLoader, "LOMModLoader is required")

local VERSION = "0.9.72"
local CIRCUIT_BREAKER_TIPS_ID = 6427242
local CIRCUIT_BREAKER_TEXT = "If the server is too crowded, it will enter a circuit-breaker state, temporarily preventing new accounts that have not created a character on the current server from queuing. Please choose another server that is not under a circuit-breaker to experience the game."

-- Production performance mode keeps warnings and errors while removing the
-- release/info traffic emitted from hot gameplay paths. It also disables the
-- packaged large-allocation diagnostic check without changing rendering or
-- gameplay behavior. Set PerformanceMode=false in cpdd_user_settings.lua to
-- restore the game's defaults on the next launch.
(function()
    Loader.Telemetry = Loader.Telemetry or {}
    local function applyPerformanceMode(stage)
        if type(Loader.Features) == "table" and Loader.Features.PerformanceMode == false then
            Loader.Telemetry.PerformanceMode = { Disabled = true, Stage = stage }
            Loader.Telemetry.PerformanceModeApplied = false
            return false
        end
        local results = {
            Stage = stage,
            NativeLogLevel = false,
            LogCategories = 0,
            LargeAllocationChecks = false,
        }
        local warningLevel = 5
        -- Unreal-backed globals can be exposed through the module environment's
        -- __index path. Normal lookup is required; rawget(_G, ...) silently
        -- misses them in the shipping runtime.
        local levels = LogLevel
        if type(levels) == "table" and tonumber(levels.Warning) ~= nil then
            warningLevel = tonumber(levels.Warning)
        end

        local gameLog = Log
        if type(gameLog) == "table" then
            gameLog.Level = warningLevel
        end
        local nativeLogger = LuaCLogger
        if nativeLogger ~= nil and type(nativeLogger.SetGameLogLevel) == "function" then
            results.NativeLogLevel = pcall(nativeLogger.SetGameLogLevel, warningLevel)
        end

        local context = nil
        local getContext = GetContextObject
        if type(getContext) == "function" then
            local contextOk, contextValue = pcall(getContext)
            if contextOk then context = contextValue end
        end
        local systemOk, systemLibrary = pcall(import, "KismetSystemLibrary")
        local execute = systemOk and systemLibrary and systemLibrary.ExecuteConsoleCommand
        if type(execute) == "function" then
            for _, category in ipairs({
                "LuaLog",
                "UBaseAnimInstanceLog",
                "LogFaceControlComponent",
                "RoleCompositeMgrLog",
            }) do
                if pcall(execute, context, "Log " .. category .. " Warning", nil) then
                    results.LogCategories = results.LogCategories + 1
                end
            end
        end

        local libraryOk, library = pcall(import, "LuaFunctionLibrary")
        local intSetter = libraryOk and library and (
            library.ChangeConsoleVariableOfIntWithCurrentPriority
            or library.ChangeConsoleVariableOfInt
        )
        if type(intSetter) == "function" then
            results.LargeAllocationChecks = pcall(
                intSetter,
                "memory.EnableLargeAllocationChecks",
                0
            )
        end
        Loader.Telemetry.PerformanceMode = results
        Loader.Telemetry.PerformanceModeApplied = results.NativeLogLevel
        return results.NativeLogLevel
    end

    applyPerformanceMode("module")
    if type(Loader.On) == "function" then
        Loader.On("after_main", function()
            if applyPerformanceMode("after_main") then
                local nativeLogger = LuaCLogger
                if nativeLogger ~= nil and type(nativeLogger.Warning) == "function" then
                    pcall(
                        nativeLogger.Warning,
                        "[CPDDPerformance] active: release logs suppressed; diagnostics disabled"
                    )
                end
            end
        end, 2000000, "cpdd.runtime-fix.performance-mode")
    end
end)()

local visibleTextExactOverrides = {
    ["命运道标"] = "Bacon of Destiny",
    ["“正义”和“倒吊人”开始默写记忆中的文字……"] = "\"Justice\" and \"The Hanged Man\" begin writing down the words from memory...",
    ["两位先生离开了，不知何时才能看到这充满风采的照片……"] = "The two gentlemen have left. Who knows when I'll get to see this splendid photograph...",
    ["机动"] = "Mobility",
    ["射程"] = "Range",
    ["在<h>【附近】/【世界】</>聊天栏中打字输入“<HyperLink stylename=\"h\">风暴比烈酒更烈</>”"] = "Type \"<HyperLink stylename=\"h\">风暴比烈酒更烈</>\" in the <h>[Nearby]/[World]</> chat bar",
    ["所向披靡，无往不利！{{player.name}}在<Chat_Highlight>{{gameMode.name}}</>中获得<Chat_Highlight>{{eventMessageParams.curWinStreak}}连胜</>，战场之上，新的神话已在书写！"] = "Invincible and unstoppable! {{player.name}} has achieved a <Chat_Highlight>{{eventMessageParams.curWinStreak}} win streak</> in <Chat_Highlight>{{gameMode.name}}</>! On the battlefield, a new legend is being written!",
    ["推理检定"] = "Deduction Check",
    ["发现它变成了一份地图，还标注了奇迹降临的位置……"] = "You discover it has become a map, marking the location where the miracle will occur...",
    ["沙利亚特"] = "Sariat",
    ["迪尼特"] = "Dinit",
    ["罗、罗茜！你今天过得好吗？"] = "R-Rosie! How are you today?",
    ["罗、罗茜！你今天过得好吗?"] = "R-Rosie! How are you today?",
    ["啊，弗雷泽！我很好，这束花是……"] = "Oh, Frazier! I'm doing well. Is that bouquet...?",
    ["啊，弗雷泽！我很好，这束花是......"] = "Oh, Frazier! I'm doing well. Is that bouquet...?",
    ["啊，弗雷泽！我很好，这束花是..."] = "Oh, Frazier! I'm doing well. Is that bouquet...?",
    ["我想把它送给你，其实，我对你……"] = "I wanted to give it to you. Actually, I...",
    ["我想把它送给你，其实，我对你......"] = "I wanted to give it to you. Actually, I...",
    ["我想把它送给你，其实，我对你..."] = "I wanted to give it to you. Actually, I...",
    ["跳过"] = "Skip",
    ["回顾"] = "Review",
    ["截图"] = "Screenshot",
    ["点击空白区域关闭"] = "Click blank area to close",
    ["点击任意区域跳过"] = "Click anywhere to skip",
    ["恭喜获得"] = "Congratulations",
    ["转化"] = "Convert",
    ["男子"] = "Man",
    ["丑人"] = "Ugly Man",
    ["愚者"] = "The Fool",
    ["“愚者”"] = "\"The Fool\"",
    ["塞巴斯蒂安"] = "Sebastian",
    ["寒巴斯蒂安"] = "Sebastian",
    ["非凡评分"] = "Beyonder Rating",
    ["再战·一号信徒"] = "Rematch: Believer Number One",
    ["推荐非凡评分"] = "Recommended Beyonder Rating",
    ["奖励预览"] = "Reward Preview",
    ["目标点数"] = "Target Score",
    ["黎明降临"] = "Dawn Arrival",
    ["仲裁烙印"] = "Arbitration Brand",
    ["窥秘凝视"] = "Mystery Pry Gaze",
    ["晨曦守护"] = "Morning Light Protection",
    ["骑士誓约"] = "Knight's Oath",
    ["蝶灵附身"] = "Butterfly Spirit Possession",
    ["丧钟回响"] = "Death Knell Echo",
    ["头狼连爪"] = "Alpha Wolf Claw Combo",
    ["钻头守护"] = "Drill Protection",
    ["未拥有"] = "Not Owned",
    ["推荐方案"] = "Recommended Builds",
    ["官方推荐方案"] = "Official Recommended Build",
    ["我的方案"] = "My Builds",
    ["我要变强"] = "Improve",
    ["要变强"] = "Improve",
    ["已领取"] = "Claimed",
    ["今日已领取"] = "Claimed Today",
    ["奖励已领取"] = "Reward Claimed",
    ["已领取全部奖励"] = "All Rewards Claimed",
    ["使用"] = "Use",
    ["使用中"] = "In Use",
    ["图鉴"] = "Codex",
    ["跟随卡萝，来到了工厂区。"] = "Follow Carol to the Factory District.",
    ["全部重置"] = "Reset All",
    ["装备方案"] = "Equipment Builds",
    ["自动分解"] = "Auto-Dismantle",
    ["获得方式"] = "How to Obtain",
    ["下一级效果"] = "Next-Level Effect",
    ["在目标位置召唤窥秘之眼，对目标造成持续伤害和减速。"] = "Summon an Eye of Mystery at the target location, dealing continuous damage and slowing the target.",
    ["感知灵界，观测星空，通过灵性物品启示的命运变化，解读其映射的现实空间异动、事态发展走向与潜在未知危险。"] = "Sense the spirit world and observe the stars. Interpret the changes in fate revealed by spiritual items to discern the real-world disturbances they reflect, how events may unfold, and potential unknown dangers.",
    ["占星启示期间，周围的玩家可以获得临时技能来获取占星指引。"] = "During Astrological Revelation, nearby players can gain a temporary skill to receive astrological guidance.",
    ["使自身获得武力加4，直觉加2。使用临时技能获取占星指引的玩家也可以获得武力加4，直觉加2。"] = "Gain +4 Might and +2 Intuition. Players who use the temporary skill to receive astrological guidance also gain +4 Might and +2 Intuition.",
    ["木桩训练"] = "Training Dummy",
    ["一键辅助"] = "One-Click Assist",
    ["家族任务"] = "Family Quests",
    ["你尚未加入任何家族"] = "You haven't joined a Family.",
    ["[队伍]"] = "[Team]",
    ["【附身能力】"] = "[Possession Ability]",
    ["请选择要使用【灵体之线】的对象"] = "Select a target for [Spirit Body Threads]",
    ["附身剩余时间"] = "Possession Time Remaining",
    ["秘偶属性生效总览"] = "Marionette Attribute Effects Overview",
    ["本频道可用传音发言"] = "Broadcasts can be sent in this channel",
    ["本频道无法发言"] = "You cannot speak in this channel",
    ["但我们的数据——"] = "But our data—",
    ["哼唧！哼唧……"] = "Oink! Oink...",
    ["嗯……都行。"] = "Hmm... anything's fine.",
    ["坏了，我可能把<P_Yellow>生物催长剂</>当成椰蓉洒在蛋糕上了！"] = "Oh no, I may have sprinkled the <P_Yellow>bio-growth stimulant</> on the cake instead of shredded coconut!",
    ["培根……你真是救我于水火啊……"] = "Bacon... you really saved me...",
    ["培根……培根怎么回事？？"] = "Bacon... what's wrong with Bacon??",
    ["太好了！拿到数据了！"] = "Great! We got the data!",
    ["好了。下次再来！"] = "There you go. Come again!",
    ["情况有点失控了！跑啊！"] = "This is getting out of control! Run!",
    ["第一次来吗？要什么口味？"] = "First time here? What flavor would you like?",
    ["等下我就买一大堆小蛋糕给你！"] = "I'll buy you a whole bunch of cupcakes later!",
    ["那就给你最经典的那种吧。"] = "Then I'll give you the classic one.",
    ["霍伊大学赛艇队招新！"] = "Hoy University Rowing Team is recruiting!",
    ["成员列表"] = "Member List",
    ["俱乐部会长"] = "Club President",
    ["正式成员"] = "Full Member",
    ["候补成员"] = "Reserve Member",
    ["可预存"] = "Can Pre-store",
    ["已预存"] = "Pre-stored",
    ["新手"] = "Beginner",
    ["赛季剧情"] = "Season Story",
    ["提交可获得猎杀进度"] = "Submit to earn Hunt Progress",
    ["可获得猎杀进度"] = "Earn Hunt Progress",
    ["当前进度："] = "Current Progress:",
    ["当前进度:"] = "Current Progress:",
    ["击杀"] = "Kills",
    ["助攻"] = "Assists",
    ["排行榜"] = "Leaderboard",
    ["技能名称"] = "Skill Name",
    ["次数"] = "Count",
    ["伤害量"] = "Damage",
    ["伤害来源"] = "Damage Source",
    ["寄售"] = "Consignment",
    ["终末猎杀"] = "Final Hunt",
    ["主宰争锋"] = "Dominator's Clash",
    ["主宰之战"] = "Dominator's Clash",
    ["副本"] = "Dungeon",
    ["秩序世界"] = "World of Order",
    ["本周获取上限"] = "Weekly Limit",
    ["城市暗面"] = "Dark City",
    ["新"] = "New",
    ["同家族/俱乐部队员达到3人及以上"] = "3+ Party Members From the Same Family/Club",
    ["对比"] = "Compare",
    ["进攻模式·PVP"] = "Offensive Mode · PvP",
    ["随机获得2-4个词条"] = "Grants 2-4 Random Affixes",
    ["神圣之杖"] = "Holy Staff",
    ["线索"] = "Clue",
    ["组队跟随中..."] = "Following Party...",
    ["组队跟随中…"] = "Following Party...",
    ["你在廷根的集体意识中失去了形态，意识正在退回现实..."] = "You lost form within Tingen's collective consciousness. Your consciousness is returning to reality...",
    ["界面返回"] = "Back",
    ["灵体之线玩法"] = "Spirit Body Threads",
    ["廷根第一市民"] = "Tingen's First Citizen",
    ["[封]"] = "[Sealed]",
    ["狂袭式"] = "Frenzied Assault",
    ["廷根守墓人"] = "Tingen Gravekeeper",
    ["机器加工厂坊"] = "Machine Processing Workshop",
    ["非凡材料每有1条词条格挡 +200"] = "Each Beyonder Material affix grants Block +200",
    ["总探索度"] = "Total Exploration",
    ["上限可累计至下周"] = "Unused Limit Carries Over to Next Week",
    ["安迪哥努斯笔记"] = "Antigonus Notebook",
    ["首通队伍"] = "First-Clear Team",
    ["男子：（癫狂）万物的“母亲”，赐予我们新生！"] = "Man: (Manically) \"Mother\" of all things, grant us rebirth!",
    ["“愚者”：拿上这个。"] = "\"The Fool\": Take this.",
    ["丑人：（有效期十四年？为什么要签这么久的合同……）"] = "Ugly Man: (Valid for fourteen years? Why would I need to sign such a long contract...)",
    ["弗莱"] = "Frye",
    ["伦纳德"] = "Leonard",
    ["罗珊"] = "Rozanne",
    ["没有太大危险了，不用特别在意。"] = "There's no real danger anymore, so you don't need to worry.",
    ["罗珊小姐，这个铃铛是用来做什么的？"] = "Miss Rozanne, what is this bell for?",
    ["三律之背反"] = "Antinomy of the Three Laws",
    ["镜像之自我"] = "Mirrored Self",
    ["技能增强提高<Mark>30</>。"] = "Skill Enhancement increased by <Mark>30</>.",
    ["技能增强提高<Mark>30</>。\n激活套装<Mark>灵与知回响</>时不生效。"] = "Skill Enhancement increased by <Mark>30</>.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    ["<CostRed>{1,2,（烙印已失效）}</>技能增强提高<Mark>30</>。\n激活套装<Mark>灵与知回响</>时不生效。"] = "<CostRed>{1,2,(Brand inactive)}</>Skill Enhancement increased by <Mark>30</>.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    ["技能增强提高30。\n激活套装灵与知回响时不生效。"] = "Skill Enhancement increased by 30.\nDoes not take effect while the Echo of Spirit and Knowledge set is active.",
}
visibleTextExactOverrides["破甲"] = "Armor Break"
visibleTextExactOverrides["破防"] = "Defense Break"
visibleTextExactOverrides["物理破防"] = "Physical Defense Break"
visibleTextExactOverrides["魔法破防"] = "Magic Defense Break"
local bit = require("bit")

local function sourceKey(value)
    local hash = bit.tobit(2166136261)
    for index = 1, #value do
        hash = bit.bxor(hash, value:byte(index))
        hash = bit.tobit(
            hash
            + bit.lshift(hash, 1)
            + bit.lshift(hash, 4)
            + bit.lshift(hash, 7)
            + bit.lshift(hash, 8)
            + bit.lshift(hash, 24)
        )
    end
    return tostring(#value) .. ":" .. bit.tohex(hash)
end
local generatedRowRepairAllowlist = {
    -- Translate narration before the black/white screen component sets its text.
    "GetDialogueBlackScreenTextRow",
    -- Rank badges read Name again on every refresh, replacing baked defaults.
    "GetTrinityRankNameDataRow",
    "GetMilitaryDataRow",
    "GetGossipGroupDataRow",
    "GetGossipDataRow",
    "GetBubbleDataRow",
    "GetNoCameraDialogueGossipDataRow",
    "GetSkillDataNewRow",
    "GetBuffDataNewRow",
    "GetFellowDataRow",
    "GetStringConstDataRow",
    "GetTextControlSentenceDataRow",
    "GetItemNewDataRow",
    "GetEquipmentUniqueDataRow",
    "GetEquipmentMythDataRow",
    "GetEquipmentSuitDataRow",
    "GetEquipmentSpiritualityConvergenceDataRow",
    "GetEquipWordAtkFixedGroupDataRow",
    "GetEquipWordAtkFixedWordDataRow",
    "GetSealedInfoAttrDataRow",
    "GetSealedInfoDataRow",
    "GetMythicGlobalDataRow",
    "GetXtraMatNameRuleDataRow",
    "GetDungeonRewardDataRow",
    "GetNpcInfoDataRow",
    "GetNickNameLibDataRow",
    "GetCommonInteractorActionDataRow",
    "GetLetterTextDataRow",
    "GetFourFactionBattleConstDataRow",
    "GetFortuityDataRow",
    "GetTaskMiniTypeDataRow",
    "GetPhyDetailDataRow",
    "GetMagDetailDataRow",
    "GetFightPropModeDataRow",
    "GetTipsDataRow",
}

local runtimeFixes = {}
local runtimeMetrics = { KsbcFallbacks = 0 }
local function report(message)
    if type(Loader.Log) == "function" then pcall(Loader.Log, message) end
end
runtimeFixes.KsbcFallbackMethods = setmetatable({}, { __mode = "k" })
runtimeFixes.KsbcFallbackReports = {}

function runtimeFixes.installKsbcMissingTableFallback(manager, source)
    local fallbacks = type(manager) == "table"
        and runtimeFixes.KsbcFallbackMethods[manager] or nil
    local ksbcManager = Game and Game.KsbcMgr
    if type(fallbacks) ~= "table"
        or ksbcManager == nil
        or ksbcManager.entry == nil
        or type(manager.GetRow) ~= "function"
        or type(manager.GetData) ~= "function"
        or type(manager.GetAttr) ~= "function"
    then
        return false
    end

    local installed = manager.__cpddKsbcMissingTableFallback
    if type(installed) == "table"
        and installed.Version == VERSION
        and installed.GetData == manager.GetData
        and installed.GetAttr == manager.GetAttr
    then
        return false
    end

    local ksbcGetRow = manager.GetRow
    local ksbcGetData = manager.GetData
    local ksbcGetAttr = manager.GetAttr
    local function isMissing(tableName)
        if type(tableName) ~= "string" then return false end
        local current = Game and Game.KsbcMgr
        local entry = current and current.entry
        if entry == nil then return true end
        local ok, value = pcall(function() return entry[tableName] end)
        return not ok or value == nil
    end
    local function noteFallback(methodName, tableName)
        runtimeMetrics.KsbcFallbacks = runtimeMetrics.KsbcFallbacks + 1
        local key = tostring(methodName) .. ":" .. tostring(tableName)
        if not runtimeFixes.KsbcFallbackReports[key] then
            runtimeFixes.KsbcFallbackReports[key] = true
            report("KSBC " .. tostring(methodName) .. " used normal table fallback for "
                .. tostring(tableName))
        end
    end

    local rowWrapper = function(self, tableName, rowKey, priority)
        if isMissing(tableName) then
            noteFallback("GetRow", tableName)
            return fallbacks.GetRow(self, tableName, rowKey, priority)
        end
        return ksbcGetRow(self, tableName, rowKey, priority)
    end
    local dataWrapper = function(self, tableName, priority)
        if isMissing(tableName) then
            noteFallback("GetData", tableName)
            return fallbacks.GetData(self, tableName, priority)
        end
        return ksbcGetData(self, tableName, priority)
    end
    local attrWrapper = function(self, tableName, attrName)
        if isMissing(tableName) then
            noteFallback("GetAttr", tableName)
            return fallbacks.GetAttr(self, tableName, attrName)
        end
        return ksbcGetAttr(self, tableName, attrName)
    end

    manager.GetRow = rowWrapper
    manager.GetData = dataWrapper
    manager.GetAttr = attrWrapper
    manager.__cpddKsbcMissingTableFallback = {
        Version = VERSION,
        GetRow = rowWrapper,
        GetData = dataWrapper,
        GetAttr = attrWrapper,
    }
    report("installed safe KSBC missing-table fallback from " .. tostring(source))
    return true
end

local enabled = true
local uiEnabled = true
local statisticsEnabled = false
local bitSourceCache = {}
local shardOrder = {}
local wrappers = setmetatable({}, { __mode = "k" })
local function hasChinese(value)
    return type(value) == "string" and value:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function exactGenerated(source)
    local key = sourceKey(source)
    local head = key:match(":([0-9a-f][0-9a-f][0-9a-f])")
    if head == nil then return nil end
    local prefix = string.format("%03x", math.floor(tonumber(head, 16) / 4))
    local shard = bitSourceCache[prefix]
    if shard == nil then
        local ok, loaded = pcall(require, "mods.cpdd_runtime_fixes.RuntimeTextGemini_" .. prefix)
        if not ok or type(loaded) ~= "table" then return nil end
        shard = loaded
        bitSourceCache[prefix] = shard
        shardOrder[#shardOrder + 1] = prefix
        if #shardOrder > 128 then
            local old = table.remove(shardOrder, 1)
            bitSourceCache[old] = nil
            package.loaded["mods.cpdd_runtime_fixes.RuntimeTextGemini_" .. old] = nil
        end
    end
    -- Full source bytes, never hash/key/index/English candidates or __index fallback.
    return rawget(shard, source)
end

local function exactCurrent(source)
    if not enabled or not hasChinese(source) then return source end
    local localValue = rawget(visibleTextExactOverrides, source)
    local generated = exactGenerated(source)
    -- Reviewed full Chinese witness; never shorten pre-existing English text.
    if source == "进入非凡世界" and generated == "Enter the Extraordinary World" then
        generated = "Enter World"
    end
    if localValue ~= nil and generated ~= nil and localValue ~= generated then return source end
    local candidate = localValue or generated
    if type(candidate) ~= "string" or candidate == "" then return source end
    return candidate
end

local function repairLiveString(tableName, rowKey, fieldPath, source)
    -- Context is diagnostic only; it cannot rescue an ambiguous/mismatched source.
    return exactCurrent(source)
end

local function repairValue(value, seen, depth)
    if type(value) == "string" then return exactCurrent(value) end
    if type(value) ~= "table" or depth >= 8 or seen[value] then return value end
    -- Metatable/userdata proxies may resolve stale values; no authoritative raw snapshot.
    if getmetatable(value) ~= nil then return value end
    seen[value] = true
    local result = value
    for key, child in next, value do
        local repaired = repairValue(child, seen, depth + 1)
        if repaired ~= child then
            if result == value then
                result = {}
                for k, v in next, value do result[k] = v end
            end
            result[key] = repaired
        end
    end
    seen[value] = nil
    return result
end

local function pack(...) return { n = select("#", ...), ... } end
local function installGetter(owner, name)
    if type(owner) ~= "table" then return end
    local original = rawget(owner, name)
    if type(original) ~= "function" then return end
    local installed = wrappers[owner]
    if installed == nil then installed = {}; wrappers[owner] = installed end
    if installed[name] == original then return end
    local wrapped = function(...)
        -- Preserve original nils, multiple returns and errors. No missing-ID fallback.
        local result = pack(original(...))
        if result.n > 0 then result[1] = repairValue(result[1], {}, 0) end
        return unpack(result, 1, result.n)
    end
    owner[name] = wrapped
    installed[name] = wrapped
end

local function symbol(value, environment, name)
    if type(value) == "table" and rawget(value, name) ~= nil then return rawget(value, name) end
    if type(environment) == "table" and rawget(environment, name) ~= nil then return rawget(environment, name) end
    local global = rawget(_G, name)
    if global ~= nil then return global end
    return type(value) == "table" and value or nil
end

local function installManager(manager)
    for _, name in ipairs({ "GetLangStr", "GetLangStrSplit", "GetRow", "GetData", "GetAttr" }) do
        installGetter(manager, name)
    end
end
local function installGenerated(tableData)
    for _, name in ipairs(generatedRowRepairAllowlist) do installGetter(tableData, name) end
end

Loader.AfterLoad("Framework.Utils.LuaCommon.Managers.TableDataManager", function(value, environment)
    installManager(symbol(value, environment, "TableDataManager"))
    return value
end, 1000000, "cpdd.source-safe.manager")

Loader.AfterLoad("Data.Excel.TableData", function(value, environment)
    installGenerated(symbol(value, environment, "TableData"))
    return value
end, 1000000, "cpdd.source-safe.generated")

Loader.AfterLoad("Gameplay.Const.StringConst.StringConst", function(value, environment)
    installGetter(symbol(value, environment, "StringConst"), "Get")
    return value
end, 1000000, "cpdd.source-safe.string-const")

-- Retain the audited loading-only KSBC fallback, then wrap its current getters.
Loader.AfterLoad("Framework.Ksbc.KsbcMgr", function(value, environment)
    local class = symbol(value, environment, "KsbcMgr")
    if type(class) ~= "table" then return value end
    local original = rawget(class, "Init")
    if type(original) == "function" and class.__cpddSourceSafeInit ~= original then
        local wrapped = function(self, ...)
            local manager = Game and Game.TableDataManager
            if type(manager) == "table" and runtimeFixes.KsbcFallbackMethods[manager] == nil then
                runtimeFixes.KsbcFallbackMethods[manager] = {
                    GetRow = manager.GetRow, GetData = manager.GetData, GetAttr = manager.GetAttr,
                }
            end
            local result = pack(original(self, ...))
            runtimeFixes.installKsbcMissingTableFallback(manager, "source-safe Init")
            installManager(manager)
            return unpack(result, 1, result.n)
        end
        class.Init = wrapped
        class.__cpddSourceSafeInit = wrapped
    end
    return value
end, 1000001, "cpdd.source-safe.ksbc")

-- Only iterate current fields. No union/merge with translation IDs, no cached rows.
local function repairLoaded(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return value end
    local data = rawget(value, "data") or value
    if type(data) ~= "table" or getmetatable(data) ~= nil then return value end
    for key, current in next, data do data[key] = repairValue(current, {}, 0) end
    return value
end
local modules = {
    "Data.Excel.LanguageData.StringDB_CN_Data", "Data.Excel.WidgetBlueprintTextData",
    "Data.Excel.DialogueTalkData", "Data.Excel.DialogueAssetData", "Data.Excel.DialogueOptionText",
    "Data.Excel.LetterTextData", "Data.Excel.NpcInfoData", "Data.Excel.BubbleData",
    "Data.Excel.GossipData", "Data.Excel.NoCameraDialogueGossipData",
}
-- Split tags are routing metadata only; their old translated ID tables are never loaded.
for _, tag in ipairs({ "buffappear", "buffdata", "debug", "monsterskill", "skill", "skill1", "skill2", "skill3", "spellfield" }) do
    modules[#modules + 1] = "Data.Excel.LanguageData.StringDB_CN_Data_" .. tag
end
for _, moduleName in ipairs(modules) do
    Loader.AfterLoad(moduleName, repairLoaded, 1000000, "cpdd.source-safe." .. moduleName)
end

local function repairPanel(component)
    if not uiEnabled or type(component) ~= "table" then return 0 end
    local count, seen = 0, {}
    local function visit(node, depth)
        if type(node) ~= "table" or seen[node] or depth > 3 then return end
        seen[node] = true
        local get, set = node.GetText, node.SetText
        if type(get) == "function" and type(set) == "function" then
            local ok, current = pcall(get, node)
            if ok and type(current) == "string" then
                local translated = exactCurrent(current)
                if translated ~= current and pcall(set, node, translated) then count = count + 1 end
            end
        end
        for _, child in next, node do visit(child, depth + 1) end
    end
    visit(component, 0)
    return count
end

-- Presentation only: never choose a translation from MenuID/ButtonEnum.
local function fitMenuCaption(self)
    if not uiEnabled then return end
    local ok, err = pcall(function()
        local view = self and self.view
        if view == nil then return end
        local widget = view.Text_Name
        if widget == nil and view.GetWidgetFromName ~= nil then
            widget = view:GetWidgetFromName("Text_Name")
        end
        if widget == nil or widget.GetText == nil then return end
        local text = tostring(widget:GetText())
        -- Leave Chinese and non-Latin labels in their original layout.
        if text == "" or text:find("[^%z\1-\127]") or not text:find("%a") then return end
        local font = widget.GetFont ~= nil and widget:GetFont() or widget.Font
        if font == nil then return end
        if type(font) == "table" then
            local copy = {}; for k, v in pairs(font) do copy[k] = v end; font = copy
        end
        local size = tonumber(font.Size)
        if size == nil then return end
        font.Size = math.min(size, 18)
        widget.Font = font
        if widget.SetFont ~= nil then widget:SetFont(font) end
        -- Fixed tile bounds; long labels wrap instead of invading adjacent buttons.
        if widget.SetAutoWrapText ~= nil then widget:SetAutoWrapText(true) end
        if widget.SetWrapTextAt ~= nil then widget:SetWrapTextAt(125) end
    end)
    if not ok then report("menu caption layout failed: " .. tostring(err)) end
end
Loader.AfterLoad("Gameplay.LogicSystem.Menu.MenuBtn_Item", function(value, environment)
    local class = symbol(value, environment, "MenuBtn_Item")
    if type(class) ~= "table" or type(class.OnRefresh) ~= "function"
        or class.__cpddSourceSafeMenuLayout then return value end
    local original = class.OnRefresh
    local function packed(...) return { n = select("#", ...), ... } end
    class.OnRefresh = function(self, ...)
        local result = packed(original(self, ...))
        fitMenuCaption(self)
        return unpack(result, 1, result.n)
    end
    class.__cpddSourceSafeMenuLayout = true
    return value
end, 1000000, "cpdd.source-safe.menu-layout")

-- Restore only the known graphics-preset row's layout flags, never its labels.
Loader.AfterLoad("Gameplay.LogicSystem.Settings.Settings_Option_Item", function(value, environment)
    local class = symbol(value, environment, "Settings_Option_Item")
    if type(class) ~= "table" or type(class.Refresh) ~= "function"
        or class.__cpddSourceSafePresetLayout then return value end
    local original = class.Refresh
    class.Refresh = function(self, ...)
        local result = pack(original(self, ...))
        if uiEnabled and not self.__cpddPresetLayoutBusy then
            self.__cpddPresetLayoutBusy = true
            local ok, err = pcall(function()
                local constants = Enum and Enum.ESettingConstData
                local overall = constants and constants.OVERALL_SCALABILITY_LEVEL
                if overall == nil or self.MetaData == nil or self.MetaData.Const_1 ~= overall
                    or type(self.ChoiceListData) ~= "table" then return end
                self.bTextLengthExceed = false
                for _, choice in pairs(self.ChoiceListData) do
                    if type(choice) == "table" then choice.bTextLengthExceed = false end
                end
                local list = self.Hori_ChoiceCom
                if list ~= nil and type(list.Refresh) == "function" then
                    list:Refresh(self.ChoiceListData)
                    if type(self.UpdateData) == "function" then self:UpdateData(false) end
                end
            end)
            self.__cpddPresetLayoutBusy = nil
            if not ok then report("graphics preset layout failed: " .. tostring(err)) end
        end
        return unpack(result, 1, result.n)
    end
    class.__cpddSourceSafePresetLayout = true
    return value
end, 1000000, "cpdd.source-safe.graphics-layout")

local function installCurrent()
    installManager(Game and Game.TableDataManager)
    installGenerated(Game and Game.TableData)
end
installCurrent()
if type(Loader.On) == "function" then
    Loader.On("after_main", installCurrent, 1000001, "cpdd.source-safe.current")
end
return {
    Version = VERSION .. ".source-safe",
    SourceSafetyPolicy = "exact-current-source-v1",
    PerformanceModeApplied = Loader.Telemetry.PerformanceModeApplied == true,
    PerformanceMetrics = runtimeMetrics,
    RepairLiveText = repairLiveString,
    RepairPanel = repairPanel,
    ResolveAuthoritativeAggregate = function(index, current)
        local translated = exactCurrent(current)
        return translated ~= current and translated or nil
    end,
    SetRuntimeRowRepair = function(value) enabled = value == true; return enabled end,
    IsRuntimeRowRepairEnabled = function() return enabled end,
    SetRuntimeUIRepair = function(value) uiEnabled = value == true; return uiEnabled end,
    IsRuntimeUIRepairEnabled = function() return uiEnabled end,
    SetStatisticsEverywhere = function(value) statisticsEnabled = value == true; return statisticsEnabled end,
    IsStatisticsEverywhereEnabled = function() return statisticsEnabled end,
}

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

visibleTextExactOverrides["“愚者”"] = "\"The Fool\""
visibleTextExactOverrides["再战·一号信徒"] = "Rematch: Believer Number One"
visibleTextExactOverrides["同家族/俱乐部队员达到3人及以上"] = "3+ Party Members From the Same Family/Club"
visibleTextExactOverrides["命运道标"] = "Bacon of Destiny"
visibleTextExactOverrides["在<h>【附近】/【世界】</>聊天栏中打字输入“<HyperLink stylename=\"h\">风暴比烈酒更烈</>”"] = "In the <h>[Nearby]/[World]</> chat bar, type \"<HyperLink stylename=\"h\">风暴比烈酒更烈</>\""
visibleTextExactOverrides["在目标位置召唤窥秘之眼，对目标造成持续伤害和减速。"] = "Summon an Eye of Mystery at the target location, dealing continuous damage and slowing the target."
visibleTextExactOverrides["坏了，我可能把<P_Yellow>生物催长剂</>当成椰蓉洒在蛋糕上了！"] = "Oh no, I may have sprinkled the <P_Yellow>bio-growth stimulant</> on the cake instead of shredded coconut!"
visibleTextExactOverrides["感知灵界，观测星空，通过灵性物品启示的命运变化，解读其映射的现实空间异动、事态发展走向与潜在未知危险。"] = "Sense the spirit world and observe the stars. Interpret the changes in fate revealed by spiritual items to discern the real-world disturbances they reflect, how events may unfold, and potential unknown dangers."
visibleTextExactOverrides["所向披靡，无往不利！{{player.name}}在<Chat_Highlight>{{gameMode.name}}</>中获得<Chat_Highlight>{{eventMessageParams.curWinStreak}}连胜</>，战场之上，新的神话已在书写！"] = "Invincible and unstoppable! {{player.name}}, in <Chat_Highlight>{{gameMode.name}}</>, has achieved a <Chat_Highlight>{{eventMessageParams.curWinStreak}} win streak</>! On the battlefield, a new legend is being written!"
visibleTextExactOverrides["没有太大危险了，不用特别在意。"] = "There's no real danger anymore, so you don't need to worry."
visibleTextExactOverrides["罗珊小姐，这个铃铛是用来做什么的？"] = "Miss Rozanne, what is this bell for?"
visibleTextExactOverrides["非凡材料每有1条词条格挡 +200"] = "Every 1 affix on a Beyonder Material grants Block +200"
visibleTextExactOverrides["首通队伍"] = "First-Clear Team"
-- Full-source editorial corrections, not English aliases or numeric-ID lookup.
-- Apply only when the existing resolver agrees with the reviewed long value.
-- Standalone labels only: sentences, markup, numbers and placeholders never match.
local compactSources = {
    ["世界冒险"] = {"World Adventure", "Explore"},
    ["以战养战"] = {"Sustain War with War", "Sustain War"},
    ["外观"] = {"Appearance", "Style"},
    ["装备"] = {"Equipment", "Gear"},
    ["技能"] = {"Skill", "Skills"},
    ["非凡天赋"] = {"Beyonder Talent", "Talent"},
    ["封印物"] = {"Sealed Artifact", "Relics"},
    ["秘偶"] = {"marionette", "Puppets"},
    ["序列晋升"] = {"Sequence Advancement", "Advance"},
    ["竞技之约"] = {"Competition Covenant", "Arena"},
    -- The standalone unit label used by distance displays, not food names.
    ["米"] = {"Rice", "m"},
}
local resolveFullSource = exactCurrent
exactCurrent = function(source)
    local reviewed = type(source) == "string" and rawget(compactSources, source)
    if reviewed and enabled then
        local localValue, generated = rawget(visibleTextExactOverrides, source), exactGenerated(source)
        local function accepted(value) return value == nil or value == reviewed[1] or value == reviewed[2] end
        if (localValue ~= nil or generated ~= nil) and accepted(localValue) and accepted(generated) then
            return reviewed[2]
        end
    end
    return resolveFullSource(source)
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

-- Restoration hooks are scoped to authored UI methods; never sweep player/chat UI.
local restoredWrappers = setmetatable({}, {__mode="k"})
local function restoreMethod(class, name, after, replacement, onDisabled)
    if type(class) ~= "table" then return end
    local original = class[name]
    if type(original) ~= "function" then return end
    local methods = restoredWrappers[class]
    if not methods then methods = {}; restoredWrappers[class] = methods end
    if methods[name] == original then return end
    local wrapped = function(...)
        if replacement and uiEnabled then return replacement(original, ...) end
        local result = pack(original(...))
        local callback = uiEnabled and after or (not uiEnabled and onDisabled)
        if callback then
            local ok, err = pcall(callback, ...)
            if not ok then report("manual UI repair failed: " .. name .. ": " .. tostring(err)) end
        end
        return unpack(result, 1, result.n)
    end
    class[name] = wrapped
    methods[name] = wrapped
end

local restoredInstallers = {}
local restoredCallbacks = {}
local function restoreHook(module, className, install)
    local apply = function(value, environment)
        install(symbol(value, environment, className))
        return value
    end
    local callbacks = restoredCallbacks[module]
    if not callbacks then
        callbacks = {}; restoredCallbacks[module] = callbacks
        local dispatch = function(value, environment)
            for _, callback in ipairs(callbacks) do callback(value, environment) end
            return value
        end
        Loader.AfterLoad(module, dispatch, 1000001, "cpdd.source-safe.restore." .. className)
        restoredInstallers[#restoredInstallers+1] = {module, dispatch}
    end
    callbacks[#callbacks+1] = apply
    apply(package.loaded[module], nil)
end
local function namedWidget(view, name)
    if view == nil then return end
    if view[name] ~= nil then return view[name] end
    if view.GetWidgetFromName ~= nil then return view:GetWidgetFromName(name) end
end
local captionGenerations = setmetatable({}, {__mode="k"})
local function repairNamed(view, name)
    if type(name) == "table" then
        for i=1,#name-1 do view = namedWidget(view, name[i]) end
        name = name[#name]
    end
    local widget = namedWidget(view, name)
    if widget == nil or widget.GetText == nil or widget.SetText == nil then return end
    local generation = (captionGenerations[widget] or 0) + 1
    captionGenerations[widget] = generation
    local source = widget:GetText()
    -- FText proxies are stringified only at a known authored widget boundary.
    if source == nil then return end
    source = tostring(source)
    local translated = exactCurrent(source)
    if translated ~= source then
        widget:SetText(translated)
        -- KGTextBlock may repaint its stored property after the live Slate text.
        -- A setter can synchronously refresh/rebind this same widget. Never let
        -- an outer call overwrite the newer source/translation from that refresh.
        if captionGenerations[widget] ~= generation or tostring(widget:GetText()) ~= translated then return end
        local ok, err = pcall(function() widget.Text = translated end)
        if not ok then report("manual caption property unavailable: " .. tostring(err)) end
    end
end
local function restoreLabels(module, className, methods, names, viewName)
    restoreHook(module, className, function(class)
        for _, method in ipairs(methods) do
            restoreMethod(class, method, function(self)
                local view = self and self[viewName or "view"]
                for _, name in ipairs(names) do
                    repairNamed(view, name)
                    if not viewName then repairNamed(self and (self.userWidget or self.widget), name) end
                end
            end)
        end
    end)
end
restoreLabels("Gameplay.LogicSystem.BrassTome.BrassTomeTask_Item", "BrassTomeTask_Item",
    {"OnRefresh"}, {"Text_Content"})
restoreLabels("Gameplay.LogicSystem.Login.LoginServerItem", "LoginServerItem",
    {"OnRefresh"}, {"Server_Name_Text", "Server_Name_Text1"})
restoreLabels("Gameplay.LogicSystem.Login.LoginPanel", "LoginPanel",
    {"setServerInfoUI"}, {"Text_ServerName"})
restoreLabels("Gameplay.LogicSystem.NPC.Dialogue.DialogueScreenTextComp", "DialogueScreenTextComp",
    {"OnSectionInit"}, {"RTB_Aside1_lua"}, "usingScreenText")
restoreLabels("Gameplay.LogicSystem.Reminder.PlayerInfo.PowerItemSpecial", "PowerItemSpecial",
    {"Refresh", "PlayInAnimation"}, {"C7TextBlock_100"})

restoreLabels("Gameplay.LogicSystem.HUD.HUD_Task.New.HUD_Task_Title", "HUD_Task_Title", {"RefreshTitle"}, {"KText_Title"})
restoreLabels("Gameplay.LogicSystem.HUD.HUD_Task.New.HUD_Task_Item", "HUD_Task_Item",
    {"refreshMainTarget", "refreshTips", "SetTouchFunBtn"}, {"Text_TargetDes", "RichText_Tips", "Text_Touch"})
restoreLabels("Gameplay.LogicSystem.HUD.HUD_Task.New.HUD_Task_Sub_Item", "HUD_Task_Sub_Item", {"OnRefresh"}, {"Text_TargetDesc"})
restoreLabels("Gameplay.LogicSystem.Task.New.Task_List_Item", "Task_List_Item", {"OnRefresh"}, {"Text_ChapterName", "Text_TaskLocation"})
restoreLabels("Gameplay.LogicSystem.Task.New.Task_Info", "Task_Info", {"RefreshInfo"},
    {"Text_TaskDesc1", "Text_ChapterName", "RichText_Hint01", "RichText_Hint02", "RichText_Path",
     {"WBP_TaskTargetItem", "Text_TargetDesc"}, {"TaskTag1", "Text_Tag_lua"}, {"TaskTag2", "Text_Tag_lua"}, {"TaskTag3", "Text_Tag_lua"}})
restoreLabels("Gameplay.LogicSystem.NPC.NPCBtnCut", "NPCBtnCut", {"InitUIView", "Refresh"}, {"Text_Name"})
restoreLabels("Gameplay.LogicSystem.Item.NewUI.ItemTagCenter", "ItemTagCenter", {"SetData"}, {"text_center_lua"})
restoreLabels("Gameplay.LogicSystem.Item.ItemSmall", "ItemSmall", {"FillItem"}, {"Tag_Receive"})
restoreLabels("Gameplay.LogicSystem.TrainTrade.Main.TrainTradeMainTask_Item", "TrainTradeMainTask_Item", {"OnRefresh"}, {"Text_Get"})
restoreLabels("Gameplay.LogicSystem.GvG.GVG_WinnerParty.GVG_WinnerParty_Player_Item", "GVG_WinnerParty_Player_Item", {"OnRefresh"}, {"Text_None"})
for _, className in ipairs({"Border_Panel", "MimeWhite_Panel"}) do
    restoreLabels("Gameplay.LogicSystem.NPC." .. className, className, {"SetBlackScreenText"}, {{"WidgetRoot", "RTB_Aside1_lua"}})
end
restoreHook("Gameplay.LogicSystem.WorldCalamityBoss.WorldBossDetail_Panel.WorldBoss_Award_Widget_Item", "WorldBoss_Award_Widget_Item", function(class)
    restoreMethod(class, "UpdateRewardState", function(self)
        local item = self and self.WBP_ItemSmallCom
        repairNamed(item and item.view, "Tag_Receive")
        repairNamed(item and (item.userWidget or item.widget), "Tag_Receive")
    end)
end)
restoreLabels("Gameplay.LogicSystem.SkillCustomizer.Main.Skill_BeStrong_Btn", "Skill_BeStrong_Btn",
    {"InitUIView", "Refresh", "UpdateState"}, {"Text_Recommend", "Text_Extra", "Text_BeStrong", "KGTextBlock_54"})
restoreLabels("Gameplay.LogicSystem.SkillCustomizer.Main.SkillCommon_Panel", "SkillCommon_Panel",
    {"InitUIView", "OnRefresh", "InitSkillCustomizer", "RefreshBeStrongArea"},
    {"Text_WoodenPost", {"WBP_Skill_OneClick_Page", "Text_Content"},
     {"WBP_Skill_BeStrong_Btn", "Text_Recommend"}, {"WBP_Skill_BeStrong_Btn", "Text_Extra"}, {"WBP_Skill_BeStrong_Btn", "Text_BeStrong"}})
restoreLabels("Gameplay.LogicSystem.Talent.Talent_Panel", "Talent_Panel",
    {"InitUIView", "OnRefresh", "refreshOneClickStatus", "refreshEnableStatus"}, {"Text_Reset"})
restoreLabels("Gameplay.LogicSystem.Equipment.Equipment_Panel", "Equipment_Panel",
    {"InitUIView", "OnRefresh", "RefreshCurrentTabPage"}, {"Text_Equip"})
restoreLabels("Gameplay.LogicSystem.Bag.MainBag.Bag_Panel", "Bag_Panel",
    {"InitUIView", "OnRefresh", "UpdateAutoDecomposeBtn", "UpdateAutoDecomposeOpenSwitch"}, {{"AutoDecomposeBtn", "TB_Word"}})
restoreLabels("Gameplay.LogicSystem.LoginPopUp.LoginActivityPopUp_Panel", "LoginActivityPopUp_Panel",
    {"InitUIView", "OnRefresh", "on_KGListViewCom_ItemSelected", "ShowTitle"}, {"Text_FashionTitleDec_1"})
restoreLabels("Gameplay.LogicSystem.SkillCustomizer.Main.SkillUpgradeTips_Panel", "SkillUpgradeTips_Panel",
    {"InitUIView", "OnRefresh", "SetContent"}, {"Text_Title_2"})
restoreLabels("Gameplay.LogicSystem.HUD.HUD_PVPLastHunt.PVPLastHunt_Details_MyData", "PVPLastHunt_Details_MyData",
    {"InitUIView", "OnRefresh", "RefreshBasicInfo", "RefreshRewardInfo"},
    {"Text_Debris01", "Text_Debris01_1", "Text_Schedule", "Text_Title01", "Text_Title02", "Text_Rank"})
for _, spec in ipairs({
    {"SkillCustomizer.SchemePlan.Scheme_Plan_Item", "Scheme_Plan_Item"},
    {"SkillCustomizer.OneClick.OneClick_Plan_Item", "OneClick_Plan_Item"},
    {"SkillCustomizer.OneClick.OneClick_PlanType_Tab_Item", "OneClick_PlanType_Tab_Item"},
    {"SkillCustomizer.SchemeAssembly.Scheme_CustomPlan_Item", "Scheme_CustomPlan_Item"},
    {"SkillCustomizer.SchemeAssembly.Scheme_CustomPlan_Equipment_Item", "Scheme_CustomPlan_Equipment_Item"},
    {"Equipment.Wear.Equipment_Wear_Attribute_Item", "Equipment_Wear_Attribute_Item"},
    {"Equipment.Wear.Equipment_Wear_Suit_Item", "Equipment_Wear_Suit_Item"},
}) do
    restoreLabels("Gameplay.LogicSystem." .. spec[1], spec[2],
        {"InitUIView", "OnRefresh", "Refresh", "SetAsDefault", "UpdateEquip", "UpdateUse", "SetAsAddPlan", "UpdateSelectionState", "SetUse"},
        {"Text_BtnName", "Text_Tips", "Text_Use", "Text_Using"})
end

-- Translate a complete authored template before numeric/formula expansion.
restoreHook("Gameplay.LogicSystem.SkillCustomizer.DescFormulaHelper", "DescFormulaHelper", function(class)
    restoreMethod(class, "GenerateTipsDesc", nil, function(original, template, ...)
        local result = pack(original(exactCurrent(template), ...))
        if result.n > 0 then result[1] = exactCurrent(result[1]) end
        return unpack(result, 1, result.n)
    end)
end)
local function restoreTextReturns(module, className, methods)
    restoreHook(module, className, function(class)
        for _, name in ipairs(methods) do
            restoreMethod(class, name, nil, function(original, ...)
                local result = pack(original(...))
                if result.n > 0 then result[1] = exactCurrent(result[1]) end
                return unpack(result, 1, result.n)
            end)
        end
    end)
end
restoreTextReturns("Gameplay.LogicSystem.SkillCustomizer.SkillCustomSystem", "SkillCustomSystem",
    {"GenerateSkillDescNoRichText", "GenerateSkillBriefDesc", "GenerateSkillDecoText"})
restoreTextReturns("Gameplay.LogicSystem.Guild.GuildSystem", "GuildSystem", {"RoleIDToRoleName", "GetOccupationText"})
restoreHook("Gameplay.LogicSystem.SkillCustomizer.SkillCustomSystem", "SkillCustomSystem", function(class)
    restoreMethod(class, "GetCurrentSkillRelatedTalentIDs", nil, function(original, ...)
        local result = pack(original(...))
        local rows = result[1]
        if type(rows) == "table" and getmetatable(rows) == nil then
            local output = rows
            for index, row in next, rows do
                if type(row) == "table" and getmetatable(row) == nil then
                    local desc = rawget(row, "Desc")
                    local translated = exactCurrent(desc)
                    if desc ~= translated then
                        if output == rows then output = {}; for k,v in next,rows do output[k]=v end end
                        local copy = {}; for k,v in next,row do copy[k]=v end
                        copy.Desc = translated; output[index] = copy
                    end
                end
            end
            result[1] = output
        end
        return unpack(result, 1, result.n)
    end)
end)

local function grouped(value)
    local rounded = math.floor(value + 0.5)
    local digits = string.format("%.0f", math.abs(rounded))
    local chunks = {}
    while #digits > 3 do
        table.insert(chunks, 1, digits:sub(-3)); digits = digits:sub(1, -4)
    end
    table.insert(chunks, 1, digits)
    return (rounded < 0 and "-" or "") .. table.concat(chunks, ",")
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function money(value)
    return value < 100000 and value or grouped(value)
end
local function installCurrency(class)
    restoreMethod(class, "GetGameMoneyFormat", nil, function(original, value, ...)
        if not finite(value) then return original(value, ...) end
        return money(value)
    end)
end
restoreHook("Gameplay.LogicSystem.Utils.CurrencyUtils", "CurrencyUtils", installCurrency)
restoreHook("Gameplay.LogicSystem.Shops.ShopsExchange.Shops_StallContent_Item", "Shops_StallContent_Item", function(class)
    restoreMethod(class, "formatPrice", nil, function(original, self, value, ...)
        if not finite(value) then return original(self, value, ...) end
        return money(value)
    end)
end)
restoreHook("Gameplay.LogicSystem.HUD.HUD_PVPLastHunt.PVPLastHunt_Details_MyData", "PVPLastHunt_Details_MyData", function(class)
    restoreMethod(class, "FormatScoreTip", nil, function(original, self, value, ...)
        if not finite(value) then return original(self, value, ...) end
        return grouped(value)
    end)
end)
restoreHook("Gameplay.LogicSystem.DungeonBattleStatistics.DungeonBattleStatisticsSystem", "DungeonBattleStatisticsSystem", function(class)
    restoreMethod(class, "GetFormatNumberString", nil, function(original, self, value, ...)
        if not finite(value) then return original(self, value, ...) end
        return grouped(math.ceil(value))
    end)
end)
local function repaintPrice(self, value, name)
    local widget = namedWidget(self and self.view, name)
    if finite(value) and widget and widget.SetText then widget:SetText(money(value)) end
end

restoreHook("Gameplay.LogicSystem.PVP.Stats.PVP_Stats_Item", "PVP_Stats_Item", function(class)
    local function repaint(self, data, maxData, mode, compact)
        local model = Game and Game.PVPSystem and Game.PVPSystem.model
        local keys = model and model.tabKeys and model.tabKeys[mode]
        if type(keys) ~= "table" or type(data) ~= "table" or type(self.StatsDataComponents) ~= "table" then return end
        for i, component in pairs(self.StatsDataComponents) do
            if type(keys[i]) == "table" and component.Refresh then
                local pieces, valid = {}, true
                for _, key in ipairs(keys[i]) do
                    local n = tonumber(data[key])
                    if not finite(n) then valid = false; break end
                    local text = grouped(n)
                    if type(maxData) == "table" and tonumber(maxData[key]) == n and n ~= 0 then
                        text = "<PVP_Data_Highlight>" .. text .. "</>"
                    end
                    pieces[#pieces+1] = text
                end
                if valid and #pieces > 0 then component:Refresh(table.concat(pieces, "/"), compact) end
            end
        end
    end
    restoreMethod(class, "SetAs6V6", function(self, data)
        repaint(self, data, nil, Enum and Enum.EPVPGameModeData and Enum.EPVPGameModeData.TEAM6V6, true)
    end)
    restoreMethod(class, "SetAs12V12", function(self, data, index, maxData)
        local mode = self.otherInfo and self.otherInfo.Mode or (Enum and Enum.EPVPGameModeData and Enum.EPVPGameModeData.TEAM12V12)
        repaint(self, data, maxData, mode, false)
    end)
    restoreMethod(class, "SetAsChampion", function(self, data, index, maxData)
        repaint(self, data, maxData, Enum and Enum.EPVPGameModeData and Enum.EPVPGameModeData.CHAMPION_GROUP_BATTLE, false)
    end)
end)
restoreHook("Gameplay.LogicSystem.Shops.ShopsExchange.Shops_AuctionContent_Item", "Shops_AuctionContent_Item", function(class)
    restoreMethod(class, "refreshAuctionItemInfo", function(self)
        repaintPrice(self, self._auctionItemData and self._auctionItemData.CurrentBidPrice, "Text_MoneyOne")
    end)
end)
for _, spec in ipairs({{"Shops_StallFashion_Item", "Text_MoneyNumber_1"}, {"Shops_SaleFashion_Item", "Text_Possess"}}) do
    local className, labelName = spec[1], spec[2]
    restoreHook("Gameplay.LogicSystem.Shops.ShopsExchange." .. className, className, function(class)
        restoreMethod(class, "OnRefresh", function(self, data)
            repaintPrice(self, data and data.Price, labelName)
        end)
    end)
end

-- Catch classes already cached before runtime mod loading, without forcing loads.
local function restoreCached()
    for _, item in ipairs(restoredInstallers) do item[2](package.loaded[item[1]], nil) end
    installCurrency(Game and Game.CurrencyUtils)
    -- The four exchange classes use a private module cache in shipping builds.
    -- Recover only these known classes, as the earlier price fix did.
    local privateRequire = rawget(_G, "kg_require")
    if type(privateRequire) == "function" then
        for _, className in ipairs({"Shops_StallContent_Item", "Shops_AuctionContent_Item", "Shops_StallFashion_Item", "Shops_SaleFashion_Item"}) do
            local module = "Gameplay.LogicSystem.Shops.ShopsExchange." .. className
            local ok, value = pcall(privateRequire, module)
            if ok then
                for _, callback in ipairs(restoredCallbacks[module] or {}) do callback(value, nil) end
            else
                report("exchange formatter class unavailable: " .. className)
            end
        end
    end
end
restoreCached()
if type(Loader.On) == "function" then
    Loader.On("after_main", restoreCached, 1000002, "cpdd.source-safe.restored-cached")
end

-- Current packaged UI contracts audited in contracts.json. Translate authored
-- full templates before the game's own player/sex/profession substitutions.
local function authoredText(source)
    return type(source) == "string" and exactCurrent(source) or source
end
local function speakerText(source)
    if type(source) ~= "string" or source == (Game and Game.me and Game.me.Name)
        or source:find("{{",1,true) then return source end
    return exactCurrent(source)
end
local function translatedDialogueArguments(...)
    local args=pack(...)
    args[1]=authoredText(args[1]); args[2]=speakerText(args[2])
    args[5]=authoredText(args[5]); args[6]=authoredText(args[6]); args[8]=authoredText(args[8])
    return args
end
local function contentArguments(original,self,...)
    local args=translatedDialogueArguments(...)
    return original(self,unpack(args,1,args.n))
end
for _,name in ipairs({"Dialogue_CSStyle","Dialogue_CSLine"}) do
    restoreHook("Gameplay.LogicSystem.NPC.Dialogue."..name,name,function(class)
        restoreMethod(class,"ShowContent",nil,contentArguments)
    end)
end
restoreHook("Gameplay.LogicSystem.NPC.Dialogue.Dialogue_Panel","Dialogue_Panel",function(class)
    restoreMethod(class,"ShowContent",nil,function(original,self,title,name,content,...)
        return original(self,authoredText(title),speakerText(name),authoredText(content),...)
    end)
end)
restoreHook("Gameplay.LogicSystem.NPC.Dialogue.ReviewListItem","ReviewListItem",function(class)
    restoreMethod(class,"OnRefresh",nil,function(original,self,data,...)
        if type(data)~="table" or getmetatable(data)~=nil then return original(self,data,...) end
        local nameSource=rawget(data,"talkerName")
        local content=authoredText(rawget(data,"content"))
        -- Leave talker identity to native color/ownership logic; repair its
        -- displayed caption afterward without mutating history or its name.
        if content~=rawget(data,"content") then
            local copy={};for k,v in next,data do copy[k]=v end
            copy.content=content;data=copy
        end
        local result=pack(original(self,data,...))
        local ok,err=pcall(function()
        local view=self and self.view
        local w=namedWidget(view,"Text_Title_lua")
        if w and w.GetText and w.SetText then
            local current=w:GetText()
            if type(nameSource)=="string" and not nameSource:find("{{",1,true)
                and current~=nil and tostring(current)==nameSource
                and nameSource~=(Game and Game.me and Game.me.Name) then
                repairNamed(view,"Text_Title_lua")
            end
        end
        end)
        if not ok then report("story log repair failed: "..tostring(err)) end
        return unpack(result,1,result.n)
    end)
end)
restoreHook("Gameplay.LogicSystem.NPC.Sequence.Sequence_Panel","Sequence_Panel",function(class)
    restoreMethod(class,"ShowDialoguePanel",nil,function(original,self,content,name,title,...)
        return original(self,authoredText(content),speakerText(name),authoredText(title),...)
    end)
    restoreMethod(class,"OnSetBottomText",nil,function(original,self,content,...)
        return original(self,authoredText(content),...)
    end)
end)
restoreLabels("Gameplay.LogicSystem.Loading.Loading_Panel","Loading_Panel",
    {"Refresh","ShowTips","TipsShuffle"},{"Text_MapName","RTB_Tips"})
restoreLabels("Gameplay.LogicSystem.NPC.Dialogue.DialogueOptionItem","DialogueOptionItem",
    {"OnRefresh"},{"Text_Item"})
for _,name in ipairs({"Border_Panel","MimeWhite_Panel"}) do
    restoreLabels("Gameplay.LogicSystem.NPC."..name,name,
        {"SetBlackScreenText"},{{"WidgetRoot","RTB_Aside1_lua"}})
end
restoreHook("Gameplay.LogicSystem.HUD.HUD_Aside.HUDAside_Bubble","HUDAside_Bubble",function(class)
    restoreMethod(class,"Refresh",nil,function(original,self,param,...)
        if type(param)=="table" and getmetatable(param)==nil then
            local text=authoredText(rawget(param,"text"))
            local name=speakerText(rawget(param,"npcName"))
            if text~=rawget(param,"text") or name~=rawget(param,"npcName") then
                local copy={};for k,v in next,param do copy[k]=v end
                copy.text=text;copy.npcName=name;param=copy
            end
        end
        return original(self,param,...)
    end)
end)
local function authoredNpc(entity)
    local ok,allowed=pcall(function()
        if entity==nil or entity.isAvatar==true or entity==(Game and Game.me) or entity.isNpc~=true then return false end
        local config=type(entity.GetEntityConfigData)=="function" and entity:GetEntityConfigData() or nil
        return config~=nil and not config.bGhost
    end)
    if not ok then report("NPC identity probe unavailable") end
    return ok and allowed
end
local function attachedEntity(self)
    local ok,entity=pcall(function()
        return self and type(self.GetAttachedEntity)=="function" and self:GetAttachedEntity() or nil
    end)
    if not ok then report("NPC attached entity unavailable");return nil end
    return entity
end
restoreHook("Gameplay.LogicSystem.NewHeadInfo.HeadInfoUI.HeadInfoName","HeadInfoName",function(class)
    restoreMethod(class,"getEntityName",nil,function(original,self,entity,...)
        local result=pack(original(self,entity,...))
        if authoredNpc(entity) then result[1]=speakerText(result[1]) end
        return unpack(result,1,result.n)
    end)
    restoreMethod(class,"OnHeadNameChanged",nil,function(original,self,name,...)
        local entity=attachedEntity(self)
        return original(self,authoredNpc(entity) and speakerText(name) or name,...)
    end)
end)
restoreHook("Gameplay.LogicSystem.NewHeadInfo.HeadInfoUI.HeadInfoBubble","HeadInfoBubble",function(class)
    restoreMethod(class,"ShowCustomBubble",nil,function(original,self,message,...)
        local entity=attachedEntity(self)
        return original(self,authoredNpc(entity) and authoredText(message) or message,...)
    end)
end)
-- This distance method writes the current numeric source plus the unit; it has
-- no StringDB lookup and must be repaired at this known distance boundary.
restoreHook("Gameplay.LogicSystem.Race.WorldWidget.RaceTrace_Widget","RaceTrace_Widget",function(class)
    restoreMethod(class,"UpdateDistance",function(self)
        local w=namedWidget(self and self.view,"Text_Distance")
        if not w or not w.GetText or not w.SetText then return end
        local current=w:GetText()
        local digits=current and tostring(current):match("^(%d+)米$")
        if digits then w:SetText(digits.."m") end
    end)
end)

-- Inject after restored_hooks.lua, before installCurrent. Presentation only.
do
    local function finite(n)
        return type(n) == "number" and n == n and math.abs(n) < math.huge
    end
    local function ascii(s)
        return type(s) == "string" and s:find("%a") ~= nil
            and not s:find("[^\9\10\13\32-\126]")
    end
    local function plain(s) return ascii(s) and not s:find("[<>]") end
    local function widget(self, name)
        return namedWidget(self and self.view, name)
            or namedWidget(self and (self.userWidget or self.widget), name)
    end
    local function text(w)
        if w == nil or type(w.GetText) ~= "function" then return end
        local v = w:GetText()
        if v ~= nil then return tostring(v) end
    end
    local function vector(x, y)
        local ok, v = pcall(function() return FVector2D(x, y) end)
        if ok and v ~= nil then return v end
        return {X=x, Y=y}
    end
    local function number(v) if finite(v) then return v end end
    local function scalar(v)
        if type(v) == "boolean" or finite(v) then return v end
    end
    local function xy(v)
        if v ~= nil and finite(v.X) and finite(v.Y) then return {X=v.X,Y=v.Y} end
    end
    local function fontCopy(v)
        -- Opaque/native structs and nested shared values have no safe clone API.
        if type(v) ~= "table" or getmetatable(v) ~= nil or not finite(v.Size) or v.Size <= 0 then return end
        local out = {}
        for k, value in next, v do
            if type(k) ~= "string" or (type(value) ~= "string" and type(value) ~= "boolean" and not finite(value)) then return end
            out[k] = value
        end
        return out
    end
    local function equal(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        for k,v in pairs(a) do if b[k] ~= v then return false end end
        for k,v in pairs(b) do if a[k] ~= v then return false end end
        return true
    end
    local function property(getter, field)
        return function(o)
            if getter and type(o[getter]) == "function" then return o[getter](o) end
            return o[field]
        end
    end
    local function setter(name) return function(o,v) o[name](o,v) end end
    local function read(o, get, copy)
        local ok, v = pcall(function() return copy(get(o)) end)
        if ok then return v end
    end
    local function safely(label, callback, ...)
        local ok,err = pcall(callback,...)
        if not ok then report(label .. tostring(err)) end
    end
    local owned = setmetatable({}, {__mode="k"})
    local function undo(record)
        local current = read(record.object, record.get, record.copy)
        -- A native refresh that changed the property owns its new value.
        if current ~= nil and equal(current, record.applied) then
            record.set(record.object, record.copy(record.before))
        end
    end
    local function cleanup(self)
        local records = owned[self]
        owned[self] = nil
        for _, record in ipairs(records or {}) do safely("layout undo failed: ",undo,record) end
    end
    local function change(self, o, get, set, copy, target)
        if o == nil then return end
        local before = read(o, get, copy)
        if before == nil or equal(before, target) then return end
        local record = {object=o,get=get,set=set,copy=copy,before=before,applied=copy(target)}
        local records = owned[self] or {}; owned[self] = records
        -- Keep the snapshot even if a native setter mutates then throws.
        records[#records+1] = record
        set(o, copy(target))
    end
    local function geometryGet(kind)
        return function(o)
            local getter = o["GetRender" .. kind]
            if type(getter) == "function" then return getter(o) end
            if kind == "TransformPivot" then return o.RenderTransformPivot end
            local transform = type(o.GetRenderTransform) == "function" and o:GetRenderTransform() or o.RenderTransform
            return transform and transform[kind]
        end
    end
    local function geometry(self, o, kind, value)
        if o == nil or type(o["SetRender" .. kind]) ~= "function" then return end
        change(self,o,geometryGet(kind),function(w,v) w["SetRender" .. kind](w,vector(v.X,v.Y)) end,xy,value)
    end
    local function smallFont(self, w, budget)
        local s = text(w)
        if not plain(s) or type(w.SetFont) ~= "function" then return end
        if budget then
            local longest = 0
            for line in s:gmatch("[^\r\n]+") do longest=math.max(longest,#line) end
            if longest <= budget then return end
        end
        local get = property("GetFont","Font")
        local f = read(w,get,fontCopy)
        if not f or f.Size <= 18 then return end
        f.Size = 18
        change(self,w,get,setter("SetFont"),fontCopy,f)
    end
    local function scaleText(self, w, budget, minimum)
        local s = text(w)
        if not plain(s) then return end
        local longest = 0
        for line in s:gmatch("[^\r\n]+") do longest=math.max(longest,#line) end
        if longest <= budget then return end
        if not read(w,geometryGet("Scale"),xy) or not read(w,geometryGet("TransformPivot"),xy) then return end
        local scale = math.max(minimum,budget/longest)
        geometry(self,w,"TransformPivot",{X=0,Y=0.5})
        geometry(self,w,"Scale",{X=scale,Y=scale})
    end
    local layoutBusy = setmetatable({}, {__mode="k"})
    local function guarded(callback)
        return function(self,...)
            if self == nil or layoutBusy[self] then return end
            layoutBusy[self]=true
            local ok,err = pcall(callback,self,...)
            layoutBusy[self]=nil
            if not ok then error(err,0) end
        end
    end
    local disabledCleanup = guarded(cleanup)
    local function after(callback)
        return guarded(function(self,...)
            cleanup(self)
            callback(self,...)
        end)
    end
    restoreHook("Gameplay.LogicSystem.Fashion.FashionMain.UIPanel.FashionMain_Panel.ChangeWidget.Fashion_DetailExpand",
        "Fashion_DetailExpand",function(class)
        restoreMethod(class,"RefreshStyle",after(function(self)
            local title,progress = widget(self,"StyleText"),widget(self,"WBP_FashionChange_StyleProgress")
            if not plain(text(title)) or progress == nil then return end
            if not read(title,geometryGet("Translation"),xy) or not read(progress,geometryGet("Translation"),xy) then return end
            geometry(self,title,"Translation",{X=48,Y=0})
            geometry(self,progress,"Translation",{X=48,Y=0})
        end),nil,disabledCleanup)
    end)
    local promotion = "Gameplay.LogicSystem.SequencePromotion.SequencePromotion_Panel."
    restoreHook(promotion .. "Sequence_Dec","Sequence_Dec",function(class)
        for _,method in ipairs({"InitUIView","Refresh"}) do
            restoreMethod(class,method,after(function(self)
                smallFont(self,widget(self and self.WBP_ConditionBtnCom,"Text_Name"))
            end),nil,disabledCleanup)
        end
    end)
    restoreHook(promotion .. "Sequence_TaskItem","Sequence_TaskItem",function(class)
        restoreMethod(class,"OnRefresh",after(function(self)
            local w = widget(self,"Text_Condition")
            smallFont(self,w,32); scaleText(self,w,32,0.78)
        end),nil,disabledCleanup)
    end)
    restoreHook(promotion .. "Sequence_TextItem","Sequence_TextItem",function(class)
        restoreMethod(class,"OnRefresh",after(function(self) scaleText(self,widget(self,"Text_Change"),21,0.42) end),nil,disabledCleanup)
    end)

    local rowNames = {"RTB_TalkContent_Back_lua","RTB_TalkContent_lua",
        "RTB_TalkContent2_Back_lua","RTB_TalkContent2_lua","RTB_TalkContent3_Back_lua","RTB_TalkContent3_lua"}
    local function dialogueShape(self)
        local root,printer = self and self.userWidget,self and self.ContentPrinter
        if root == nil or printer == nil then return end
        local rows = {}
        for i,name in ipairs(rowNames) do rows[i]=namedWidget(root,name) end
        for i=1,4 do if rows[i] == nil then return end end
        if (rows[5] == nil) ~= (rows[6] == nil) then return end
        -- Existing third-row widgets do not prove that the printer binds them.
        -- No verified live binding-count API is available; use the core two rows.
        return printer,rows,2
    end
    local capacity = setmetatable({}, {__mode="k"})
    local capacityGet = property(nil,"LineMaxCharCount")
    local capacitySet = function(o,v) o.LineMaxCharCount=v end
    local function dialogueUndo(self)
        cleanup(self)
        local record = capacity[self]; capacity[self]=nil
        if record then safely("dialogue capacity undo failed: ",undo,record) end
    end
    local function prepareCapacity(self,content)
        local previous = capacity[self]
        local printer,_,count = dialogueShape(self)
        local target = ascii(content) and printer and math.max(42,math.ceil(#content/count)) or nil
        local object = printer or (previous and previous.object)
        if not object then return end
        local before = read(object,capacityGet,number)
        if before == nil then return end
        local record = previous
        if record and (record.object ~= object or before ~= record.applied) then record=nil end
        if target == nil then target=record and record.before or before end
        local nextRecord
        if ascii(content) and printer and (target ~= before or record) then
            nextRecord = {object=object,get=capacityGet,set=capacitySet,copy=number,
                before=record and record.before or before,applied=target}
        end
        return {object=object,before=before,target=target,previous=previous,nextRecord=nextRecord}
    end
    local function simple(self,o,getter,field,set,target)
        if o ~= nil and type(o[set]) == "function" then
            change(self,o,property(getter,field),setter(set),scalar,target)
        end
    end
    local function dialogueLayout(self,content)
        cleanup(self)
        if not ascii(content) then return end
        local printer,rows,count = dialogueShape(self)
        if not printer then return end
        -- BindWidget has no verified snapshot API: native code owns row bindings.
        simple(self,printer,"GetEnableTwoLinePrinter","EnableTwoLinePrinter","SetEnableTwoLinePrinter",true)
        for i=1,count*2 do simple(self,rows[i],"GetAutoWrapText","AutoWrapText","SetAutoWrapText",false) end
        -- Third-row visibility/height also remain native-owned until binding is proven.
    end
    local dialogueBusy = setmetatable({}, {__mode="k"})
    restoreHook("Gameplay.LogicSystem.NPC.Dialogue.DialogueTalk","DialogueTalk",function(class)
        restoreMethod(class,"ShowContent",nil,function(original,self,content,...)
            if self == nil or dialogueBusy[self] then return original(self,content,...) end
            dialogueBusy[self]=true
            local args=translatedDialogueArguments(content,...)
            local renderedContent=args[1]
            local ok,transaction = pcall(prepareCapacity,self,renderedContent)
            if not ok then report("dialogue snapshot failed: " .. tostring(transaction)); transaction=nil end
            if transaction and transaction.target ~= transaction.before then
                safely("dialogue capacity failed: ",capacitySet,transaction.object,transaction.target)
            end
            local result = pack(pcall(original,self,unpack(args,1,args.n)))
            if not result[1] then
                if transaction then
                    safely("dialogue rollback failed: ",function()
                        if read(transaction.object,capacityGet,number) == transaction.target then
                            capacitySet(transaction.object,transaction.before)
                        end
                    end)
                end
                dialogueBusy[self]=nil
                error(result[2],0)
            end
            if transaction then
                if transaction.previous and transaction.previous.object ~= transaction.object then
                    safely("old dialogue capacity undo failed: ",undo,transaction.previous)
                end
                capacity[self]=transaction.nextRecord
            end
            safely("dialogue layout failed: ",dialogueLayout,self,renderedContent)
            dialogueBusy[self]=nil
            return unpack(result,2,result.n)
        end,guarded(dialogueUndo))
    end)
    restoreHook("Gameplay.NetEntities.SceneActor.Components.SceneTextBoardComponent","SceneTextBoardComponent",function(class)
        local function fit(self)
            cleanup(self)
            local s = self and self.displayText
            if not plain(s) then return end
            local longest = 0
            for line in s:gmatch("[^\r\n]+") do longest=math.max(longest,#line) end
            if longest <= 12 then return end
            local actor = self.CppEntity
            -- SceneConf.FontInfo is not a snapshot of the live native actor.
            if actor == nil or type(actor.KAPI_Actor_GetFontSize) ~= "function"
                or type(actor.KAPI_Actor_UpdateFontSize) ~= "function" then return end
            local get = function(o) return o:KAPI_Actor_GetFontSize() end
            local size = read(actor,get,number)
            if not size or size <= 0 then return end
            local target = math.min(size,71)
            if longest > 15 then target=math.min(target,math.max(48,math.floor(size*15/longest+0.5))) end
            change(self,actor,get,setter("KAPI_Actor_UpdateFontSize"),number,target)
        end
        restoreMethod(class,"RefreshContent",guarded(fit),nil,disabledCleanup)
        restoreMethod(class,"InnerTextBlockReady",guarded(fit),nil,disabledCleanup)
    end)
end

-- Item names and descriptions have separate delivery paths. Translate only the
-- current full authored text, before formatting or immediately after rendering.
restoreHook("Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTips_Item", "ItemTips_Item", function(class)
    for _, method in ipairs({"FillMainLibText", "FillLibText"}) do
        restoreMethod(class, method, nil, function(original, self, text, ...)
            return original(self, exactCurrent(text), ...)
        end)
    end
end)

restoreLabels("Gameplay.LogicSystem.Lib.LibText", "LibText", {"Refresh"}, {"Text_TipsContent_lua"})
restoreLabels("Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsText_Item", "ItemTipsText_Item",
    {"OnRefresh"}, {"Text_TipsContent"})
restoreLabels("Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipStory", "ItemTipsEquipStory",
    {"SetData"}, {{"WBP_Lib_Text", "Text_TipsContent_lua"}})

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

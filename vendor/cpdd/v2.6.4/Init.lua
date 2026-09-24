local Loader = assert(LOMModLoader, "LOMModLoader is required")

local VERSION = "0.9.71"
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

local aggregateOverrides = {
    -- Equipment reform paints these season-lock messages into a narrow banner.
    -- Override the already-English StringDB rows themselves so the explicit
    -- line break survives even when no Chinese runtime-map lookup occurs.
    [413898750559745] = "Affix inheritance is available.\nRemolding unlocks in %s days.",
    [413898750560769] = "Affix inheritance is available.\nRemolding is currently unavailable.",
    -- Player Details exposes two distinct mechanics that the old catalog
    -- translated identically. The standalone ShieldBreak property is Armor
    -- Break; the lower DefReduce group and its children are Defense Break.
    [255431368783360] = "Armor Break",
    [141494476346368] = "Defense Break",
    [255431368777472] = "Physical Defense Break",
    [255431368780800] = "Magic Defense Break",
    -- Launch 1.1 Esc-menu compact labels. These are the confirmed four-row
    -- values from esc_menu_hotfix_v2 and must win over the external StringDB.
    [74905303409152] = "Explore",
    [466331174441472] = "Archive",
    [501378376016640] = "Style",
    [514572247120128] = "Puppets",
    [527972545072640] = "Story",
    [625210604657664] = "Contacts",
    [712484608544768] = "Easy Wins",
    [774126247610880] = "Gear",
    [774126784481024] = "Artifacts",
    [866415967995648] = "Warfront",
    [866622663296512] = "Dark City",
    [884214580905472] = "Advance",
    [933074128867328] = "Arts",
    [989630258218752] = "Talents",
    [1020416583796224] = "Skip",
    [1020416583796480] = "Review",
    [936784443737600] = "Beyonder Rating",
    [936990870604032] = "Reward Preview",
    [1271036247030528] = "Claimed",
    [620129389936640] = "Use",
    [1073124154021632] = "Auto-Dismantle Settings",
    [1073124154089984] = "In Use",
    [1073124154205952] = "My Builds",
    [1073124154228480] = "Auto-Dismantle Confirmation",
    [1073124154229760] = "Official Recommended Build",
    [1271036247052800] = "Recommended Builds",
    [1068726107902976] = "Codex",
    [1271036247021824] = "Click blank area to close",
    [1240251532142337] = [=[1. <Highlight>Family Application:</> Any Beyonder who has not joined a family can publish a personal application to find a suitable family. The application is automatically withdrawn <Highlight>3 days</> after publication or after successfully joining a family.
2. <Highlight>Recruitment Response:</> Beyonders who have not joined a family may start a recruitment response or join one started by another Beyonder. The initiator becomes the <Highlight>Family Chief</> by default.
3. <Highlight>Create Family:</> During the recruitment-response phase, a family can be created once at least <Highlight>3 people</> have responded. During creation, the Chief can adjust the family name and member positions.
4. <Highlight>Join Family:</> When a family has fewer than <Highlight>14 members</>, the Chief can recruit. Other Beyonders may apply and join directly after the Chief approves their application.]=],
    [1271036247235584] = "Equipment Builds",
    [312331095508480] = "Comments",
    [1068726108208384] = "%d0%% Price",
    -- Manor upgrade UI splits these records on commas. Preserve the data
    -- contract instead of using the prose-style colon from the old patch.
    [677369761236481] = "New Feature Unlocked,Visit Friends' Castles",
    [677369761236737] = "New Feature Unlocked,Workshop",
    -- Launch 1.2 EquipmentUniqueData rows 6801-6803. These values are cached
    -- while the data module loads, so translate the authoritative StringDB IDs
    -- in addition to repairing ItemTipsEquipSpecial:SetData below.
    [409365949475072] = "<CostRed>{1,2,(Brand inactive)}</>Skill Enhancement increased by <Mark>30</>.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    [409365949475328] = "<CostRed>{1,2,(Brand inactive)}</>After using a Cleanse Skill, gain <Mark>50</> Skill Block for <Mark>10</> seconds. Can trigger at most once every <Mark>30</> seconds.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    [409365949475584] = "<CostRed>{1,2,(Brand inactive)}</>Armor Break increased by <Mark>80</>. When taking damage, there is a chance to gain <Mark>60</> Defense for <Mark>5</> seconds. Can trigger at most once every <Mark>10</> seconds.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    [211107843337216] = "The sealing chains of the \"Door\" domain coil around your heart to ward off fatal damage. A single hit cannot reduce your HP by more than 25% of Max HP.",
    [211107843655936] = [=[When a class combat skill enters cooldown, the cooldown is immediately refunded. If it is a charged skill, all charge counts are refunded. Each individual skill can trigger this refund at most once. {CheckStar(Type="sealed",ID=2085021)=1?The refunded skill deals <Yellow>*f**</> less damage and healing.}{CheckStar(Type="sealed",ID=2085021)=3?The refunded skill additionally gains <Yellow>*f**</> damage and healing.}]=],
    [211107844315392] = "Miss Justice witnessed your fall and watched you rise again. A will that has been seen will not be easily extinguished. Damage taken is reduced by 30%, and damage dealt is increased by 40%.",
    [286012073289984] = "\"The pure-white one sleeping within the crimson cocoon, the divine child who governs rebirth and corruption, the final possibility at the end of days.\"",
    [286012610526208] = "\"Woof, woof!\"",
    [1240251532052225] = "Mr. Fool has grafted onto you a destiny from the future, allowing you to wield the power of higher Sequences. As your strength grows, the variety and power of the skills you learn will continue to increase. Skills are divided into three categories: Combat Skills, Special Skills, and Acting Skills. You can equip up to four Combat Skills or Acting Skills at the same time. Special Skills do not need to be equipped and include Basic Attack, Crowd-Control Break, and Finisher Skills.",
}

local splitOverrides = {
    buffappear = {
        [1253512780450048] = "Fear",
    },
    buffdata = {
        [1253512780450048] = "Fear",
    },
    debug = {
        [1169950433818880] = "Enter the Dream",
    },
    monsterskill = {
        [1271036247082752] = "Projection",
    },
    skill = {
        [1240389776443904] = "Purifying Slash",
    },
    skill1 = {
        [1240389776521984] = "Star Strike",
    },
    skill2 = {
        [611398258279936] = "Beacon of History",
    },
    skill3 = {
        [998771022409216] = "Nebula Slash",
    },
    spellfield = {
        [1068726107518720] = "Tip",
    },
}

local stringConstOverrides = {
    BAG_AUTO_AUTO_RESOLVE_TITLE = "Auto-Dismantle Confirmation",
    BAG_AUTO_DECOMPOSE_TITLE = "Auto-Dismantle Settings",
    COMMENT_PANEL_TITLE = "Comments",
    DIALOGUE_SKIP = "Skip",
    EQUIPMENT_PLAN_APPLY_CURRENT_PLAN = "Apply Build",
    FASHION_APPEARANCE = "Appearance",
    FASHION_DYE_MY_PLAN = "My Builds",
    GUILD_CARGO_HUB_REWARD_COMPLETE = "Claimed",
    GVG_HONOR_CLAIMED_TEXT = "Claimed",
    ITEM_GOT = "Claimed",
    MONTH_CARD_MAIN_PAGE_TODAY_RECEIVED_LABEL = "(Claimed Today)",
    FAMILY_INVITE_SHARE_TEAM = "Party Channel",
    FAMILY_INVITE_SHARE_WORLD = "World Channel",
    FAMILY_MEMBER_COUNT_FMT = "Current Family Members: %s/14",
    FAMILY_MEMBER_FMT = "Family Members (%d/%d)",
    ONE_CLICK_IN_USE = "In Use",
    ONE_CLICK_RECOMMEND_PLAN = "Official Recommended Build",
    ONE_CLICK_SHARE_RECOMMEND_PLAN = "Recommended Builds",
    ONE_CLICK_TITLE = "One-Click Assist",
    ONE_CLICK_USE = "Use",
    TRAINTRADE_ITEM_DISCOUNT_CHINESE = "%d0%% Price",
    MAP_PVP_LAST_HUNT_DRAGON_BOSS_BELONG_FORMAT = "<Green>%s</> Team Affiliation",
    MAP_PVP_LAST_HUNT_DRAGON_BOSS_NAME = "Dragon Projection",
    MAP_PVP_LAST_HUNT_DRAGON_BOSS_NOT_BELONG_FORMAT = "<Red>%s</> Team Affiliation",
    PVP_LAST_HUNT_ACTIVE_TIME_FORMAT = "Activating %M:%S",
    PVP_LAST_HUNT_ACTIVITY_NOT_OPEN_TEXT = "Use <Highlight>Seed of Sighs</> to activate Power of Sighs, start the Sighs Quest, and complete it to receive rich rewards.",
    PVP_LAST_HUNT_ACTIVITY_OPEN_FORMAT = "Starts in %H hours %M minutes",
    PVP_LAST_HUNT_ACTIVITY_OPEN_TEXT = "Event Start Time",
    PVP_LAST_HUNT_ACTIVITY_REWARD_PREVIEW_FORMAT = "Quest Rewards",
    PVP_LAST_HUNT_BOSS_BUTTON_DESC = "Go",
    PVP_LAST_HUNT_BOSS_CONTENT_DESC = "Royal City Dragon Description Placeholder",
    PVP_LAST_HUNT_BOSS_DETAIL_CONDITION_TITLE = "Refresh Status",
    PVP_LAST_HUNT_BOSS_DETAIL_CONTENT = "Defeat elite monsters to earn abundant rewards",
    PVP_LAST_HUNT_BOSS_DETAIL_NOT_SPAWNED = "Target has not appeared yet",
    PVP_LAST_HUNT_BOSS_DETAIL_SPAWNED = "Target has appeared",
    PVP_LAST_HUNT_BOSS_DETAIL_TITLE = "Hunt Target",
    PVP_LAST_HUNT_BOSS_DRAGON_FORMAT = "Dragon appears in %M:%S",
    PVP_LAST_HUNT_BOSS_SECOND_TITLE = "Defeat the Royal City Dragon",
    PVP_LAST_HUNT_BOSS_TAG_NAME = "Royal City Guardian",
    PVP_LAST_HUNT_BOSS_TITLE = "Slay the Dragon",
    PVP_LAST_HUNT_CAMP_SUBMIT_FORMAT = "%s Submission Point",
    PVP_LAST_HUNT_CHAT_BUTTON_TEXT = "Go",
    PVP_LAST_HUNT_CHAT_TITLE = "Horn",
    PVP_LAST_HUNT_CROSS_SERVER_SCORE_TITLE = "Military Merit",
    PVP_LAST_HUNT_DETAIL_MY_DATA_TAB = "My Data",
    PVP_LAST_HUNT_DETAIL_RANK_TAB = "Ranking",
    PVP_LAST_HUNT_FIGHT_ASSISTANT_FORMAT = "%s was defeated by %s at %s. Support needed!",
    PVP_LAST_HUNT_FIGHT_KILL_RESULT_FORMAT = "%s successfully hunted %s at %s!",
    PVP_LAST_HUNT_GUILD_ACTIVITY_DESC_TIPS = "Final Hunt Dragon Raid <Highlight>[Team Auction]</>: %d/%d (this Friday) at 19:10",
    PVP_LAST_HUNT_GUILD_NAME_FORMAT = "<Enemy_Name>%s</> Club",
    PVP_LAST_HUNT_HIGHER_DETAIL_CONTENT = "Advanced quest area containing many out-of-control monsters",
    PVP_LAST_HUNT_HIGHER_DETAIL_NOT_OPENED_TITLE = "Currently Closed",
    PVP_LAST_HUNT_HIGHER_DETAIL_OPENED_TIME = "Open daily: 19:00-21:00\nAdditional hours: Saturday and Sunday, 14:00-16:00",
    PVP_LAST_HUNT_HIGHER_DETAIL_TITLE_NAME = "Advanced · Tide",
    PVP_LAST_HUNT_HUD_PROGRESS_CURRENCY_FORMAT = "<Highlight>%s</>/%s",
    PVP_LAST_HUNT_HUD_PROGRESS_FORMAT = "<Highlight>%d</>/%d",
    PVP_LAST_HUNT_ITEM_CAN_NOT_USE = "Insufficient Quantity",
    PVP_LAST_HUNT_LACK_USE_ITEM_PROP_COUNT_FORMAT = "Attempts Remaining: %s",
    PVP_LAST_HUNT_MAIN_PROGRESS_TITLE = "Reward Preview",
    PVP_LAST_HUNT_MAP_DETAIL_DESC = "Faction-area teleport entrance",
    PVP_LAST_HUNT_MAP_ITEM_NAME = "Seed of Sighs · Monster Tide Area",
    PVP_LAST_HUNT_MEMBER_COUNT_FORMAT = "(Party Members: %d/%d)",
    PVP_LAST_HUNT_MONSTER_CANCEL_BUTTON_NAME = "Cancel",
    PVP_LAST_HUNT_MONSTER_DROP_REWARD_TEXT = "Chance to drop from defeated <HyperLink stylename=\"Clickable\" u=\"\">minor monsters</>",
    PVP_LAST_HUNT_MONSTER_DROP_REWARD_UNDERLINE_TEXT = "Chance to drop from defeated <HyperLink stylename=\"Underline\" u=\"\">minor monsters</>",
    PVP_LAST_HUNT_MONSTER_RECOMMEND_GROUP = "Group Recommended",
    PVP_LAST_HUNT_MONSTER_RECOMMEND_TEAM = "Party Recommended",
    PVP_LAST_HUNT_MONSTER_SUMMON_BUTTON_NAME = "Go to Summon",
    PVP_LAST_HUNT_MONSTER_SUMMON_LEFT_COUNT_FORMAT = "Summons remaining this week: %d",
    PVP_LAST_HUNT_NOT_OPENED_BUTTON_TEXT = "Available when the event begins",
    PVP_LAST_HUNT_RANK_TAB_GUILD_NAME = "Club",
    PVP_LAST_HUNT_RANK_TAB_PERSONAL_NAME = "Personal",
    PVP_LAST_HUNT_RESURGENCE_TIPS = "Select a respawn point, then click Go",
    PVP_LAST_HUNT_RESURGENCE_TITLE = "Select Respawn Point",
    PVP_LAST_HUNT_REVIVE_BUTTON_NAME = "Go to Respawn",
    PVP_LAST_HUNT_REWARD_PREVIEW_TITLE = "Quest Reward Preview",
    PVP_LAST_HUNT_SCORE_TITLE = "Rank Points",
    PVP_LAST_HUNT_SEND_BUTTON_TITLE = "Send Horn",
    PVP_LAST_HUNT_SEND_CHAT_DEFAULT_TEXT = "Brothers, come help me",
    PVP_LAST_HUNT_SEND_DEFAULT_TIP_TEXT = "Summon up to %d players",
    PVP_LAST_HUNT_SEND_PANEL_TIPS = "Summon up to 14 players",
    PVP_LAST_HUNT_SEND_PANEL_TITLE = "Send Horn",
    PVP_LAST_HUNT_SETTLE_MENT_ASSIST_NUM_TITLE = "Assists",
    PVP_LAST_HUNT_SETTLE_MENT_CANCEL = "Cancel",
    PVP_LAST_HUNT_SETTLE_MENT_KILL_NUM_TITLE = "Kills",
    PVP_LAST_HUNT_SETTLE_MENT_LEAVE = "Teleport Away",
    PVP_LAST_HUNT_SETTLE_MENT_PROGRESS_NUM_TITLE = "Hunt Settlement",
    PVP_LAST_HUNT_SETTLE_MENT_SCORE_NUM_TITLE = "Rank Points",
    PVP_LAST_HUNT_SETTLE_MENT_TITLE = "Hunt Settlement",
    PVP_LAST_HUNT_SUBMIT_CONTENT = "Submit Scarlet Relic materials in exchange for Hunt Vouchers",
    PVP_LAST_HUNT_SUBMIT_REFRESH_DESC = "The Hunting Butler changes position on the map every 30 minutes. More Butlers appear when combat is intense.",
    PVP_LAST_HUNT_SUBMIT_REFRESH_TITLE = "Refresh Rules",
    PVP_LAST_HUNT_SUBMIT_TITLE = "Hunting Butler",
    PVP_LAST_HUNT_SUMMON_AUTHOER_FORMAT = "(Summoned by: %s)",
    PVP_LAST_HUNT_SUMMON_MONSTER_GET_NUM = "Attempts Obtained",
    PVP_LAST_HUNT_SUMMON_MONSTER_LACK_NUM = "No attempts remain this week. Earn Hunt Vouchers to obtain more.",
    PVP_LAST_HUNT_TASK_BUFF_NAME = "Power of Sighs",
    PVP_LAST_HUNT_TASK_COMMIT_TEXT = "Go to Submit",
    PVP_LAST_HUNT_TASK_FINISH_TITLE_TEXT = "Ended",
    PVP_LAST_HUNT_TASK_FRAGMENT_NAME = "Prey Fragment",
    PVP_LAST_HUNT_TASK_NOT_ACTIVE_CONTENT_TEXT = "Use a Seed of Sighs, defeat monsters or plunder players to obtain Prey Fragments, then submit them to the Earl of Order for rewards.",
    PVP_LAST_HUNT_TASK_NOT_ACTIVE_FINISH_TEXT = "The quest has ended. Find the Earl of Order to submit your fragments for rewards.",
    PVP_LAST_HUNT_TASK_NOT_ACTIVE_TEXT = "Inactive",
    PVP_LAST_HUNT_TASK_PROGRESS_TEXT = "Hunt Progress",
    PVP_LAST_HUNT_TASK_PROP_TEXT = "Seed of Sighs",
    PVP_LAST_HUNT_TASK_QUICK_TEAM = "Quick Party",
    PVP_LAST_HUNT_TASK_TITLE_NAME = "Final Hunt",
    PVP_LAST_HUNT_TITLE_DETAIL_NAME = "Details",
    PVP_LAST_HUNT_TITLE_FOLD_NAME = "Collapse",
    PVP_LAST_HUNT_USE_ITEM_NOT_ACTIVITY_OPEN_FORMAT = "Cannot be used outside event hours. Event time: <highlight>%s-%s</>",
    PVP_LAST_HUNT_USE_ITEM_PROP_DESC = "Using Seed of Sighs...",
    PVP_LAST_HUNT_USE_TASK_TEXT_NAME = "Go to Accept Quest",
    RED_PACKET_ALREADY_RECEIVED = "Claimed",
    SECRET_PARTNER_BTN_ALREADY_CHANGE_ACTOR_NAME = "Shifting",
    SECRET_PARTNER_BTN_CHANGE_ACTOR_NAME = "Shift",
    SECRET_PARTNER_CANCEL_CHANGE_ACTOR = "Cancel Shift",
    SECRET_PARTNER_CHANGE_ACTOR_TITLE = "Shift Target",
    SECRET_PARTNER_SKILL_TEXT = "Marionette Skill",
    SECRET_PARTNER_STAR_UP_TEXT_FORMAT = "Sequence %d",
    SKILL_PRESET_TAB_1 = "Recommended Builds",
    TASK_TRACE_DISTANCE = "m",
    TRINITY_ALL_TREASURE_HAVE_CLAIMED = "All Rewards Claimed",
    TEAM_INVITE_SECRET_PARTNER_TITLE = "Illusion Application",
    UIAPPEARANCE_USE = "Use",
    UIAPPEARANCE_USING = "In Use",
}

-- This quest validates the literal Chinese chat input server-side. Keep only
-- the password Chinese so the surrounding quest instructions remain English.
local QUEST_CHAT_PASSWORD_EN = "The storm is stronger than spirits"
local QUEST_CHAT_PASSWORD_ZH = "风暴比烈酒更烈"
local ENTER_WORLD_LABEL_LONG = "Enter the Extraordinary World"
local ENTER_WORLD_LABEL_SHORT = "Enter World"

local function shortenEnterWorldLabel(value)
    if value == ENTER_WORLD_LABEL_LONG then
        return ENTER_WORLD_LABEL_SHORT
    end
    return value
end

local function restoreQuestChatPassword(value)
    if type(value) ~= "string" or not value:find(QUEST_CHAT_PASSWORD_EN, 1, true) then
        return value
    end
    return value:gsub(QUEST_CHAT_PASSWORD_EN, function()
        return QUEST_CHAT_PASSWORD_ZH
    end)
end

-- These strings are emitted by Launch 1.2 dialogue/widgets without a stable
-- StringDB key. Keep the replacements exact or narrowly scoped so the
-- aggregate entry for 米 (which legitimately means "Rice" in chat/filter
-- data) is not changed globally.
local visibleTextExactOverrides = {
    ["命运道标"] = "Bacon of Destiny",
    ["Beacon of Destiny"] = "Bacon of Destiny",
    ["“正义”和“倒吊人”开始默写记忆中的文字……"] =
        "\"Justice\" and \"The Hanged Man\" begin writing down the words from memory...",
    ["两位先生离开了，不知何时才能看到这充满风采的照片……"] =
        "The two gentlemen have left. Who knows when I'll get to see this splendid photograph...",
    ["机动"] = "Mobility",
    ["射程"] = "Range",
    ["Win by Lying Down"] = "Easy Wins",
    ["在<h>【附近】/【世界】</>聊天栏中打字输入“<HyperLink stylename=\"h\">风暴比烈酒更烈</>”"] =
        "Type \"<HyperLink stylename=\"h\">风暴比烈酒更烈</>\" in the <h>[Nearby]/[World]</> chat bar",
    ["所向披靡，无往不利！{{player.name}}在<Chat_Highlight>{{gameMode.name}}</>中获得<Chat_Highlight>{{eventMessageParams.curWinStreak}}连胜</>，战场之上，新的神话已在书写！"] =
        "Invincible and unstoppable! {{player.name}} has achieved a <Chat_Highlight>{{eventMessageParams.curWinStreak}} win streak</> in <Chat_Highlight>{{gameMode.name}}</>! On the battlefield, a new legend is being written!",
    ["Invincible and unstoppable! {{player.name}} has achieved a <Chat_Highlight>{{eventMessageParams.curWinStreak}} win streak in <Chat_Highlight>{{gameMode.name}}</>! On the battlefield, a new legend is being written!</>"] =
        "Invincible and unstoppable! {{player.name}} has achieved a <Chat_Highlight>{{eventMessageParams.curWinStreak}} win streak</> in <Chat_Highlight>{{gameMode.name}}</>! On the battlefield, a new legend is being written!",
    ["推理检定"] = "Deduction Check",
    ["发现它变成了一份地图，还标注了奇迹降临的位置……"] =
        "You discover it has become a map, marking the location where the miracle will occur...",
    ["沙利亚特"] = "Sariat",
    ["迪尼特"] = "Dinit",
    ["罗、罗茜！你今天过得好吗？"] = "R-Rosie! How are you today?",
    ["罗、罗茜！你今天过得好吗?"] = "R-Rosie! How are you today?",
    ["啊，弗雷泽！我很好，这束花是……"] =
        "Oh, Frazier! I'm doing well. Is that bouquet...?",
    ["啊，弗雷泽！我很好，这束花是......"] =
        "Oh, Frazier! I'm doing well. Is that bouquet...?",
    ["啊，弗雷泽！我很好，这束花是..."] =
        "Oh, Frazier! I'm doing well. Is that bouquet...?",
    ["我想把它送给你，其实，我对你……"] =
        "I wanted to give it to you. Actually, I...",
    ["我想把它送给你，其实，我对你......"] =
        "I wanted to give it to you. Actually, I...",
    ["我想把它送给你，其实，我对你..."] =
        "I wanted to give it to you. Actually, I...",
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
    ["在目标位置召唤窥秘之眼，对目标造成持续伤害和减速。"] =
        "Summon an Eye of Mystery at the target location, dealing continuous damage and slowing the target.",
    ["感知灵界，观测星空，通过灵性物品启示的命运变化，解读其映射的现实空间异动、事态发展走向与潜在未知危险。"] =
        "Sense the spirit world and observe the stars. Interpret the changes in fate revealed by spiritual items to discern the real-world disturbances they reflect, how events may unfold, and potential unknown dangers.",
    ["占星启示期间，周围的玩家可以获得临时技能来获取占星指引。"] =
        "During Astrological Revelation, nearby players can gain a temporary skill to receive astrological guidance.",
    ["使自身获得武力加4，直觉加2。使用临时技能获取占星指引的玩家也可以获得武力加4，直觉加2。"] =
        "Gain +4 Might and +2 Intuition. Players who use the temporary skill to receive astrological guidance also gain +4 Might and +2 Intuition.",
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
    ["坏了，我可能把<P_Yellow>生物催长剂</>当成椰蓉洒在蛋糕上了！"] =
        "Oh no, I may have sprinkled the <P_Yellow>bio-growth stimulant</> on the cake instead of shredded coconut!",
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
    ["你在廷根的集体意识中失去了形态，意识正在退回现实..."] =
        "You lost form within Tingen's collective consciousness. Your consciousness is returning to reality...",
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
    ["男子：（癫狂）万物的“母亲”，赐予我们新生！"] =
        "Man: (Manically) \"Mother\" of all things, grant us rebirth!",
    ["“愚者”：拿上这个。"] = "\"The Fool\": Take this.",
    ["丑人：（有效期十四年？为什么要签这么久的合同……）"] =
        "Ugly Man: (Valid for fourteen years? Why would I need to sign such a long contract...)",
    ["弗莱"] = "Frye",
    ["伦纳德"] = "Leonard",
    ["罗珊"] = "Rozanne",
    ["没有太大危险了，不用特别在意。"] =
        "There's no real danger anymore, so you don't need to worry.",
    ["罗珊小姐，这个铃铛是用来做什么的？"] =
        "Miss Rozanne, what is this bell for?",
    ["三律之背反"] = "Antinomy of the Three Laws",
    ["镜像之自我"] = "Mirrored Self",
    ["技能增强提高<Mark>30</>。"] = "Skill Enhancement increased by <Mark>30</>.",
    ["技能增强提高<Mark>30</>。\n激活套装<Mark>灵与知回响</>时不生效。"] =
        "Skill Enhancement increased by <Mark>30</>.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    ["<CostRed>{1,2,（烙印已失效）}</>技能增强提高<Mark>30</>。\n激活套装<Mark>灵与知回响</>时不生效。"] =
        "<CostRed>{1,2,(Brand inactive)}</>Skill Enhancement increased by <Mark>30</>.\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active.",
    ["技能增强提高30。\n激活套装灵与知回响时不生效。"] =
        "Skill Enhancement increased by 30.\nDoes not take effect while the Echo of Spirit and Knowledge set is active.",
}

-- Nearby NPC chat can prepend a channel and translated speaker name to the
-- authored line inside the same widget. Replace only the exact Chinese body
-- and preserve that live prefix.
visibleTextExactOverrides.__translateNearbyConfessionDialogue = function(value)
    for _, replacement in ipairs({
        { "罗、罗茜！你今天过得好吗？", "R-Rosie! How are you today?" },
        { "罗、罗茜！你今天过得好吗?", "R-Rosie! How are you today?" },
        { "啊，弗雷泽！我很好，这束花是……", "Oh, Frazier! I'm doing well. Is that bouquet...?" },
        { "啊，弗雷泽！我很好，这束花是......", "Oh, Frazier! I'm doing well. Is that bouquet...?" },
        { "啊，弗雷泽！我很好，这束花是...", "Oh, Frazier! I'm doing well. Is that bouquet...?" },
        { "我想把它送给你，其实，我对你……", "I wanted to give it to you. Actually, I..." },
        { "我想把它送给你，其实，我对你......", "I wanted to give it to you. Actually, I..." },
        { "我想把它送给你，其实，我对你...", "I wanted to give it to you. Actually, I..." },
    }) do
        local first, last = value:find(replacement[1], 1, true)
        if first ~= nil then
            return value:sub(1, first - 1) .. replacement[2] .. value:sub(last + 1)
        end
    end
    return value
end

-- These current-season material descriptions are delivered outside the
-- reviewed static StringDB corpus. Match the complete semantic signature after
-- removing rich-text tags so wrapping and highlight changes do not bypass the
-- translation.
local function translateSeasonBroochDescription(value)
    if type(value) ~= "string" then
        return value
    end
    local plain = value:gsub("<[^>]+>", "")
    if not plain:find("至多累计至15个。", 1, true) then
        return value
    end
    if plain:find("铸造神话品质胸针（竞技倾向）的关键材料。", 1, true)
        and plain:find("灰雾晶砾", 1, true)
    then
        return "Key material for forging a Mythical-quality brooch (<Highlight>Competitive</>).\n\n"
            .. "Forging consumes <Highlight>15</> Gray Fog Crystal Grit to create an Item Level 64 Mythical-quality brooch (<Highlight>Competitive</>).\n\n"
            .. "As the season progresses, item-level upgrades for Mythical brooches (Competitive) will unlock. Each upgrade consumes a certain amount of Gray Fog Crystal Grit.\n\n"
            .. "Each week, you can obtain up to <Highlight>3</> Gray Fog Crystal Grit directly from Final Hunt, Four-Way League, Hunting City Battle/Highland Battle, and Sustain War with War Treasures. Any unearned amount carries over to the next week, up to a maximum of <Highlight>15</>."
    end
    if plain:find("铸造神话品质胸针（冒险倾向）的关键材料。", 1, true)
        and plain:find("灰雾尘埃", 1, true)
    then
        return "Key material for forging a Mythical-quality brooch (<Highlight>Adventure</>).\n\n"
            .. "Forging consumes <Highlight>15</> Gray Fog Dust to create an Item Level 64 Mythical-quality brooch (<Highlight>Adventure</>).\n\n"
            .. "As the season progresses, item-level upgrades for Mythical brooches (Adventure) will unlock. Each upgrade consumes a certain amount of Gray Fog Dust.\n\n"
            .. "Each week, you can obtain up to <Highlight>3</> Gray Fog Dust directly from Party Dungeons, Team Dungeons, and World Adventure Treasures. Any unearned amount carries over to the next week, up to a maximum of <Highlight>15</>."
    end
    return value
end

local function translateFamilyRecruitmentGuide(value)
    if type(value) ~= "string" then
        return value
    end
    local plain = value:gsub("<[^>]+>", ""):gsub("\r\n", "\n")
    if not plain:find("家族申请表：", 1, true)
        or not plain:find("响应招募：", 1, true)
        or not plain:find("创建家族：", 1, true)
        or not plain:find("加入家族：", 1, true)
    then
        return value
    end

    local expiryDays = plain:find("发布3天后", 1, true) and "3" or "7"
    return "1. <Highlight>Family Application:</> Any Beyonder who has not joined a family can publish a personal application to find a suitable family. The application is automatically withdrawn "
        .. expiryDays .. " days after publication or after successfully joining a family.\n"
        .. "2. <Highlight>Recruitment Response:</> Beyonders who have not joined a family may start a recruitment response or join one started by another Beyonder. The initiator becomes the <Highlight>Family Chief</> by default.\n"
        .. "3. <Highlight>Create Family:</> During the recruitment-response phase, a family can be created once at least <Highlight>3 people</> have responded. During creation, the Chief can adjust the family name and member positions.\n"
        .. "4. <Highlight>Join Family:</> When a family has fewer than <Highlight>14 members</>, the Chief can recruit. Other Beyonders may apply and join directly after the Chief approves their application."
end

-- EquipmentUniqueData descriptions pass through a conditional rich-text
-- formatter before they are painted. Match the complete semantic signature so
-- CostRed/Mark tag variations and the already-formatted plain form take the
-- same reviewed translation path.
visibleTextExactOverrides.__translateEquipmentSpecialText = function(value)
    if type(value) ~= "string" then
        return value
    end
    local plain = value:gsub("<[^>]+>", ""):gsub("\r\n", "\n")
    if not plain:find("激活套装灵与知回响时不生效。", 1, true) then
        return value
    end

    local prefix = ""
    if value:find("<CostRed>", 1, true) then
        prefix = "<CostRed>{1,2,(Brand inactive)}</>"
    end
    local inactive = "\nDoes not take effect while the <Mark>Echo of Spirit and Knowledge</> set is active."

    if plain:find("技能增强提高30。", 1, true) then
        return prefix .. "Skill Enhancement increased by <Mark>30</>." .. inactive
    end
    if plain:find("释放解控技能后，获得50点技能抵挡", 1, true)
        and plain:find("每30秒最多触发一次。", 1, true)
    then
        return prefix
            .. "After using a Cleanse Skill, gain <Mark>50</> Skill Block for <Mark>10</> seconds. "
            .. "Can trigger at most once every <Mark>30</> seconds."
            .. inactive
    end
    if plain:find("破防提高80。", 1, true)
        and plain:find("获得60点防御", 1, true)
        and plain:find("每10秒最多触发一次。", 1, true)
    then
        return prefix
            .. "Armor Break increased by <Mark>80</>. When taking damage, there is a chance to gain "
            .. "<Mark>60</> Defense for <Mark>5</> seconds. Can trigger at most once every <Mark>10</> seconds."
            .. inactive
    end
    return value
end

-- Sealed Artifact descriptions are evaluated before display, so CheckStar
-- expressions become live numbers and no longer match the source template.
-- Rebuild the complete reviewed text from its semantic fields while retaining
-- every evaluated value supplied by the game.
visibleTextExactOverrides.__translateLifeStaffDetails = function(value)
    if type(value) ~= "string" then
        return value
    end
    local plain = value:gsub("<[^>]+>", ""):gsub("\r\n", "\n")
    if not plain:find("生命能量", 1, true)
        or not plain:find("蓬勃生长", 1, true)
        or not plain:find("生命之种", 1, true)
        or not plain:find("累计有效治疗", 1, true)
    then
        return value
    end

    local interval = plain:match("每隔([%d%.,]+)秒")
    local energyLimit = plain:match("持有上限为([%d%.,]+)点")
    local healingThreshold = plain:match("生命值上限的([%d%.,]+)%%")
    local growthStacks = plain:match("附加([%d%.,]+)层")
    local growthDuration = plain:match("蓬勃生长.-持续([%d%.,]+)秒")
    local seedLimit = plain:match("生命之种.-持有上限为([%d%.,]+)枚")
    local growthLine = plain:match("蓬勃生长：([^\n]+)") or ""
    local healingAmount = growthLine:match("恢复([%d%.,]+)点生命值")
    local seedLine = plain:match("生命之种：([^\n]+)") or ""
    local lowHealthThreshold = seedLine:match("生命值低于([%d%.,]+)%%")
    local seedRecovery = seedLine:match("固定恢复([%d%.,]+)%%上限")
    if interval == nil or energyLimit == nil or healingThreshold == nil
        or growthStacks == nil or growthDuration == nil or seedLimit == nil
        or healingAmount == nil or lowHealthThreshold == nil or seedRecovery == nil
    then
        return value
    end

    local translated = "<Yellow>Life Energy</>: The bearer gains 1 Life Energy every <Yellow>"
        .. interval .. " seconds</>, up to <Yellow>" .. energyLimit .. "</>. When the bearer's cumulative "
        .. "effective healing to themself or an ally exceeds <Yellow>" .. healingThreshold
        .. "%</> of the bearer's maximum HP, 1 Life Energy is consumed to apply <Yellow>"
        .. growthStacks .. "</> stacks of <Yellow>Flourishing Growth</> to the target for <Yellow>"
        .. growthDuration .. " seconds</>. The bearer also gains 1 <Yellow>Seed of Life</>, up to <Yellow>"
        .. seedLimit .. "</>.\n\n<Yellow>Flourishing Growth</>: While HP is not full, consumes 1 stack "
        .. "per second to restore <Yellow>" .. healingAmount .. "</> HP.\n<Yellow>Seed of Life</>: "
        .. "When the bearer takes damage below <Yellow>" .. lowHealthThreshold
        .. "%</> HP, automatically consumes 1 Seed of Life to restore <Yellow>"
        .. seedRecovery .. "%</> of maximum HP."
    if plain:find("主宰争锋", 1, true) then
        translated = translated
            .. "\nWhile in Dominator's Clash, Life Staff effects are reduced."
    end
    return translated
end

-- Brass Book bounty descriptions are formatted with live progress before display.
visibleTextExactOverrides.__translateBrassBookBounty = function(value)
    if type(value) ~= "string" then return value end
    local plain = value:gsub("（", "("):gsub("）", ")"):gsub("　", " "):gsub(" ", " ")
    local current, target = plain:match("^获取城市暗面玩法悬赏值%s*([%d,]+)/([%d,]+)。%s*%(黄铜书挑战开启后计数%)%s*$")
    if current == nil then return value end
    return "Earn " .. current .. "/" .. target
        .. " bounty points in City of Shadows. (Counted after the Brass Book Challenge begins.)"
end


local visibleTextReplacements = {
    {
        "绯红月辉？难道是这张红月纸牌？用它试试。",
        "Crimson moonlight? Could this Red Moon card be it? Let's try it.",
    },
    { "点击空白区域关闭", "Click blank area to close" },
    { "跳过", "Skip" },
    { "推荐非凡评分", "Recommended Beyonder Rating" },
    { "非凡评分", "Beyonder Rating" },
    { "塞巴斯蒂安", "Sebastian" },
    { "寒巴斯蒂安", "Sebastian" },
    { "男子：", "Man: " },
    { "丑人：", "Ugly Man: " },
    { "“愚者”：", "\"The Fool\": " },
    { "愚者", "The Fool" },
    { "（癫狂）", "(Manically) " },
    { "万物的“母亲”", "\"Mother\" of all things" },
    { "赐予我们新生", "grant us rebirth" },
    { "拿上这个", "Take this" },
    { "有效期十四年？为什么要签这么久的合同……", "Valid for fourteen years? Why would I need to sign such a long contract..." },
    {
        "感知灵界，观测星空，通过灵性物品启示的命运变化，解读其映射的现实空间异动、事态发展走向与潜在未知危险。",
        "Sense the spirit world and observe the stars. Interpret the changes in fate revealed by spiritual items to discern the real-world disturbances they reflect, how events may unfold, and potential unknown dangers.",
    },
    {
        "占星启示期间，周围的玩家可以获得临时技能来获取占星指引。",
        "During Astrological Revelation, nearby players can gain a temporary skill to receive astrological guidance.",
    },
    {
        "使自身获得武力加4，直觉加2。使用临时技能获取占星指引的玩家也可以获得武力加4，直觉加2。",
        "Gain +4 Might and +2 Intuition. Players who use the temporary skill to receive astrological guidance also gain +4 Might and +2 Intuition.",
    },
}

-- Exact localization keys from build 1.2018737.2044036. These repair rows
-- that were evaluated before the translated StringDB partitions were ready.
local marionetteSkillLocalization = {
    [87303001] = { 286217962784256, 286218768090624, 286218231219712, 514572247120128 },
    [87303002] = { 286217962784512, 286218768090880, 286218231219968, 514572247120128 },
    [87303003] = { 286217962784256, 286218768090624, nil, 514572247120128 },
    [87303004] = { 286217962785024, 286218768091392, 286218231220480, 286219304962304 },
    [87303010] = { 286217962786048, 286218768092416, 286218231221504, 286219304963328 },
    [87303020] = { 286217962786560, 286218768092928, 286218231222016, 286219304963840 },
    [87303030] = { 286217962787840, 286218768094208, 286218231223296, 286219304965120 },
    [87303040] = { 286217962791168, 286218768097536, 286218231226624, 1240250726755840 },
    [87303050] = { 998771022366208, 286218768099840, 286218231228928, 286219304970752 },
    [87303060] = { 286217962794240, 286218768100608, 286218231229696, 286219304971520 },
    [87303070] = { 286217962795264, 286218768101632, 286218231230720, 514572247120128 },
    [87303071] = { 286217962795776 },
    [87303072] = { 286217962796032 },
    [87303080] = { 286217962796288, 286218768102656, 286218231231744, 286219304965120 },
    [87303090] = { 286217962797824, 286218768104192, 286218231233280, 286219304975104 },
    [87303100] = { 286217962798848, 286218231234304, 286218231234304, 514572247120128 },
    [87303110] = { 286217962799360, 286218768105728, 286218231234816, 202518445427712 },
    [87303120] = { 286217962799872, 286218768106240, 286218231235328, 294670189988096 },
    [87303130] = { 286217962800384, 286218768106752, 286218231235840, 286219304977664 },
    [87303140] = { 286217962801152, 286218768107520, 286218231236608, 286219304970752 },
    [87303150] = { 286217962802688, 286218768109056, 286218231238144, 294670189993984 },
    [87303160] = { 998771022396928, 286218768109824, 286218231238912, 286219304980736 },
    [87303170] = { 998771022409216, 286218768110848, 286218231239936, 286219304971520 },
    [87303180] = { 286217962805504, 286218768111872, 286218231240960 },
    [87303190] = { 286217962806016, 286218768112384, 286218231241472 },
    [87303200] = { 998771022398464, 286218768112896, 286218231241984, 286219304965120 },
    [87303210] = { 998771022400000, 286218768113664, 286218231242752, 286219304971520 },
    [87303220] = { 286217962787840, 286218768094208, 286218231223296, 286219304965120 },
    [87303300] = { 286217962808064, 286218768114432, 286218231243520, 294670189988352 },
    [87303310] = { 286217962808576, 286218768114944, 286218231244032, 294670189988096 },
    [87303320] = { 286217962809344, 286218768115712, 286218231244800, 286219304971520 },
    [87303330] = { 286217962810368, 286218768116736, 286218231245824, 286219304971520 },
    [87303340] = { 286217962811136, 286218768117504, 286218231246592, 286219304988416 },
    [87303350] = { 286217962811648, 286218768118016, 286218231247104, 294670189988864 },
    [87303360] = { 286217962812160, 286218768118528, 286218231247616, 1240250995202816 },
    [87303370] = { 286217962812928, 286218768119296, 286218231248384, 286219304970752 },
    [87303380] = { 286217962813440, 286218768119808, 286218231248896, 255362649299968 },
    [87303390] = { 286217962813952, 286218768120320, 286218231249408, 286219304965120 },
    [87303400] = { 286217962814464, 286218768120832, 286218231249920, 282026343139328 },
    [87303410] = { 286217962814976, 286218768121344, 286218231250432, 514572247120128 },
    [87303420] = { 286217962815744, 286218768122112, 286218231251200, 514572247120128 },
    [87303430] = { 286217962816256, 286218768122624, 286218231251712, 514572247120128 },
    [87303440] = { 286217962816768, 286218768123136, 286218231252224, 514572247120128 },
}

local marionetteEnglishNames = {
    [87303350] = "Dawn Arrival",
    [87303360] = "Arbitration Brand",
    [87303370] = "Mystery Pry Gaze",
    [87303380] = "Morning Light Protection",
    [87303390] = "Knight's Oath",
    [87303400] = "Butterfly Spirit Possession",
    [87303410] = "Descending Shadow",
    [87303420] = "Death Knell Echo",
    [87303430] = "Alpha Wolf Claw Combo",
    [87303440] = "Drill Protection",
}

local marionetteSkillIdByIconNumber = {
    [14] = 87303410,
    [20] = 87303350,
    [21] = 87303360,
    [22] = 87303370,
    [23] = 87303380,
    [24] = 87303390,
    [25] = 87303400,
    [31] = 87303420,
    [32] = 87303430,
    [33] = 87303440,
}

local shortMenuLabels = {
    Fashion = "Style",
    Pastime = "Explore",
    Dungeon = "Dungeon",
    PVP = "Arena",
    Equip = "Gear",
    Skill = "Skills",
    Talent = "Talent",
    Promotion = "Pathway",
    Sealed = "Relics",
    SecretPartner = "Puppets",
    Fellow = "Allies",
    Paotuan = "TRPG",
    Guild = "Club",
    Home = "Castle",
    Task = "Quests",
    Family = "Family",
    Qingyuan = "Bonds",
    Achievement = "Awards",
    Strategy = "Guide",
    VideoCreation = "Creator",
    Friend = "Friends",
    ShadowCity = "DarkCity",
    Character = "Profile",
    HomePage = "Home",
    Bag = "Bag",
    Notice = "News",
    Email = "Mail",
    Rank = "Ranking",
    Detach = "Unequip",
    Setting = "Settings",
    QuitGame = "Exit",
}

local directTables = {}
local MISSING_DIRECT_TABLE = {}
local function report(message)
    local logger = Log or LaunchLog
    if logger and logger.Info then
        logger.Info("[CPDDRuntimeFix] " .. tostring(message))
    end
end

local runtimeMetrics = {
    GeminiLoads = 0,
    GeminiShardLoadMillis = 0,
    GeminiShardEvictions = 0,
    GeminiShardReloads = 0,
    GeminiLookupCacheHits = 0,
    GeminiLookupCacheMisses = 0,
    GeminiLookupCacheEvictions = 0,
    SourceShardLoads = 0,
    SourceShardLoadMillis = 0,
    SourceShardEvictions = 0,
    SourceShardReloads = 0,
    SourceShardHits = 0,
    SourceShardMisses = 0,
    TranslationCacheHits = 0,
    TranslationCacheMisses = 0,
    LiveRepairCacheHits = 0,
    LiveRepairCacheMisses = 0,
    WidgetIndexesBuilt = 0,
    WidgetTreeReplacements = 0,
    WidgetCacheInvalidations = 0,
    GetAllWidgetsCalls = 0,
    WidgetsVisited = 0,
    PanelsRepaired = 0,
    PanelRepairMillis = 0,
    PanelLabelsRepaired = 0,
    PanelRepairReportsSuppressed = 0,
    SlowPanelRepairs = 0,
    SlowTargetedRepairs = 0,
    TargetedPanelSkips = 0,
    NestedComponentSkips = 0,
    NestedRefreshCoalesces = 0,
    SinglePassPanelSkips = 0,
    TaskBoardTargetRuns = 0,
    TaskBoardTargetComponents = 0,
    TaskBoardTargetWidgetsFound = 0,
    TaskBoardTargetLabelsRepaired = 0,
    TaskBoardTargetFailures = 0,
    KsbcFallbacks = 0,
    UnresolvedVisibleCjk = 0,
    UnresolvedCjkWrites = 0,
    UnresolvedCjkWriteFailures = 0,
    CaptureDataAssignmentsEnabled = false,
}
local runtimeFixes = {}
-- These IDs describe confirmed, distinct player attributes. Numeric IDs from
-- downloaded localization data are normally treated as non-authoritative, but
-- these overrides may safely win when the live value still matches one of the
-- known aliases. This keeps an unrelated shifted KMF row from being relabeled.
runtimeFixes.AuthoritativeAggregateAliases = {
    [255431368783360] = {
        ["破甲"] = true,
        ["Armor Break"] = true,
        ["Shield Break"] = true,
    },
    [141494476346368] = {
        ["破防"] = true,
        ["Armor Break"] = true,
        ["Armor Penetration"] = true,
        ["Defense Break"] = true,
    },
    [255431368777472] = {
        ["物理破防"] = true,
        ["Physical Armor Break"] = true,
        ["Physical Armor Penetration"] = true,
        ["Physical Defense Break"] = true,
    },
    [255431368780800] = {
        ["魔法破防"] = true,
        ["Magic Armor Break"] = true,
        ["Magic Armor Penetration"] = true,
        ["Magic Defense Break"] = true,
    },
}

function runtimeFixes.normalizeDefenseBreakTerminology(value)
    if type(value) ~= "string" then
        return value
    end
    value = value:gsub("Physical Armor Break", "Physical Defense Break")
    value = value:gsub("Magic Armor Break", "Magic Defense Break")
    return value
end
Loader.Telemetry = Loader.Telemetry or {}
Loader.Telemetry.Runtime = runtimeMetrics

local function nowMilliseconds()
    if os and type(os.clock) == "function" then
        return os.clock() * 1000
    end
    return 0
end

local function runtimeRowRepairEnabled()
    local loader = rawget(_G, "LOMModLoader")
    local features = loader and loader.Features
    if type(features) ~= "table" then
        return true
    end
    return features.RuntimeRowRepair ~= false
end

local function setRuntimeRowRepair(enabled)
    local loader = rawget(_G, "LOMModLoader")
    if loader == nil then
        loader = { Features = {} }
        rawset(_G, "LOMModLoader", loader)
    elseif type(loader.Features) ~= "table" then
        loader.Features = {}
    end
    loader.Features.RuntimeRowRepair = enabled == true
    return loader.Features.RuntimeRowRepair
end

local function runtimeUIRepairEnabled()
    local loader = rawget(_G, "LOMModLoader")
    local features = loader and loader.Features
    if type(features) ~= "table" then
        return true
    end
    return features.RuntimeUIRepair ~= false
end

local function setRuntimeUIRepair(enabled)
    local loader = rawget(_G, "LOMModLoader")
    if loader == nil then
        loader = { Features = {} }
        rawset(_G, "LOMModLoader", loader)
    elseif type(loader.Features) ~= "table" then
        loader.Features = {}
    end
    loader.Features.RuntimeUIRepair = enabled == true
    return loader.Features.RuntimeUIRepair
end

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

local geminiTextCache = {
    Shards = {},
    Order = {},
    Missing = {},
    Seen = {},
    Lookups = {},
    LookupOrder = {},
    LookupWriteIndex = 1,
    LookupCount = 0,
    ShardLimit = 128,
    LookupLimit = 8192,
}

local function touchGeminiShard(prefix)
    for index = #geminiTextCache.Order, 1, -1 do
        if geminiTextCache.Order[index] == prefix then
            table.remove(geminiTextCache.Order, index)
            break
        end
    end
    geminiTextCache.Order[#geminiTextCache.Order + 1] = prefix
    if #geminiTextCache.Order <= geminiTextCache.ShardLimit then return end
    local evicted = table.remove(geminiTextCache.Order, 1)
    geminiTextCache.Shards[evicted] = nil
    package.loaded["mods.cpdd_runtime_fixes.RuntimeTextGemini_" .. evicted] = nil
    runtimeMetrics.GeminiShardEvictions = runtimeMetrics.GeminiShardEvictions + 1
end

local function cacheGeminiLookup(value, translated)
    if geminiTextCache.LookupCount >= geminiTextCache.LookupLimit then
        local evicted = geminiTextCache.LookupOrder[geminiTextCache.LookupWriteIndex]
        if evicted ~= nil then geminiTextCache.Lookups[evicted] = nil end
        runtimeMetrics.GeminiLookupCacheEvictions =
            runtimeMetrics.GeminiLookupCacheEvictions + 1
    else
        geminiTextCache.LookupCount = geminiTextCache.LookupCount + 1
    end
    geminiTextCache.Lookups[value] = translated ~= nil and translated or false
    geminiTextCache.LookupOrder[geminiTextCache.LookupWriteIndex] = value
    geminiTextCache.LookupWriteIndex =
        geminiTextCache.LookupWriteIndex % geminiTextCache.LookupLimit + 1
end

local function lookupGeminiText(value)
    if type(value) ~= "string" then return nil end
    local cached = geminiTextCache.Lookups[value]
    if cached ~= nil then
        runtimeMetrics.GeminiLookupCacheHits = runtimeMetrics.GeminiLookupCacheHits + 1
        return cached ~= false and cached or nil
    end
    runtimeMetrics.GeminiLookupCacheMisses = runtimeMetrics.GeminiLookupCacheMisses + 1
    local key = sourceKey(value)
    local hashPrefix = key:match(":([0-9a-f][0-9a-f][0-9a-f])")
    local prefix = hashPrefix
        and string.format("%03x", math.floor(tonumber(hashPrefix, 16) / 4))
        or nil
    if prefix == nil or geminiTextCache.Missing[prefix] then return nil end

    local shard = geminiTextCache.Shards[prefix]
    if shard == nil then
        local moduleName = "mods.cpdd_runtime_fixes.RuntimeTextGemini_" .. prefix
        local started = nowMilliseconds()
        local ok, loaded = pcall(require, moduleName)
        local elapsed = nowMilliseconds() - started
        runtimeMetrics.GeminiShardLoadMillis = runtimeMetrics.GeminiShardLoadMillis
            + elapsed
        if not ok or type(loaded) ~= "table" then
            geminiTextCache.Missing[prefix] = true
            report("Gemini runtime text shard unavailable " .. prefix .. ": " .. tostring(loaded))
            return nil
        end
        shard = loaded
        if geminiTextCache.Seen[prefix] then
            runtimeMetrics.GeminiShardReloads = runtimeMetrics.GeminiShardReloads + 1
        else
            geminiTextCache.Seen[prefix] = true
        end
        if elapsed >= 8 then
            report("slow Gemini text shard " .. prefix .. " loaded in "
                .. string.format("%.2f", elapsed) .. " ms")
        end
        geminiTextCache.Shards[prefix] = shard
        runtimeMetrics.GeminiLoads = runtimeMetrics.GeminiLoads + 1
    end
    touchGeminiShard(prefix)
    local translated = shard[value]
    cacheGeminiLookup(value, translated)
    return translated
end

-- TextControlSentenceData uses #CanMove...# as executable puzzle markup, not
-- decoration. Translate the visible word inside each marker, but never let a
-- reviewed whole-string translation remove the marker or make it disagree
-- with the separately translated `word` field used to validate the answer.
local function preserveMovableAnswerMarkup(source, translated)
    if type(source) ~= "string" or type(translated) ~= "string"
        or not source:find("#CanMove", 1, true)
    then
        return translated
    end

    local answers = {}
    for inner in source:gmatch("#CanMove(.-)#") do
        local innerTranslation = lookupGeminiText(inner)
        if type(innerTranslation) ~= "string" or innerTranslation == "" then
            innerTranslation = inner
        end
        answers[#answers + 1] = innerTranslation
    end
    if #answers == 0 then
        return translated
    end

    local markerIndex = 0
    local repaired, markerCount = translated:gsub("#CanMove.-#", function()
        markerIndex = markerIndex + 1
        return "#CanMove" .. (answers[markerIndex] or answers[#answers]) .. "#"
    end)
    if markerCount == #answers then
        return repaired
    end

    if #answers == 1 and source:match("^#CanMove.-#$") then
        return "#CanMove" .. answers[1] .. "#"
    end

    -- A few contextual translations moved the answer within the English
    -- sentence while dropping its marker. Locate the translated answer in the
    -- reviewed sentence and restore the control tag around that exact span.
    if #answers == 1 then
        local haystack = translated:lower():gsub("grey", "gray")
        local needle = answers[1]:lower():gsub("grey", "gray")
        local first, last = haystack:find(needle, 1, true)
        if first ~= nil then
            return translated:sub(1, first - 1)
                .. "#CanMove" .. answers[1] .. "#"
                .. translated:sub(last + 1)
        end
    end
    return translated
end

local function getSymbol(value, environment, name)
    if type(value) == "table" and value[name] ~= nil then
        return value[name]
    end
    if type(environment) == "table" and environment[name] ~= nil then
        return environment[name]
    end
    return rawget(_G, name)
end

-- Generated Lua views expose only widgets marked as Blueprint variables. The
-- game still contains several important text blocks (including dialogue row 3)
-- that are present in the UWidgetTree but intentionally omitted from that
-- generated view. Resolve both forms, plus the WidgetTree API used by a few
-- older panels.
local widgetLists = setmetatable({}, { __mode = "k" })
local widgetNameIndexes = setmetatable({}, { __mode = "k" })
local NO_WIDGET_LIST = {}

-- Native UWidgetTree enumeration is build-dependent: some C7 builds accept a
-- Lua table as the out array, while others require a typed slua.Array.  The
-- latter was the missing discovery path for cooked Blueprint-only labels.
local unrealArrayTypes = {
    Resolved = false,
    PropertyClass = nil,
    WidgetClass = nil,
}

local function resolveUnrealArrayTypes()
    if unrealArrayTypes.Resolved
        and unrealArrayTypes.PropertyClass ~= nil
        and unrealArrayTypes.WidgetClass ~= nil
    then
        return
    end
    unrealArrayTypes.Resolved = true
    if unrealArrayTypes.PropertyClass == nil then
        pcall(function() unrealArrayTypes.PropertyClass = import("EPropertyClass") end)
    end
    if unrealArrayTypes.WidgetClass == nil then
        pcall(function() unrealArrayTypes.WidgetClass = import("Widget") end)
    end
    if unrealArrayTypes.WidgetClass == nil and slua and type(slua.loadClass) == "function" then
        pcall(function()
            unrealArrayTypes.WidgetClass = slua.loadClass("/Script/UMG.Widget")
        end)
    end
end

local function newWidgetObjectArray()
    resolveUnrealArrayTypes()
    if not slua or type(slua.Array) ~= "function"
        or unrealArrayTypes.PropertyClass == nil
        or unrealArrayTypes.WidgetClass == nil
    then
        return nil
    end
    local ok, output = pcall(
        slua.Array,
        unrealArrayTypes.PropertyClass.Object,
        unrealArrayTypes.WidgetClass
    )
    return ok and output or nil
end

local function unrealArrayToTable(value)
    if type(value) == "table" then return value end
    if value and type(value.ToTable) == "function" then
        local ok, result = pcall(value.ToTable, value)
        if ok and type(result) == "table" then return result end
    end
    if value and type(value.Num) == "function" and type(value.Get) == "function" then
        local output = {}
        local countOk, count = pcall(value.Num, value)
        if countOk and type(count) == "number" then
            for index = 0, count - 1 do
                local itemOk, item = pcall(value.Get, value, index)
                if itemOk and item ~= nil then output[#output + 1] = item end
            end
        end
        return output
    end
    return {}
end

local function invalidateWidgetCache(owner)
    if owner ~= nil then
        if widgetLists[owner] ~= nil or widgetNameIndexes[owner] ~= nil then
            runtimeMetrics.WidgetCacheInvalidations =
                runtimeMetrics.WidgetCacheInvalidations + 1
        end
        widgetLists[owner] = nil
        widgetNameIndexes[owner] = nil
    end
end

local function getWidgetList(owner)
    if owner == nil then
        return nil
    end
    -- Most owners reached by the recursive walk are leaf widgets. Resolve the
    -- tree before allocating an Unreal object array so leaf visits stay cheap.
    local tree = nil
    local getAllWidgets = nil
    local treeOk = pcall(function()
        tree = owner.WidgetTree
        getAllWidgets = tree and tree.GetAllWidgets or nil
    end)
    local cached = widgetLists[owner]
    if cached ~= nil and cached.Tree == tree then
        return cached.Widgets ~= NO_WIDGET_LIST and cached.Widgets or nil
    end
    if cached ~= nil then
        widgetNameIndexes[owner] = nil
        runtimeMetrics.WidgetTreeReplacements =
            runtimeMetrics.WidgetTreeReplacements + 1
    end
    if not treeOk or tree == nil or type(getAllWidgets) ~= "function" then
        widgetLists[owner] = { Tree = tree, Widgets = NO_WIDGET_LIST }
        return nil
    end

    local widgets = newWidgetObjectArray() or {}
    local ok, result = pcall(function()
        runtimeMetrics.GetAllWidgetsCalls = runtimeMetrics.GetAllWidgetsCalls + 1
        return getAllWidgets(tree, widgets)
    end)
    if not ok then
        widgetLists[owner] = { Tree = tree, Widgets = NO_WIDGET_LIST }
        return nil
    end
    widgets = unrealArrayToTable(result ~= nil and result or widgets)
    widgetLists[owner] = { Tree = tree, Widgets = widgets }
    runtimeMetrics.WidgetIndexesBuilt = runtimeMetrics.WidgetIndexesBuilt + 1
    return widgets
end

local function getWidgetNameIndex(owner)
    local widgets = getWidgetList(owner) or {}
    local cached = widgetNameIndexes[owner]
    if cached ~= nil then
        return cached
    end
    local index = {}
    for _, candidate in pairs(widgets) do
        local candidateName = nil
        pcall(function()
            if candidate ~= nil and candidate.GetName ~= nil then
                candidateName = tostring(candidate:GetName())
            end
        end)
        if candidateName ~= nil and index[candidateName] == nil then
            index[candidateName] = candidate
        end
    end
    widgetNameIndexes[owner] = index
    return index
end

local function getNamedWidget(owner, name)
    if owner == nil or type(name) ~= "string" then
        return nil
    end

    local widget = nil
    pcall(function()
        widget = owner[name]
    end)
    if widget ~= nil then
        return widget
    end

    pcall(function()
        if owner.GetWidgetFromName ~= nil then
            widget = owner:GetWidgetFromName(name)
        end
    end)
    if widget ~= nil then
        return widget
    end

    pcall(function()
        local tree = owner.WidgetTree
        if tree ~= nil then
            if tree.FindWidget ~= nil then
                widget = tree:FindWidget(name)
            elseif tree.GetWidgetFromName ~= nil then
                widget = tree:GetWidgetFromName(name)
            end
        end
    end)
    if widget ~= nil then
        return widget
    end

    -- Several cooked UserWidgets keep static Blueprint variables out of both
    -- the generated Lua view and FindWidget/GetWidgetFromName. GetAllWidgets
    -- still exposes them. This is the path used by the third dialogue row and
    -- by embedded copies of the Improve header in Talent/Artifact screens.
    return getWidgetNameIndex(owner)[name]
end

local repairLiveString
local hasCjk
-- Development builds replace this no-op inside the stripped JSONL block.
-- Keeping the callable in production lets the targeted repair remain free of
-- development-only branches and private logging state.
runtimeMetrics.CaptureDataAssignment = function() return false end
runtimeMetrics.CaptureTranslationAssignment = function(...) return runtimeMetrics.CaptureDataAssignment(...) end

local visibleTextCache = {}

local function walkWidgetDescendants(owner, visited, visitor)
    if owner == nil or visited[owner] then
        return
    end
    visited[owner] = true
    runtimeMetrics.WidgetsVisited = runtimeMetrics.WidgetsVisited + 1
    visitor(owner)

    -- Cooked Blueprint variables can be absent from both the generated Lua
    -- view and WidgetTree lookups. Their parent panel is still exposed, and
    -- UPanelWidget child traversal reaches the actual painted text blocks.
    local count = nil
    pcall(function()
        if owner.GetChildrenCount ~= nil then
            count = tonumber(owner:GetChildrenCount())
        end
    end)
    if count ~= nil then
        for index = 0, count - 1 do
            local child = nil
            pcall(function()
                child = owner:GetChildAt(index)
            end)
            walkWidgetDescendants(child, visited, visitor)
        end
    end

    local content = nil
    pcall(function()
        if owner.GetContent ~= nil then
            content = owner:GetContent()
        end
    end)
    walkWidgetDescendants(content, visited, visitor)

    -- ListView and TileView rows are virtualized UUserWidgets. They are not
    -- children of the owning panel's WidgetTree, so text in a displayed item
    -- tooltip can be painted while remaining invisible to the normal tree
    -- walk. Follow only the entries that Unreal currently has on screen; this
    -- is bounded by the viewport and does not enumerate every live widget.
    local getDisplayedEntries = nil
    pcall(function() getDisplayedEntries = owner.GetDisplayedEntryWidgets end)
    if type(getDisplayedEntries) == "function" then
        local displayedEntries = {}
        local displayedOk, displayedResult = pcall(
            getDisplayedEntries,
            owner,
            displayedEntries
        )
        if displayedOk then
            local entries = type(displayedResult) == "table" and displayedResult or displayedEntries
            for _, entry in pairs(entries) do
                walkWidgetDescendants(entry, visited, visitor)
            end
        end
    end

    for _, widget in pairs(getWidgetList(owner) or {}) do
        walkWidgetDescendants(widget, visited, visitor)
    end
end

runtimeFixes.normalizeLocalizedLargeNumbers = function(value)
    if type(value) ~= "string" then
        return value
    end

    local function groupedInteger(number)
        number = math.floor(number + 0.5)
        local grouped = tostring(number)
        while true do
            local nextValue, replacements = grouped:gsub("^(%d+)(%d%d%d)", "%1,%2")
            grouped = nextValue
            if replacements == 0 then
                return grouped
            end
        end
    end
    local result = value
    local function replaceSuffix(pattern, multiplier)
        result = result:gsub(pattern, function(rawNumber)
            local number = tonumber((rawNumber:gsub(",", "")))
            if number == nil then
                return rawNumber
            end
            return groupedInteger(number * multiplier)
        end)
    end

    replaceSuffix(
        "(%d[%d,]*%.?%d*)%s*[Oo][Nn][Ee]%s*[Hh][Uu][Nn][Dd][Rr][Ee][Dd]%s*[Mm][Ii][Ll][Ll][Ii][Oo][Nn]",
        100000000
    )
    replaceSuffix(
        "(%d[%d,]*%.?%d*)%s*[Aa]%s*[Hh][Uu][Nn][Dd][Rr][Ee][Dd]%s*[Mm][Ii][Ll][Ll][Ii][Oo][Nn]",
        100000000
    )
    replaceSuffix(
        "(%d[%d,]*%.?%d*)%s*[Hh][Uu][Nn][Dd][Rr][Ee][Dd]%s*[Mm][Ii][Ll][Ll][Ii][Oo][Nn]",
        100000000
    )
    replaceSuffix(
        "(%d[%d,]*%.?%d*)%s*[Tt][Ee][Nn]%s*[Tt][Hh][Oo][Uu][Ss][Aa][Nn][Dd]",
        10000
    )
    return result
end

local function translateVisibleText(value)
    if type(value) ~= "string" then
        return value
    end

    local cached = visibleTextCache[value]
    if cached ~= nil then
        runtimeMetrics.TranslationCacheHits = runtimeMetrics.TranslationCacheHits + 1
        return cached
    end
    runtimeMetrics.TranslationCacheMisses = runtimeMetrics.TranslationCacheMisses + 1
    -- HUD quest tips prepend this header after looking up the authored body.
    -- Preserve the body lookup instead of requiring every prefixed variant.
    local tipBody = value:match("^Tip:(.+)$") or value:match("^Tip：(.+)$")
    if tipBody ~= nil then
        local translatedBody = translateVisibleText(tipBody)
        if translatedBody ~= tipBody then
            local result = "Tip: " .. translatedBody
            visibleTextCache[value] = result
            return result
        end
    end
    local enterWorldShortened = shortenEnterWorldLabel(value)
    if enterWorldShortened ~= value then
        visibleTextCache[value] = enterWorldShortened
        return enterWorldShortened
    end
    local questPasswordRestored = restoreQuestChatPassword(value)
    if questPasswordRestored ~= value then
        visibleTextCache[value] = questPasswordRestored
        return questPasswordRestored
    end
    local reviewedExact = visibleTextExactOverrides[value]
    if reviewedExact ~= nil then
        visibleTextCache[value] = reviewedExact
        return reviewedExact
    end
    local normalizedLargeNumber = runtimeFixes.normalizeLocalizedLargeNumbers(value)
    if normalizedLargeNumber ~= value
        and (not hasCjk or not hasCjk(normalizedLargeNumber))
    then
        visibleTextCache[value] = normalizedLargeNumber
        if runtimeFixes.ExchangeLargeNumberRepairReported ~= true then
            runtimeFixes.ExchangeLargeNumberRepairReported = true
            report("normalized rendered localized large number=" .. normalizedLargeNumber)
        end
        return normalizedLargeNumber
    end
    if hasCjk and not hasCjk(value) then
        visibleTextCache[value] = value
        return value
    end

    local confessionDialogue = visibleTextExactOverrides.__translateNearbyConfessionDialogue(value)
    if confessionDialogue ~= value then
        visibleTextCache[value] = confessionDialogue
        return confessionDialogue
    end

    local familyGuide = translateFamilyRecruitmentGuide(value)
    if familyGuide ~= value then
        visibleTextCache[value] = familyGuide
        return familyGuide
    end

    local broochDescription = translateSeasonBroochDescription(value)
    if broochDescription ~= value then
        visibleTextCache[value] = broochDescription
        return broochDescription
    end

    local bountyText = visibleTextExactOverrides.__translateBrassBookBounty(value)
    if bountyText ~= value then
        visibleTextCache[value] = bountyText
        return bountyText
    end

    local equipmentSpecialText = visibleTextExactOverrides.__translateEquipmentSpecialText(value)
    if equipmentSpecialText ~= value then
        visibleTextCache[value] = equipmentSpecialText
        return equipmentSpecialText
    end

    local lifeStaffDetails = visibleTextExactOverrides.__translateLifeStaffDetails(value)
    if lifeStaffDetails ~= value then
        visibleTextCache[value] = lifeStaffDetails
        return lifeStaffDetails
    end

    local voiceChatCount = value:match("^<GreenVoice>(%d+)</>人连麦中%.%.%.$")
        or value:match("^<GreenVoice>(%d+)</>人连麦中……$")
    if voiceChatCount ~= nil then
        local result = "<GreenVoice>" .. voiceChatCount .. "</> people in voice chat..."
        visibleTextCache[value] = result
        return result
    end

    local obtainableQuantity = value:match("^可获得数量：(%d+)$")
        or value:match("^可获得数量:(%d+)$")
    if obtainableQuantity ~= nil then
        local result = "Obtainable Quantity: " .. obtainableQuantity
        visibleTextCache[value] = result
        return result
    end

    local physicalBlock, magicalBlock = value:match(
        "^提高角色格挡物理伤害或魔法伤害的几率。格挡后，角色仅受到30%%伤害，且此次伤害不会触发暴击（格挡率不会高于75%%）。%s*"
            .. "角色物理格挡：(<Mark>.-</>)%s*角色魔法格挡：(<Mark>.-</>)$"
    )
    if physicalBlock ~= nil then
        local result = "Increases the chance to block physical or magical damage. "
            .. "After blocking, the character takes only 30% damage, and the blocked hit "
            .. "cannot critically strike (Block Rate cannot exceed 75%).\n\n"
            .. "Physical Block: " .. physicalBlock .. "\n"
            .. "Magical Block: " .. magicalBlock
        visibleTextCache[value] = result
        return result
    end

    local sharedOpenCurrent, sharedOpenMaximum = value:match(
        "^今日剩余共享开启次数：<Remaining>(%d+)/(%d+)次</>$"
    )
    if sharedOpenCurrent ~= nil then
        local result = "Shared Openings Remaining Today: <Remaining>"
            .. sharedOpenCurrent .. "/" .. sharedOpenMaximum .. "</>"
        visibleTextCache[value] = result
        return result
    end

    local newMessageCount = value:match("^新消息(%d+)条$")
    if newMessageCount ~= nil then
        local result = newMessageCount .. " new messages"
        visibleTextCache[value] = result
        return result
    end

    local aggregateCount = value:match("^本次一键聚合累计聚合(%d+)次，共消耗$")
    if aggregateCount ~= nil then
        local result = "This one-click aggregation performed " .. aggregateCount
            .. " merges in total, consuming"
        visibleTextCache[value] = result
        return result
    end

    local probabilityRate = value:match("^概率(<Rate>.-</>)$")
    if probabilityRate ~= nil then
        local result = "Probability " .. probabilityRate
        visibleTextCache[value] = result
        return result
    end

    local fashionValue = value:match("^风尚值：(%d+)$")
        or value:match("^风尚值:(%d+)$")
    if fashionValue ~= nil then
        local result = "Fashion Value: " .. fashionValue
        visibleTextCache[value] = result
        return result
    end

    local ratingValue = value:match("^非凡评分%s*([%d].*)$")
    if ratingValue ~= nil then
        local result = "Beyonder Rating " .. ratingValue
        visibleTextCache[value] = result
        return result
    end

    local shieldCurrent, shieldMaximum = value:match("^米尔贡根之盾%((%d+)/(%d+)%)$")
    if shieldCurrent ~= nil then
        local result = "Milgongen's Shield (" .. shieldCurrent .. "/" .. shieldMaximum .. ")"
        visibleTextCache[value] = result
        return result
    end

    local mergeCurrent, mergeMaximum = value:match("^选择需要聚合的非凡物质(%d+)/(%d+)$")
    if mergeCurrent ~= nil then
        local result = "Select Beyonder Materials to Merge " .. mergeCurrent .. "/" .. mergeMaximum
        visibleTextCache[value] = result
        return result
    end

    local distributionTime = value:match("^分配中(<Time>.-</>)$")
    if distributionTime ~= nil then
        local result = "Distributing " .. distributionTime
        visibleTextCache[value] = result
        return result
    end

    local recollectionLevel = value:match("^回想(%d+)级$")
    if recollectionLevel ~= nil then
        local result = "Recollection Lv. " .. recollectionLevel
        visibleTextCache[value] = result
        return result
    end

    local awakeningLevel = value:match("^觉醒等级Lv(%d+)$")
    if awakeningLevel ~= nil then
        local result = "Awakening Lv. " .. awakeningLevel
        visibleTextCache[value] = result
        return result
    end

    local unlockDays, unlockHours, unlockMinutes = value:match(
        "^解冻剩余时间：(%d+)天(%d+)小时(%d+)分$"
    )
    if unlockDays ~= nil then
        local result = "Time until unlocked: " .. unlockDays .. "d "
            .. unlockHours .. "h " .. unlockMinutes .. "m"
        visibleTextCache[value] = result
        return result
    end

    local dailyRefreshHour = value:match("^每日(%d+)点自动刷新$")
    if dailyRefreshHour ~= nil then
        local result = "Refreshes daily at " .. dailyRefreshHour .. ":00"
        visibleTextCache[value] = result
        return result
    end

    local noticeHours, noticeMinutes = value:match("^公示期(%d+)小时(%d+)分$")
    if noticeHours ~= nil then
        local result = "Listing period: " .. noticeHours .. "h " .. noticeMinutes .. "m"
        visibleTextCache[value] = result
        return result
    end

    local countdownHours, countdownMinutes = value:match(
        "^公示期倒计时：(%d+)小时(%d+)分钟$"
    )
    if countdownHours ~= nil then
        local result = "Listing period remaining: " .. countdownHours
            .. "h " .. countdownMinutes .. "m"
        visibleTextCache[value] = result
        return result
    end

    local historyPoints = value:match("^达成奖励：获得历史研究积分%+(%d+)$")
    if historyPoints ~= nil then
        local result = "Completion Reward: Historical Research Points +" .. historyPoints
        visibleTextCache[value] = result
        return result
    end

    local stackCount = value:match("^(%d+)层$")
    if stackCount ~= nil then
        local result = "Stack " .. stackCount
        visibleTextCache[value] = result
        return result
    end

    local selectedCount, selectedMaximum = value:match(
        "^当前已选择%s*<Yellow>(%d+)</>/(%d+)$"
    )
    if selectedCount ~= nil then
        local result = "Selected <Yellow>" .. selectedCount .. "</>/" .. selectedMaximum
        visibleTextCache[value] = result
        return result
    end

    if value:find("【半神】", 1, true) == 1 and value:find("真神：序列0", 1, true) then
        local result = "[Demigod]\n"
            .. "Description: A collective term for Saints and Angels from Sequence 4 through Sequence 1. "
            .. "Their life and spirit undergo a qualitative transformation, they gain 50% divinity, and their abilities transcend the human realm. "
            .. "Demigods can continue advancing toward True Godhood. Demigods are further divided into Saints and Angels; Sequence 0, above Sequence 1, is known as a True God.\n"
            .. "True God: Sequence 0, possessing a complete Mythical Creature form.\n"
            .. "Location: Open Menu - Sequence to advance.\n"
            .. "Related: Character Development - Improve"
        visibleTextCache[value] = result
        return result
    end

    local interval, damage, slowPercent, duration = value:match(
        "^在目标位置召唤窥秘之眼链接目标，每([%d%.]+)秒对目标造成([%d%.]+)伤害并使目标减速([%d%.]+)%%。链接最多持续([%d%.]+)秒，目标远离窥秘之眼一定距离后链接会提前断开。$"
    )
    if interval ~= nil then
        local result = "Summon an Eye of Mystery at the target location to link to the target, dealing "
            .. damage .. " damage every " .. interval .. " seconds and slowing the target by "
            .. slowPercent .. "%. The link lasts up to " .. duration
            .. " seconds and breaks early if the target moves too far from the Eye of Mystery."
        visibleTextCache[value] = result
        return result
    end

    local gemini = lookupGeminiText(value)
    if gemini ~= nil then
        gemini = preserveMovableAnswerMarkup(value, gemini)
        gemini = runtimeFixes.normalizeDefenseBreakTerminology(gemini)
        visibleTextCache[value] = gemini
        return gemini
    end

    local result = value
    for _, replacement in ipairs(visibleTextReplacements) do
        result = result:gsub(replacement[1], function()
            return replacement[2]
        end)
    end
    visibleTextCache[value] = result
    return result
end

local function translateTextWidget(widget, discoveryContext)
    if widget == nil then
        return 0
    end

    local getText = nil
    local methodOk = pcall(function() getText = widget.GetText end)
    if not methodOk or type(getText) ~= "function" then
        return 0
    end
    local ok, current = pcall(getText, widget)
    if not ok or current == nil then
        return 0
    end

    local currentText = type(current) == "string" and current or tostring(current)
    local widgetName = "Text"
    pcall(function()
        widgetName = tostring(widget:GetName())
    end)
    local translated = repairLiveString and repairLiveString("WidgetText", widgetName, widgetName, currentText)
        or translateVisibleText(currentText)
    local repairedCount = 0
    if translated ~= currentText then
        local changed = pcall(function()
            widget:SetText(translated)
        end)
        -- KGTextBlock can repaint its serialized Text property after a
        -- Blueprint state change. Keep the property and Slate value aligned.
        pcall(function()
            widget.Text = translated
        end)
        pcall(function()
            if widget.SynchronizeProperties ~= nil then
                widget:SynchronizeProperties()
            end
        end)
        pcall(function()
            if widget.InvalidateLayoutAndVolatility ~= nil then
                widget:InvalidateLayoutAndVolatility()
            end
        end)
        repairedCount = changed and 1 or 0
    end
        return repairedCount
end

-- The reference translation runtime generates a global list of text-like
-- Blueprint variable names and probes them through UIFunctionLibrary.FindWidget.
-- That reaches cooked widgets which are absent from both the Lua view and the
-- owning UWidgetTree.  Probe in small timer batches so full coverage does not
-- create a single-frame UI hitch.
local criticalWidgetProbeNames = {
    "Text_Use", "Text_Used", "TextUsing", "Text_State", "Text_Status",
    "Text_Apply", "Text_Equip", "RichText_Use", "Button_Text",
    "Text_Name", "Text_Title", "Text_Content", "Text_Tips", "Text_BtnName",
}
local generatedWidgetProbeNames = nil
local generatedWidgetProbeUnavailable = false
local widgetProbeStates = setmetatable({}, { __mode = "k" })
local widgetProbeLibrary = nil
local WIDGET_PROBE_BATCH_SIZE = 192

local function loadGeneratedWidgetProbeNames()
    if generatedWidgetProbeNames ~= nil then return generatedWidgetProbeNames end
    local output, seen = {}, {}
    local function append(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            output[#output + 1] = name
        end
    end
    for _, name in ipairs(criticalWidgetProbeNames) do append(name) end
    if not generatedWidgetProbeUnavailable then
        local ok, names = pcall(require, "mods.cpdd_runtime_fixes.WidgetNameIndex")
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do append(name) end
        else
            generatedWidgetProbeUnavailable = true
            report("generated widget-name index unavailable: " .. tostring(names))
        end
    end
    generatedWidgetProbeNames = output
    return output
end

local function resolveWidgetProbeLibrary()
    if widgetProbeLibrary and widgetProbeLibrary ~= false then return widgetProbeLibrary end
    local ok, value = pcall(import, "UIFunctionLibrary")
    widgetProbeLibrary = ok and value or false
    return widgetProbeLibrary or nil
end

local function scheduleWidgetProbe(component, callback)
    local owners = { component, Game and Game.NewUIManager }
    for _, owner in ipairs(owners) do
        local ok, addTimer = pcall(function() return owner and owner.AddTimerWithFunction end)
        if ok and type(addTimer) == "function"
            and pcall(addTimer, owner, 0.01, 1, callback)
        then
            return true
        end
    end
    return false
end

local function queueGeneratedWidgetProbe(rootWidget, component, discoveryContext)
    if rootWidget == nil then return end
    local library = resolveWidgetProbeLibrary()
    local findWidget = library and library.FindWidget
    if type(findWidget) ~= "function" then return end

    local state = widgetProbeStates[rootWidget]
    if state == nil then
        state = {
            NextIndex = 1,
            Pending = false,
            Complete = false,
            HitNames = {},
            Visited = setmetatable({}, { __mode = "k" }),
        }
        widgetProbeStates[rootWidget] = state
    end

    -- Dynamic Blueprint state changes can restore serialized Chinese after the
    -- initial probe. Revisit only previously confirmed names on every refresh.
    for name in pairs(state.HitNames) do
        local ok, widget = pcall(findWidget, rootWidget, name)
        if ok and widget ~= nil then
            walkWidgetDescendants(widget, setmetatable({}, { __mode = "k" }), function(candidate)
                translateTextWidget(candidate, discoveryContext)
            end)
        end
    end
    if state.Pending or state.Complete then return end

    state.Pending = true
    local names = loadGeneratedWidgetProbeNames()
    local function runBatch()
        if component and component.isDestroyed then
            state.Pending = false
            return
        end
        local finish = math.min(#names, state.NextIndex + WIDGET_PROBE_BATCH_SIZE - 1)
        for index = state.NextIndex, finish do
            local name = names[index]
            local ok, widget = pcall(findWidget, rootWidget, name)
            if ok and widget ~= nil then
                state.HitNames[name] = true
                walkWidgetDescendants(widget, state.Visited, function(candidate)
                    translateTextWidget(candidate, discoveryContext)
                end)
            end
        end
        state.NextIndex = finish + 1
        if state.NextIndex > #names then
            state.Pending = false
            state.Complete = true
        elseif not scheduleWidgetProbe(component, runBatch) then
            state.Pending = false
        end
    end
    if not scheduleWidgetProbe(component, runBatch) then runBatch() end
end

runtimeFixes.VisibleWidgetNames = {
    "Text_Name", "Text_Title", "Text_Power", "Text_PowerName",
    "Text_CEName", "Text_CETitle", "Text_ScoreName", "Text_Rating",
    "RTB_Text", "RTB_Name", "RTB_Title", "Text_lua", "Text2_lua",
    "Text_Recommend", "Text_Extra", "Text_BeStrong", "Text_Reset",
    "Text_Equip", "Text_Tips", "Text_BtnName", "Text_Plan",
    "Text_Content", "TextUsing", "TB_Word",
}

local function translateViewTextWidgets(view, userWidget, discoveryContext, component, sharedVisited)
    local visited = sharedVisited or {}
    local repairedCount = 0
    local function translateWidgetTree(owner)
        walkWidgetDescendants(owner, visited, function(widget)
            repairedCount = repairedCount + translateTextWidget(widget, discoveryContext)
        end)
    end

    -- Panel views frequently expose nested UserWidgets rather than their text
    -- blocks. Seed the recursive walk from every generated view entry so those
    -- child WidgetTrees are repaired even when the panel has no userWidget.
    if type(view) == "table" then
        for _, widget in pairs(view) do
            translateWidgetTree(widget)
        end
        -- Framework views cache lazily resolved Blueprint widgets here. They
        -- are not necessarily direct values in the generated view table.
        if type(view._widgetCache) == "table" then
            for _, widget in pairs(view._widgetCache) do
                translateWidgetTree(widget)
            end
        end
    end

    if userWidget == nil then
        return repairedCount
    end

    -- Static Blueprint text is not always included in the generated Lua view.
    -- Check the names used by the rating reminder and, where available, walk
    -- the widget tree so its label is translated after every refresh.
    for _, name in ipairs(runtimeFixes.VisibleWidgetNames) do
        translateWidgetTree(getNamedWidget(userWidget, name))
    end

    -- Nested UserWidgets own separate WidgetTrees, so recurse into each one.
    -- This is required for the skill screen's embedded top tabs and footer
    -- buttons, whose text does not belong to the panel's root tree.
    translateWidgetTree(userWidget)
    queueGeneratedWidgetProbe(userWidget, component, discoveryContext)
    return repairedCount
end

-- Data and view hooks already know which component changed. Restrict their
-- hot-path fallback to directly exposed text widgets instead of recursively
-- revisiting every descendant in the owning panel.
local function translateDirectViewTextWidgets(view, discoveryContext)
    if type(view) ~= "table" then return 0 end
    local visited = setmetatable({}, { __mode = "k" })
    local repairedCount = 0
    local function translateDirect(widget)
        local widgetType = type(widget)
        if (widgetType ~= "table" and widgetType ~= "userdata")
            or visited[widget]
        then
            return
        end
        visited[widget] = true
        runtimeMetrics.WidgetsVisited = runtimeMetrics.WidgetsVisited + 1
        repairedCount = repairedCount + translateTextWidget(widget, discoveryContext)
    end
    for _, widget in pairs(view) do translateDirect(widget) end
    if type(view._widgetCache) == "table" then
        for _, widget in pairs(view._widgetCache) do translateDirect(widget) end
    end
    return repairedCount
end

local function translateTableStrings(value, seen, captureContext, fieldPath)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return value
    end
    seen[value] = true

    fieldPath = fieldPath or ""
    for key, child in pairs(value) do
        local childPath = fieldPath == "" and tostring(key) or (fieldPath .. "." .. tostring(key))
        if type(child) == "string" then
            local translated = translateVisibleText(child)
            value[key] = translated
            if captureContext ~= nil then
                runtimeMetrics.CaptureDataAssignment(
                    captureContext.component,
                    captureContext.module,
                    captureContext.class,
                    childPath,
                    child,
                    translated,
                    captureContext.record
                )
            end
        elseif type(child) == "table" then
            translateTableStrings(child, seen, captureContext, childPath)
        end
    end
    return value
end

local function applyVisibleTextOverrides(value, environment)
    local module = value
    if type(module) ~= "table" then
        module = getSymbol(value, environment, "TopData")
    end
    if type(module) ~= "table" then
        return value
    end

    translateTableStrings(module)
    return value
end

local function applyVisibleFieldOverrides(moduleName, allowedFields)
    return function(value, environment)
        local module = value
        if type(module) ~= "table" then
            module = getSymbol(value, environment, "TopData")
        end
        if type(module) ~= "table" then
            return value
        end

        local seen = {}
        local function visit(node, recordIdentity, fieldPath)
            if type(node) ~= "table" or seen[node] then return end
            seen[node] = true
            for field, child in pairs(node) do
                local childPath = fieldPath == "" and tostring(field)
                    or (fieldPath .. "." .. tostring(field))
                if allowedFields[field] and type(child) == "string" then
                    local translated = translateVisibleText(child)
                    node[field] = translated
                    runtimeMetrics.CaptureDataAssignment(
                        nil,
                        moduleName,
                        "StaticDataRow",
                        childPath,
                        child,
                        translated,
                        recordIdentity
                    )
                elseif type(child) == "table" then
                    visit(child, recordIdentity or field, childPath)
                end
            end
        end

        visit(module.data or module, nil, "")
        return value
    end
end

local function explicitLookup(index, tag)
    if tag then
        local values = splitOverrides[tag]
        return values and values[index] or nil
    end
    return aggregateOverrides[index]
end

function runtimeFixes.authoritativeAggregateLookup(index, candidate)
    local aliases = runtimeFixes.AuthoritativeAggregateAliases[index]
    if aliases == nil or type(candidate) ~= "string" or not aliases[candidate] then
        return nil
    end
    return aggregateOverrides[index]
end

local function getDirectTable(tag)
    local cacheKey = tag or "__aggregate"
    local cached = directTables[cacheKey]
    if cached ~= nil then
        return cached ~= MISSING_DIRECT_TABLE and cached or nil
    end

    local suffix = tag and ("_" .. tag) or ""
    for _, candidate in ipairs({
        { "cpdd_translation.Data.Excel.LanguageData.StringDB_CN_Data" .. suffix, true },
        { "Data.Excel.LanguageData.StringDB_EN_Data" .. suffix, false },
        { "Data.Excel.LanguageData.StringDB_CN_Data" .. suffix, false },
    }) do
        local moduleName, external = candidate[1], candidate[2]
        local ok, module
        if external and type(Loader.LoadExternal) == "function" then
            ok, module = pcall(Loader.LoadExternal, moduleName)
        else
            ok, module = pcall(require, moduleName)
        end
        if ok and type(module) == "table" then
            local data = module.data or module
            if type(data) == "table" then
                directTables[cacheKey] = data
                report("using direct localization table " .. moduleName)
                return data
            end
        end
    end

    directTables[cacheKey] = MISSING_DIRECT_TABLE
    return nil
end

local function directLookup(index, tag)
    local data = getDirectTable(tag)
    return data and data[index] or nil
end

hasCjk = function(value)
    return type(value) == "string" and value:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local SOURCE_SHARD_CACHE_LIMIT = 128
local sourceShardCache = {}
local sourceShardOrder = {}
local missingSourceShards = {}
local seenSourceShards = {}

local function touchSourceShard(prefix)
    for index = #sourceShardOrder, 1, -1 do
        if sourceShardOrder[index] == prefix then
            table.remove(sourceShardOrder, index)
            break
        end
    end
    sourceShardOrder[#sourceShardOrder + 1] = prefix
    while #sourceShardOrder > SOURCE_SHARD_CACHE_LIMIT do
        local evicted = table.remove(sourceShardOrder, 1)
        sourceShardCache[evicted] = nil
        package.loaded["mods.cpdd_runtime_fixes.LanguageSourceIndex_" .. evicted] = nil
        runtimeMetrics.SourceShardEvictions = runtimeMetrics.SourceShardEvictions + 1
    end
end

local function sourceIndexLookup(key)
    local hashPrefix = type(key) == "string" and key:match(":([0-9a-f][0-9a-f])") or nil
    local prefix = hashPrefix
    if prefix == nil or missingSourceShards[prefix] then
        runtimeMetrics.SourceShardMisses = runtimeMetrics.SourceShardMisses + 1
        return nil
    end

    local shard = sourceShardCache[prefix]
    if shard ~= nil then
        runtimeMetrics.SourceShardHits = runtimeMetrics.SourceShardHits + 1
        touchSourceShard(prefix)
        return shard[key]
    end

    local moduleName = "mods.cpdd_runtime_fixes.LanguageSourceIndex_" .. prefix
    local started = nowMilliseconds()
    local ok, loaded = pcall(require, moduleName)
    if not ok or type(loaded) ~= "table" then
        missingSourceShards[prefix] = true
        runtimeMetrics.SourceShardMisses = runtimeMetrics.SourceShardMisses + 1
        report("language source shard unavailable " .. prefix .. ": " .. tostring(loaded))
        return nil
    end
    sourceShardCache[prefix] = loaded
    if seenSourceShards[prefix] then
        runtimeMetrics.SourceShardReloads = runtimeMetrics.SourceShardReloads + 1
    else
        seenSourceShards[prefix] = true
    end
    touchSourceShard(prefix)
    runtimeMetrics.SourceShardLoads = runtimeMetrics.SourceShardLoads + 1
    local elapsed = nowMilliseconds() - started
    runtimeMetrics.SourceShardLoadMillis = runtimeMetrics.SourceShardLoadMillis + elapsed
    if elapsed >= 8 then
        report("slow language source shard " .. prefix .. " loaded in "
            .. string.format("%.2f", elapsed) .. " ms")
    end
    return loaded[key]
end

local function sourceReference(reference)
    if type(reference) == "number" then
        return nil, reference
    end
    if type(reference) ~= "string" then
        return nil, nil
    end
    local tag, languageId = reference:match("^([A-Za-z0-9_]+):(%d+)$")
    return tag, tag and tonumber(languageId) or nil
end

local function referenceScore(reference, tableName, fieldPath)
    if type(reference) ~= "string" then
        return 0
    end
    local tag = reference:match("^([A-Za-z0-9_]+):")
    if not tag then
        return 0
    end
    local context = (tostring(tableName or "") .. "." .. tostring(fieldPath or "")):lower()
    tag = tag:lower()
    local score = context:find(tag, 1, true) and 100 or 0
    for _, family in ipairs({
        "skill", "buff", "item", "talk", "task", "guide",
        "achievement", "manor", "gossip", "loading",
    }) do
        if context:find(family, 1, true) and tag:sub(1, #family) == family then
            score = score + 50
        end
    end
    if (context:find("dialog", 1, true) or context:find("npc", 1, true))
        and tag:find("talk", 1, true)
    then
        score = score + 25
    end
    return score
end

local function lookupSourceTranslation(sourceReferenceValue, tableName, fieldPath)
    local references = type(sourceReferenceValue) == "table"
        and sourceReferenceValue
        or { sourceReferenceValue }
    local translated, bestScore, conflicting = nil, -1, false
    for _, reference in ipairs(references) do
        local tag, languageId = sourceReference(reference)
        if languageId then
            local candidate = directLookup(languageId, tag) or explicitLookup(languageId, tag)
            candidate = runtimeFixes.authoritativeAggregateLookup(languageId, candidate) or candidate
            if type(candidate) == "string" then
                candidate = translateVisibleText(candidate)
                local score = referenceScore(reference, tableName, fieldPath)
                if score > bestScore then
                    translated, bestScore, conflicting = candidate, score, false
                elseif score == bestScore and translated ~= candidate then
                    conflicting = true
                end
            end
        end
    end
    return conflicting and nil or translated
end

local liveRepairCache = {}
local liveRepairCacheSize = 0
local LIVE_REPAIR_CACHE_LIMIT = 8192

local function returnLiveRepairResult(tableName, rowKey, fieldPath, original, rendered)
    if runtimeMetrics.CaptureDataAssignmentsEnabled and hasCjk(rendered) then
        runtimeMetrics.CaptureDataAssignment(
            nil,
            tostring(tableName or "LiveString"),
            "LiveString",
            tostring(fieldPath or "value"),
            original,
            rendered,
            rowKey
        )
    end
    return rendered
end

repairLiveString = function(tableName, rowKey, fieldPath, value)
    local enterWorldShortened = shortenEnterWorldLabel(value)
    if enterWorldShortened ~= value then
        return enterWorldShortened
    end
    local questPasswordRestored = restoreQuestChatPassword(value)
    if questPasswordRestored ~= value then
        return questPasswordRestored
    end
    local reviewedExact = visibleTextExactOverrides[value]
    if reviewedExact ~= nil then
        return reviewedExact
    end
    local normalizedLargeNumber = runtimeFixes.normalizeLocalizedLargeNumbers(value)
    if normalizedLargeNumber ~= value then
        if runtimeFixes.ExchangeLargeNumberRepairReported ~= true then
            runtimeFixes.ExchangeLargeNumberRepairReported = true
            report("normalized rendered localized large number=" .. normalizedLargeNumber)
        end
        return normalizedLargeNumber
    end
    local normalized = runtimeFixes.normalizeDefenseBreakTerminology(value)
    if normalized ~= value then
        return normalized
    end
    if not hasCjk(value) then
        return value
    end

    -- Exact generated translations are authoritative for a complete source
    -- value. Consult them before either cache: an earlier fragment repair may
    -- have cached a mixed result such as "你在做What?", which must never mask
    -- the reviewed whole-string translation on KSBC rows.
    local geminiExact = lookupGeminiText(value)
    if type(geminiExact) == "string" and geminiExact ~= ""
        and not hasCjk(geminiExact)
    then
        return runtimeFixes.normalizeDefenseBreakTerminology(
            preserveMovableAnswerMarkup(value, geminiExact)
        )
    end

    local cacheKey = tostring(tableName or "") .. "\0" .. tostring(fieldPath or "") .. "\0" .. value
    local cached = liveRepairCache[cacheKey]
    if cached ~= nil then
        runtimeMetrics.LiveRepairCacheHits = runtimeMetrics.LiveRepairCacheHits + 1
        return returnLiveRepairResult(tableName, rowKey, fieldPath, value, cached)
    end
    runtimeMetrics.LiveRepairCacheMisses = runtimeMetrics.LiveRepairCacheMisses + 1

    -- Dialogue captions may prepend a live player/NPC name to an otherwise
    -- authored StringDB line. Resolve the authored tail independently while
    -- preserving user-created names verbatim.
    local speakerPrefix, spokenText = value:match("^([^:：]-[:：]%s*)(.+)$")
    if speakerPrefix ~= nil and hasCjk(spokenText) then
        local exactSpoken = visibleTextExactOverrides[spokenText]
            or lookupGeminiText(spokenText)
        if type(exactSpoken) == "string" and not hasCjk(exactSpoken) then
            local combined = translateVisibleText(speakerPrefix) .. exactSpoken
            if liveRepairCacheSize >= LIVE_REPAIR_CACHE_LIMIT then
                liveRepairCache = {}
                liveRepairCacheSize = 0
            end
            liveRepairCache[cacheKey] = combined
            liveRepairCacheSize = liveRepairCacheSize + 1
            return combined
        end
        local spokenReference = sourceIndexLookup(sourceKey(spokenText))
        if spokenReference ~= nil then
            local spokenTranslation = lookupSourceTranslation(spokenReference, tableName, fieldPath)
            if type(spokenTranslation) == "string" and not hasCjk(spokenTranslation) then
                local combined = translateVisibleText(speakerPrefix) .. spokenTranslation
                if liveRepairCacheSize >= LIVE_REPAIR_CACHE_LIMIT then
                    liveRepairCache = {}
                    liveRepairCacheSize = 0
                end
                liveRepairCache[cacheKey] = combined
                liveRepairCacheSize = liveRepairCacheSize + 1
                return combined
            end
        end
    end

    local known = translateVisibleText(value)
    local partialKnown = nil
    if known ~= value and not hasCjk(known) then
        if liveRepairCacheSize >= LIVE_REPAIR_CACHE_LIMIT then
            liveRepairCache = {}
            liveRepairCacheSize = 0
        end
        liveRepairCache[cacheKey] = known
        liveRepairCacheSize = liveRepairCacheSize + 1
        return known
    elseif known ~= value then
        -- A token replacement is only a fallback while Chinese remains.  The
        -- complete authored source may still have an authoritative StringDB
        -- entry, so do not let a partial replacement bypass that lookup.
        partialKnown = known
    end

    local sourceReferenceValue = sourceIndexLookup(sourceKey(value))
    if sourceReferenceValue ~= nil then
        local translated = lookupSourceTranslation(sourceReferenceValue, tableName, fieldPath)
        if type(translated) == "string" and translated ~= value and not hasCjk(translated) then
            if liveRepairCacheSize >= LIVE_REPAIR_CACHE_LIMIT then
                liveRepairCache = {}
                liveRepairCacheSize = 0
            end
            liveRepairCache[cacheKey] = translated
            liveRepairCacheSize = liveRepairCacheSize + 1
            return translated
        end
    end
    -- A source-index miss is stable for this release and is safe to cache.
    -- A known source whose direct table is not ready must remain retryable.
    if sourceReferenceValue == nil then
        if liveRepairCacheSize >= LIVE_REPAIR_CACHE_LIMIT then
            liveRepairCache = {}
            liveRepairCacheSize = 0
        end
        liveRepairCache[cacheKey] = partialKnown or value
        liveRepairCacheSize = liveRepairCacheSize + 1
    end
    return returnLiveRepairResult(
        tableName,
        rowKey,
        fieldPath,
        value,
        partialKnown or value
    )
end

-- Server hotfixes can replace values inside the live StringDB tables after
-- the English overlays were merged. The table identity does not change, so a
-- normal overlay reapply treats it as already translated. Force the reviewed
-- English rows back into every loaded StringDB after each hotfix batch.
local function installPostHotfixTranslationRestore(value, environment)
    local utils = type(value) == "table" and value
        or getSymbol(value, environment, "HotfixUtils")
        or (Game and Game.HotfixUtils)
    if type(utils) ~= "table" or utils.__cpddTranslationRestore == VERSION then
        return value
    end

    local originalPostHotfix = utils.PostHotfix
    if type(originalPostHotfix) ~= "function" then
        return value
    end

    utils.PostHotfix = function(...)
        local results = { originalPostHotfix(...) }
        local ok, count = pcall(Loader.ReapplyOverlays, true)
        if ok then
            report(
                "restored translated overlays after server hotfix modules="
                .. tostring(count or 0)
            )
        else
            report("post-hotfix translation restore failed: " .. tostring(count))
        end
        return unpack(results)
    end

    utils.__cpddTranslationRestore = VERSION
    report("installed post-hotfix translation restore")
    return value
end

Loader.AfterLoad(
    "Framework.DoraSDK.HotfixUtils",
    installPostHotfixTranslationRestore,
    1000001,
    "cpdd.runtime-fix.post-hotfix-translation-restore"
)

local claimedBlueprintTextOverrides = {
    ["WBP_TrainTradeMainTask_Item/Text_Get"] = "Claimed",
    ["WBP_WeeklyOrdersTips_Item/Text_Get"] = "Claimed",
    ["WBP_GVG_WinnerParty_Player_Item/Text_None"] = "Claimed",
}

local function repairWidgetBlueprintTextData(value, environment, source)
    local module = value
    if type(module) ~= "table" then
        module = getSymbol(value, environment, "TopData")
    end
    if type(module) ~= "table" then
        return value
    end

    local data = module.data or module
    if type(data) ~= "table" then
        return value
    end

    local repairedCount = 0
    for rowKey, row in pairs(data) do
        if type(row) == "table" and type(row.DisplayString) == "string" then
            local repaired = claimedBlueprintTextOverrides[rowKey] or repairLiveString(
                "WidgetBlueprintTextData",
                rowKey,
                "DisplayString",
                row.DisplayString
            )
            if repaired ~= row.DisplayString then
                row.DisplayString = repaired
                repairedCount = repairedCount + 1
            end
        end
    end
    if repairedCount > 0 then
        report("repaired " .. repairedCount .. " cached Blueprint text entries from " .. tostring(source))
    end
    return value
end

local function repairLiveValue(tableName, rowKey, fieldPath, value, depth, seen, maxDepth)
    local valueType = type(value)
    if valueType == "string" then
        local repaired = repairLiveString(tableName, rowKey, fieldPath, value)
        runtimeMetrics.CaptureDataAssignment(
            nil,
            tostring(tableName),
            "TableDataRow",
            fieldPath ~= "" and fieldPath or "value",
            value,
            repaired,
            rowKey
        )
        return repaired
    end
    if depth >= (maxDepth or 3)
        or seen[value]
        or (valueType ~= "table" and valueType ~= "userdata")
    then
        return value
    end

    local manager = Game and Game.TableDataManager
    if valueType == "userdata" and manager and type(manager.isSpecialUEType) == "function" then
        local ok, special = pcall(manager.isSpecialUEType, manager, value)
        if ok and special then
            return value
        end
    end
    seen[value] = true

    local iterator = valueType == "userdata" and rawget(_G, "ksbcpairs") or pairs
    if type(iterator) ~= "function" then
        return value
    end
    local ok, nextFunction, state, firstKey = pcall(iterator, value)
    if not ok or type(nextFunction) ~= "function" then
        return value
    end

    local entries = {}
    for field, child in nextFunction, state, firstKey do
        entries[#entries + 1] = { field, child }
    end

    local output = value
    for _, entry in ipairs(entries) do
        local field, child = entry[1], entry[2]
        local path = fieldPath == "" and tostring(field) or (fieldPath .. "." .. tostring(field))
        local repaired = repairLiveValue(
            tableName,
            rowKey,
            path,
            child,
            depth + 1,
            seen,
            maxDepth
        )
        if repaired ~= child then
            if output == value then
                output = {}
                for _, originalEntry in ipairs(entries) do
                    output[originalEntry[1]] = originalEntry[2]
                end
                if valueType == "table" then
                    setmetatable(output, getmetatable(value))
                end
            end
            output[field] = repaired
        end
    end
    return output
end

local function repairPickObjectSayTexts(value, environment)
    local module = value
    if type(module) ~= "table" then
        module = getSymbol(value, environment, "TopData")
    end
    if type(module) ~= "table" then
        return value
    end

    local data = module.data or module
    if type(data) ~= "table" then
        return value
    end

    local visited = {}
    local sayActions = 0
    local repairedActions = 0

    local function visit(node, rowKey, fieldPath, depth)
        if type(node) ~= "table" or visited[node] or depth > 12 then
            return
        end
        visited[node] = true

        local isSay = node.FuncName == "Say" and type(node.FuncArgInfos) == "table"
        if isSay then
            sayActions = sayActions + 1
            local repaired = repairLiveValue(
                "PickObjectData",
                rowKey,
                fieldPath .. ".FuncArgInfos",
                node.FuncArgInfos,
                0,
                {},
                8
            )
            if repaired ~= node.FuncArgInfos then
                node.FuncArgInfos = repaired
                repairedActions = repairedActions + 1
            end
        end

        for field, child in pairs(node) do
            if type(child) == "table" and not (isSay and field == "FuncArgInfos") then
                visit(child, rowKey, fieldPath .. "." .. tostring(field), depth + 1)
            end
        end
    end

    for rowKey, row in pairs(data) do
        visit(row, rowKey, tostring(rowKey), 0)
    end

    if sayActions > 0 then
        report(
            "processed PickObjectData Say actions=" .. tostring(sayActions)
            .. " repaired=" .. tostring(repairedActions)
        )
    end
    return value
end

for _, moduleName in ipairs({
    "Data.Excel.WidgetBlueprintTextData",
    "Data.Excel.DialogueTalkData",
    "Data.Excel.DialogueAssetData",
    "Data.Excel.DialogueOptionText",
    "Data.Excel.LetterTextData",
    "Data.Excel.NpcInfoData",
}) do
    Loader.AfterLoad(
        moduleName,
        applyVisibleTextOverrides,
        1000000,
        "cpdd.runtime-fix.visible-text." .. moduleName:gsub("[^%w]", "-")
    )
end

local visibleFieldOverrideSpecs = {
    { "Data.Excel.ActivityNameData", { Name = true } },
    { "Data.Excel.BattleBotTemplateData", { Name = true } },
    { "Data.Excel.BoxManLevelData", { LevelDesc = true, LevelName = true } },
    -- Gossip and world-bubble tables are resolved before their widgets exist.
    -- Traverse the authored tables once when loaded so every line is repaired
    -- and every genuine miss is captured without waiting for it to appear.
    { "Data.Excel.BubbleData", { BubbleText = true } },
    { "Data.Excel.BuffDataNew", { UIName = true } },
    { "Data.Excel.ClientNpcData", { Name = true } },
    { "Data.Excel.DungeonRewardData", { SocialRewardDesc = true } },
    { "Data.Excel.FashionStationOfficialAccountData", { Name = true } },
    { "Data.Excel.FashionStationOfficialPostsData", { pDesc = true, pName = true } },
    { "Data.Excel.GossipData", { Text = true } },
    { "Data.Excel.MonsterData", { Name = true } },
    { "Data.Excel.NoCameraDialogueGossipData", { Text = true } },
    { "Data.Excel.SpecialNickNameData", { Nickname = true } },
    { "Data.Excel.TextControlSentenceData", { TextInfo = true, word = true } },
}

for _, spec in ipairs(visibleFieldOverrideSpecs) do
    local moduleName = spec[1]
    Loader.AfterLoad(
        moduleName,
        applyVisibleFieldOverrides(moduleName, spec[2]),
        1000000,
        "cpdd.runtime-fix.visible-fields." .. moduleName:gsub("[^%w]", "-")
    )
end

Loader.AfterLoad(
    "Data.Excel.WidgetBlueprintTextData",
    function(value, environment)
        return repairWidgetBlueprintTextData(value, environment, "loader")
    end,
    1000001,
    "cpdd.runtime-fix.widget-blueprint-source"
)

-- WidgetBlueprintTextData is commonly loaded while the launch UI is being
-- assembled, before runtime mods finish registering their callbacks. Repair
-- that already-cached table now; AfterLoad still covers later/lazy loads.
local cachedWidgetBlueprintTextData = package.loaded["Data.Excel.WidgetBlueprintTextData"]
if type(cachedWidgetBlueprintTextData) == "table" then
    repairWidgetBlueprintTextData(cachedWidgetBlueprintTextData, nil, "startup cache")
end

Loader.AfterLoad(
    "Data.Excel.PickObjectData",
    repairPickObjectSayTexts,
    1000000,
    "cpdd.runtime-fix.pick-object-say-texts"
)

local function fillLocalizedField(row, field, key, tag, force)
    if not force and row[field] ~= nil and row[field] ~= "" then
        return
    end
    local value = directLookup(key, tag) or explicitLookup(key, tag)
    value = runtimeFixes.authoritativeAggregateLookup(key, value) or value
    if value ~= nil then
        row[field] = translateVisibleText(value)
    end
end

local function normalizeSkillId(skillId)
    if type(skillId) == "number" then
        return skillId
    end
    local ok, numericId = pcall(tonumber, skillId)
    if ok and type(numericId) == "number" then
        return numericId
    end
    return nil
end

local function getMarionetteSkillLocalizationById(skillId)
    skillId = normalizeSkillId(skillId)
    if skillId == nil then
        return nil, false, nil
    end

    local keys = marionetteSkillLocalization[skillId]
    if keys then
        return keys, true, skillId
    end

    -- Runtime/upgraded variants reuse the base row's name localization key,
    -- but intentionally leave their own description fields empty. Most
    -- families use the final digit as a variant index. The Alien Hound family
    -- starts at 04 instead of 00.
    local baseSkillId = skillId - skillId % 10
    keys = marionetteSkillLocalization[baseSkillId]
    if not keys and skillId >= 87303004 and skillId <= 87303009 then
        baseSkillId = 87303004
        keys = marionetteSkillLocalization[87303004]
    end
    return keys, false, keys and baseSkillId or nil
end

local function getMarionetteSkillLocalization(skillId, row)
    local keys, isBaseRow, mappedSkillId = getMarionetteSkillLocalizationById(skillId)
    if keys then
        return keys, isBaseRow, mappedSkillId
    end

    if type(row) ~= "table" then
        return nil, false, nil
    end

    for _, candidate in ipairs({ row.ID, row.InitialSkill, row.InitialSkillID, row.RoleSkillID }) do
        keys, isBaseRow, mappedSkillId = getMarionetteSkillLocalizationById(candidate)
        if keys then
            return keys, isBaseRow, mappedSkillId
        end
    end

    for _, field in ipairs({ "SkillDisplayIcon", "SkillIcon", "IconTexture" }) do
        local icon = row[field]
        if type(icon) == "string" then
            local iconNumber = tonumber(icon:match("SecretPartner_Skill_(%d+)"))
            local iconSkillId = iconNumber and marionetteSkillIdByIconNumber[iconNumber]
            if iconSkillId then
                return marionetteSkillLocalization[iconSkillId], false, iconSkillId
            end
        end
    end

    return nil, false, nil
end

local function repairMarionetteSkillRow(row, skillId)
    local keys, isBaseRow, mappedSkillId = getMarionetteSkillLocalization(skillId, row)
    if type(row) ~= "table" or not keys then
        return row
    end

    -- The official row can already contain the shared Chinese placeholder
    -- when it was cached before the StringDB overlays were applied. Always
    -- replace mapped Marionette fields from their exact translated keys.
    fillLocalizedField(row, "Name", keys[1], "skill3", true)
    if marionetteEnglishNames[mappedSkillId]
        and (row.Name == nil or row.Name == "" or hasCjk(row.Name)) then
        row.Name = marionetteEnglishNames[mappedSkillId]
    end
    if isBaseRow then
        fillLocalizedField(row, "BriefDescription", keys[2], "skill3", true)
        fillLocalizedField(row, "SkillDisc", keys[3], "skill3", true)
        fillLocalizedField(row, "Tag", keys[4], nil, true)
    end
    return row
end

local function isMarionetteSkillRow(row, skillId)
    local numericId = normalizeSkillId(skillId)
    if not numericId and type(row) == "table" then
        numericId = normalizeSkillId(row.ID) or normalizeSkillId(row.InitialSkill)
    end
    if numericId and numericId >= 87303000 and numericId < 87304000 then
        return true
    end
    if type(row) == "table" then
        for _, field in ipairs({ "SkillDisplayIcon", "SkillIcon", "IconTexture" }) do
            local icon = row[field]
            if type(icon) == "string" and icon:find("SecretPartner_Skill_", 1, true) then
                return true
            end
        end
    end
    return false
end

Loader.AfterLoad("Framework.Utils.LuaCommon.Managers.TableDataManager", function(value, environment)
    local manager = getSymbol(value, environment, "TableDataManager")
    if type(manager) ~= "table" or manager.__cpddRuntimeFixV1 then
        return value
    end

    manager.__cpddRuntimeFixV1 = true
    local originalGetLangStr = assert(manager.GetLangStr)
    local originalGetLangStrSplit = assert(manager.GetLangStrSplit)
    local originalGetRow = manager.GetRow

    function manager:GetLangStr(index)
        local ok, result = pcall(originalGetLangStr, self, index)
        if ok and result ~= nil then
            if type(result) == "string" then
                local authoritative = runtimeFixes.authoritativeAggregateLookup(index, result)
                if authoritative ~= nil then
                    return translateVisibleText(authoritative)
                end
                return repairLiveString(
                    "LanguageData.StringDB_CN_Data",
                    index,
                    "Value",
                    result
                )
            end
            return result
        end

        -- Numeric IDs are not stable across the base PAK and the active KMF
        -- localization cache. Only use an ID overlay when the live provider
        -- returned no source value that could be translated exactly.
        local replacement = directLookup(index, nil) or explicitLookup(index, nil)
        replacement = runtimeFixes.authoritativeAggregateLookup(index, replacement) or replacement
        if replacement ~= nil then
            return translateVisibleText(replacement)
        end

        if type(index) == "string" and hasCjk(index) then
            local translated = repairLiveString(
                "LanguageData.StringDB_CN_Data",
                index,
                "RawText",
                index
            )
            if translated ~= index then
                return translated
            end
        end

                return nil
    end

    function manager:GetLangStrSplit(index, tag)
        local ok, result = pcall(originalGetLangStrSplit, self, index, tag)
        if ok and result ~= nil then
            if type(result) == "string" then
                local authoritative = runtimeFixes.authoritativeAggregateLookup(index, result)
                if authoritative ~= nil then
                    return translateVisibleText(authoritative)
                end
                return repairLiveString(
                    "LanguageData.StringDB_CN_Data_" .. tostring(tag or ""),
                    index,
                    "Value",
                    result
                )
            end
            return result
        end

        local replacement = directLookup(index, tag) or explicitLookup(index, tag)
        replacement = runtimeFixes.authoritativeAggregateLookup(index, replacement) or replacement
        if replacement ~= nil then
            return translateVisibleText(replacement)
        end

        if type(index) == "string" and hasCjk(index) then
            local translated = repairLiveString(
                "LanguageData.StringDB_CN_Data_" .. tostring(tag or ""),
                index,
                "RawText",
                index
            )
            if translated ~= index then
                return translated
            end
        end

                return nil
    end

    if type(originalGetRow) == "function" then
        function manager:GetRow(tableName, rowKey, priority)
            local languagePrefix = "LanguageData.StringDB_CN_Data"
            if type(tableName) == "string" and tableName:sub(1, #languagePrefix) == languagePrefix then
                local suffix = tableName:sub(#languagePrefix + 1)
                local tag = suffix:sub(1, 1) == "_" and suffix:sub(2) or nil
                if tag == "" then
                    tag = nil
                end
                local ok, result = pcall(
                    originalGetRow,
                    self,
                    tableName,
                    rowKey,
                    priority
                )
                if ok and result ~= nil then
                    if type(result) == "string" then
                        local authoritative = runtimeFixes.authoritativeAggregateLookup(rowKey, result)
                        if authoritative ~= nil then
                            return translateVisibleText(authoritative)
                        end
                        return repairLiveString(tableName, rowKey, "Value", result)
                    end
                    return result
                end
                local translated = directLookup(rowKey, tag) or explicitLookup(rowKey, tag)
                translated = runtimeFixes.authoritativeAggregateLookup(rowKey, translated) or translated
                if translated ~= nil then
                    return translateVisibleText(translated)
                end
                return nil
            end

            return originalGetRow(self, tableName, rowKey, priority)
        end
    end

    report("installed translated localization lookup")
    return value
end, 1000000, "cpdd.runtime-fix.localization")

-- Only these generated helpers have confirmed runtime-only localization gaps.
-- Iterating this tiny list avoids scanning and wrapping every TableData helper.
local generatedRowRepairAllowlist = {
    -- Translate narration before the black/white screen component sets its text.
    "GetDialogueBlackScreenTextRow",
    -- Rank badges read Name again on every refresh, replacing baked defaults.
    "GetTrinityRankNameDataRow",
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
local generatedRowRepairCache = setmetatable({}, { __mode = "k" })

local function wrapGeneratedRowHelper(helperName, original)
    return function(...)
        local rowKey = select(1, ...)
        local row = original(...)
        if not runtimeRowRepairEnabled() then
            return row
        end

        local rowType = type(row)
        if rowType == "table" or rowType == "userdata" then
            local cached = generatedRowRepairCache[row]
            if cached and cached[helperName] ~= nil then
                return cached[helperName]
            end
        end

        if helperName == "GetSkillDataNewRow" then
            row = repairMarionetteSkillRow(row, rowKey)
        elseif helperName == "GetBuffDataNewRow" and rowKey == 82071030 and type(row) == "table" then
            fillLocalizedField(row, "BuffName", 211107038233344, "buffdata")
            fillLocalizedField(row, "BuffName1", 211107038233344, "buffappear")
            fillLocalizedField(row, "BuffDisc", 211107843539712, nil)
        elseif helperName == "GetPhyDetailDataRow" or helperName == "GetMagDetailDataRow" then
            runtimeFixes.repairPlayerDetailConfig(row)
        elseif helperName == "GetFightPropModeDataRow" then
            runtimeFixes.repairFightPropertyConfig(row)
        elseif helperName == "GetTipsDataRow" then
            runtimeFixes.repairDefenseBreakTipsRow(row, rowKey)
        end
        local repaired = repairLiveValue(helperName, rowKey, "", row, 0, {})
        if rowType == "table" or rowType == "userdata" then
            local cached = generatedRowRepairCache[row]
            if cached == nil then
                cached = setmetatable({}, { __mode = "v" })
                generatedRowRepairCache[row] = cached
            end
            cached[helperName] = repaired
        end
        return repaired
    end
end

local function installTableDataRowRepair(tableData, source)
    if type(tableData) ~= "table" then
        return false
    end

    local wrappers = tableData.__cpddRuntimeFixGeneratedRowWrappers
    if type(wrappers) ~= "table" then
        wrappers = {}
    end

    local wrapped = 0
    for _, helperName in ipairs(generatedRowRepairAllowlist) do
        local member = tableData[helperName]
        if type(member) == "function" and wrappers[helperName] ~= member then
            local original = member
            local wrapper = wrapGeneratedRowHelper(helperName, original)
            tableData[helperName] = wrapper
            wrappers[helperName] = wrapper
            wrapped = wrapped + 1
        end
    end

    tableData.__cpddRuntimeFixGeneratedRowWrappers = wrappers
    tableData.__cpddRuntimeFixRows = VERSION
    if wrapped > 0 then
        report(
            "installed generated TableData row repair on " .. tostring(source)
            .. " helpers=" .. tostring(wrapped)
        )
    end
    return wrapped > 0
end

local tableDataProbesLogged = {}
local function ensureGameTableDataRowRepair(source)
    local tableData = Game and Game.TableData
    local installed = installTableDataRowRepair(tableData, source)
    if not tableDataProbesLogged[source] then
        tableDataProbesLogged[source] = true
        report(
            "probed Game.TableData from " .. tostring(source)
            .. " type=" .. type(tableData)
            .. " installed=" .. tostring(installed)
            .. " target=" .. tostring(tableData)
        )
    end
    return installed
end

local function tableDataFrom(value, environment)
    if type(value) == "table" and type(value.GetSkillDataNewRow) == "function" then
        return value
    end
    if type(value) == "table" and type(value.TableData) == "table" then
        return value.TableData
    end
    if type(environment) == "table" and type(environment.TableData) == "table" then
        return environment.TableData
    end
    return Game and Game.TableData
end

Loader.AfterLoad("Data.Excel.TableData", function(value, environment)
    local tableData = tableDataFrom(value, environment)
    installTableDataRowRepair(tableData, "Data.Excel.TableData")
    ensureGameTableDataRowRepair("Data.Excel.TableData callback")
    return value
end, 1000000, "cpdd.runtime-fix.table-rows")

-- KsbcMgr replaces Game.TableDataManager.GetRow after the ordinary manager
-- localization hook is installed. Some Sealed Artifact rows therefore reach
-- the UI with already-resolved Chinese strings and never pass through
-- GetLangStr or the generated Data.Excel.TableData helpers. Repair only the
-- confirmed player-facing equipment tables at that authoritative boundary.
local managerRowRepairTables = {
    EquipmentUniqueData = true,
    EquipmentMythData = true,
    EquipmentSuitData = true,
    EquipmentSpiritualityConvergenceData = true,
    EquipWordAtkFixedGroupData = true,
    EquipWordAtkFixedWordData = true,
    SealedInfoAttrData = true,
    SealedInfoData = true,
}

-- KsbcMgr replaces the normal table getters with direct archive indexing. A
-- server hotfix can legitimately reference a Lua table omitted from that
-- archive; the shipped getter then indexes nil and aborts the entire hotfix.
-- Capture the ordinary getters before KsbcMgr.Init and use them only when the
-- requested KSBC entry is absent.
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

local function normalizedManagerTableName(tableName)
    if type(tableName) ~= "string" then
        return nil
    end
    return tableName:gsub("^Data%.Excel%.", "")
end

local function installRuntimeManagerRowRepair(manager, source)
    if type(manager) ~= "table" or type(manager.GetRow) ~= "function" then
        return false
    end

    local current = manager.GetRow
    local installed = manager.__cpddRuntimeManagerRowRepair
    if type(installed) == "table"
        and installed.Version == VERSION
        and installed.Wrapper == current
    then
        return false
    end

    local originalGetRow = current
    local wrapper = function(self, tableName, rowKey, priority)
        local row = originalGetRow(self, tableName, rowKey, priority)
        local normalized = normalizedManagerTableName(tableName)
        if not runtimeRowRepairEnabled()
            or normalized == nil
            or not managerRowRepairTables[normalized]
        then
            return row
        end
        return repairLiveValue(normalized, rowKey, "", row, 0, {}, 4)
    end

    manager.GetRow = wrapper
    manager.__cpddRuntimeManagerRowRepair = {
        Version = VERSION,
        Wrapper = wrapper,
        Original = originalGetRow,
    }
    report("installed live KSBC equipment-row repair from " .. tostring(source))
    return true
end

local function installKsbcManagerRowRepair(value, environment)
    local managerClass = getSymbol(value, environment, "KsbcMgr")
    if type(managerClass) ~= "table"
        or managerClass.__cpddRuntimeManagerRowRepair == VERSION
    then
        return value
    end

    local originalInit = managerClass.Init
    if type(originalInit) == "function" then
        managerClass.Init = function(self, ...)
            local manager = Game and Game.TableDataManager
            if type(manager) == "table"
                and runtimeFixes.KsbcFallbackMethods[manager] == nil
            then
                runtimeFixes.KsbcFallbackMethods[manager] = {
                    GetRow = manager.GetRow,
                    GetData = manager.GetData,
                    GetAttr = manager.GetAttr,
                }
            end
            local results = { originalInit(self, ...) }
            runtimeFixes.installKsbcMissingTableFallback(manager, "KsbcMgr.Init")
            installRuntimeManagerRowRepair(
                manager,
                "KsbcMgr.Init"
            )
            return unpack(results)
        end
    end

    managerClass.__cpddRuntimeManagerRowRepair = VERSION
    installRuntimeManagerRowRepair(
        Game and Game.TableDataManager,
        "KsbcMgr loader callback"
    )
    return value
end


Loader.AfterLoad(
    "Framework.Ksbc.KsbcMgr",
    installKsbcManagerRowRepair,
    1000001,
    "cpdd.runtime-fix.ksbc-equipment-rows"
)

Loader.On("after_main", function()
    installRuntimeManagerRowRepair(
        Game and Game.TableDataManager,
        "after_main"
    )
end, 1000001, "cpdd.runtime-fix.ksbc-equipment-rows-main")

local SCENE_TEXT_PRIMARY_ROW_MAX = 12
local SCENE_TEXT_TITLE_MAX = 80
local SCENE_TEXT_HEIGHT_MULTIPLIER = 2
local SCENE_TEXT_INNER_HEIGHT = 640
local SCENE_TEXT_MAIN_LINE_CHAR_BUDGET = 15
local SCENE_TEXT_MAX_ENGLISH_FONT_SIZE = 71
local SCENE_TEXT_MIN_FONT_SIZE = 48
local sceneTextSurfaceReports = 0
local sceneTextSurfaceFailures = 0
local sceneTextSurfaceApplied = setmetatable({}, { __mode = "k" })
local sceneTextInnerReports = 0
local sceneTextInnerApplied = setmetatable({}, { __mode = "k" })
local sceneTextWidgetComponentClass
local sceneTextImportedObjectActorManager

local function needsTallEnglishSceneText(value)
    if type(value) ~= "string" then
        return false
    end
    local plain = value:gsub("<.->", "")
    return plain:find("[A-Za-z]") ~= nil
        and (#plain > SCENE_TEXT_PRIMARY_ROW_MAX or plain:find("[\r\n]") ~= nil)
end

local function isPlainAsciiSceneTitle(value)
    if type(value) ~= "string" or value == "" or #value > SCENE_TEXT_TITLE_MAX then
        return false
    end
    if value:find("[\r\n]") or value:find("<", 1, true) or value:find(">", 1, true) then
        return false
    end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 32 or byte > 126 then
            return false
        end
    end
    return true
end

local function reflowEnglishSceneTitle(displayText, leonSubTitle)
    if not isPlainAsciiSceneTitle(displayText)
        or (leonSubTitle ~= nil and leonSubTitle ~= "")
        or #displayText <= SCENE_TEXT_PRIMARY_ROW_MAX then
        return displayText, leonSubTitle
    end

    local words = {}
    for word in displayText:gmatch("%S+") do
        words[#words + 1] = word
    end
    if #words < 2 then
        return displayText, leonSubTitle
    end

    local bestIndex
    local bestScore
    for index = 1, #words - 1 do
        local primary = table.concat(words, " ", 1, index)
        local continuation = table.concat(words, " ", index + 1)
        local overflow = math.max(0, #primary - SCENE_TEXT_PRIMARY_ROW_MAX)
        local score = overflow * 100 + math.abs(#primary - #continuation)
        if bestScore == nil or score < bestScore then
            bestIndex = index
            bestScore = score
        end
    end

    local primary = table.concat(words, " ", 1, bestIndex)
    local continuation = table.concat(words, " ", bestIndex + 1)
    -- Synthetic English continuations must remain normal scene text. Passing
    -- them through LeonSubTitle forces the second line to 32% of the main font,
    -- which makes quiz questions and answers look truncated from a distance.
    return primary .. "\n" .. continuation, nil
end

local function longestPlainAsciiSceneLine(value)
    if type(value) ~= "string" then
        return nil
    end
    local longest
    for line in value:gmatch("[^\r\n]+") do
        local plain = line:gsub("<.->", "")
        if isPlainAsciiSceneTitle(plain)
            and (longest == nil or #plain > #longest) then
            longest = plain
        end
    end
    return longest
end

local function removeRedundantAuthoredSceneSubtitle(displayText, leonSubTitle)
    if leonSubTitle ~= nil or type(displayText) ~= "string" then
        return displayText, leonSubTitle, false
    end
    local primary, authoredSubtitle = displayText:match(
        "^%s*(.-)%s*[\r\n]+%s*<LeonSubTitle[^>]*>(.-)</>%s*$"
    )
    if not isPlainAsciiSceneTitle(primary) then
        return displayText, leonSubTitle, false
    end
    authoredSubtitle = authoredSubtitle and authoredSubtitle:gsub("<.->", "") or ""
    if not isPlainAsciiSceneTitle(authoredSubtitle) then
        return displayText, leonSubTitle, false
    end
    return primary, nil, true
end

local function sceneTextImport(name)
    if type(import) ~= "function" then
        return nil
    end
    local ok, imported = pcall(import, name)
    if ok then
        return imported
    end
    return nil
end

local function sceneTextObjectByID(manager, objectID)
    if manager == nil then
        return nil
    end
    local getter = manager.GetObjectByID
    if type(getter) ~= "function" then
        return nil
    end
    local ok, object = pcall(getter, objectID)
    if ok and object ~= nil then
        return object
    end
    ok, object = pcall(getter, manager, objectID)
    if ok then
        return object
    end
    return nil
end

local function sceneTextObjectActorManager()
    if type(Game) == "table" and Game.ObjectActorManager ~= nil then
        return Game.ObjectActorManager
    end
    sceneTextImportedObjectActorManager = sceneTextImportedObjectActorManager
        or sceneTextImport("KGObjectActorManager")
    return sceneTextImportedObjectActorManager
end

local function sceneTextVector2D(x, y)
    if type(FVector2D) == "function" then
        local ok, value = pcall(FVector2D, x, y)
        if ok then
            return value
        end
    end
    return { X = x, Y = y }
end

local function liveSceneTextWidgetComponent(self)
    local cppEntity = self and self.CppEntity
    if cppEntity == nil or type(cppEntity.KAPI_Actor_GetComponentByClass) ~= "function" then
        return nil
    end
    sceneTextWidgetComponentClass = sceneTextWidgetComponentClass
        or sceneTextImport("WidgetComponent")
    local objectActorManager = sceneTextObjectActorManager()
    if sceneTextWidgetComponentClass == nil or objectActorManager == nil then
        return nil
    end
    local idOk, componentID = pcall(
        cppEntity.KAPI_Actor_GetComponentByClass,
        cppEntity,
        sceneTextWidgetComponentClass
    )
    if not idOk or componentID == nil then
        return nil
    end
    return sceneTextObjectByID(objectActorManager, componentID)
end

local function fitEnglishSceneTextFont(self)
    local displayText = self and self.displayText
    local cppEntity = self and self.CppEntity
    if type(displayText) ~= "string" or cppEntity == nil then
        return false
    end
    local longestLine = longestPlainAsciiSceneLine(displayText)
    if longestLine == nil then
        return false
    end
    local fontInfo = self.SceneConf and self.SceneConf.FontInfo
    local baseSize = fontInfo and tonumber(fontInfo.Size)
    if not baseSize or baseSize <= 0 then
        return false
    end
    local targetSize = baseSize
    if #longestLine > SCENE_TEXT_PRIMARY_ROW_MAX then
        targetSize = math.min(targetSize, SCENE_TEXT_MAX_ENGLISH_FONT_SIZE)
        if #longestLine > SCENE_TEXT_MAIN_LINE_CHAR_BUDGET then
            targetSize = math.min(
                targetSize,
                math.max(
                    SCENE_TEXT_MIN_FONT_SIZE,
                    math.floor(
                        baseSize * SCENE_TEXT_MAIN_LINE_CHAR_BUDGET / #longestLine + 0.5
                    )
                )
            )
        end
    end
    local changed = false
    if type(cppEntity.KAPI_Actor_UpdateFontSize) == "function" then
        changed = pcall(cppEntity.KAPI_Actor_UpdateFontSize, cppEntity, targetSize) or changed
    end
    if type(cppEntity.KAPI_Actor_UpdateFontLetterSpacing) == "function" then
        changed = pcall(cppEntity.KAPI_Actor_UpdateFontLetterSpacing, cppEntity, 0) or changed
    end
    return changed
end

local function repairEnglishSceneTextInnerLayout(self, phase)
    if type(self) ~= "table"
        or sceneTextInnerApplied[self]
        or not needsTallEnglishSceneText(self.displayText) then
        return false
    end
    local component = liveSceneTextWidgetComponent(self)
    if component == nil or type(component.GetUserWidgetObject) ~= "function" then
        return false
    end
    local rootOk, root = pcall(component.GetUserWidgetObject, component)
    if not rootOk or root == nil then
        return false
    end
    local sizeBox = getNamedWidget(root, "SizeBox_0")
    local textDetail = getNamedWidget(root, "Text_Detail")
    local changed = false
    if sizeBox ~= nil then
        if type(sizeBox.SetHeightOverride) == "function" then
            changed = pcall(sizeBox.SetHeightOverride, sizeBox, SCENE_TEXT_INNER_HEIGHT) or changed
        end
        if type(sizeBox.SetMinDesiredHeight) == "function" then
            changed = pcall(sizeBox.SetMinDesiredHeight, sizeBox, SCENE_TEXT_INNER_HEIGHT) or changed
        end
        pcall(function()
            if sizeBox.InvalidateLayoutAndVolatility ~= nil then
                sizeBox:InvalidateLayoutAndVolatility()
            end
        end)
    end
    if textDetail ~= nil then
        pcall(function()
            local slot = textDetail.Slot
            if slot ~= nil and slot.SetAutoSize ~= nil then
                slot:SetAutoSize(true)
                changed = true
            end
        end)
        pcall(function()
            if textDetail.InvalidateLayoutAndVolatility ~= nil then
                textDetail:InvalidateLayoutAndVolatility()
            end
        end)
    end
    if not changed then
        return false
    end
    sceneTextInnerApplied[self] = true
    if sceneTextInnerReports < 5 then
        sceneTextInnerReports = sceneTextInnerReports + 1
        report(string.format(
            "repaired inner scene text layout phase=%s sizebox=%s text=%s height=%s",
            tostring(phase),
            tostring(sizeBox ~= nil),
            tostring(textDetail ~= nil),
            tostring(SCENE_TEXT_INNER_HEIGHT)
        ))
    end
    return true
end

local function enlargeEnglishSceneTextSurface(self, phase)
    if type(self) ~= "table"
        or sceneTextSurfaceApplied[self]
        or not needsTallEnglishSceneText(self.displayText) then
        return false
    end
    local component = liveSceneTextWidgetComponent(self)
    if component == nil
        or type(component.GetDrawSize) ~= "function"
        or type(component.SetDrawSize) ~= "function" then
        if sceneTextSurfaceFailures < 3 then
            sceneTextSurfaceFailures = sceneTextSurfaceFailures + 1
            report("scene text surface unavailable phase=" .. tostring(phase))
        end
        return false
    end
    local sizeOk, drawSize = pcall(component.GetDrawSize, component)
    local width = sizeOk and drawSize and tonumber(drawSize.X)
    local height = sizeOk and drawSize and tonumber(drawSize.Y)
    if not width or not height or width <= 0 or height <= 0 then
        return false
    end
    local newHeight = math.max(height + 64, math.floor(height * SCENE_TEXT_HEIGHT_MULTIPLIER + 0.5))
    local setOk = pcall(
        component.SetDrawSize,
        component,
        sceneTextVector2D(width, newHeight)
    )
    if not setOk then
        return false
    end
    sceneTextSurfaceApplied[self] = true
    if sceneTextSurfaceReports < 5 then
        sceneTextSurfaceReports = sceneTextSurfaceReports + 1
        report(string.format(
            "enlarged live scene text surface phase=%s size=%sx%s->%sx%s text=%q",
            tostring(phase),
            tostring(width),
            tostring(height),
            tostring(width),
            tostring(newHeight),
            tostring(self.displayText):sub(1, 160)
        ))
    end
    return true
end

Loader.AfterLoad(
    "Gameplay.NetEntities.SceneActor.Components.SceneTextBoardComponent",
    function(value, environment)
        local source = "Gameplay.NetEntities.SceneActor.Components.SceneTextBoardComponent"
        local class = getSymbol(value, environment, "SceneTextBoardComponent")
        if type(class) ~= "table" or class.__cpddSceneTextRepair == VERSION then
            return value
        end
        local originalSetDisplayText = class.SetDisplayText
        if type(originalSetDisplayText) ~= "function" then
            return value
        end
        class.SetDisplayText = function(self, displayText, leonSubTitle)
            if runtimeUIRepairEnabled() then
                displayText = repairLiveString(source, "SetDisplayText", "DisplayText", displayText)
                leonSubTitle = repairLiveString(source, "SetDisplayText", "LeonSubTitle", leonSubTitle)
                local removedAuthoredSubtitle
                displayText, leonSubTitle, removedAuthoredSubtitle = removeRedundantAuthoredSceneSubtitle(
                    displayText,
                    leonSubTitle
                )
                if not removedAuthoredSubtitle then
                    displayText, leonSubTitle = reflowEnglishSceneTitle(displayText, leonSubTitle)
                end
            end
            return originalSetDisplayText(self, displayText, leonSubTitle)
        end
        local originalRefreshContent = class.RefreshContent
        if type(originalRefreshContent) == "function" then
            class.RefreshContent = function(self, ...)
                if runtimeUIRepairEnabled() then
                    enlargeEnglishSceneTextSurface(self, "RefreshContent")
                end
                local result = originalRefreshContent(self, ...)
                if runtimeUIRepairEnabled() then
                    fitEnglishSceneTextFont(self)
                    repairEnglishSceneTextInnerLayout(self, "RefreshContent")
                end
                return result
            end
        end
        local originalInnerTextBlockReady = class.InnerTextBlockReady
        if type(originalInnerTextBlockReady) == "function" then
            class.InnerTextBlockReady = function(self, ...)
                local result = originalInnerTextBlockReady(self, ...)
                if runtimeUIRepairEnabled() then
                    fitEnglishSceneTextFont(self)
                    repairEnglishSceneTextInnerLayout(self, "InnerTextBlockReady")
                    enlargeEnglishSceneTextSurface(self, "InnerTextBlockReady")
                end
                return result
            end
        end
        class.__cpddSceneTextRepair = VERSION
        report("installed scene text translation and complete inner/outer layout repair")
        return value
    end,
    1000000,
    "cpdd.runtime-fix.scene-text"
)

for _, moduleName in ipairs({
    "Gameplay.LogicSystem.SkillCustomizer.Main.Skill_Fight_Item",
    "Gameplay.LogicSystem.SecretPartner.Base.SecretPartnerSkill",
}) do
    Loader.AfterLoad(moduleName, function(value)
        installTableDataRowRepair(Game and Game.TableData, moduleName)
        return value
    end, 1000000, "cpdd.runtime-fix.table-rows-late." .. moduleName:gsub("[^%w]", "-"))
end

Loader.AfterLoad("Gameplay.Const.StringConst.StringConst", function(value, environment)
    local stringConst = getSymbol(value, environment, "StringConst")
    if type(stringConst) ~= "table" or stringConst.__cpddRuntimeFixV1 then
        return value
    end

    stringConst.__cpddRuntimeFixV1 = true
    local originalGet = assert(stringConst.Get)

    stringConst.Get = function(key, ...)
        local replacement = stringConstOverrides[key]
        if replacement ~= nil then
            if select("#", ...) > 0 then
                local formatOk, formatted = pcall(string.format, replacement, ...)
                if formatOk then
                    return formatted
                end
                report("StringConst override format failed key=" .. tostring(key))
            end
            return replacement
        end
        local getOk, result = pcall(originalGet, key, ...)
        if not getOk then
            report("StringConst.Get failed key=" .. tostring(key) .. " error=" .. tostring(result))
            return tostring(key or "")
        end
        return repairLiveString("StringConst", key, key, result)
    end

    return value
end, 1000000, "cpdd.runtime-fix.string-const")

local numberWordsUnderTwenty = {
    "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
    "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
    "Seventeen", "Eighteen", "Nineteen",
}
local numberWordsTens = {
    [2] = "Twenty",
    [3] = "Thirty",
    [4] = "Forty",
    [5] = "Fifty",
    [6] = "Sixty",
    [7] = "Seventy",
    [8] = "Eighty",
    [9] = "Ninety",
}

local function englishNumberUnderHundred(num)
    if num < 20 then
        return numberWordsUnderTwenty[num + 1]
    end

    local tens = math.floor(num / 10)
    local ones = num % 10
    local result = numberWordsTens[tens]
    if ones ~= 0 then
        result = result .. " " .. numberWordsUnderTwenty[ones + 1]
    end
    return result
end

local function englishNumberUnderThousand(num)
    if num < 100 then
        return englishNumberUnderHundred(num)
    end

    local hundreds = math.floor(num / 100)
    local remainder = num % 100
    local result = numberWordsUnderTwenty[hundreds + 1] .. " Hundred"
    if remainder ~= 0 then
        result = result .. " " .. englishNumberUnderHundred(remainder)
    end
    return result
end

local function englishNumber(num)
    if type(num) ~= "number" or num < 0 or num >= 10000 or math.floor(num) ~= num then
        return num
    end
    if num < 1000 then
        return englishNumberUnderThousand(num)
    end

    local thousands = math.floor(num / 1000)
    local remainder = num % 1000
    local result = englishNumberUnderThousand(thousands) .. " Thousand"
    if remainder ~= 0 then
        result = result .. " " .. englishNumberUnderThousand(remainder)
    end
    return result
end

Loader.AfterLoad("Gameplay.LogicSystem.Utils.HUDUtils", function(value, environment)
    ensureGameTableDataRowRepair("HUDUtils")
    local hudUtils = getSymbol(value, environment, "HUDUtils")
    if type(hudUtils) ~= "table" or hudUtils.__cpddRuntimeFixV1 then
        return value
    end

    hudUtils.__cpddRuntimeFixV1 = true
    hudUtils.NumberToChinese = englishNumber
    report("installed English HUD number formatter")
    return value
end, 1000000, "cpdd.runtime-fix.hud-number-format")

-- FamilySystem builds seat labels by concatenating NumberToChinese(index)
-- with the localized suffix. After the global English number formatter that
-- produces labels such as "ThreeSeat". Return the lore-facing ordinal names
-- directly for every authored family seat instead.
Loader.AfterLoad("Gameplay.LogicSystem.Family.FamilySystem", function(value, environment)
    local familySystem = getSymbol(value, environment, "FamilySystem")
    if type(familySystem) ~= "table"
        or familySystem.__cpddEnglishFamilySeatName == VERSION
    then
        return value
    end

    local originalGetSeatName = familySystem.GetSeatName
    if type(originalGetSeatName) ~= "function" then
        return value
    end

    local familySeatNames = {
        [2] = "Second Seat",
        [3] = "Third Seat",
        [4] = "Fourth Seat",
        [5] = "Fifth Seat",
        [6] = "Sixth Seat",
        [7] = "Seventh Seat",
        [8] = "Eighth Seat",
        [9] = "Ninth Seat",
        [10] = "Tenth Seat",
        [11] = "Eleventh Seat",
        [12] = "Twelfth Seat",
        [13] = "Thirteenth Seat",
        [14] = "Fourteenth Seat",
    }
    familySystem.GetSeatName = function(self, index)
        local replacement = familySeatNames[index]
        if replacement ~= nil then
            return replacement
        end
        return originalGetSeatName(self, index)
    end
    familySystem.__cpddEnglishFamilySeatName = VERSION
    report("installed English family-seat ordinal names")
    return value
end, 1000000, "cpdd.runtime-fix.family-seat-names")

-- The Style detail section was authored for short Chinese labels. Its two
-- sibling widgets begin too close to the left edge, so longer English style
-- names are clipped by the parent panel. Move the complete title and progress
-- section together, preserving the row spacing and rank bars.
Loader.AfterLoad(
    "Gameplay.LogicSystem.Fashion.FashionMain.UIPanel.FashionMain_Panel.ChangeWidget.Fashion_DetailExpand",
    function(value, environment)
        local fashionDetail = getSymbol(value, environment, "Fashion_DetailExpand")
        if type(fashionDetail) ~= "table"
            or fashionDetail.__cpddEnglishStyleLayout == VERSION
        then
            return value
        end

        local function reflowStyleDetails(owner)
            if not runtimeUIRepairEnabled() then
                return false
            end

            local view = owner and owner.view
            local root = owner and (owner.userWidget or owner.widget)
            local changed = false
            for _, widgetName in ipairs({
                "StyleText",
                "WBP_FashionChange_StyleProgress",
            }) do
                local widget = getNamedWidget(view, widgetName)
                    or getNamedWidget(root, widgetName)
                if widget ~= nil then
                    local ok = pcall(function()
                        if widget.SetRenderTranslation ~= nil then
                            widget:SetRenderTranslation(sceneTextVector2D(48, 0))
                            changed = true
                        end
                        if widget.InvalidateLayoutAndVolatility ~= nil then
                            widget:InvalidateLayoutAndVolatility()
                        end
                    end)
                    changed = ok or changed
                end
            end
            return changed
        end

        local originalRefreshStyle = fashionDetail.RefreshStyle
        if type(originalRefreshStyle) ~= "function" then
            return value
        end

        fashionDetail.RefreshStyle = function(self, ...)
            local results = { originalRefreshStyle(self, ...) }
            reflowStyleDetails(self)
            scheduleRepairBurst(self, reflowStyleDetails, 0.50)
            return unpack(results)
        end
        fashionDetail.__cpddEnglishStyleLayout = VERSION
        report("installed English Style detail horizontal reflow")
        return value
    end,
    1000000,
    "cpdd.runtime-fix.fashion-style-layout"
)

Loader.AfterLoad("Gameplay.LogicSystem.Reminder.PlayerInfo.PowerItemSpecial", function(value, environment)
    ensureGameTableDataRowRepair("PowerItemSpecial")
    local powerItem = getSymbol(value, environment, "PowerItemSpecial")
    if type(powerItem) ~= "table" or powerItem.__cpddRuntimeFixV1 then
        return value
    end

    powerItem.__cpddRuntimeFixV1 = true
    local originalRefresh = assert(powerItem.Refresh)
    function powerItem:Refresh(...)
        local results = { originalRefresh(self, ...) }
        if runtimeUIRepairEnabled() then
            translateViewTextWidgets(self.view, self.userWidget)
        end
        return unpack(results)
    end

    report("installed Beyonder Rating reminder label fix")
    return value
end, 1000000, "cpdd.runtime-fix.power-rating-label")

Loader.AfterLoad("Gameplay.LogicSystem.NewHeadInfo.HeadInfoUI.HeadInfoName", function(value, environment)
    ensureGameTableDataRowRepair("HeadInfoName")
    local headInfoName = getSymbol(value, environment, "HeadInfoName")
    if type(headInfoName) ~= "table" or headInfoName.__cpddRuntimeFixV1 then
        return value
    end

    headInfoName.__cpddRuntimeFixV1 = true
    local originalGetEntityName = assert(headInfoName.getEntityName)
    local originalOnHeadNameChanged = assert(headInfoName.OnHeadNameChanged)

    function headInfoName:getEntityName(entity)
        return translateVisibleText(originalGetEntityName(self, entity))
    end

    function headInfoName:OnHeadNameChanged(name)
        return originalOnHeadNameChanged(self, translateVisibleText(name))
    end

    report("installed translated overhead NPC names")
    return value
end, 1000000, "cpdd.runtime-fix.head-info-name")

Loader.AfterLoad("Gameplay.LogicSystem.Race.WorldWidget.RaceTrace_Widget", function(value, environment)
    local raceWidget = getSymbol(value, environment, "RaceTrace_Widget")
    if type(raceWidget) ~= "table" or raceWidget.__cpddRuntimeFixV1 then
        return value
    end

    local mathLibrary = getSymbol(value, environment, "KismetMathLibrary")
    if type(mathLibrary) ~= "table" then
        local ok, imported = pcall(import, "KismetMathLibrary")
        if ok then
            mathLibrary = imported
        end
    end
    if type(mathLibrary) ~= "table" or type(mathLibrary.Vector_Distance) ~= "function" then
        report("could not install RaceTrace meter fix: KismetMathLibrary unavailable")
        return value
    end

    raceWidget.__cpddRuntimeFixV1 = true
    function raceWidget:UpdateDistance()
        if not Game or not Game.me or not self.checkpointPos then
            return
        end

        local playerPos = Game.me.CppEntity:KAPI_GetLocation()
        local dist = mathLibrary.Vector_Distance(playerPos, self.checkpointPos)
        local distMeter = math.floor(dist / 100)
        local distanceWidget = self.view and self.view.Text_Distance
        if distanceWidget
            and (self.__cpddDistanceWidget ~= distanceWidget
                or self.__cpddLastDistanceMeter ~= distMeter)
        then
            self.__cpddDistanceWidget = distanceWidget
            self.__cpddLastDistanceMeter = distMeter
            distanceWidget:SetText(tostring(distMeter) .. "m")
        end
    end

    report("installed RaceTrace meter fix")
    return value
end, 1000000, "cpdd.runtime-fix.racetrace-meter")

Loader.AfterLoad("Gameplay.LogicSystem.Tips.TipsSystem", function(value, environment)
    local tipsSystem = getSymbol(value, environment, "TipsSystem")
    if type(tipsSystem) ~= "table" or tipsSystem.__cpddRuntimeFixV1 then
        return value
    end

    tipsSystem.__cpddRuntimeFixV1 = true
    local originalParse = assert(tipsSystem._parseTipsDataSections)

    function tipsSystem:_parseTipsDataSections(tipsId)
        if tipsId == CIRCUIT_BREAKER_TIPS_ID then
            return {
                {
                    Content = { CIRCUIT_BREAKER_TEXT },
                },
            }
        end
        return originalParse(self, tipsId)
    end

    return value
end, 1000000, "cpdd.runtime-fix.circuit-breaker-content")

Loader.AfterLoad("Gameplay.LogicSystem.Login.LoginServerSelect_Panel", function(value, environment)
    local panel = getSymbol(value, environment, "LoginServerSelect_Panel")
    if type(panel) ~= "table" or panel.__cpddRuntimeFixV1 then
        return value
    end

    panel.__cpddRuntimeFixV1 = true
    function panel:on_Btn_Info_Clicked()
        Game.TipsSystem:ShowTips(CIRCUIT_BREAKER_TIPS_ID, self.view.Btn_Info:GetCachedGeometry())
    end

    return value
end, 1000000, "cpdd.runtime-fix.circuit-breaker-button")

Loader.AfterLoad("Gameplay.LogicSystem.SkillCustomizer.SkillBuffDescUtils", function(value, environment)
    local utils = getSymbol(value, environment, "SkillBuffDescUtils")
    if type(utils) ~= "table" or utils.__cpddRuntimeFixV1 then
        return value
    end

    utils.__cpddRuntimeFixV1 = true
    local originalPostProcessingString = assert(utils.PostProcessingString)
    local originalAssembleDescString = assert(utils.AssembleDescString)

    function utils:PostProcessingString(inString, rtbOverWrite, id, level, descType, originalType, descContext)
        local result = originalPostProcessingString(self, inString, rtbOverWrite, id, level, descType, originalType, descContext)
        if id ~= 86071030 or type(result) ~= "string" then
            return result
        end

        local spellFieldIds = { 811710303, 811710304 }
        local replacementIndex = 0
        result = result:gsub("spellfielddisc%(%s*82071030%s*%)", function()
            replacementIndex = replacementIndex + 1
            local spellFieldId = spellFieldIds[replacementIndex] or spellFieldIds[#spellFieldIds]
            local helper = getSymbol(nil, environment, "DescFormulaHelper")
            if type(helper) == "table" and type(helper.GenerateDesc) == "function" then
                local ok, generated = pcall(helper.GenerateDesc, spellFieldId, level, utils.DescType.SpellField, originalType, descContext)
                if ok and generated ~= nil and generated ~= "" then
                    return tostring(generated)
                end
            end
            return "additional"
        end)
        result = result:gsub("NO_BUFF_NAME", "Star Sand Gathering")
        result = result:gsub("NO_SUCH_INFORMATION", "Each stack reduces Movement Speed.")
        return result
    end

    function utils:AssembleDescString(inString, values, rtbOverWrite, id, level, descType, originalType, descContext)
        local original = originalAssembleDescString(
            self, inString, values, rtbOverWrite, id, level,
            descType, originalType, descContext
        )
        if type(original) ~= "string" then
            return original
        end
        local translated = repairLiveString(
            "SkillBuffDescUtils", id, "AssembleDescString.return", original
        )
        runtimeMetrics.CaptureTranslationAssignment(
            self, "SkillBuffDescUtils", "SkillBuffDescUtils",
            "Description", original, translated
        )
        return translated
    end

    report("installed shared generated skill/buff-description translation")
    return value
end, 1000000, "cpdd.runtime-fix.star-sand-description")

Loader.AfterLoad("Gameplay.LogicSystem.SkillCustomizer.DescFormulaHelper", function(value, environment)
    local helper = getSymbol(value, environment, "DescFormulaHelper")
    if type(helper) ~= "table" or helper.__cpddGeneratedTipsRepair == VERSION then
        return value
    end
    local originalGenerateTipsDesc = helper.GenerateTipsDesc
    if type(originalGenerateTipsDesc) ~= "function" then
        return value
    end

    helper.GenerateTipsDesc = function(tipsString, markTag)
        local original = originalGenerateTipsDesc(tipsString, markTag)
        if type(original) ~= "string" then
            return original
        end
        local translated = repairLiveString(
            "DescFormulaHelper", "GenerateTipsDesc",
            "GenerateTipsDesc.return", original
        )
        runtimeMetrics.CaptureTranslationAssignment(
            nil, "DescFormulaHelper", "DescFormulaHelper",
            "TipsDescription", original, translated
        )
        return translated
    end
    helper.__cpddGeneratedTipsRepair = VERSION
    report("installed shared generated equipment-tip translation")
    return value
end, 1000000, "cpdd.runtime-fix.generated-equipment-tip-description")

local function installSkillDescriptionRepair(value, environment)
    local skillSystem = getSymbol(value, environment, "SkillCustomSystem")
    if type(skillSystem) ~= "table" or skillSystem.__cpddGeneratedTextRepair == VERSION then
        return false
    end

    local wrapped = 0
    for _, methodName in ipairs({
        "GenerateSkillDescNoRichText",
        "GenerateSkillBriefDesc",
        "GenerateSkillDecoText",
    }) do
        local original = skillSystem[methodName]
        if type(original) == "function" then
            skillSystem[methodName] = function(self, ...)
                local results = { original(self, ...) }
                if type(results[1]) == "string" then
                    results[1] = repairLiveString("SkillCustomSystem", select(1, ...), methodName, results[1])
                end
                return unpack(results)
            end
            wrapped = wrapped + 1
        end
    end

    local originalTalents = skillSystem.GetCurrentSkillRelatedTalentIDs
    if type(originalTalents) == "function" then
        skillSystem.GetCurrentSkillRelatedTalentIDs = function(self, skillId)
            -- This method builds fresh rows from SkillIDTalentNodeMap, which
            -- bypasses GetRow. Translate before consumers strip rich-text tags.
            local rows = originalTalents(self, skillId)
            if type(rows) == "table" then
                for _, row in ipairs(rows) do
                    if type(row) == "table" and type(row.Desc) == "string" then
                        row.Desc = repairLiveString("SkillCustomSystem", row.NodeID,
                            "GetCurrentSkillRelatedTalentIDs.Desc", row.Desc)
                    end
                end
            end
            return rows
        end
        wrapped = wrapped + 1
    end

    skillSystem.__cpddGeneratedTextRepair = VERSION
    if wrapped > 0 then
        report("installed generated skill-description repair")
    end
    return wrapped > 0
end

Loader.AfterLoad(
    "Gameplay.LogicSystem.SkillCustomizer.SkillCustomSystem",
    function(value, environment)
        installSkillDescriptionRepair(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.generated-skill-description"
)

local function installViewMethodRepair(value, environment, symbolName, methodNames, source, directOnly)
    local class = getSymbol(value, environment, symbolName)
    if type(class) ~= "table" then
        return false
    end

    local marker = "__cpddViewTextRepair_" .. VERSION
    if class[marker] then
        return true
    end

    local wrapped = 0
    for _, methodName in ipairs(methodNames) do
        local original = class[methodName]
        if type(original) == "function" then
            class[methodName] = function(self, ...)
                local results = { original(self, ...) }
                if runtimeUIRepairEnabled() then
                    -- Refresh methods can repaint serialized Blueprint text or
                    -- bind a different row to an existing component. Rescan on
                    -- the event itself; this remains bounded to this view and
                    -- does not restore the expensive global widget sweep.
                    local started = nowMilliseconds()
                    local repaired = directOnly
                        and translateDirectViewTextWidgets(self and self.view)
                        or translateViewTextWidgets(
                            self and self.view,
                            self and (self.userWidget or self.widget)
                        )
                    local elapsed = nowMilliseconds() - started
                    if elapsed >= 8 then
                        runtimeMetrics.SlowTargetedRepairs =
                            runtimeMetrics.SlowTargetedRepairs + 1
                        report("slow targeted view repair source=" .. tostring(source)
                            .. " method=" .. tostring(methodName)
                            .. " elapsed_ms=" .. string.format("%.2f", elapsed)
                            .. " labels=" .. tostring(repaired or 0)
                            .. " direct=" .. tostring(directOnly == true))
                    end
                end
                return unpack(results)
            end
            wrapped = wrapped + 1
        end
    end

    class[marker] = true
    if wrapped > 0 then
        report("installed post-refresh widget repair for " .. source)
    end
    return wrapped > 0
end

local function installDataMethodRepair(value, environment, symbolName, methodNames, source)
    local class = getSymbol(value, environment, symbolName)
    if type(class) ~= "table" then
        return false
    end

    local marker = "__cpddDataTextRepair_" .. VERSION
    if class[marker] then
        return true
    end

    local wrapped = 0
    for _, methodName in ipairs(methodNames) do
        local original = class[methodName]
        if type(original) == "function" then
            class[methodName] = function(self, ...)
                if not runtimeUIRepairEnabled() then
                    return original(self, ...)
                end
                local argumentCount = select("#", ...)
                local arguments = { ... }
                local translateStarted = nowMilliseconds()
                for argumentIndex = 1, argumentCount do
                    local data = arguments[argumentIndex]
                    local fieldName = methodName .. ".argument" .. tostring(argumentIndex)
                    if type(data) == "string" then
                        local translated = repairLiveString(source, methodName, fieldName, data)
                        runtimeMetrics.CaptureDataAssignment(
                            self, source, symbolName, fieldName, data, translated, methodName
                        )
                        arguments[argumentIndex] = translated
                    elseif type(data) == "table" then
                        translateTableStrings(data, nil, {
                            component = self,
                            module = source,
                            class = symbolName,
                            record = methodName,
                        }, fieldName)
                    end
                end
                local translateElapsed = nowMilliseconds() - translateStarted
                local results = { original(self, unpack(arguments, 1, argumentCount)) }
                -- Data-driven rows and tooltip blocks are reused. Their first
                -- refresh can contain a placeholder or an earlier item's text,
                -- so a per-instance "already repaired" flag leaves later CJK
                -- values untranslated and invisible to the detector. This is
                -- still event-driven: only the small component being refreshed
                -- is rescanned, never every widget on every frame.
                local widgetStarted = nowMilliseconds()
                local repaired = translateDirectViewTextWidgets(self and self.view)
                local widgetElapsed = nowMilliseconds() - widgetStarted
                local elapsed = translateElapsed + widgetElapsed
                if elapsed >= 8 then
                    runtimeMetrics.SlowTargetedRepairs =
                        runtimeMetrics.SlowTargetedRepairs + 1
                    report("slow targeted data repair source=" .. tostring(source)
                        .. " method=" .. tostring(methodName)
                        .. " elapsed_ms=" .. string.format("%.2f", elapsed)
                        .. " argument_ms=" .. string.format("%.2f", translateElapsed)
                        .. " widget_ms=" .. string.format("%.2f", widgetElapsed)
                        .. " labels=" .. tostring(repaired or 0))
                end
                return unpack(results)
            end
            wrapped = wrapped + 1
        end
    end

    class[marker] = true
    if wrapped > 0 then
        report("installed rendered data repair for " .. source)
    end
    return wrapped > 0
end

runtimeMetrics.InstallEquipmentSpecialTextRepair = function(value, environment)
    local source = "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipSpecial"
    local className = "ItemTipsEquipSpecial"
    local class = getSymbol(value, environment, className)
    if type(class) ~= "table" or class.__cpddEquipmentSpecialTextRepair == VERSION then
        return type(class) == "table"
    end

    local originalSetData = class.SetData
    if type(originalSetData) ~= "function" then
        return false
    end

    class.SetData = function(self, suitName, suitBrief, suitDesc, story, uniqueData, index)
        if not runtimeUIRepairEnabled() then
            return originalSetData(self, suitName, suitBrief, suitDesc, story, uniqueData, index)
        end

        local originalName, originalBrief, originalDesc, originalStory = suitName, suitBrief, suitDesc, story
        suitName = repairLiveString(source, index, "SuitName", suitName)
        suitBrief = repairLiveString(source, index, "SuitBrief", suitBrief)
        suitDesc = repairLiveString(source, index, "SuitDesc", suitDesc)
        story = repairLiveString(source, index, "Story", story)

        runtimeMetrics.CaptureTranslationAssignment(self, source, className, "SuitName", originalName, suitName)
        runtimeMetrics.CaptureTranslationAssignment(self, source, className, "SuitBrief", originalBrief, suitBrief)
        runtimeMetrics.CaptureTranslationAssignment(self, source, className, "SuitDesc", originalDesc, suitDesc)
        runtimeMetrics.CaptureTranslationAssignment(self, source, className, "Story", originalStory, story)

        local results = { originalSetData(self, suitName, suitBrief, suitDesc, story, uniqueData, index) }
        local context = {
            panel = className,
            module = source,
            class = className,
            pass = "item-tips-set-data",
        }
        local view = self and self.view
        if type(view) == "table" then
            translateTextWidget(view.Text_Name, context)
            translateTextWidget(view.Text_Detail, context)
            translateTextWidget(view.Text_Story, context)
        end
        return unpack(results)
    end
    class.__cpddEquipmentSpecialTextRepair = VERSION
    report("installed authoritative ItemTipsEquipSpecial:SetData translation")
    return true
end

runtimeMetrics.InstallSealedSkillDescRepair = function(value, environment)
    local source = "Gameplay.LogicSystem.Sealed_2.SealedSystem"
    local className = "SealedSystem"
    local class = getSymbol(value, environment, className)
    if type(class) ~= "table" or class.__cpddSealedSkillDescRepair == VERSION then
        return type(class) == "table"
    end

    local originalGetDesc = class.GetSealedSkillDescText
    if type(originalGetDesc) ~= "function" then
        return false
    end

    class.GetSealedSkillDescText = function(self, skillList, sealedId, sealedGrade, knowledgeLevel)
        local original = originalGetDesc(self, skillList, sealedId, sealedGrade, knowledgeLevel)
        if not runtimeUIRepairEnabled() or type(original) ~= "string" then
            return original
        end

        -- Sealed descriptions are assembled after StringDB lookup and formula
        -- evaluation. Repair the generated result so every consumer (equip,
        -- promote, quick assembly, and item tips) receives the same English
        -- text, including descriptions whose CheckStar tokens became numbers.
        local translated = repairLiveString(
            source, sealedId, "GetSealedSkillDescText.return", original
        )
        runtimeMetrics.CaptureTranslationAssignment(
            self, source, className, "SkillDescription", original, translated
        )
        return translated
    end
    class.__cpddSealedSkillDescRepair = VERSION
    report("installed authoritative SealedSystem skill-description translation")
    return true
end

local function installGuildRoleRepair(value, environment)
    local guildSystem = getSymbol(value, environment, "GuildSystem")
    if type(guildSystem) ~= "table" or guildSystem.__cpddRoleTextRepair == VERSION then
        return false
    end

    local wrapped = 0
    for _, methodName in ipairs({ "RoleIDToRoleName", "GetOccupationText" }) do
        local original = guildSystem[methodName]
        if type(original) == "function" then
            guildSystem[methodName] = function(self, ...)
                local results = { original(self, ...) }
                if type(results[1]) == "string" then
                    results[1] = repairLiveString("GuildSystem", select(1, ...), methodName, results[1])
                end
                return unpack(results)
            end
            wrapped = wrapped + 1
        end
    end

    guildSystem.__cpddRoleTextRepair = VERSION
    if wrapped > 0 then
        report("installed translated club-role names")
    end
    return wrapped > 0
end

local DIALOGUE_LINE_MAX = 42
local DIALOGUE_ROW_HEIGHT = 58
local DIALOGUE_VISIBLE = 4
do
    local ok, visibility = pcall(function()
        return import("ESlateVisibility")
    end)
    if ok and visibility ~= nil then
        DIALOGUE_VISIBLE = visibility.SelfHitTestInvisible or visibility.Visible or DIALOGUE_VISIBLE
    end
end

local function scheduleRepairAfter(self, delay, repair)
    if self == nil or type(repair) ~= "function" then
        return false
    end
    local ok, addTimer = pcall(function()
        return self.AddTimerWithFunction
    end)
    if not ok or type(addTimer) ~= "function" then
        return false
    end
    return pcall(addTimer, self, delay, 1, function()
        pcall(repair, self)
    end)
end

local pendingRepairBursts = setmetatable({}, { __mode = "k" })
local function scheduleRepairBurst(self, repair, finalDelay)
    if self == nil or type(repair) ~= "function" then
        return false
    end
    local ok, addTimer = pcall(function()
        return self.AddTimerWithFunction
    end)
    if not ok or type(addTimer) ~= "function" then
        return false
    end

    local pending = pendingRepairBursts[self]
    if pending == nil then
        pending = {}
        pendingRepairBursts[self] = pending
    elseif pending[repair] then
        return false
    end
    pending[repair] = true

    local function clearPending()
        pending[repair] = nil
        if next(pending) == nil then
            pendingRepairBursts[self] = nil
        end
    end

    local scheduledOk, scheduled = pcall(addTimer, self, 0.01, 1, function()
        pcall(repair, self)
        local finalOk, finalScheduled = pcall(addTimer, self, finalDelay or 0.50, 1, function()
            pcall(repair, self)
            clearPending()
        end)
        if not finalOk or finalScheduled == false then
            clearPending()
        end
    end)
    if not scheduledOk or scheduled == false then
        clearPending()
        return false
    end
    return true
end

local function normalizeDialogueWhitespace(value)
    if type(value) ~= "string" then
        return value
    end
    value = value:gsub("%s*\r?\n%s*", " ")
    value = value:gsub("[ \t]+", " ")
    return value:match("^%s*(.-)%s*$")
end

local function dialogueVisibleLength(value)
    if type(value) ~= "string" then
        return 0
    end
    local plain = value:gsub("<.->", "")
    local ok, length = pcall(function()
        return utf8.len(plain)
    end)
    return ok and length or #plain
end

local function revealDialogueRows(self)
    local talkWidget = self and self.userWidget
    if talkWidget == nil then
        return false
    end
    local changed = false
    -- The native printer already assigns one line to each RichTextBlock. Do
    -- not enable RichText auto-wrap as that wraps the foreground and shadow
    -- layers independently and produces the narrow duplicate text tower.
    for _, widgetName in ipairs({
        "RTB_TalkContent_Back_lua", "RTB_TalkContent_lua",
        "RTB_TalkContent2_Back_lua", "RTB_TalkContent2_lua",
        "RTB_TalkContent3_Back_lua", "RTB_TalkContent3_lua",
    }) do
        pcall(function()
            local widget = getNamedWidget(talkWidget, widgetName)
            if widget ~= nil then
                if widget.SetAutoWrapText ~= nil then
                    widget:SetAutoWrapText(false)
                end
                changed = true
            end
        end)
    end

    -- Only reveal the third row when it was actually bound. Never force both
    -- the CanvasPanel and VerticalBox layout variants visible: some cooked
    -- dialogue widgets contain both and doing so renders the same text twice.
    if self.__cpddDialogueHasThirdLine then
        for _, widgetName in ipairs({
            "RTB_TalkContent3_Back_lua", "RTB_TalkContent3_lua",
        }) do
            pcall(function()
                local widget = getNamedWidget(talkWidget, widgetName)
                if widget ~= nil then
                    widget:SetVisibility(DIALOGUE_VISIBLE)
                    if widget.SetRenderOpacity ~= nil then
                        widget:SetRenderOpacity(1)
                    end
                end
            end)
        end

        pcall(function()
            local canvasRow = getNamedWidget(talkWidget, "Canvas_Content03")
            local sizeRow = nil
            if canvasRow ~= nil then
                canvasRow:SetVisibility(DIALOGUE_VISIBLE)
                if canvasRow.SetRenderOpacity ~= nil then
                    canvasRow:SetRenderOpacity(1)
                end
                sizeRow = getNamedWidget(talkWidget, "SizeBox_3")
            else
                sizeRow = getNamedWidget(talkWidget, "SizeBox_2")
            end
            if sizeRow ~= nil then
                sizeRow:SetVisibility(DIALOGUE_VISIBLE)
                if sizeRow.SetRenderOpacity ~= nil then
                    sizeRow:SetRenderOpacity(1)
                end
                if sizeRow.SetHeightOverride ~= nil then
                    sizeRow:SetHeightOverride(DIALOGUE_ROW_HEIGHT)
                end
            end
        end)
    end
    return changed
end

local function reportDialogueThirdRowState(self)
    if self == nil or self.__cpddDialogueThirdRowReported == VERSION then
        return
    end
    self.__cpddDialogueThirdRowReported = VERSION
    local talkWidget = self.userWidget
    if talkWidget == nil then
        return
    end
    local states = {}
    for _, widgetName in ipairs({
        "Canvas_Content03", "SizeBox_2", "SizeBox_3",
        "RTB_TalkContent3_Back_lua", "RTB_TalkContent3_lua",
    }) do
        pcall(function()
            local widget = getNamedWidget(talkWidget, widgetName)
            if widget ~= nil then
                local visibility = widget.GetVisibility and tostring(widget:GetVisibility()) or "?"
                local opacity = widget.GetRenderOpacity and tostring(widget:GetRenderOpacity()) or "?"
                states[#states + 1] = widgetName .. "=" .. visibility .. "/" .. opacity
            end
        end)
    end
    report("dialogue third-row live state " .. table.concat(states, ","))
end

local function bindDialogueRows(self)
    local talkWidget = self and self.userWidget
    local printer = self and self.ContentPrinter
    if talkWidget == nil or printer == nil then
        return false
    end

    local widgetNames = {
        "RTB_TalkContent_Back_lua",
        "RTB_TalkContent_lua",
        "RTB_TalkContent2_Back_lua",
        "RTB_TalkContent2_lua",
        "RTB_TalkContent3_Back_lua",
        "RTB_TalkContent3_lua",
    }
    local widgets = {}
    local missing = {}
    for index, widgetName in ipairs(widgetNames) do
        widgets[index] = getNamedWidget(talkWidget, widgetName)
        if widgets[index] == nil then
            missing[#missing + 1] = widgetName
        end
    end

    local hasCoreRows = widgets[1] ~= nil and widgets[2] ~= nil
        and widgets[3] ~= nil and widgets[4] ~= nil
    local hasThirdLine = widgets[5] ~= nil and widgets[6] ~= nil
    self.__cpddDialogueHasThirdLine = hasThirdLine

    local ok = hasCoreRows and pcall(function()
        printer:BindWidget(
            widgets[1], widgets[2], widgets[3],
            widgets[4], widgets[5], widgets[6]
        )
        printer.LineMaxCharCount = DIALOGUE_LINE_MAX
        printer:SetEnableTwoLinePrinter(true)
    end)
    self.__cpddDialogueRowsBound = ok and VERSION or nil
    if #missing > 0 and self.__cpddDialogueWidgetLookupReported ~= VERSION then
        self.__cpddDialogueWidgetLookupReported = VERSION
        report("dialogue widget lookup missing " .. table.concat(missing, ","))
    elseif #missing == 0 and self.__cpddDialogueWidgetLookupReported ~= VERSION then
        self.__cpddDialogueWidgetLookupReported = VERSION
        report("dialogue third row bound from the live widget tree")
    end
    revealDialogueRows(self)
    return ok and hasThirdLine
end

local function configureDialogueLineCapacity(self, content)
    local printer = self and self.ContentPrinter
    if printer == nil then
        return DIALOGUE_LINE_MAX
    end
    local rows = self.__cpddDialogueHasThirdLine and 3 or 2
    local visibleLength = math.max(1, dialogueVisibleLength(content))
    -- Distribute the complete entry over the rows that are really available.
    -- This prevents the native printer from assigning an unbound third-row
    -- remainder, while retaining its foreground/shadow typewriter behavior.
    local lineCapacity = math.max(DIALOGUE_LINE_MAX, math.ceil(visibleLength / rows))
    printer.LineMaxCharCount = lineCapacity
    return lineCapacity
end

local function installDialogueTalkRepair(value, environment)
    local dialogueTalk = getSymbol(value, environment, "DialogueTalk")
    if type(dialogueTalk) ~= "table" or dialogueTalk.__cpddEnglishLayoutRepair == VERSION then
        return false
    end

    local originalInitUIData = dialogueTalk.InitUIData
    local originalShowContent = dialogueTalk.ShowContent
    if type(originalInitUIData) ~= "function" or type(originalShowContent) ~= "function" then
        return false
    end

    dialogueTalk.InitUIData = function(self, ...)
        local results = { originalInitUIData(self, ...) }
        if runtimeUIRepairEnabled() then
            -- InitUIData may replace the native printer or widget tree on a
            -- reused panel. Rebind once for the new UI, then let ShowContent
            -- reuse that binding for every dialogue entry.
            self.__cpddDialogueRowsBound = nil
            self.__cpddDialogueVisibleTextRepaired = nil
            bindDialogueRows(self)
        end
        return unpack(results)
    end

    dialogueTalk.ShowContent = function(self, content, ...)
        if not runtimeUIRepairEnabled() then
            return originalShowContent(self, content, ...)
        end
        if self.__cpddDialogueRowsBound ~= VERSION then
            bindDialogueRows(self)
        end
        local normalizedContent = normalizeDialogueWhitespace(content)
        self.__cpddDialogueWrappedContent = normalizedContent
        configureDialogueLineCapacity(self, normalizedContent)
        local results = { originalShowContent(self, normalizedContent, ...) }
        -- The Blueprint's BP_SetFontType call runs at the end of the original
        -- method and can refresh the outer row wrapper again on the next UI
        -- tick. Repair now, then use one coalesced retry burst after the
        -- Blueprint updates land.
        revealDialogueRows(self)
        scheduleRepairBurst(self, revealDialogueRows, 0.50)
        scheduleRepairAfter(self, 0.55, reportDialogueThirdRowState)
        if self.__cpddDialogueVisibleTextRepaired ~= VERSION then
            translateViewTextWidgets(self and self.view, self and self.userWidget)
            self.__cpddDialogueVisibleTextRepaired = VERSION
        end
        return unpack(results)
    end

    dialogueTalk.__cpddEnglishLayoutRepair = VERSION
    report("installed dynamic multi-row English dialogue layout")
    return true
end

local function setLayeredDialogueLabel(owner, text)
    if owner == nil then
        return false
    end

    local changed = false
    local ok = pcall(function()
        owner:SetText(text)
    end)
    changed = changed or ok

    for _, fieldName in ipairs({ "Text_lua", "Text2_lua" }) do
        local fieldOk = pcall(function()
            local widget = owner[fieldName]
            if widget ~= nil then
                widget:SetText(text)
                changed = true
            end
        end)
        changed = changed or fieldOk
    end

    -- These Blueprint components can contain additional nested labels. Run
    -- the normal bootstrap text pass as well so no other Chinese caption is
    -- left behind when the component refreshes.
    translateViewTextWidgets(nil, owner)
    return changed
end

runtimeFixes.setNamedWidgetText = function(owner, widgetName, text)
    if owner == nil then
        return false
    end

    local widget = getNamedWidget(owner, widgetName)
    if widget == nil then
        return false
    end

    local changed = false
    local setOk = pcall(function()
        widget:SetText(text)
    end)
    changed = changed or setOk

    -- Some cooked KGTextBlocks retain their serialized Text property after
    -- BP_SetType. Update both representations and synchronize the Slate copy.
    local propertyOk = pcall(function()
        widget.Text = text
    end)
    changed = changed or propertyOk
    pcall(function()
        if widget.SynchronizeProperties ~= nil then
            widget:SynchronizeProperties()
        end
    end)
    pcall(function()
        if widget.InvalidateLayoutAndVolatility ~= nil then
            widget:InvalidateLayoutAndVolatility()
        end
    end)
    return changed
end

runtimeFixes.setPanelWidgetText = function(self, widgetName, text)
    local changed = false
    local view = self and self.view
    if view ~= nil then
        local widget = getNamedWidget(view, widgetName)
        if widget ~= nil then
            changed = pcall(function()
                widget:SetText(text)
            end) or changed
        end
    end
    return runtimeFixes.setNamedWidgetText(
        self and (self.userWidget or self.widget), widgetName, text
    ) or changed
end

runtimeFixes.GuildEventPreviewMonths = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

runtimeFixes.formatGuildEventPreviewText = function(value)
    if type(value) ~= "string" then
        return value, false
    end

    local changed = false
    local display = value:gsub(
        " *Month%s+(%d%d?)%s+Day%s+(%d%d?)",
        function(monthValue, dayValue)
            local month = runtimeFixes.GuildEventPreviewMonths[tonumber(monthValue)]
            local day = tonumber(dayValue)
            if month == nil or day == nil or day < 1 or day > 31 then
                return " Month " .. monthValue .. " Day " .. dayValue
            end
            changed = true
            return "\n" .. month .. " " .. tostring(day)
        end,
        1
    )
    return display, changed
end

runtimeFixes.repairGuildEventPreviewTextWidget = function(widget)
    if widget == nil then
        return false
    end

    local current = nil
    pcall(function() current = tostring(widget:GetText()) end)
    local display, changed = runtimeFixes.formatGuildEventPreviewText(current)
    if not changed then
        return false
    end

    pcall(function() widget:SetText(display) end)
    pcall(function()
        -- The cooked list row is tall enough for two compact lines but not for
        -- the original full-size English sentence. Keep wrapping deterministic
        -- so recycling the item cannot produce a third clipped line.
        if widget.SetAutoWrapText ~= nil then widget:SetAutoWrapText(false) end
        if widget.SetRenderTransformPivot ~= nil then
            widget:SetRenderTransformPivot(sceneTextVector2D(0, 0.5))
        end
        if widget.SetRenderScale ~= nil then
            widget:SetRenderScale(sceneTextVector2D(0.66, 0.66))
        end
        if widget.InvalidateLayoutAndVolatility ~= nil then
            widget:InvalidateLayoutAndVolatility()
        end
    end)
    return true
end

runtimeFixes.repairGuildEventPreviewLayout = function(self)
    local widget = getNamedWidget(self and self.view, "RichText_Content")
        or getNamedWidget(self and (self.userWidget or self.widget), "RichText_Content")
    return runtimeFixes.repairGuildEventPreviewTextWidget(widget)
end

runtimeFixes.repairGuildEventPreviewTree = function(view, root)
    local repaired = 0
    local visited = setmetatable({}, { __mode = "k" })
    local function inspect(widget)
        if runtimeFixes.repairGuildEventPreviewTextWidget(widget) then
            repaired = repaired + 1
        end
    end
    if type(view) == "table" then
        for _, widget in pairs(view) do
            walkWidgetDescendants(widget, visited, inspect)
        end
        if type(view._widgetCache) == "table" then
            for _, widget in pairs(view._widgetCache) do
                walkWidgetDescendants(widget, visited, inspect)
            end
        end
    end
    walkWidgetDescendants(root, visited, inspect)
    if repaired > 0 and not runtimeFixes.GuildEventPreviewFallbackReported then
        runtimeFixes.GuildEventPreviewFallbackReported = true
        report("repaired Guild Event Preview through displayed-widget fallback")
    end
    return repaired
end

runtimeFixes.fitSequencePromotionConditionText = function(widget)
    if widget == nil then
        return false
    end

    local current = nil
    pcall(function() current = tostring(widget:GetText()) end)
    if type(current) ~= "string" or current == "" then
        return false
    end

    -- The original row is a single Chinese-height canvas with its progress
    -- value painted over the right edge. Keep that value untouched, but split
    -- the two long English sentence forms into balanced lines so neither can
    -- collide with it.
    local display = current:gsub(
        "^Acting level reached%s+(%d+)$",
        "Reach Acting Level %1",
        1
    )
    display = display:gsub(
        "^Fully digested%s+",
        "Fully digested\n",
        1
    )
    display = display:gsub(
        "^Collected all materials%s+for%s+the%s+",
        "Collected all\nmaterials for the ",
        1
    )
    if display ~= current then
        pcall(function() widget:SetText(display) end)
        pcall(function() widget.Text = display end)
    end

    -- Eighteen pixels allows two lines to remain inside the cooked entry
    -- height. An additional bounded scale handles unusually long pathway
    -- names without changing or truncating their translation.
    local font = nil
    pcall(function()
        if widget.GetFont ~= nil then
            font = widget:GetFont()
        else
            font = widget.Font
        end
    end)
    if font ~= nil then
        pcall(function()
            local currentSize = tonumber(font.Size) or 18
            font.Size = math.min(currentSize, 18)
            widget.Font = font
            if widget.SetFont ~= nil then widget:SetFont(font) end
        end)
    end

    local longestLine = 0
    for line in display:gmatch("[^\r\n]+") do
        local ok, length = pcall(function() return utf8.len(line) end)
        longestLine = math.max(longestLine, ok and length or #line)
    end
    local scale = math.max(0.78, math.min(1, 32 / math.max(1, longestLine)))
    pcall(function()
        if widget.SetAutoWrapText ~= nil then widget:SetAutoWrapText(false) end
        if widget.SetRenderTransformPivot ~= nil then
            widget:SetRenderTransformPivot(sceneTextVector2D(0, 0.5))
        end
        if widget.SetRenderScale ~= nil then
            widget:SetRenderScale(sceneTextVector2D(scale, scale))
        end
        if widget.SynchronizeProperties ~= nil then widget:SynchronizeProperties() end
        if widget.InvalidateLayoutAndVolatility ~= nil then
            widget:InvalidateLayoutAndVolatility()
        end
    end)
    return true
end

runtimeFixes.repairSequencePromotionConditionLayout = function(self)
    local widget = getNamedWidget(self and self.view, "Text_Condition")
        or getNamedWidget(self and (self.userWidget or self.widget), "Text_Condition")
    return runtimeFixes.fitSequencePromotionConditionText(widget)
end

runtimeFixes.fitSequencePromotionChangeText = function(widget)
    if widget == nil then
        return false
    end

    local current = nil
    pcall(function() current = tostring(widget:GetText()) end)
    if type(current) ~= "string" or current == "" then
        return false
    end
    local plain = current:gsub("<.->", ""):match("^%s*(.-)%s*$")
    local ok, length = pcall(function() return utf8.len(plain) end)
    length = ok and length or #plain

    -- This RichTextBlock gets its fonts from inline styles, so SetFont cannot
    -- resize it reliably. Scale only this label, from its left edge, using the
    -- cooked row's measured 21-character English budget.
    local scale = math.max(0.42, math.min(1, 21 / math.max(1, length)))
    pcall(function()
        if widget.SetAutoWrapText ~= nil then widget:SetAutoWrapText(false) end
        if widget.SetRenderTransformPivot ~= nil then
            widget:SetRenderTransformPivot(sceneTextVector2D(0, 0.5))
        end
        if widget.SetRenderScale ~= nil then
            widget:SetRenderScale(sceneTextVector2D(scale, scale))
        end
        if widget.InvalidateLayoutAndVolatility ~= nil then
            widget:InvalidateLayoutAndVolatility()
        end
    end)
    return true
end

runtimeFixes.repairSequencePromotionChangeLayout = function(self)
    local widget = getNamedWidget(self and self.view, "Text_Change")
        or getNamedWidget(self and (self.userWidget or self.widget), "Text_Change")
    return runtimeFixes.fitSequencePromotionChangeText(widget)
end

runtimeFixes.repairSequencePromotionPanelButtons = function(self)
    local button = self and self.WBP_ConditionBtnCom
    local widget = getNamedWidget(button and button.view, "Text_Name")
        or getNamedWidget(button and (button.userWidget or button.widget), "Text_Name")
    if widget == nil then
        return false
    end

    local font = nil
    pcall(function()
        if widget.GetFont ~= nil then
            font = widget:GetFont()
        else
            font = widget.Font
        end
    end)
    if font == nil then
        return false
    end
    local changed = pcall(function()
        local currentSize = tonumber(font.Size) or 18
        font.Size = math.min(currentSize, 18)
        widget.Font = font
        if widget.SetFont ~= nil then widget:SetFont(font) end
        if widget.SynchronizeProperties ~= nil then widget:SynchronizeProperties() end
        if widget.InvalidateLayoutAndVolatility ~= nil then
            widget:InvalidateLayoutAndVolatility()
        end
    end)
    return changed
end

runtimeFixes.translateNamedContainers = function(view, root, names)
    local repaired = 0
    local seen = setmetatable({}, { __mode = "k" })
    for _, name in ipairs(names) do
        local container = getNamedWidget(view, name) or getNamedWidget(root, name)
        if container ~= nil and not seen[container] then
            seen[container] = true
            repaired = repaired + translateViewTextWidgets(nil, container)
        end
    end
    return repaired
end

runtimeFixes.repairSkillHeaderWidget = function(widget)
    if widget == nil then
        return false
    end
    local changed = false
    changed = runtimeFixes.setNamedWidgetText(widget, "Text_Recommend", "Recommended Builds") or changed
    changed = runtimeFixes.setNamedWidgetText(widget, "Text_Extra", "My Builds") or changed
    changed = runtimeFixes.setNamedWidgetText(widget, "Text_BeStrong", "Improve") or changed
    -- Launch 1.1 also registers the recommended caption under its cooked
    -- Blueprint name instead of the generated Lua alias.
    changed = runtimeFixes.setNamedWidgetText(widget, "KGTextBlock_54", "Recommended Builds") or changed
    runtimeFixes.translateNamedContainers(nil, widget, {
        "Canvas_BeStrong", "Canvas_Extraordinarily", "Canvas_Recommend", "HB_Btn",
    })
    translateViewTextWidgets(nil, widget)
    return changed
end

runtimeFixes.skillImproveRepairLogged = false

runtimeFixes.reportSkillImproveRepair = function(self)
    if runtimeFixes.skillImproveRepairLogged then
        return
    end
    runtimeFixes.skillImproveRepairLogged = true

    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    local widget = getNamedWidget(view, "Text_BeStrong")
        or getNamedWidget(root, "Text_BeStrong")
    if widget == nil then
        local visited = setmetatable({}, { __mode = "k" })
        local function inspect(candidate)
            walkWidgetDescendants(candidate, visited, function(descendant)
                if widget ~= nil then
                    return
                end
                local ok, value = pcall(function()
                    return tostring(descendant:GetText())
                end)
                if ok and (value == "Improve" or value == "我要变强" or value == "要变强") then
                    widget = descendant
                end
            end)
        end
        inspect(getNamedWidget(view, "Canvas_BeStrong"))
        inspect(getNamedWidget(root, "Canvas_BeStrong"))
        if type(view) == "table" then
            for _, candidate in pairs(view) do
                inspect(candidate)
            end
        end
    end
    local value = "<not found>"
    if widget ~= nil then
        value = "<unreadable>"
        pcall(function()
            value = tostring(widget:GetText())
        end)
    end
    report("Improve caption verification found=" .. tostring(widget ~= nil) .. " value=" .. tostring(value))
end

runtimeFixes.repairSkillHeaderLabels = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    runtimeFixes.setPanelWidgetText(self, "Text_Recommend", "Recommended Builds")
    runtimeFixes.setPanelWidgetText(self, "Text_Extra", "My Builds")
    runtimeFixes.setPanelWidgetText(self, "Text_BeStrong", "Improve")
    runtimeFixes.translateNamedContainers(view, root, {
        "Canvas_BeStrong", "Canvas_Extraordinarily", "Canvas_Recommend", "HB_Btn",
    })
    translateViewTextWidgets(view, root)
    runtimeFixes.repairSkillHeaderWidget(root)
    scheduleRepairAfter(self, 3.00, runtimeFixes.reportSkillImproveRepair)
end

runtimeFixes.repairEmbeddedSkillHeaderLabels = function(self)
    if self == nil then
        return
    end
    local view = self.view
    local root = self.userWidget or self.widget
    local header = getNamedWidget(view, "WBP_Skill_BeStrong_Btn")
        or getNamedWidget(view, "WBP_Skill_BeStrong_Btn_lua")
        or getNamedWidget(root, "WBP_Skill_BeStrong_Btn")
        or getNamedWidget(root, "WBP_Skill_BeStrong_Btn_lua")
    runtimeFixes.translateNamedContainers(view, header or root, {
        "Canvas_BeStrong", "Canvas_Extraordinarily", "Canvas_Recommend", "HB_Btn",
    })
    runtimeFixes.repairSkillHeaderWidget(header)
end

runtimeFixes.repairDynamicPanelLabels = function(self)
    if self == nil then
        return
    end
    translateViewTextWidgets(self.view, self.userWidget or self.widget)
end

runtimeFixes.repairSkillCommonLabels = function(self)
    local view = self and self.view
    if view == nil then
        return
    end

    -- These two footer labels belong to the parent panel, not to the
    -- Skill_BeStrong_Btn component.
    runtimeFixes.setNamedWidgetText(view, "Text_WoodenPost", "Training Dummy")
    local oneClickPage = nil
    pcall(function()
        oneClickPage = view.WBP_Skill_OneClick_Page
    end)
    runtimeFixes.setNamedWidgetText(oneClickPage, "Text_Content", "One-Click Assist")

    -- BP_SetType on the embedded header can refresh all three captions after
    -- its Lua component returns. Repair the nested UserWidget from the parent
    -- as the final owner as well as through the component hook.
    runtimeFixes.repairEmbeddedSkillHeaderLabels(self)
    runtimeFixes.repairSkillHeaderLabels(self and self.WBP_Skill_BeStrong_BtnCom)
end

runtimeFixes.repairTalentLabels = function(self)
    runtimeFixes.setPanelWidgetText(self, "Text_Reset", "Reset All")
    runtimeFixes.repairEmbeddedSkillHeaderLabels(self)
end

runtimeFixes.repairEquipmentLabels = function(self)
    runtimeFixes.setPanelWidgetText(self, "Text_Equip", "Equipment Builds")
end

runtimeFixes.repairEquipmentReformUnlockText = function(self)
    local view = self and self.view
    local widget = getNamedWidget(view, "Text_LevelTips")
    if widget == nil then
        return false
    end

    local current = nil
    pcall(function()
        current = tostring(widget:GetText())
    end)
    if type(current) ~= "string" or current == "" then
        return false
    end

    -- CheckConfigLocked can supply either the static English StringDB value or
    -- the runtime override. Normalize both paths after the native page refresh
    -- and retain a manual break rather than relying on width-sensitive wrapping.
    local wrapped, replacements = current:gsub(
        "Affix inheritance is available%.%s*Remolding",
        "Affix inheritance is available.\nRemolding",
        1
    )
    if replacements == 0 then
        return false
    end

    pcall(function()
        if widget.SetAutoWrapText ~= nil then
            widget:SetAutoWrapText(false)
        end
    end)
    return runtimeFixes.setNamedWidgetText(view, "Text_LevelTips", wrapped)
end

runtimeFixes.repairBagLabels = function(self)
    local autoDecomposeButton = self and self.view and self.view.AutoDecomposeBtn
    runtimeFixes.setNamedWidgetText(autoDecomposeButton, "TB_Word", "Auto-Dismantle")
end

runtimeFixes.repairSchemePlanItemLabels = function(self)
    runtimeFixes.setPanelWidgetText(self, "Text_Tips", "In Use")
end

runtimeFixes.repairSchemeUseLabels = function(self)
    runtimeFixes.setPanelWidgetText(self, "Text_BtnName", "Use")
    runtimeFixes.setPanelWidgetText(self, "Text_Tips", "In Use")
    runtimeFixes.setPanelWidgetText(self, "Text_Use", "Use")
    runtimeFixes.setPanelWidgetText(self, "Text_Using", "In Use")
end

runtimeFixes.repairScreenshotLabel = function(self)
    runtimeFixes.setPanelWidgetText(self, "Text_Name", "Screenshot")
end

runtimeFixes.repairLoginActivityLabels = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    runtimeFixes.setPanelWidgetText(self, "Text_FashionTitleDec_1", "Reward Preview")
    runtimeFixes.translateNamedContainers(view, root, {
        "Canvas_Reward", "Canvas_Title", "VB_MainTitle",
    })
    translateViewTextWidgets(view, root)
end

runtimeFixes.repairItemReceivedLabels = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    runtimeFixes.setPanelWidgetText(self, "text_center_lua", "Claimed")
    runtimeFixes.translateNamedContainers(view, root, { "Canvas_Received" })
    translateViewTextWidgets(view, root)
end

runtimeFixes.repairClaimedRewardLabel = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    -- Train Trade and Weekly Orders use this authored label only for the
    -- rewarded state; their Blueprint controls its visibility separately.
    runtimeFixes.setPanelWidgetText(self, "Text_Get", "Claimed")
    translateViewTextWidgets(view, root)
end

runtimeFixes.repairGvgRewardStatusLabel = function(self)
    -- Text_None can also show other GvG status messages, so translate the
    -- value selected by OnRefresh instead of forcing every state to Claimed.
    translateViewTextWidgets(
        self and self.view,
        self and (self.userWidget or self.widget)
    )
end

runtimeFixes.repairLegacyItemSmallLabels = function(self)
    if self == nil then
        return 0
    end

    -- WBP_ItemSmall's claimed badge is the non-generated Blueprint widget
    -- Tag_Receive. It is absent from ItemSmall.view and generic traversal in
    -- the shipping build, but remains directly addressable on the UserWidget.
    local repaired = 0
    local function repairOwner(owner)
        if runtimeFixes.setNamedWidgetText(owner, "Tag_Receive", "Claimed") then
            repaired = repaired + 1
        end
    end
    repairOwner(self.view)
    repairOwner(self.userWidget)
    repairOwner(self.widget)
    repaired = repaired + (translateViewTextWidgets(
        self.view,
        self.userWidget or self.widget
    ) or 0)
    return repaired
end

runtimeFixes.repairWorldBossClaimedLabel = function(self)
    if self == nil then
        return
    end
    -- WorldBoss_Award_Widget_Item calls WBP_ItemSmall:SetGet after FillItem,
    -- repainting the baked Chinese badge after ItemSmall's own refresh has
    -- completed. Repair the nested component after that final state update.
    local repaired = runtimeFixes.repairLegacyItemSmallLabels(self.WBP_ItemSmallCom)
    repaired = repaired + (translateViewTextWidgets(
        self.view,
        self.userWidget or self.widget
    ) or 0)
    if self.claimed == true and self.__cpddClaimedBadgeReport ~= VERSION then
        self.__cpddClaimedBadgeReport = VERSION
        report("World Boss claimed badge repair labels=" .. tostring(repaired))
    end
end

runtimeFixes.repairDiceResultLabels = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    runtimeFixes.translateNamedContainers(view, root, {
        "Canvas_ResultRoot", "Canvas_Content", "Canvas_GUI",
        "Canvas_SuccessText", "Canvas_BigSuccessText",
    })
    translateViewTextWidgets(view, root)
end

runtimeFixes.repairSkillUpgradeTipsLabels = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    runtimeFixes.setPanelWidgetText(self, "Text_Title_2", "Next-Level Effect")
    runtimeFixes.translateNamedContainers(view, root, {
        "VB_Content", "SizeBox_Content", "ScrollBox_Content",
    })
    translateViewTextWidgets(view, root)
end

runtimeFixes.repairSecretPartnerLabels = function(self)
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    runtimeFixes.translateNamedContainers(view, root, {
        "PanelSlot", "Canvas_BaseAttribute", "Canvas_Content", "Canvas_Main",
    })
    translateViewTextWidgets(view, root)
end

runtimeFixes.lastHuntLabelVerificationLogged = false

runtimeFixes.repairLastHuntMyDataLabels = function(self)
    runtimeFixes.setPanelWidgetText(self, "Text_Debris01", "Submit to earn Hunt Progress")
    runtimeFixes.setPanelWidgetText(self, "Text_Debris01_1", "Submit to earn Hunt Progress")
    runtimeFixes.setPanelWidgetText(self, "Text_Schedule", "Current Progress:")
    runtimeFixes.setPanelWidgetText(self, "Text_Title01", "Kills")
    runtimeFixes.setPanelWidgetText(self, "Text_Title02", "Assists")
    runtimeFixes.setPanelWidgetText(self, "Text_Rank", "Leaderboard")
    local view = self and self.view
    local root = self and (self.userWidget or self.widget)
    local containerNames = {
        "Canvas_MyData", "Canvas_Record", "Canvas_Task", "Canvas_RankBtn",
        "HB_MyData", "HB_Schedule", "HB_Task", "VB_MyData", "VB_Task",
        "VB_Tetx01", "VB_Tetx02", "VB_Tetx03",
    }
    runtimeFixes.translateNamedContainers(view, root, containerNames)
    translateViewTextWidgets(view, root)

    if not runtimeFixes.lastHuntLabelVerificationLogged then
        local expected = {
            ["Submit to earn Hunt Progress"] = true,
            ["Current Progress:"] = true,
            ["Kills"] = true,
            ["Assists"] = true,
            ["Leaderboard"] = true,
        }
        local observed = {}
        local unresolved = 0
        local visited = setmetatable({}, { __mode = "k" })
        local function inspect(widget)
            local ok, text = pcall(function()
                return tostring(widget:GetText())
            end)
            if not ok then
                return
            end
            if expected[text] then
                observed[text] = true
            elseif hasCjk and hasCjk(text) then
                unresolved = unresolved + 1
            end
        end
        for _, name in ipairs(containerNames) do
            walkWidgetDescendants(getNamedWidget(view, name) or getNamedWidget(root, name), visited, inspect)
        end
        local englishCount = 0
        for _ in pairs(observed) do
            englishCount = englishCount + 1
        end
        if englishCount == 5 then
            runtimeFixes.lastHuntLabelVerificationLogged = true
            report("Last Hunt painted-caption verification english=5 unresolvedChinese=" .. tostring(unresolved))
        end
    end
end

runtimeFixes.formatGroupedInteger = function(value)
    local number = tonumber(value)
    if number == nil then
        return tostring(value or "")
    end
    number = math.floor(number + 0.5)
    local sign = number < 0 and "-" or ""
    local grouped = tostring(math.abs(number))
    while true do
        local nextValue, replacements = grouped:gsub("^(%d+)(%d%d%d)", "%1,%2")
        grouped = nextValue
        if replacements == 0 then
            break
        end
    end
    return sign .. grouped
end

runtimeFixes.installLastHuntScoreFormatting = function(value, environment)
    local class = getSymbol(value, environment, "PVPLastHunt_Details_MyData")
    if type(class) ~= "table" or class.__cpddFullScoreFormatting == VERSION then
        return false
    end
    if type(class.FormatScoreTip) ~= "function" then
        return false
    end

    class.FormatScoreTip = function(_, number)
        return runtimeFixes.formatGroupedInteger(number)
    end
    class.__cpddFullScoreFormatting = VERSION
    report("installed full-number Last Hunt score formatting")
    return true
end

runtimeFixes.installCurrencyFormatting = function(value, environment)
    local class = getSymbol(value, environment, "CurrencyUtils")
    local function installTarget(target)
        if target == nil then
            return false
        end
        local readable, current = pcall(function()
            return target.GetGameMoneyFormat
        end)
        if not readable or type(current) ~= "function"
            or current == runtimeFixes.formatGameMoney
        then
            return false
        end
        return pcall(function()
            target.GetGameMoneyFormat = runtimeFixes.formatGameMoney
        end)
    end

    local moduleInstalled = installTarget(class)
    if type(class) == "table" then
        class.__cpddFullCurrencyFormatting = VERSION
    end

    -- Shops Exchange retains a pre-created Game.CurrencyUtils singleton. It
    -- can therefore keep the native TEN_THOUSAND formatter even after the
    -- module export has been replaced. Patch both objects independently.
    local liveCurrency = Game and Game.CurrencyUtils
    local liveInstalled = installTarget(liveCurrency)
    if type(liveCurrency) == "table" then
        liveCurrency.__cpddFullCurrencyFormatting = VERSION
    end

    if moduleInstalled or liveInstalled then
        report("installed full-number shared currency formatting"
            .. " module=" .. tostring(moduleInstalled)
            .. " live=" .. tostring(liveInstalled))
    end
    return moduleInstalled or liveInstalled
end

-- Preserve the original numeric return type below its abbreviation threshold.
-- Above it, return the complete grouped value instead of a locale suffix such
-- as "12.5Ten Thousand".
runtimeFixes.formatGameMoney = function(number)
        assert(type(number) == "number", "Num not a number")
        if number < 100000 then
            return number
        end
        local formatted = runtimeFixes.formatGroupedInteger(number)
        if runtimeFixes.CurrencyFormattingVerificationReported ~= true then
            runtimeFixes.CurrencyFormattingVerificationReported = true
            report("shared currency formatting verification output=" .. formatted)
        end
        return formatted
end

runtimeFixes.installExchangeStallPriceFormatting = function(value, environment)
    local class = getSymbol(value, environment, "Shops_StallContent_Item")
    if type(class) ~= "table" or class.__cpddFullExchangePriceFormatting == VERSION then
        return false
    end
    if type(class.formatPrice) ~= "function" then
        return false
    end

    -- Stall cards route every regular, market-instance, and lowest-price label
    -- through this method, making it the narrowest reliable display fix.
    class.formatPrice = function(_, number)
        return runtimeFixes.formatGameMoney(number)
    end
    class.__cpddFullExchangePriceFormatting = VERSION
    report("installed full-number Shops Exchange stall price formatting")
    return true
end

runtimeFixes.installExchangeAuctionPriceFormatting = function(value, environment)
    local class = getSymbol(value, environment, "Shops_AuctionContent_Item")
    if type(class) ~= "table" or class.__cpddFullExchangePriceFormatting == VERSION then
        return false
    end
    local originalRefresh = class.refreshAuctionItemInfo
    if type(originalRefresh) ~= "function" then
        return false
    end

    class.refreshAuctionItemInfo = function(self, ...)
        local result = originalRefresh(self, ...)
        -- Repaint from the raw bid price after the native method. This protects
        -- auction cards even when their cached CurrencyUtils reference cannot
        -- be reassigned by the shipping Lua bridge.
        pcall(function()
            local data = self and self._auctionItemData
            local price = data and data.CurrentBidPrice
            local label = self and self.view and self.view.Text_MoneyOne
            if type(price) == "number" and label ~= nil then
                label:SetText(runtimeFixes.formatGameMoney(price))
            end
        end)
        return result
    end
    class.__cpddFullExchangePriceFormatting = VERSION
    report("installed full-number Shops Exchange auction price formatting")
    return true
end

runtimeFixes.installExchangeFashionPriceFormatting = function(
    value, environment, symbolName, labelName, reportName
)
    local class = getSymbol(value, environment, symbolName)
    if type(class) ~= "table" or class.__cpddFullExchangePriceFormatting == VERSION then
        return false
    end
    local originalRefresh = class.OnRefresh
    if type(originalRefresh) ~= "function" then
        return false
    end

    class.OnRefresh = function(self, data, ...)
        local result = originalRefresh(self, data, ...)
        -- Fashion/display cards bypass the standard stall formatter. Repaint
        -- their exact price label from the unformatted exchange row.
        pcall(function()
            local price = data and data.Price
            local label = self and self.view and self.view[labelName]
            if type(price) == "number" and label ~= nil then
                label:SetText(runtimeFixes.formatGameMoney(price))
            end
        end)
        return result
    end
    class.__cpddFullExchangePriceFormatting = VERSION
    report("installed full-number Shops Exchange " .. reportName .. " price formatting")
    return true
end

runtimeFixes.installExchangeStallFashionPriceFormatting = function(value, environment)
    return runtimeFixes.installExchangeFashionPriceFormatting(
        value,
        environment,
        "Shops_StallFashion_Item",
        "Text_MoneyNumber_1",
        "stall-fashion"
    )
end

runtimeFixes.installExchangeSaleFashionPriceFormatting = function(value, environment)
    return runtimeFixes.installExchangeFashionPriceFormatting(
        value,
        environment,
        "Shops_SaleFashion_Item",
        "Text_Possess",
        "sale-fashion"
    )
end

runtimeFixes.installCachedExchangePriceFormatting = function()
    local privateRequire = rawget(_G, "kg_require")
    if type(privateRequire) ~= "function" then
        return 0
    end

    -- C7's kg_require cache is separate from package.loaded. Exchange classes
    -- are initialized before runtime mods, so recover their module tables from
    -- the authoritative cache and patch the already-live class objects.
    local specs = {
        {
            "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_StallContent_Item",
            runtimeFixes.installExchangeStallPriceFormatting,
        },
        {
            "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_AuctionContent_Item",
            runtimeFixes.installExchangeAuctionPriceFormatting,
        },
        {
            "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_StallFashion_Item",
            runtimeFixes.installExchangeStallFashionPriceFormatting,
        },
        {
            "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_SaleFashion_Item",
            runtimeFixes.installExchangeSaleFashionPriceFormatting,
        },
    }
    local installed = 0
    for _, spec in ipairs(specs) do
        local ok, module = pcall(privateRequire, spec[1])
        if ok and spec[2](module, nil) then
            installed = installed + 1
        end
    end
    report("recovered cached Shops Exchange formatters=" .. tostring(installed))
    return installed
end

runtimeFixes.installBattleStatisticsFormatting = function(value, environment)
    local class = getSymbol(value, environment, "DungeonBattleStatisticsSystem")
    if type(class) ~= "table" or class.__cpddFullBattleStatisticsFormatting == VERSION then
        return false
    end
    if type(class.GetFormatNumberString) ~= "function" then
        return false
    end

    -- The DPS meter has a separate formatter from CurrencyUtils. Its original
    -- implementation appends localized TEN_THOUSAND/AHUNDREDMILLION suffixes,
    -- which renders as literal English words after localization. Preserve its
    -- round-up behavior but always display the complete grouped value.
    class.GetFormatNumberString = function(_, number)
        number = tonumber(number) or 0
        return runtimeFixes.formatGroupedInteger(math.ceil(number))
    end
    class.__cpddFullBattleStatisticsFormatting = VERSION
    report("installed full-number DPS/statistics formatting")
    return true
end

runtimeMetrics.InstallPvpStatisticsFormatting = function(value, environment)
    local class = getSymbol(value, environment, "PVP_Stats_Item")
    if type(class) ~= "table" or class.__cpddFullPvpStatisticsFormatting == VERSION then
        return false
    end

    local originalSetAs6V6 = class.SetAs6V6
    local originalSetAs12V12 = class.SetAs12V12
    local originalSetAsChampion = class.SetAsChampion
    if type(originalSetAs6V6) ~= "function"
        and type(originalSetAs12V12) ~= "function"
        and type(originalSetAsChampion) ~= "function"
    then
        return false
    end

    -- Several PVP result screens share this row class. The 12v12 and champion
    -- paths abbreviate values above 10,000 with TEN_THOUSAND, and some 6v6
    -- result/history layouts fall through to the champion path. Re-render all
    -- three row variants from their raw data so every mode receives exact,
    -- grouped integers while retaining its layout and best-stat highlights.
    local function refreshStatisticCells(self, data, maxData, gameMode, compactLayout)
        if type(data) ~= "table" or type(self.StatsDataComponents) ~= "table" then
            return false
        end

        local pvpSystem = Game and Game.PVPSystem
        local model = pvpSystem and pvpSystem.model
        local keys = model and model.tabKeys and model.tabKeys[gameMode]
        if type(keys) ~= "table" then
            return false
        end

        for componentIndex, component in pairs(self.StatsDataComponents) do
            local componentKeys = keys[componentIndex]
            if type(componentKeys) == "table" and type(component) == "table"
                and type(component.Refresh) == "function"
            then
                local infoText = {}
                for _, key in pairs(componentKeys) do
                    local sourceValue = data[key]
                    local rawValue = tonumber(sourceValue)
                    local valueText = rawValue ~= nil
                        and runtimeFixes.formatGroupedInteger(rawValue)
                        or tostring(sourceValue or 0)
                    local isHigh = type(maxData) == "table"
                        and rawValue ~= nil
                        and tonumber(maxData[key]) == rawValue
                        and rawValue ~= 0
                    if isHigh then
                        valueText = string.format("<PVP_Data_Highlight>%s</>", valueText)
                    end
                    table.insert(infoText, valueText)
                end
                component:Refresh(
                    table.concat(infoText, "/", 1, #infoText),
                    compactLayout == true
                )
            end
        end

        return true
    end

    local pvpModes = Enum and Enum.EPVPGameModeData
    local installedMethods = 0
    local verifiedPaths = {}

    local function reportApplied(path, applied)
        if applied and not verifiedPaths[path] then
            verifiedPaths[path] = true
            report("PVP scoreboard number formatting applied path=" .. path)
        end
    end

    if type(originalSetAs6V6) == "function" then
        class.SetAs6V6 = function(self, data)
            local result = originalSetAs6V6(self, data)
            reportApplied(
                "6v6",
                refreshStatisticCells(
                    self, data, nil, pvpModes and pvpModes.TEAM6V6, true
                )
            )
            return result
        end
        installedMethods = installedMethods + 1
    end

    if type(originalSetAs12V12) == "function" then
        class.SetAs12V12 = function(self, data, index, maxData, maxIndex, bOtherSide, bEndGameStats)
            local result = originalSetAs12V12(
                self, data, index, maxData, maxIndex, bOtherSide, bEndGameStats
            )
            local gameMode = self.otherInfo and self.otherInfo.Mode
                or (pvpModes and pvpModes.TEAM12V12)
            reportApplied(
                "12v12",
                refreshStatisticCells(self, data, maxData, gameMode, false)
            )
            return result
        end
        installedMethods = installedMethods + 1
    end

    if type(originalSetAsChampion) == "function" then
        class.SetAsChampion = function(self, data, index, maxData, maxIndex, bOtherSide, bEndGameStats)
            local result = originalSetAsChampion(
                self, data, index, maxData, maxIndex, bOtherSide, bEndGameStats
            )
            reportApplied(
                "fallback",
                refreshStatisticCells(
                    self, data, maxData,
                    pvpModes and pvpModes.CHAMPION_GROUP_BATTLE, false
                )
            )
            return result
        end
        installedMethods = installedMethods + 1
    end

    class.__cpddFullPvpStatisticsFormatting = VERSION
    report(
        "installed full-number PVP scoreboard formatting methods="
        .. tostring(installedMethods)
    )
    return true
end

local function repairDialoguePanelLabels(self)
    local view = self and self.view
    if type(view) ~= "table" then
        return
    end

    setLayeredDialogueLabel(view.WBP_NPCReviewBtn, "Review")

    local skipOwner = view.WBP_Skip
    if skipOwner ~= nil then
        local ok, nested = pcall(function()
            return skipOwner.WBP_NPCBtnText_lua
        end)
        setLayeredDialogueLabel(ok and nested or skipOwner, "Skip")
    end
end

local function repairDialogueSkipLabels(self)
    local view = self and self.view
    if type(view) ~= "table" then
        return
    end
    setLayeredDialogueLabel(view.WBP_NPCBtnText_lua, "Skip")
end

local function installDialogueControlRepair(value, environment, symbolName, methodNames, repair, source)
    local class = getSymbol(value, environment, symbolName)
    if type(class) ~= "table" then
        return false
    end

    local marker = "__cpddDialogueControlRepair_" .. VERSION
    if class[marker] then
        return true
    end

    local wrapped = 0
    for _, methodName in ipairs(methodNames) do
        local original = class[methodName]
        if type(original) == "function" then
            class[methodName] = function(self, ...)
                local results = { original(self, ...) }
                if runtimeUIRepairEnabled() then
                    repair(self)
                    scheduleRepairBurst(self, repair, 0.10)
                end
                return unpack(results)
            end
            wrapped = wrapped + 1
        end
    end

    class[marker] = true
    if wrapped > 0 then
        report("installed exact English dialogue controls for " .. source)
    end
    return wrapped > 0
end

local function installExactWidgetRepair(value, environment, symbolName, methodNames, repair, source, repeatRepair)
    local class = getSymbol(value, environment, symbolName)
    if type(class) ~= "table" then
        return false
    end

    local marker = "__cpddExactWidgetRepair_" .. VERSION
    if class[marker] then
        return true
    end

    local wrapped = 0
    local repairErrorReported = false
    local repairedInstances = setmetatable({}, { __mode = "k" })
    for _, methodName in ipairs(methodNames) do
        local original = class[methodName]
        if type(original) == "function" then
            -- true repeats after every wrapped method; a table repeats only
            -- after callbacks that can repaint an already-repaired widget.
            local repeatAfterMethod = repeatRepair == true
                or (type(repeatRepair) == "table" and repeatRepair[methodName] == true)
            class[methodName] = function(self, ...)
                local results = { original(self, ...) }
                if runtimeUIRepairEnabled() and (repeatAfterMethod or not repairedInstances[self]) then
                    if not repeatAfterMethod then
                        repairedInstances[self] = true
                    end
                    local ok, err = pcall(repair, self)
                    if not ok and not repairErrorReported then
                        repairErrorReported = true
                        report("exact widget repair failed safely for " .. tostring(source)
                            .. ": " .. tostring(err))
                    end
                end
                return unpack(results)
            end
            wrapped = wrapped + 1
        end
    end

    class[marker] = true
    if wrapped > 0 then
        report("installed exact English widget labels for " .. source)
    end
    return wrapped > 0
end

-- These player-detail tables resolve their localized captions while the data
-- module is first loaded. Correcting GetLangStr later therefore does not update
-- the cached rows. Repair both the cached tables and the final list-item input,
-- using the stable config IDs so the legitimate top Armor Break is untouched.
runtimeFixes.PlayerDetailAttributeLabels = {
    [21] = "Armor Break",
    [37] = "Defense Break",
    [38] = "Physical Defense Break",
    [40] = "Magic Defense Break",
}

function runtimeFixes.repairPlayerDetailConfig(config)
    local configType = type(config)
    if configType ~= "table" and configType ~= "userdata" then
        return false
    end

    local id = nil
    local current = nil
    pcall(function()
        id = config.ID
        current = config.ShowPropertyName
    end)
    local label = runtimeFixes.PlayerDetailAttributeLabels[tonumber(id)]
    if label == nil or current == label then
        return false
    end
    return pcall(function()
        config.ShowPropertyName = label
    end)
end

function runtimeFixes.repairPlayerDetailRowData(data)
    local dataType = type(data)
    if dataType ~= "table" and dataType ~= "userdata" then
        return false
    end
    local config = nil
    pcall(function() config = data.config end)
    return runtimeFixes.repairPlayerDetailConfig(config or data)
end

function runtimeFixes.isDefenseBreakGroupData(data)
    local dataType = type(data)
    if dataType ~= "table" and dataType ~= "userdata" then
        return false
    end

    local config = nil
    local childData = nil
    pcall(function()
        config = data.config
        childData = data.childData
    end)
    config = config or data

    local id = nil
    local tipsId = nil
    pcall(function()
        id = config.ID
        tipsId = config.TipsID
    end)
    if tonumber(id) == 37 or tonumber(tipsId) == 6421037 then
        return true
    end

    if type(childData) ~= "table" then
        return false
    end
    for _, child in pairs(childData) do
        local childConfig = nil
        local childLabel = nil
        pcall(function()
            childConfig = child.config or child
            childLabel = childConfig.ShowPropertyName
        end)
        if childLabel == "Physical Defense Break" or childLabel == "Magic Defense Break" then
            return true
        end
    end
    return false
end

function runtimeFixes.repairPlayerDetailTable(value)
    local rows = type(value) == "table" and (value.data or value) or nil
    if type(rows) ~= "table" then
        return value
    end
    for _, config in pairs(rows) do
        runtimeFixes.repairPlayerDetailConfig(config)
    end
    return value
end

runtimeFixes.FightPropertyLabels = {
    ShieldBreak = "Armor Break",
    pDefReduce = "Physical Defense Break",
    mDefReduce = "Magic Defense Break",
}

function runtimeFixes.repairFightPropertyConfig(config)
    local configType = type(config)
    if configType ~= "table" and configType ~= "userdata" then
        return false
    end
    local prop = nil
    local current = nil
    pcall(function()
        prop = config.Prop
        current = config.PropName
    end)
    local label = runtimeFixes.FightPropertyLabels[prop]
    if label == nil or current == label then
        return false
    end
    return pcall(function() config.PropName = label end)
end

function runtimeFixes.repairFightPropertyTable(value)
    local rows = type(value) == "table" and (value.data or value) or nil
    if type(rows) ~= "table" then
        return value
    end
    for _, config in pairs(rows) do
        runtimeFixes.repairFightPropertyConfig(config)
    end
    return value
end

runtimeFixes.DefenseBreakTipLabels = {
    [6421037] = "Defense Break",
    [6421038] = "Physical Defense Break",
    [6421040] = "Magic Defense Break",
}

function runtimeFixes.repairDefenseBreakTipText(value)
    if type(value) ~= "string" then
        return value
    end
    value = value:gsub("Physical Armor Penetration", "Physical Defense Break")
    value = value:gsub("Magic Armor Penetration", "Magic Defense Break")
    value = value:gsub("Physical Armor Break", "Physical Defense Break")
    value = value:gsub("Magic Armor Break", "Magic Defense Break")
    value = value:gsub("Armor Penetration", "Defense Break")
    value = value:gsub("Armor Break", "Defense Break")
    return value
end

function runtimeFixes.repairDefenseBreakTipsTable(value)
    local rows = type(value) == "table" and (value.data or value) or nil
    if type(rows) ~= "table" then
        return value
    end
    for key, row in pairs(rows) do
        runtimeFixes.repairDefenseBreakTipsRow(row, key)
    end
    return value
end

function runtimeFixes.repairDefenseBreakTipsRow(row, fallbackId)
    local rowType = type(row)
    if rowType ~= "table" and rowType ~= "userdata" then
        return false
    end
    local rowId = nil
    local descriptions = nil
    pcall(function()
        rowId = row.Id
        descriptions = row.Description1
    end)
    local label = runtimeFixes.DefenseBreakTipLabels[tonumber(rowId or fallbackId)]
    if label == nil then
        return false
    end
    local changed = pcall(function() row.SubTitle1 = label end)
    if type(descriptions) == "table" then
        for index, description in pairs(descriptions) do
            descriptions[index] = runtimeFixes.repairDefenseBreakTipText(description)
        end
    end
    return changed
end

function runtimeFixes.installPlayerDetailRowRepair(value, environment, symbolName, source)
    local class = getSymbol(value, environment, symbolName)
    if type(class) ~= "table" or class.__cpddPlayerDetailLabels == VERSION then
        return type(class) == "table"
    end

    local original = class.OnRefresh
    if type(original) ~= "function" then
        return false
    end
    class.OnRefresh = function(self, data, ...)
        runtimeFixes.repairPlayerDetailRowData(data)
        local results = { original(self, data, ...) }
        -- The aggregate caption is painted by the expandable row and can retain
        -- its serialized English text even after the backing config is repaired.
        -- Repaint only the Defense Break group; the standalone Armor Break row
        -- uses the normal-row widget and is deliberately left untouched.
        if symbolName == "PlayerDetails_List_Drop_Item"
            and runtimeFixes.isDefenseBreakGroupData(data)
        then
            runtimeFixes.setNamedWidgetText(self and self.view, "Text_Title", "Defense Break")
        end
        return unpack(results)
    end
    class.__cpddPlayerDetailLabels = VERSION
    report("installed exact player-detail attribute labels for " .. source)
    return true
end

function runtimeFixes.repairPlayerDetailGroupData(groupData)
    if type(groupData) ~= "table" then
        return false
    end
    local changed = false
    for _, group in pairs(groupData) do
        if type(group) == "table" then
            for _, data in pairs(group) do
                if runtimeFixes.repairPlayerDetailRowData(data) then
                    changed = true
                end
                local childData = type(data) == "table" and data.childData or nil
                if type(childData) == "table" then
                    for _, child in pairs(childData) do
                        if runtimeFixes.repairPlayerDetailRowData(child) then
                            changed = true
                        end
                    end
                end
            end
        end
    end
    return changed
end

function runtimeFixes.repairLivePlayerDetailTables()
    local tableData = Game and Game.TableData
    if type(tableData) ~= "table" then
        return false
    end
    local changed = false
    for _, getterName in ipairs({
        "GetPhyDetailDataTable",
        "GetMagDetailDataTable",
    }) do
        local getter = tableData[getterName]
        if type(getter) == "function" then
            local ok, rows = pcall(getter)
            if ok and type(rows) == "table" then
                runtimeFixes.repairPlayerDetailTable(rows)
                changed = true
            end
        end
    end
    return changed
end

function runtimeFixes.installPlayerDetailPanelRepair(value, environment, source)
    local class = getSymbol(value, environment, "PlayerDetails_List_Panel")
    if type(class) ~= "table" or class.__cpddPlayerDetailPanelLabels == VERSION then
        return type(class) == "table"
    end

    local original = class.RefreshProperties
    if type(original) ~= "function" then
        return false
    end
    class.RefreshProperties = function(self, ...)
        runtimeFixes.repairLivePlayerDetailTables()
        local results = { original(self, ...) }
        if runtimeFixes.repairPlayerDetailGroupData(self and self.GroupData) then
            local list = self and self.HB_ListCom
            if list ~= nil and type(list.Refresh) == "function" then
                pcall(list.Refresh, list, self.GroupData)
            end
        end
        return unpack(results)
    end
    class.__cpddPlayerDetailPanelLabels = VERSION
    report("installed complete player-detail attribute repair for " .. source)
    return true
end

-- The original creator widgets paint one Chinese character in each of two
-- large labels and keep the complete English word in a faint decorative
-- subtitle. The former PAK fix edited those two WidgetBlueprint assets. Do
-- the equivalent on the live widgets so bootstrap-only installs retain the
-- full choices without shipping cooked asset replacements.
local creatorChoiceLabels = {
    [1] = { "Madness", "Sanity" },
    [2] = { "Wisdom", "Power" },
    [3] = { "Glory", "Emotion" },
}

local function promoteCreatorChoiceLabel(container, firstName, secondName, promotedName, text)
    if container == nil then
        return false
    end

    local first = getNamedWidget(container, firstName)
    local second = getNamedWidget(container, secondName)
    local promoted = getNamedWidget(container, promotedName)
    if promoted == nil then
        return false
    end

    -- Remove the character-split labels and place the complete reviewed word
    -- in the existing full-width subtitle text block.
    runtimeFixes.setNamedWidgetText(container, firstName, "")
    runtimeFixes.setNamedWidgetText(container, secondName, "")
    runtimeFixes.setNamedWidgetText(container, promotedName, text)

    -- Reuse the normal label's exact cooked font and tint. This replaces the
    -- fictional-glyph subtitle font, its extreme tracking, and its low alpha
    -- without needing to construct a fragile FSlateFontInfo in Lua.
    local font = nil
    local color = nil
    pcall(function()
        if first ~= nil and first.GetFont ~= nil then
            font = first:GetFont()
        elseif first ~= nil then
            font = first.Font
        end
    end)
    pcall(function()
        if first ~= nil and first.GetColorAndOpacity ~= nil then
            color = first:GetColorAndOpacity()
        elseif first ~= nil then
            color = first.ColorAndOpacity
        end
    end)
    if font ~= nil then
        pcall(function() promoted.Font = font end)
        pcall(function()
            if promoted.SetFont ~= nil then promoted:SetFont(font) end
        end)
    end
    if color ~= nil then
        pcall(function() promoted.ColorAndOpacity = color end)
        pcall(function()
            if promoted.SetColorAndOpacity ~= nil then promoted:SetColorAndOpacity(color) end
        end)
    end

    pcall(function()
        if promoted.SetRenderOpacity ~= nil then promoted:SetRenderOpacity(1) end
    end)
    pcall(function()
        if promoted.SetLetterSpacing ~= nil then promoted:SetLetterSpacing(0) end
    end)
    pcall(function()
        if promoted.SetRenderTranslation ~= nil then
            promoted:SetRenderTranslation(FVector2D(-50, 0))
        end
    end)
    pcall(function()
        if promoted.Slot ~= nil and promoted.Slot.SetPadding ~= nil then
            promoted.Slot:SetPadding(FMargin(0, 0, 0, 0))
        end
    end)
    pcall(function()
        if promoted.SynchronizeProperties ~= nil then promoted:SynchronizeProperties() end
    end)
    pcall(function()
        if promoted.InvalidateLayoutAndVolatility ~= nil then
            promoted:InvalidateLayoutAndVolatility()
        end
    end)
    return true
end

local function repairCreateRoleChoiceLabels(self)
    local labels = creatorChoiceLabels[tonumber(self and self.nowIndex)]
    local view = self and self.view
    if labels == nil or view == nil then
        return false
    end

    local left = getNamedWidget(view, "WBP_CreateRole_Answer_Sub01")
    local right = getNamedWidget(view, "WBP_CreateRole_Answer_Sub02")
    local changed = promoteCreatorChoiceLabel(
        left,
        "Text_Answer_Text01_L",
        "Text_Answer_Text02_L",
        "Text_Answer_TheLeon01_L",
        labels[1]
    )
    changed = promoteCreatorChoiceLabel(
        right,
        "Text_Answer_Text01_R",
        "Text_Answer_Text02_R",
        "Text_Answer_TheLeon01_R",
        labels[2]
    ) or changed
    return changed
end

local function compactOverallGraphicsChoices(self)
    if self == nil or type(self.ChoiceListData) ~= "table" then
        return false
    end
    local overallConst = nil
    pcall(function()
        overallConst = Enum.ESettingConstData.OVERALL_SCALABILITY_LEVEL
    end)
    if overallConst == nil or self.MetaData == nil or self.MetaData.Const_1 ~= overallConst then
        return false
    end

    self.bTextLengthExceed = false
    for _, choice in pairs(self.ChoiceListData) do
        if type(choice) == "table" then
            choice.bTextLengthExceed = false
        end
    end

    local list = self.Hori_ChoiceCom
    if list ~= nil and type(list.Refresh) == "function" then
        pcall(list.Refresh, list, self.ChoiceListData)
        if type(self.UpdateData) == "function" then
            pcall(self.UpdateData, self, false)
        end
        return true
    end
    return false
end

local function installSettingsPresetLayoutRepair(value, environment)
    local class = getSymbol(value, environment, "Settings_Option_Item")
    if type(class) ~= "table" or class.__cpddCompactGraphicsPresets == VERSION then
        return false
    end
    local originalRefresh = class.Refresh
    if type(originalRefresh) ~= "function" then
        return false
    end

    class.Refresh = function(self, ...)
        local results = { originalRefresh(self, ...) }
        compactOverallGraphicsChoices(self)
        return unpack(results)
    end
    class.__cpddCompactGraphicsPresets = VERSION
    report("installed compact overall graphics preset row")
    return true
end

local taskBoardWidgetNames = {
    "Text_TargetDesc",
    "Text_Name",
    "Text_ChapterName",
    "RichText_Hint01",
    "RichText_Hint02",
    "RichText_Path",
}

local taskInfoRepairReports = setmetatable({}, { __mode = "k" })
local function repairTaskInfoLabels(self)
    if self == nil then return 0 end
    local view = nil
    local readable = pcall(function() view = self.view end)
    if not readable or type(view) ~= "table" then return 0 end

    local repaired = 0
    local visited = setmetatable({}, { __mode = "k" })
    local function repair(widget)
        local widgetType = type(widget)
        if (widgetType ~= "table" and widgetType ~= "userdata")
            or visited[widget]
        then
            return
        end
        visited[widget] = true
        repaired = repaired + translateTextWidget(widget)
    end
    local function repairNamed(owner, name)
        repair(getNamedWidget(owner, name))
    end

    for _, name in ipairs({
        "Text_TaskDesc1", "Text_ChapterName",
        "RichText_Hint01", "RichText_Hint02", "RichText_Path",
    }) do
        repairNamed(view, name)
    end

    local targetRoot = getNamedWidget(view, "WBP_TaskTargetItem")
    repairNamed(targetRoot, "Text_TargetDesc")
    pcall(function()
        repairNamed(self.WBP_TaskTargetItemCom and self.WBP_TaskTargetItemCom.view,
            "Text_TargetDesc")
    end)

    for _, tagName in ipairs({ "TaskTag1", "TaskTag2", "TaskTag3" }) do
        repairNamed(getNamedWidget(view, tagName), "Text_Tag_lua")
    end

    if taskInfoRepairReports[self] ~= true then
        taskInfoRepairReports[self] = true
        report("Task Info targeted repair active labels=" .. tostring(repaired))
    end
    return repaired
end

local taskListItemRepairReports = setmetatable({}, { __mode = "k" })
local function repairTaskListItemLabels(self)
    if self == nil then return 0 end
    local view = nil
    local readable = pcall(function() view = self.view end)
    if not readable or type(view) ~= "table" then return 0 end

    local repaired = 0
    for _, name in ipairs({ "Text_ChapterName", "Text_TaskLocation" }) do
        repaired = repaired + translateTextWidget(getNamedWidget(view, name))
    end
    if taskListItemRepairReports[self] ~= true then
        taskListItemRepairReports[self] = true
        report("Task list item targeted repair active labels=" .. tostring(repaired))
    end
    return repaired
end

local taskBoardRepairStates = setmetatable({}, { __mode = "k" })
local taskBoardRepairBursts = setmetatable({}, { __mode = "k" })

local function repairTaskBoardLabelsNow(self)
    if self == nil then return 0 end
    local destroyed = false
    pcall(function() destroyed = self.isDestroyed == true end)
    if destroyed then return 0 end

    local repaired = 0
    local foundCount = 0
    local componentCount = 0
    local visitedWidgets = setmetatable({}, { __mode = "k" })
    local visitedComponents = setmetatable({}, { __mode = "k" })
    local library = resolveWidgetProbeLibrary()
    local findWidget = library and library.FindWidget
    local function repairComponent(component)
        if component == nil or visitedComponents[component] then return end
        visitedComponents[component] = true
        componentCount = componentCount + 1
        local view, root, children
        local readable = pcall(function()
            view = component.view
            root = component.userWidget or component.widget
            children = component._childComponents
        end)
        if not readable then
            runtimeMetrics.TaskBoardTargetFailures = runtimeMetrics.TaskBoardTargetFailures + 1
            return
        end
        repaired = repaired + translateDirectViewTextWidgets(view)
        for _, name in ipairs(taskBoardWidgetNames) do
            local widget = getNamedWidget(view, name) or getNamedWidget(root, name)
            if widget == nil and root ~= nil and type(findWidget) == "function" then
                local ok, found = pcall(findWidget, root, name)
                if ok then widget = found end
            end
            if widget ~= nil and not visitedWidgets[widget] then
                visitedWidgets[widget] = true
                foundCount = foundCount + 1
                repaired = repaired + translateTextWidget(widget)
            end
        end
        if type(children) == "table" then
            for _, child in pairs(children) do
                repairComponent(child)
            end
        end
    end
    repairComponent(self)
    runtimeMetrics.TaskBoardTargetRuns = runtimeMetrics.TaskBoardTargetRuns + 1
    runtimeMetrics.TaskBoardTargetComponents =
        runtimeMetrics.TaskBoardTargetComponents + componentCount
    runtimeMetrics.TaskBoardTargetWidgetsFound =
        runtimeMetrics.TaskBoardTargetWidgetsFound + foundCount
    runtimeMetrics.TaskBoardTargetLabelsRepaired =
        runtimeMetrics.TaskBoardTargetLabelsRepaired + repaired

    local state = taskBoardRepairStates[self]
    if state == nil then
        state = { Runs = 0, Components = 0, Found = 0, Repaired = 0 }
        taskBoardRepairStates[self] = state
    end
    state.Runs = state.Runs + 1
    state.Components = math.max(state.Components, componentCount)
    state.Found = math.max(state.Found, foundCount)
    state.Repaired = state.Repaired + repaired
    return repaired
end

local function reportTaskBoardRepair(self)
    repairTaskBoardLabelsNow(self)
    taskBoardRepairBursts[self] = nil
    local state = taskBoardRepairStates[self]
    if state ~= nil and state.Reported ~= true then
        state.Reported = true
        report("Task Board targeted repair runs=" .. tostring(state.Runs)
            .. " child_components=" .. tostring(state.Components)
            .. " widgets_found=" .. tostring(state.Found)
            .. " labels_repaired=" .. tostring(state.Repaired))
    end
end

local function repairTaskBoardLabels(self)
    local started = nowMilliseconds()
    local repaired = repairTaskBoardLabelsNow(self)
    if taskBoardRepairBursts[self] ~= true then
        taskBoardRepairBursts[self] = true
        scheduleRepairAfter(self, 0.05, repairTaskBoardLabelsNow)
        scheduleRepairAfter(self, 0.25, repairTaskBoardLabelsNow)
        if not scheduleRepairAfter(self, 0.75, reportTaskBoardRepair) then
            taskBoardRepairBursts[self] = nil
            reportTaskBoardRepair(self)
        end
    end
    local elapsed = nowMilliseconds() - started
    if elapsed >= 8 then
        runtimeMetrics.SlowTargetedRepairs = runtimeMetrics.SlowTargetedRepairs + 1
        report("slow targeted Task Board repair elapsed_ms="
            .. string.format("%.2f", elapsed)
            .. " labels=" .. tostring(repaired))
    end
    return repaired
end

local viewRepairSpecs = {
    {
        "Gameplay.LogicSystem.SkillCustomizer.Main.SkillCommon_Panel",
        "SkillCommon_Panel",
        { "OnRefresh", "RefreshBeStrongArea" },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.Main.Skill_BeStrong_Btn",
        "Skill_BeStrong_Btn",
        { "Refresh", "UpdateState" },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.Main.Secret.Skill_Secret_Detail",
        "Skill_Secret_Detail",
        { "Refresh", "RefreshSkillInfo", "IShowSkillDesc" },
    },
    {
        "Gameplay.LogicSystem.Guild.GuildInside.Members.GuildInside_Permission_Panel.GuildInside_Permission_Panel",
        "GuildInside_Permission_Panel",
        { "OnRefresh", "OnReceiveGuildRights", "RefreshRightsData" },
    },
}

local exactWidgetRepairSpecs = {
    -- Brass Tome writes freshly formatted descriptions directly on each refresh.
    {
        "Gameplay.LogicSystem.BrassTome.BrassTomeTask_Item",
        "BrassTomeTask_Item",
        { "OnRefresh" },
        function(self)
            translateTextWidget(getNamedWidget(self and self.view, "Text_Content"))
        end,
        true,
    },
    -- Server names arrive with login data, including recycled list rows.
    {
        "Gameplay.LogicSystem.Login.LoginServerItem",
        "LoginServerItem",
        { "OnRefresh" },
        function(self)
            local view = self and self.view
            translateTextWidget(getNamedWidget(view, "Server_Name_Text"))
            translateTextWidget(getNamedWidget(view, "Server_Name_Text1"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.Login.LoginPanel",
        "LoginPanel",
        { "setServerInfoUI" },
        function(self)
            translateTextWidget(getNamedWidget(self and self.view, "Text_ServerName"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.Dialogue.DialogueScreenTextComp",
        "DialogueScreenTextComp",
        { "OnSectionInit" },
        function(self)
            translateTextWidget(getNamedWidget(self and self.usingScreenText, "RTB_Aside1_lua"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.Border_Panel",
        "Border_Panel",
        { "SetBlackScreenText" },
        function(self)
            local view = self and self.view
            translateTextWidget(getNamedWidget(view and view.WidgetRoot, "RTB_Aside1_lua"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.MimeWhite_Panel",
        "MimeWhite_Panel",
        { "SetBlackScreenText" },
        function(self)
            local view = self and self.view
            translateTextWidget(getNamedWidget(view and view.WidgetRoot, "RTB_Aside1_lua"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.Reminder.PlayerInfo.PowerItemSpecial",
        "PowerItemSpecial",
        { "Refresh", "PlayInAnimation" },
        function(self)
            -- The rating caption is serialized inside this small reminder.
            -- Do not hook SetCEText: the score tween calls it every frame.
            local root = self and (self.userWidget or self.widget)
            local caption = getNamedWidget(self and self.view, "C7TextBlock_100")
                or getNamedWidget(root, "C7TextBlock_100")
            if caption ~= nil then
                -- This serialized C7TextBlock need not expose a readable GetText.
                runtimeFixes.setNamedWidgetText({ caption = caption }, "caption", "Beyonder Rating")
                return
            end
            local function repairCaption(widget)
                local name
                pcall(function() name = tostring(widget:GetName()) end)
                if name == "C7TextBlock_100" then
                    runtimeFixes.setNamedWidgetText({ caption = widget }, "caption", "Beyonder Rating")
                else
                    translateTextWidget(widget)
                end
            end
            local visited = {}
            walkWidgetDescendants(root, visited, repairCaption)
            local treeRoot
            pcall(function() treeRoot = root.WidgetTree.RootWidget end)
            if treeRoot == nil then
                pcall(function() treeRoot = root:GetRootWidget() end)
            end
            walkWidgetDescendants(treeRoot, visited, repairCaption)
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.GameplayIntegration.UI.PVP.GameplayIntegration_PVPEntrance_Item",
        "GameplayIntegration_PVPEntrance_Item",
        { "OnRefresh" },
        function(self)
            -- Translate the four known data values directly; no panel scan or
            -- lazy dictionary read is needed when the entrance card refreshes.
            local english = {
                ["高原竞逐"] = "Highland Competition",
                ["大战场"] = "Large Battlefield",
                ["800人战场"] = "800-Player Battlefield",
                ["周三、周六晚上开放"] = "Open Wednesday and Saturday nights",
                ["周三、周六晚开放"] = "Open Wednesday and Saturday nights",
            }
            local row = Game and Game.TableData
                and Game.TableData.GetPlayEntrancePVPTypeDataRow(self.id)
            if type(row) ~= "table" and type(row) ~= "userdata" then return end
            local view = self.view
            for name, field in pairs({ Text_Title = "Name", Text_TypeName = "Subtitle", Text_Type = "MiniName" }) do
                local text = english[row[field]]
                if text then runtimeFixes.setNamedWidgetText(view, name, text) end
            end
            local text = english[row.TimeDesc]
            if text then
                runtimeFixes.setNamedWidgetText(view and view.WBP_GameplayIntegration_TimeTip, "Text_TimeTip", text)
            end
        end,
        true,
    },
    -- HUD quests repaint independently of HUD_Panel. Touch only the bound
    -- labels after their text-producing methods; never queue a HUD tree walk.
    {
        "Gameplay.LogicSystem.HUD.HUD_Task.New.HUD_Task_Title",
        "HUD_Task_Title",
        { "RefreshTitle" },
        function(self)
            translateTextWidget(getNamedWidget(self and self.view, "KText_Title"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.HUD.HUD_Task.New.HUD_Task_Item",
        "HUD_Task_Item",
        { "refreshMainTarget", "refreshTips", "SetTouchFunBtn" },
        function(self)
            local view = self and self.view
            for _, name in ipairs({ "Text_TargetDes", "RichText_Tips", "Text_Touch" }) do
                translateTextWidget(getNamedWidget(view, name))
            end
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.HUD.HUD_Task.New.HUD_Task_Sub_Item",
        "HUD_Task_Sub_Item",
        { "OnRefresh" },
        function(self)
            translateTextWidget(getNamedWidget(self and self.view, "Text_TargetDesc"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.Task.New.Task_List_Item",
        "Task_List_Item",
        { "OnRefresh" },
        repairTaskListItemLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.Task.New.Task_Info",
        "Task_Info",
        { "RefreshInfo" },
        repairTaskInfoLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.Guild.GuildInside.Entrance.GuildInside_Panel.GuildInside_Announce_Preview_Item",
        "GuildInside_Announce_Preview_Item",
        { "OnRefresh" },
        runtimeFixes.repairGuildEventPreviewLayout,
        true,
    },
    {
        "Gameplay.LogicSystem.SequencePromotion.SequencePromotion_Panel.Sequence_Dec",
        "Sequence_Dec",
        { "InitUIView", "Refresh" },
        runtimeFixes.repairSequencePromotionPanelButtons,
        true,
    },
    {
        "Gameplay.LogicSystem.SequencePromotion.SequencePromotion_Panel.Sequence_TaskItem",
        "Sequence_TaskItem",
        { "OnRefresh" },
        runtimeFixes.repairSequencePromotionConditionLayout,
        true,
    },
    {
        "Gameplay.LogicSystem.SequencePromotion.SequencePromotion_Panel.Sequence_TextItem",
        "Sequence_TextItem",
        { "OnRefresh" },
        runtimeFixes.repairSequencePromotionChangeLayout,
        true,
    },
    {
        "Gameplay.LogicSystem.CreateRole.CreateRoleAnswer_Panel",
        "CreateRoleAnswer_Panel",
        { "setChooseInfo" },
        repairCreateRoleChoiceLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.NPCBtnCut",
        "NPCBtnCut",
        { "InitUIView", "Refresh" },
        runtimeFixes.repairScreenshotLabel,
        true,
    },
    {
        "Gameplay.LogicSystem.LoginPopUp.LoginActivityPopUp_Panel",
        "LoginActivityPopUp_Panel",
        { "InitUIView", "OnRefresh", "on_KGListViewCom_ItemSelected", "ShowTitle" },
        runtimeFixes.repairLoginActivityLabels,
        {
            OnRefresh = true,
            on_KGListViewCom_ItemSelected = true,
            ShowTitle = true,
        },
    },
    {
        "Gameplay.LogicSystem.Item.NewUI.ItemTagCenter",
        "ItemTagCenter",
        { "SetData" },
        runtimeFixes.repairItemReceivedLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.TrainTrade.Main.TrainTradeMainTask_Item",
        "TrainTradeMainTask_Item",
        { "OnRefresh" },
        runtimeFixes.repairClaimedRewardLabel,
        true,
    },
    {
        "Gameplay.LogicSystem.GvG.GVG_WinnerParty.GVG_WinnerParty_Player_Item",
        "GVG_WinnerParty_Player_Item",
        { "OnRefresh" },
        runtimeFixes.repairGvgRewardStatusLabel,
        true,
    },
    {
        "Gameplay.LogicSystem.Item.ItemSmall",
        "ItemSmall",
        { "FillItem" },
        runtimeFixes.repairLegacyItemSmallLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.WorldCalamityBoss.WorldBossDetail_Panel.WorldBoss_Award_Widget_Item",
        "WorldBoss_Award_Widget_Item",
        { "UpdateRewardState" },
        runtimeFixes.repairWorldBossClaimedLabel,
        true,
    },
    {
        "Gameplay.LogicSystem.SecretPartner.Gacha.SecretPartner_Gacha_Get_Panel",
        "SecretPartner_Gacha_Get_Panel",
        {
            "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh",
            "RefreshView", "UpdateUI", "PlayAnimation",
        },
        runtimeFixes.repairDynamicPanelLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.SecretPartner.Star.SecretPartner_StarUp_Panel",
        "SecretPartner_StarUp_Panel",
        {
            "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh",
            "RefreshView", "UpdateUI", "PlayAnimation",
        },
        runtimeFixes.repairDynamicPanelLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.DiceRollV2.Panels.DiceRollV2_Result_Succ_Panel",
        "DiceRollV2_Result_Succ_Panel",
        { "InitUIView", "OnRefresh", "PlaySuccessAnim" },
        runtimeFixes.repairDiceResultLabels,
        { OnRefresh = true, PlaySuccessAnim = true },
    },
    {
        "Gameplay.LogicSystem.DiceRollV2.Panels.DiceRollV2_Result_SuccessDefault",
        "DiceRollV2_Result_SuccessDefault",
        { "InitUIView", "Refresh" },
        runtimeFixes.repairDiceResultLabels,
        { Refresh = true },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.Main.SkillUpgradeTips_Panel",
        "SkillUpgradeTips_Panel",
        { "InitUIView", "OnRefresh", "SetContent" },
        runtimeFixes.repairSkillUpgradeTipsLabels,
        { OnRefresh = true, SetContent = true },
    },
    {
        "Gameplay.LogicSystem.SecretPartner.SecretPartner_Panel",
        "SecretPartner_Panel",
        {
            "InitUIView", "OnRefresh", "OnShow", "RefreshMainTab",
            "on_WBP_SecretPuppetTabListCom_ItemSelected",
        },
        runtimeFixes.repairSecretPartnerLabels,
    },
    {
        "Gameplay.LogicSystem.SecretPartner.Base.SecretPartnerBase_Sub",
        "SecretPartnerBase_Sub",
        {
            "InitUIView", "Refresh", "RefreshPartnerItemListPanel",
            "RefreshPartnerItemList", "RefreshSecretPartnerSelectedState",
        },
        runtimeFixes.repairSecretPartnerLabels,
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.Main.Skill_BeStrong_Btn",
        "Skill_BeStrong_Btn",
        { "InitUIView", "Refresh", "UpdateState" },
        runtimeFixes.repairSkillHeaderLabels,
        { Refresh = true, UpdateState = true },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.Main.SkillCommon_Panel",
        "SkillCommon_Panel",
        { "InitUIView", "OnRefresh", "InitSkillCustomizer", "RefreshBeStrongArea" },
        runtimeFixes.repairSkillCommonLabels,
    },
    {
        "Gameplay.LogicSystem.Talent.Talent_Panel",
        "Talent_Panel",
        {
            "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh",
            "RefreshView", "refreshOneClickStatus", "refreshEnableStatus",
        },
        runtimeFixes.repairTalentLabels,
    },
    {
        "Gameplay.LogicSystem.Equipment.Reform.EquipmentForging_Plan_Panel",
        "EquipmentForging_Plan_Panel",
        { "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh", "RefreshView", "UpdateUI" },
        runtimeFixes.repairEmbeddedSkillHeaderLabels,
    },
    {
        "Gameplay.LogicSystem.PlayerDetails.ExtraordinaryScore.ExtraordinaryScore_Panel",
        "ExtraordinaryScore_Panel",
        { "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh", "RefreshView", "UpdateUI" },
        runtimeFixes.repairEmbeddedSkillHeaderLabels,
    },
    {
        "Gameplay.LogicSystem.PlayerDetails.PlayerTotal_Panel",
        "PlayerTotal_Panel",
        { "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh", "RefreshView", "UpdateUI" },
        runtimeFixes.repairEmbeddedSkillHeaderLabels,
    },
    {
        "Gameplay.LogicSystem.Sealed_2.Sealed_Main_Panel",
        "Sealed_Main_Panel",
        { "InitUIView", "OnRefresh", "OnOpen", "OnShow", "Refresh", "RefreshView", "UpdateUI" },
        runtimeFixes.repairEmbeddedSkillHeaderLabels,
    },
    {
        "Gameplay.LogicSystem.Equipment.Equipment_Panel",
        "Equipment_Panel",
        { "InitUIView", "OnRefresh", "RefreshCurrentTabPage" },
        runtimeFixes.repairEquipmentLabels,
    },
    {
        "Gameplay.LogicSystem.Equipment.Reform.EquipmentReform_Page",
        "EquipmentReform_Page",
        { "RefreshReformPanelState" },
        runtimeFixes.repairEquipmentReformUnlockText,
        true,
    },
    {
        "Gameplay.LogicSystem.Bag.MainBag.Bag_Panel",
        "Bag_Panel",
        { "InitUIView", "OnRefresh", "UpdateAutoDecomposeBtn", "UpdateAutoDecomposeOpenSwitch" },
        runtimeFixes.repairBagLabels,
        {
            OnRefresh = true,
            UpdateAutoDecomposeBtn = true,
            UpdateAutoDecomposeOpenSwitch = true,
        },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.SchemePlan.Scheme_Plan_Item",
        "Scheme_Plan_Item",
        { "InitUIView", "OnRefresh" },
        runtimeFixes.repairSchemePlanItemLabels,
        { OnRefresh = true },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.OneClick.OneClick_Plan_Item",
        "OneClick_Plan_Item",
        { "InitUIView", "OnRefresh", "SetAsDefault", "UpdateEquip" },
        runtimeFixes.repairSchemePlanItemLabels,
        { OnRefresh = true, SetAsDefault = true, UpdateEquip = true },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.OneClick.OneClick_PlanType_Tab_Item",
        "OneClick_PlanType_Tab_Item",
        { "InitUIView", "OnRefresh", "Refresh", "UpdateEquip", "UpdateUse" },
        runtimeFixes.repairSchemeUseLabels,
        {
            OnRefresh = true,
            Refresh = true,
            UpdateEquip = true,
            UpdateUse = true,
        },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.SchemeAssembly.Scheme_CustomPlan_Item",
        "Scheme_CustomPlan_Item",
        { "InitUIView", "OnRefresh", "SetAsAddPlan", "UpdateSelectionState" },
        runtimeFixes.repairSchemeUseLabels,
        { OnRefresh = true, SetAsAddPlan = true, UpdateSelectionState = true },
    },
    {
        "Gameplay.LogicSystem.SkillCustomizer.SchemeAssembly.Scheme_CustomPlan_Equipment_Item",
        "Scheme_CustomPlan_Equipment_Item",
        { "InitUIView", "OnRefresh", "SetAsAddPlan", "UpdateSelectionState" },
        runtimeFixes.repairSchemeUseLabels,
        { OnRefresh = true, SetAsAddPlan = true, UpdateSelectionState = true },
    },
    {
        "Gameplay.LogicSystem.Equipment.Wear.Equipment_Wear_Attribute_Item",
        "Equipment_Wear_Attribute_Item",
        { "InitUIView", "OnRefresh", "Refresh", "UpdateUse", "SetUse" },
        runtimeFixes.repairSchemeUseLabels,
        {
            OnRefresh = true,
            Refresh = true,
            UpdateUse = true,
            SetUse = true,
        },
    },
    {
        "Gameplay.LogicSystem.Equipment.Wear.Equipment_Wear_Suit_Item",
        "Equipment_Wear_Suit_Item",
        { "InitUIView", "OnRefresh", "Refresh", "UpdateUse", "SetUse" },
        runtimeFixes.repairSchemeUseLabels,
        {
            OnRefresh = true,
            Refresh = true,
            UpdateUse = true,
            SetUse = true,
        },
    },
    {
        "Gameplay.LogicSystem.HUD.HUD_PVPLastHunt.PVPLastHunt_Details_MyData",
        "PVPLastHunt_Details_MyData",
        { "InitUIView", "OnRefresh", "RefreshBasicInfo", "RefreshRewardInfo" },
        runtimeFixes.repairLastHuntMyDataLabels,
    },
}

local dataRepairSpecs = {
    {
        "Framework.KGFramework.KGUI.Component.Tools.UIComDiyTitle",
        "UIComDiyTitle",
        { "Refresh" },
    },
    {
        "Gameplay.LogicSystem.Gossip.GossipSystem",
        "GossipSystem",
        { "PlayBubbleByEidOrUid", "PlayBottomBubble" },
    },
    {
        "Gameplay.LogicSystem.NewHeadInfo.HeadInfoUI.HeadInfoBubble",
        "HeadInfoBubble",
        { "ShowCustomBubble" },
    },
    {
        "Gameplay.LogicSystem.HUD.HUD_Aside.HUDAside_Bubble",
        "HUDAside_Bubble",
        { "Refresh" },
    },
    {
        "Gameplay.LogicSystem.NPC.Sequence.Sequence_Panel",
        "Sequence_Panel",
        { "ShowDialoguePanel", "OnSetBottomText" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Button.UIComText",
        "UIComText",
        { "Refresh" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Button.UIComButton",
        "UIComButton",
        { "Refresh", "OnRefresh", "SetName" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Select.UIComDropDown",
        "UIComDropDown",
        { "Refresh", "refreshOptionsList", "refreshOptionBtn" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Select.UIComDropDownItem",
        "UIComDropDownItem",
        { "OnRefresh", "SetName" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Tab.UIComTabList",
        "UIComTabList",
        { "Refresh" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Tab.UIComSimpleTabList",
        "UIComSimpleTabList",
        { "Refresh" },
    },
    {
        "Framework.KGFramework.KGUI.Component.Tab.UIComTabItem",
        "UIComTabItem",
        { "OnRefresh" },
    },
    {
        "Gameplay.LogicSystem.Lib.LibText",
        "LibText",
        { "Refresh" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsText_Item",
        "ItemTipsText_Item",
        { "OnRefresh" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipStory",
        "ItemTipsEquipStory",
        { "SetData" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipSuit",
        "ItemTipsEquipSuit",
        { "SetData" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipSuitItem",
        "ItemTipsEquipSuitItem",
        { "OnRefresh" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipSpirituality",
        "ItemTipsEquipSpirituality",
        { "SetData" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsQuickAssembly_Page",
        "ItemTipsQuickAssembly_Page",
        { "SetContent" },
    },
    {
        "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsQuickAssembly_Entry_Page",
        "ItemTipsQuickAssembly_Entry_Page",
        { "SetContent" },
    },
}

local function registerViewRepair(spec)
    local moduleName, symbolName, methodNames, directOnly = spec[1], spec[2], spec[3], spec[4]
    Loader.AfterLoad(moduleName, function(value, environment)
        installViewMethodRepair(
            value, environment, symbolName, methodNames, moduleName, directOnly
        )
        return value
    end, 1000000, "cpdd.runtime-fix.view." .. moduleName:gsub("[^%w]", "-"))
end

local function registerDataRepair(spec)
    local moduleName, symbolName, methodNames = spec[1], spec[2], spec[3]
    Loader.AfterLoad(moduleName, function(value, environment)
        installDataMethodRepair(value, environment, symbolName, methodNames, moduleName)
        return value
    end, 1000000, "cpdd.runtime-fix.data." .. moduleName:gsub("[^%w]", "-"))
end


local function registerExactWidgetRepair(spec)
    local moduleName, symbolName, methodNames, repair, repeatRepair = spec[1], spec[2], spec[3], spec[4], spec[5]
    Loader.AfterLoad(moduleName, function(value, environment)
        installExactWidgetRepair(value, environment, symbolName, methodNames, repair, moduleName, repeatRepair)
        return value
    end, 1000000, "cpdd.runtime-fix.exact-widget." .. moduleName:gsub("[^%w]", "-"))
    -- A launch panel can require its list-item class before this mod registers
    -- AfterLoad. getSymbol falls back to the live global class in that case.
    if package.loaded[moduleName] ~= nil then
        installExactWidgetRepair(
            package.loaded[moduleName], nil, symbolName, methodNames,
            repair, moduleName .. " (startup cache)", repeatRepair
        )
    end
end

for _, spec in ipairs(viewRepairSpecs) do
    registerViewRepair(spec)
end
for _, spec in ipairs(dataRepairSpecs) do
    registerDataRepair(spec)
end
for _, spec in ipairs(exactWidgetRepairSpecs) do
    registerExactWidgetRepair(spec)
end

function runtimeFixes.registerPlayerDetailLabelRepairs()
    local function registerDataTable(moduleName)
        Loader.AfterLoad(moduleName, function(value)
            return runtimeFixes.repairPlayerDetailTable(value)
        end, 1000000, "cpdd.runtime-fix.player-detail-data." .. moduleName:gsub("[^%w]", "-"))
    end

    local function registerRow(moduleName, symbolName)
        Loader.AfterLoad(moduleName, function(value, environment)
            runtimeFixes.installPlayerDetailRowRepair(value, environment, symbolName, moduleName)
            return value
        end, 1000000, "cpdd.runtime-fix.player-detail-row." .. moduleName:gsub("[^%w]", "-"))
    end

    registerDataTable("Data.Excel.PhyDetailData")
    registerDataTable("Data.Excel.MagDetailData")

    Loader.AfterLoad("Data.Excel.FightPropModeData", function(value)
        return runtimeFixes.repairFightPropertyTable(value)
    end, 1000000, "cpdd.runtime-fix.fight-property-labels")

    Loader.AfterLoad("Data.Excel.TipsData", function(value)
        return runtimeFixes.repairDefenseBreakTipsTable(value)
    end, 1000000, "cpdd.runtime-fix.defense-break-tips")

    registerRow(
        "Gameplay.LogicSystem.PlayerDetails.PlayerDetails_List_Drop_Item",
        "PlayerDetails_List_Drop_Item"
    )
    registerRow(
        "Gameplay.LogicSystem.PlayerDetails.PlayerDetails_List_DropList_Item",
        "PlayerDetails_List_DropList_Item"
    )
    registerRow(
        "Gameplay.LogicSystem.PlayerDetails.PlayerDetails_List_Normal_Item",
        "PlayerDetails_List_Normal_Item"
    )

    local panelModule = "Gameplay.LogicSystem.PlayerDetails.PlayerDetails_List_Panel"
    Loader.AfterLoad(panelModule, function(value, environment)
        runtimeFixes.installPlayerDetailPanelRepair(value, environment, panelModule)
        return value
    end, 1000000, "cpdd.runtime-fix.player-detail-panel")
end
runtimeFixes.registerPlayerDetailLabelRepairs()

Loader.AfterLoad(
    "Gameplay.LogicSystem.Item.Popup.ItemTips.ItemTipsEquipSpecial",
    function(value, environment)
        runtimeMetrics.InstallEquipmentSpecialTextRepair(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.item-tips-equip-special"
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.Sealed_2.SealedSystem",
    function(value, environment)
        runtimeMetrics.InstallSealedSkillDescRepair(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.sealed-skill-description"
)

Loader.AfterLoad("Gameplay.LogicSystem.Guild.GuildSystem", function(value, environment)
    installGuildRoleRepair(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.guild-role-names")

Loader.AfterLoad("Gameplay.LogicSystem.Settings.Settings_Option_Item", function(value, environment)
    installSettingsPresetLayoutRepair(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.compact-graphics-presets")

Loader.AfterLoad("Gameplay.LogicSystem.HUD.HUD_PVPLastHunt.PVPLastHunt_Details_MyData", function(value, environment)
    runtimeFixes.installLastHuntScoreFormatting(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.last-hunt-score-format")

Loader.AfterLoad("Gameplay.LogicSystem.Utils.CurrencyUtils", function(value, environment)
    runtimeFixes.installCurrencyFormatting(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.currency-number-format")

-- CurrencyUtils is loaded before C7 assigns its class to Game.CurrencyUtils.
-- Patch the live singleton after gameplay-manager initialization as well.
Loader.On("after_main", function()
    runtimeFixes.installCurrencyFormatting(
        { CurrencyUtils = Game and Game.CurrencyUtils },
        nil
    )
end, 1000000, "cpdd.runtime-fix.currency-number-format-main")

Loader.On("after_main", function()
    runtimeFixes.installCachedExchangePriceFormatting()
end, 999999, "cpdd.runtime-fix.exchange-cached-classes-main")

local exchangeStallItemModule =
    "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_StallContent_Item"
Loader.AfterLoad(
    exchangeStallItemModule,
    function(value, environment)
        runtimeFixes.installExchangeStallPriceFormatting(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.exchange-stall-price-format"
)
-- Shops_Panel eagerly requires both card classes during launch. AfterLoad does
-- not replay for an already-cached module, so patch its live global class now.
runtimeFixes.installExchangeStallPriceFormatting(
    package.loaded[exchangeStallItemModule],
    nil
)

local exchangeAuctionItemModule =
    "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_AuctionContent_Item"
Loader.AfterLoad(
    exchangeAuctionItemModule,
    function(value, environment)
        runtimeFixes.installExchangeAuctionPriceFormatting(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.exchange-auction-price-format"
)
runtimeFixes.installExchangeAuctionPriceFormatting(
    package.loaded[exchangeAuctionItemModule],
    nil
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_StallFashion_Item",
    function(value, environment)
        runtimeFixes.installExchangeStallFashionPriceFormatting(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.exchange-stall-fashion-price-format"
)
runtimeFixes.installExchangeStallFashionPriceFormatting(
    package.loaded[
        "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_StallFashion_Item"
    ],
    nil
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_SaleFashion_Item",
    function(value, environment)
        runtimeFixes.installExchangeSaleFashionPriceFormatting(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.exchange-sale-fashion-price-format"
)
runtimeFixes.installExchangeSaleFashionPriceFormatting(
    package.loaded[
        "Gameplay.LogicSystem.Shops.ShopsExchange.Shops_SaleFashion_Item"
    ],
    nil
)

Loader.AfterLoad(
    "Gameplay.LogicSystem.DungeonBattleStatistics.DungeonBattleStatisticsSystem",
    function(value, environment)
        runtimeFixes.installBattleStatisticsFormatting(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.dps-number-format"
)

Loader.AfterLoad("Gameplay.LogicSystem.PVP.Stats.PVP_Stats_Item", function(value, environment)
    runtimeMetrics.InstallPvpStatisticsFormatting(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.pvp-scoreboard-number-format")

Loader.AfterLoad("Gameplay.LogicSystem.NPC.Dialogue.DialogueTalk", function(value, environment)
    installDialogueTalkRepair(value, environment)
    return value
end, 1000000, "cpdd.runtime-fix.dialogue-layout")

Loader.AfterLoad("Gameplay.LogicSystem.NPC.Dialogue.Dialogue_Panel", function(value, environment)
    installDialogueControlRepair(
        value,
        environment,
        "Dialogue_Panel",
        {
            "InitUIView", "OnRefresh", "OnOpen", "RefreshPCModeKeyPrompt",
            "SetReviewButtonVisible", "SetSkipButtonVisible",
        },
        repairDialoguePanelLabels,
        "Dialogue_Panel"
    )
    return value
end, 1000000, "cpdd.runtime-fix.dialogue-panel-controls")

Loader.AfterLoad("Gameplay.LogicSystem.NPC.Dialogue.Dialogue_NPCBtnSkip", function(value, environment)
    installDialogueControlRepair(
        value,
        environment,
        "Dialogue_NPCBtnSkip",
        { "InitUIView", "Refresh" },
        repairDialogueSkipLabels,
        "Dialogue_NPCBtnSkip"
    )
    return value
end, 1000000, "cpdd.runtime-fix.dialogue-skip-controls")

local function installShortMenuLabels(value, environment)
    local class = getSymbol(value, environment, "MenuBtn_Item")
    if type(class) ~= "table" or type(class.OnRefresh) ~= "function" then
        return false
    end
    if class.__cpddShortMenuLabels then
        return true
    end

    local originalRefresh = class.OnRefresh
    class.OnRefresh = function(self, params)
        local results = { originalRefresh(self, params) }
        local menuId = self.MenuID
        local menuData = menuId and Game and Game.TableData and Game.TableData.GetMenuDataRow(menuId)
        local label = menuData and shortMenuLabels[menuData.ButtonEnum]
        if label and self.view then
            -- KGTextBlock can repaint its serialized long translation after
            -- OnRefresh. Persist the compact value in both the widget property
            -- and the live Slate text so later menu refreshes cannot restore it.
            runtimeFixes.setNamedWidgetText(self.view, "Text_Name", label)
        end
        return unpack(results)
    end
    class.__cpddShortMenuLabels = true
    report("installed compact English menu labels")
    return true
end

Loader.AfterLoad(
    "Gameplay.LogicSystem.Menu.MenuBtn_Item",
    function(value, environment)
        installShortMenuLabels(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.short-menu-labels"
)

-- Item tooltips are reused for subsequent hovered items without closing their
-- UIComponent. Rescan only this proven dynamic panel on Refresh; the pending
-- delayed pass coalesces bursts so this does not restore the global sweep.
local dynamicPanelRescanUids = {
    ActivityMain_Panel = true,
    FashionStation_Details_Panel = true,
    NewbieGuide_MainPanel = true,
    Sealed_Fuse_Main_Panel = true,
    Sealed_Fuse_Select_Panel = true,
    Shops_Panel = true,
    Sequence_Panel = true,
    TrainTrade_Hud_Panel = true,
}

local extendedPanelRepairDelays = {
    FashionStation_Details_Panel = { 0.25, 0.75, 1.50 },
    NewbieGuide_MainPanel = { 0.25, 0.75, 1.50, 3.00 },
    Sealed_Fuse_Main_Panel = { 0.25, 0.75, 1.50, 3.00, 6.00, 10.00, 20.00 },
    Sealed_Fuse_Select_Panel = { 0.25, 0.75, 1.50 },
    Sequence_Panel = { 0.50, 1.50, 3.00, 6.00, 10.00, 20.00 },
    Shops_Panel = { 0.25, 0.50, 1.00, 2.00 },
}

-- Current-session telemetry showed that these panels translated useful text
-- during their completed root Open pass, then spent 9-37 ms per delayed pass
-- revisiting 209-2162 widgets without changing a label. Their dynamic rows
-- already have dedicated data/view hooks above.
runtimeFixes.SinglePassPanelUids = {
    GuildInside_Panel = true,
    Menu_Panel = true,
    Sealed_Equip_Panel = true,
    SequencePromotion_Panel = true,
}

-- These high-frequency panels have dedicated data/view hooks above. A generic
-- recursive UIComponent pass only duplicates that work and was measured at up
-- to 80 ms for item previews and 26 ms every 0.2 seconds for the task board.
local targetedPanelRepairUids = {
    BagItemTips_Panel = true,
    TaskBoardPanel = true,
}

local function isDynamicPanelRescan(component)
    if component == nil then
        return false
    end
    local uid = component.uid or component.UID or component.__cname
    return uid ~= nil and dynamicPanelRescanUids[tostring(uid)] == true
end

local panelTextRepair = {
    States = setmetatable({}, { __mode = "k" }),
    Reports = {},
}

function panelTextRepair:StateKey(component)
    if component == nil then return nil end
    return component.userWidget or component.widget or component
end

function panelTextRepair:Repair(component, reason)
    if not runtimeUIRepairEnabled() or component == nil or component.isDestroyed then
        return 0
    end
    local started = nowMilliseconds()
    local visitedBefore = runtimeMetrics.WidgetsVisited
    local geminiLoadsBefore = runtimeMetrics.GeminiLoads
    local geminiEvictionsBefore = runtimeMetrics.GeminiShardEvictions
    local geminiReloadsBefore = runtimeMetrics.GeminiShardReloads
    local sourceLoadsBefore = runtimeMetrics.SourceShardLoads
    local sourceEvictionsBefore = runtimeMetrics.SourceShardEvictions
    local sourceReloadsBefore = runtimeMetrics.SourceShardReloads
    local repaired = 0
    local componentUid = component.uid or component.UID or component.__cname
    local visitedWidgets = {}
    if tostring(componentUid) == "Shops_Panel" then
        -- The shop can restore its live formatter after after_main. Reassert it
        -- immediately before scanning cards populated by the list view.
        runtimeFixes.installCurrencyFormatting(
            { CurrencyUtils = Game and Game.CurrencyUtils },
            nil
        )
    end
    local visitedComponents = {}
    local function repairComponent(current)
        if current == nil or current.isDestroyed or visitedComponents[current] then return end
        visitedComponents[current] = true
        local rootWidget = current.userWidget or current.widget
        local discoveryContext = nil
                repaired = repaired + (translateViewTextWidgets(
            current.view,
            rootWidget,
            discoveryContext,
            current,
            visitedWidgets
        ) or 0)
        if tostring(componentUid) == "GuildInside_Panel" then
            repaired = repaired + runtimeFixes.repairGuildEventPreviewTree(
                current.view,
                rootWidget
            )
        end

        -- Child UIComponents and cached subviews own independent UWidgetTrees.
        -- Walking them is the important coverage difference from the old panel
        -- pass, and remains bounded to the panel being opened or refreshed.
        if type(current._childComponents) == "table" then
            for _, child in pairs(current._childComponents) do repairComponent(child) end
        end
    end
    repairComponent(component)
        runtimeMetrics.PanelsRepaired = runtimeMetrics.PanelsRepaired + 1
    local elapsed = nowMilliseconds() - started
    runtimeMetrics.PanelRepairMillis = runtimeMetrics.PanelRepairMillis + elapsed
    runtimeMetrics.PanelLabelsRepaired = runtimeMetrics.PanelLabelsRepaired + repaired
    if elapsed >= 8 then
        runtimeMetrics.SlowPanelRepairs = runtimeMetrics.SlowPanelRepairs + 1
        report("slow panel repair uid=" .. tostring(componentUid or "unknown")
            .. " reason=" .. tostring(reason or "unknown")
            .. " elapsed_ms=" .. string.format("%.2f", elapsed)
            .. " widgets=" .. tostring(runtimeMetrics.WidgetsVisited - visitedBefore)
            .. " labels=" .. tostring(repaired)
            .. " gemini_shards=" .. tostring(runtimeMetrics.GeminiLoads - geminiLoadsBefore)
            .. " gemini_evictions=" .. tostring(runtimeMetrics.GeminiShardEvictions - geminiEvictionsBefore)
            .. " gemini_reloads=" .. tostring(runtimeMetrics.GeminiShardReloads - geminiReloadsBefore)
            .. " source_shards=" .. tostring(runtimeMetrics.SourceShardLoads - sourceLoadsBefore)
            .. " source_evictions=" .. tostring(runtimeMetrics.SourceShardEvictions - sourceEvictionsBefore)
            .. " source_reloads=" .. tostring(runtimeMetrics.SourceShardReloads - sourceReloadsBefore))
    end
    if repaired > 0 then
        local label = tostring(component.uid or component.__cname or reason or "panel")
        local summary = self.Reports[label]
        if summary == nil then
            self.Reports[label] = { Events = 1, Labels = repaired }
            report("event-driven panel repair active for " .. label
                .. "; later instances are aggregated")
        else
            summary.Events = summary.Events + 1
            summary.Labels = summary.Labels + repaired
            runtimeMetrics.PanelRepairReportsSuppressed =
                runtimeMetrics.PanelRepairReportsSuppressed + 1
        end
    end
    return repaired
end

function panelTextRepair:ProcessOnce(component, reason)
    if component == nil then return 0 end
    local rootComponent = component
    local parentReadable = pcall(function()
        local depth = 0
        while rootComponent.parentComponent ~= nil and depth < 64 do
            rootComponent = rootComponent.parentComponent
            depth = depth + 1
        end
    end)
    if parentReadable and rootComponent ~= component then
        runtimeMetrics.NestedComponentSkips = runtimeMetrics.NestedComponentSkips + 1
        if reason == "Refresh" and isDynamicPanelRescan(rootComponent) then
            runtimeMetrics.NestedRefreshCoalesces =
                runtimeMetrics.NestedRefreshCoalesces + 1
            self:Queue(rootComponent, true)
        end
        return 0
    end
    local uid = component.uid or component.UID or component.__cname
    if tostring(uid) == "TaskBoardPanel" then
        runtimeMetrics.TargetedPanelSkips = runtimeMetrics.TargetedPanelSkips + 1
        return 0
    end
    if uid ~= nil and targetedPanelRepairUids[tostring(uid)] then
        runtimeMetrics.TargetedPanelSkips = runtimeMetrics.TargetedPanelSkips + 1
        return 0
    end
    local repeatable = isDynamicPanelRescan(component)
    local key = self:StateKey(component)
    local state = self.States[key]
    if state == nil then
        state = {}
        self.States[key] = state
    end
    local alreadyScanned = state.Scanned == true
    if alreadyScanned and not repeatable then
        return 0
    end
    state.Scanned = true
    if alreadyScanned then
        self:Queue(component, true)
        return 0
    end
    local repaired = self:Repair(component, reason)
    if uid ~= nil and runtimeFixes.SinglePassPanelUids[tostring(uid)] then
        runtimeMetrics.SinglePassPanelSkips = runtimeMetrics.SinglePassPanelSkips + 1
        return repaired
    end
    self:Queue(component, repeatable)
    self:QueueExtended(component)
    return repaired
end

function panelTextRepair:Queue(component, repeatable)
    local key = self:StateKey(component)
    local state = self.States[key]
    if state == nil then
        state = {}
        self.States[key] = state
    elseif state.Pending or (state.DelayedDone and not repeatable) then
        return
    end
    state.Pending = true
    local scheduled = scheduleRepairAfter(component, 0.10, function(liveComponent)
        local liveState = self.States[self:StateKey(liveComponent)]
        if liveState then
            liveState.Pending = false
            if not repeatable then
                liveState.DelayedDone = true
            end
        end
        self:Repair(liveComponent, "delayed")
    end)
    if not scheduled then
        state.Pending = false
    end
end

function panelTextRepair:QueueExtended(component)
    local uid = component and (component.uid or component.UID or component.__cname)
    local delays = uid and extendedPanelRepairDelays[tostring(uid)] or nil
    if delays == nil then
        return
    end
    local key = self:StateKey(component)
    local state = self.States[key]
    if state == nil then
        state = {}
        self.States[key] = state
    elseif state.ExtendedQueued then
        return
    end
    state.ExtendedQueued = true
    for _, delay in ipairs(delays) do
        scheduleRepairAfter(component, delay, function(liveComponent)
            self:Repair(liveComponent, "extended-" .. tostring(delay))
        end)
    end
end

local function installEventDrivenPanelRepair(value, environment)
    local class = getSymbol(value, environment, "UIComponent")
    if type(class) ~= "table" or rawget(class, "__cpddEventTextRepair") == VERSION then
        return false
    end

    local repairErrorReported = false
    for _, methodName in ipairs({ "Open", "Refresh" }) do
        local original = rawget(class, methodName)
        if type(original) == "function" then
            class[methodName] = function(self, ...)
                local results = { original(self, ...) }
                local ok, err = pcall(panelTextRepair.ProcessOnce,
                    panelTextRepair, self, methodName)
                if not ok and not repairErrorReported then
                    repairErrorReported = true
                    report("event-driven panel repair failed safely: " .. tostring(err))
                end
                return unpack(results)
            end
        end
    end
    local function clearComponentCaches(self)
        local rootWidget = nil
        pcall(function()
            panelTextRepair.States[panelTextRepair:StateKey(self)] = nil
            rootWidget = self and (self.userWidget or self.widget)
        end)
        invalidateWidgetCache(rootWidget)
        if rootWidget ~= nil then
            widgetProbeStates[rootWidget] = nil
        end
    end
    for _, methodName in ipairs({ "Close", "Destroy", "OnDestroy", "Dispose" }) do
        local original = rawget(class, methodName)
        if type(original) == "function" then
            class[methodName] = function(self, ...)
                clearComponentCaches(self)
                return original(self, ...)
            end
        end
    end
    class.__cpddEventTextRepair = VERSION
    report("installed event-driven panel text repair")
    return true
end

Loader.AfterLoad(
    "Framework.KGFramework.KGUI.Core.UIComponent",
    function(value, environment)
        installEventDrivenPanelRepair(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.event-driven-panels"
)

local function statisticsEverywhereEnabled()
    local loader = rawget(_G, "LOMModLoader")
    local features = loader and loader.Features
    if type(features) ~= "table" then
        return true
    end
    return features.StatisticsEverywhere ~= false
end

local function installStatisticsEverywhereTarget(target, label)
    if type(target) ~= "table" then
        return false
    end
    if rawget(target, "__cpddStatisticsEverywhereVersion") == VERSION then
        return true
    end

    local original = rawget(target, "CheckSwitchMapStats")
    if type(original) ~= "function" then
        return false
    end

    target.CheckSwitchMapStats = function(...)
        if statisticsEverywhereEnabled() then
            return true
        end
        return original(...)
    end
    target.__cpddStatisticsEverywhereVersion = VERSION
    report("installed Statistics button everywhere hook for " .. tostring(label))
    return true
end

local function installStatisticsEverywhere(value, environment)
    local installed = false
    if type(value) == "table" then
        installed = installStatisticsEverywhereTarget(value, "module") or installed
        installed = installStatisticsEverywhereTarget(rawget(value, "HUDMiddleMenuCheck"), "module.HUDMiddleMenuCheck") or installed
    end
    if type(environment) == "table" and environment ~= value then
        installed = installStatisticsEverywhereTarget(environment, "environment") or installed
        installed = installStatisticsEverywhereTarget(rawget(environment, "HUDMiddleMenuCheck"), "environment.HUDMiddleMenuCheck") or installed
    end
    return value
end

local function setStatisticsEverywhere(enabled)
    local loader = rawget(_G, "LOMModLoader")
    if loader == nil then
        loader = { Features = {} }
        rawset(_G, "LOMModLoader", loader)
    elseif type(loader.Features) ~= "table" then
        loader.Features = {}
    end
    loader.Features.StatisticsEverywhere = enabled == true

    pcall(function()
        if Game and Game.HUDMiddleMenuSystem and Enum and Enum.EHUD_MiddleMenu then
            Game.HUDMiddleMenuSystem:UpdateMiddleMenuBtn(Enum.EHUD_MiddleMenu.SwitchMapStats)
        end
    end)
    return loader.Features.StatisticsEverywhere
end

Loader.AfterLoad(
    "Gameplay.LogicSystem.HUD.HUD_MiddleBtnContent.HUDMiddleMenuCheck",
    installStatisticsEverywhere,
    1000000,
    "cpdd.runtime-fix.statistics-everywhere"
)

Loader.On("after_main", function()
    -- Hooks apply immediately to already-loaded modules and through the loader
    -- for future modules. Reapply only the loaded set; never force-load UI/data
    -- modules during the launch-critical after_main phase.
    if type(Loader.ReapplyAll) == "function" then
        Loader.ReapplyAll()
    end
    report("startup metrics gemini_loads=" .. tostring(runtimeMetrics.GeminiLoads)
        .. " source_shards=" .. tostring(runtimeMetrics.SourceShardLoads)
        .. " widget_indexes=" .. tostring(runtimeMetrics.WidgetIndexesBuilt)
        .. " get_all_widgets=" .. tostring(runtimeMetrics.GetAllWidgetsCalls)
        .. " cache_hits=" .. tostring(runtimeMetrics.TranslationCacheHits + runtimeMetrics.LiveRepairCacheHits)
        .. " cache_misses=" .. tostring(runtimeMetrics.TranslationCacheMisses + runtimeMetrics.LiveRepairCacheMisses))
    end, 1500, "cpdd.runtime-fix.translation-layout")

report("registered v" .. VERSION)
return {
    Version = VERSION,
    PerformanceModeApplied = Loader.Telemetry.PerformanceModeApplied == true,
    RepairLiveText = repairLiveString,
    SetRuntimeRowRepair = setRuntimeRowRepair,
    IsRuntimeRowRepairEnabled = runtimeRowRepairEnabled,
    SetRuntimeUIRepair = setRuntimeUIRepair,
    IsRuntimeUIRepairEnabled = runtimeUIRepairEnabled,
    SetStatisticsEverywhere = setStatisticsEverywhere,
    IsStatisticsEverywhereEnabled = statisticsEverywhereEnabled,
    ResolveAuthoritativeAggregate = runtimeFixes.authoritativeAggregateLookup,
    PerformanceMetrics = runtimeMetrics,
    RepairPanel = function(component) return panelTextRepair:Repair(component, "manual") end,
        }

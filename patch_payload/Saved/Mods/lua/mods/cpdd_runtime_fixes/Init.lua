local Loader = assert(LOMModLoader, "LOMModLoader is required")

local VERSION = "0.9.84"

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
    [413898750559745] = "Наследование аффиксов доступно.\nПерековка откроется через %s дн.",
    [413898750560769] = "Наследование аффиксов доступно.\nПерековка в данный момент недоступна.",
    -- Player Details exposes two distinct mechanics that the old catalog
    -- translated identically. The standalone ShieldBreak property is Armor
    -- Break; the lower DefReduce group and its children are Defense Break.
    [255431368783360] = "Пробивание брони",
    [141494476346368] = "Снижение защиты",
    [255431368777472] = "Снижение физ. защиты",
    [255431368780800] = "Снижение маг. защиты",
    -- Launch 1.1 Esc-menu compact labels. These are the confirmed four-row
    -- values from esc_menu_hotfix_v2 and must win over the external StringDB.
    [74905303409152] = "Исслед.",
    [466331174441472] = "Архив",
    [501378376016640] = "Стиль",
    [514572247120128] = "Марион.",
    [527972545072640] = "Сюжет",
    [625210604657664] = "Связи",
    [712484608544768] = "Победы",
    [774126247610880] = "Снаряж.",
    [774126784481024] = "Релик.",
    [866415967995648] = "Арена",
    [866622663296512] = "Тень",
    [884214580905472] = "Путь",
    [933074128867328] = "Навыки",
    [989630258218752] = "Таланты",
    [1020416583796224] = "Пропуск",
    [1020416583796480] = "Обзор",
    [936784443737600] = "Оценка",
    [936990870604032] = "Награды",
    [1271036247030528] = "Получено",
    [620129389936640] = "Использовать",
    [1073124154021632] = "Настройки авторазбора",
    [1073124154089984] = "Используется",
    [1073124154205952] = "Мои схемы",
    [1073124154228480] = "Подтверждение авторазбора",
    [1073124154229760] = "Официальная схема",
    [1271036247052800] = "Рекомендуемые схемы",
    [1068726107902976] = "Энциклопедия",
    [1271036247021824] = "Нажмите в любом месте, чтобы закрыть",
    [1240251532142337] = [=[1. <Highlight>Заявка в семью:</> Любой Потусторонний, не состоящий в семье, может подать личную заявку для поиска подходящей семьи. Заявка автоматически отзывается через <Highlight>3 дня</> после публикации или после успешного вступления в семью.
2. <Highlight>Отклик на набор:</> Потусторонние без семьи могут начать набор или присоединиться к чужому набору. Инициатор по умолчанию становится <Highlight>Главой семьи</>.
3. <Highlight>Создание семьи:</> Во время отклика на набор семья может быть создана, как только откликнется не менее <Highlight>3 человек</>. При создании глава может настроить название семьи и должности участников.
4. <Highlight>Вступление в семью:</> Если в семье менее <Highlight>14 участников</>, глава может проводить набор. Другие Потусторонние могут подать заявку и вступить после одобрения главой.]=],
    [1271036247235584] = "Схемы снаряжения",
    [312331095508480] = "Комментарии",
    [1068726108208384] = "Цена: %d0%%",
    -- Manor upgrade UI splits these records on commas. Preserve the data
    -- contract instead of using the prose-style colon from the old patch.
    [677369761236481] = "Новая функция открыта,Посетить замок друга",
    [677369761236737] = "Новая функция открыта,Мастерская",
    -- Launch 1.2 EquipmentUniqueData rows 6801-6803. These values are cached
    -- while the data module loads, so translate the authoritative StringDB IDs
    -- in addition to repairing ItemTipsEquipSpecial:SetData below.
    [409365949475072] = "<CostRed>{1,2,(Клеймо неактивно)}</>Усиление навыков увеличено на <Mark>30</>.\nНе действует, пока активен комплект <Mark>Эхо Духа и Знания</>.",
    [409365949475328] = "<CostRed>{1,2,(Клеймо неактивно)}</>После применения навыка снятия контроля дает <Mark>50</> ед. блокирования навыков на <Mark>10</> секунд. Срабатывает не чаще одного раза в <Mark>30</> секунд.\nНе действует, пока активен комплект <Mark>Эхо Духа и Знания</>.",
    [409365949475584] = "<CostRed>{1,2,(Клеймо неактивно)}</>Пробивание брони увеличено на <Mark>80</>. При получении урона есть шанс получить <Mark>60</> ед. защиты на <Mark>5</> секунд. Срабатывает не чаще одного раза в <Mark>10</> секунд.\nНе действует, пока активен комплект <Mark>Эхо Духа и Знания</>.",
    [211107843337216] = "Запечатывающие цепи домена «Двери» обвивают ваше сердце, защищая от смертельного урона. Одиночный удар не может снизить здоровье более чем на 25% от макс. HP.",
    [211107843655936] = [=[Когда боевой навык класса уходит на перезарядку, она мгновенно сбрасывается. Если это заряжаемый навык, восполняются все заряды. Каждый отдельный навык может вызвать этот сброс не чаще одного раза. {CheckStar(Type="sealed",ID=2085021)=1?Сброшенный навык наносит на <Yellow>*f**</> меньше урона и исцеления.}{CheckStar(Type="sealed",ID=2085021)=3?Сброшенный навык дополнительно получает <Yellow>*f**</> к урону и исцелению.}]=],
    [211107844315392] = "Мисс Справедливость стала свидетелем вашего падения и увидела, как вы поднялись вновь. Волю, которую узрели, не так-то просто угасить. Получаемый урон снижен на 30%, а наносимый урон увеличен на 40%.",
    [286012073289984] = "«Чистейшая белизна, спящая в багряном коконе, божественное дитя, правящее перерождением и порчей, последний шанс на исходе времен».",
    [286012610526208] = "«Гав, гав!»",
    [1240251532052225] = "Господин Шут привил вам судьбу из будущего, позволив использовать силу высших Последовательностей. По мере роста вашего могущества разнообразие и мощь изучаемых навыков будут расти. Навыки делятся на три категории: Боевые, Особые и Навыки действия. Вы можете экипировать до четырех Боевых навыков или Навыков действия одновременно. Особые навыки не требуют экипировки и включают Базовую атаку, Снятие контроля и Добивающие навыки.",
}

local splitOverrides = {
    buffappear = {
        [1253512780450048] = "Страх",
    },
    buffdata = {
        [1253512780450048] = "Страх",
    },
    debug = {
        [1169950433818880] = "Войти в Сон",
    },
    monsterskill = {
        [1271036247082752] = "Проекция",
    },
    skill = {
        [1240389776443904] = "Очищающий взмах",
    },
    skill1 = {
        [1240389776521984] = "Звездный удар",
    },
    skill2 = {
        [611398258279936] = "Маяк истории",
    },
    skill3 = {
        [998771022409216] = "Взмах туманности",
    },
    spellfield = {
        [1068726107518720] = "Подсказка",
    },
}

local stringConstOverrides = {
    BAG_AUTO_AUTO_RESOLVE_TITLE = "Подтверждение авторазбора",
    BAG_AUTO_DECOMPOSE_TITLE = "Настройки авторазбора",
    COMMENT_PANEL_TITLE = "Комментарии",
    DIALOGUE_SKIP = "Пропустить",
    EQUIPMENT_PLAN_APPLY_CURRENT_PLAN = "Применить схему",
    FASHION_APPEARANCE = "Внешний вид",
    FASHION_DYE_MY_PLAN = "Мои схемы",
    GUILD_CARGO_HUB_REWARD_COMPLETE = "Получено",
    GVG_HONOR_CLAIMED_TEXT = "Получено",
    ITEM_GOT = "Получено",
    MONTH_CARD_MAIN_PAGE_TODAY_RECEIVED_LABEL = "(Получено сегодня)",
    FAMILY_INVITE_SHARE_TEAM = "Канал группы",
    FAMILY_INVITE_SHARE_WORLD = "Мировой канал",
    FAMILY_MEMBER_COUNT_FMT = "Текущие члены семьи: %s/14",
    FAMILY_MEMBER_FMT = "Члены семьи (%d/%d)",
    ONE_CLICK_IN_USE = "Используется",
    ONE_CLICK_RECOMMEND_PLAN = "Официальная схема",
    ONE_CLICK_SHARE_RECOMMEND_PLAN = "Рекомендуемые схемы",
    ONE_CLICK_TITLE = "Автопомощь",
    ONE_CLICK_USE = "Использовать",
    TRAINTRADE_ITEM_DISCOUNT_CHINESE = "Цена: %d0%%",
    MAP_PVP_LAST_HUNT_DRAGON_BOSS_BELONG_FORMAT = "Принадлежность: <Green>%s</>",
    MAP_PVP_LAST_HUNT_DRAGON_BOSS_NAME = "Проекция дракона",
    MAP_PVP_LAST_HUNT_DRAGON_BOSS_NOT_BELONG_FORMAT = "Принадлежность: <Red>%s</>",
    PVP_LAST_HUNT_ACTIVE_TIME_FORMAT = "Активация через %M:%S",
    PVP_LAST_HUNT_ACTIVITY_NOT_OPEN_TEXT = "Используйте <Highlight>Семя вздохов</>, чтобы активировать Силу вздохов, начать задание вздохов и получить щедрые награды за его выполнение.",
    PVP_LAST_HUNT_ACTIVITY_OPEN_FORMAT = "Начнется через %H ч. %M мин.",
    PVP_LAST_HUNT_ACTIVITY_OPEN_TEXT = "Время начала события",
    PVP_LAST_HUNT_ACTIVITY_REWARD_PREVIEW_FORMAT = "Награды за задание",
    PVP_LAST_HUNT_BOSS_BUTTON_DESC = "Перейти",
    PVP_LAST_HUNT_BOSS_CONTENT_DESC = "Дракон Королевского Города (описание)",
    PVP_LAST_HUNT_BOSS_DETAIL_CONDITION_TITLE = "Статус обновления",
    PVP_LAST_HUNT_BOSS_DETAIL_CONTENT = "Побеждайте элитных монстров, чтобы заработать ценные награды",
    PVP_LAST_HUNT_BOSS_DETAIL_NOT_SPAWNED = "Цель еще не появилась",
    PVP_LAST_HUNT_BOSS_DETAIL_SPAWNED = "Цель появилась",
    PVP_LAST_HUNT_BOSS_DETAIL_TITLE = "Цель охоты",
    PVP_LAST_HUNT_BOSS_DRAGON_FORMAT = "Дракон появится через %M:%S",
    PVP_LAST_HUNT_BOSS_SECOND_TITLE = "Победите Дракона Королевского Города",
    PVP_LAST_HUNT_BOSS_TAG_NAME = "Страж Королевского Города",
    PVP_LAST_HUNT_BOSS_TITLE = "Убить дракона",
    PVP_LAST_HUNT_CAMP_SUBMIT_FORMAT = "Точка сдачи лагеря %s",
    PVP_LAST_HUNT_CHAT_BUTTON_TEXT = "Перейти",
    PVP_LAST_HUNT_CHAT_TITLE = "Горн",
    PVP_LAST_HUNT_CROSS_SERVER_SCORE_TITLE = "Военные заслуги",
    PVP_LAST_HUNT_DETAIL_MY_DATA_TAB = "Мои данные",
    PVP_LAST_HUNT_DETAIL_RANK_TAB = "Рейтинг",
    PVP_LAST_HUNT_FIGHT_ASSISTANT_FORMAT = "%s повержен игроком %s в %s. Требуется помощь!",
    PVP_LAST_HUNT_FIGHT_KILL_RESULT_FORMAT = "%s успешно выследил %s в %s!",
    PVP_LAST_HUNT_GUILD_ACTIVITY_DESC_TIPS = "Рейд на дракона в Финальной охоте <Highlight>[Аукцион команды]</>: %d/%d (в эту пятницу) в 19:10",
    PVP_LAST_HUNT_GUILD_NAME_FORMAT = "Клуб <Enemy_Name>%s</>",
    PVP_LAST_HUNT_HIGHER_DETAIL_CONTENT = "Зона повышенной сложности с множеством вышедших из-под контроля монстров",
    PVP_LAST_HUNT_HIGHER_DETAIL_NOT_OPENED_TITLE = "Сейчас закрыто",
    PVP_LAST_HUNT_HIGHER_DETAIL_OPENED_TIME = "Открыто ежедневно: 19:00-21:00\nДополнительно: сб и вс, 14:00-16:00",
    PVP_LAST_HUNT_HIGHER_DETAIL_TITLE_NAME = "Продвинутый · Прилив",
    PVP_LAST_HUNT_HUD_PROGRESS_CURRENCY_FORMAT = "<Highlight>%s</>/%s",
    PVP_LAST_HUNT_HUD_PROGRESS_FORMAT = "<Highlight>%d</>/%d",
    PVP_LAST_HUNT_ITEM_CAN_NOT_USE = "Недостаточно предметов",
    PVP_LAST_HUNT_LACK_USE_ITEM_PROP_COUNT_FORMAT = "Осталось попыток: %s",
    PVP_LAST_HUNT_MAIN_PROGRESS_TITLE = "Предпросмотр наград",
    PVP_LAST_HUNT_MAP_DETAIL_DESC = "Вход в телепорт зоны фракции",
    PVP_LAST_HUNT_MAP_ITEM_NAME = "Семя вздохов · Зона прилива монстров",
    PVP_LAST_HUNT_MEMBER_COUNT_FORMAT = "(Члены группы: %d/%d)",
    PVP_LAST_HUNT_MONSTER_CANCEL_BUTTON_NAME = "Отмена",
    PVP_LAST_HUNT_MONSTER_DROP_REWARD_TEXT = "Шанс выпадения с побежденных <HyperLink stylename=\"Clickable\" u=\"\">обычных монстров</>",
    PVP_LAST_HUNT_MONSTER_DROP_REWARD_UNDERLINE_TEXT = "Шанс выпадения с побежденных <HyperLink stylename=\"Underline\" u=\"\">обычных монстров</>",
    PVP_LAST_HUNT_MONSTER_RECOMMEND_GROUP = "Рекомендуется рейд",
    PVP_LAST_HUNT_MONSTER_RECOMMEND_TEAM = "Рекомендуется группа",
    PVP_LAST_HUNT_MONSTER_SUMMON_BUTTON_NAME = "Призвать",
    PVP_LAST_HUNT_MONSTER_SUMMON_LEFT_COUNT_FORMAT = "Осталось призывов на этой неделе: %d",
    PVP_LAST_HUNT_NOT_OPENED_BUTTON_TEXT = "Доступно после начала события",
    PVP_LAST_HUNT_RANK_TAB_GUILD_NAME = "Клуб",
    PVP_LAST_HUNT_RANK_TAB_PERSONAL_NAME = "Личный",
    PVP_LAST_HUNT_RESURGENCE_TIPS = "Выберите точку возрождения и нажмите «Перейти»",
    PVP_LAST_HUNT_RESURGENCE_TITLE = "Выбор точки возрождения",
    PVP_LAST_HUNT_REVIVE_BUTTON_NAME = "Возродиться",
    PVP_LAST_HUNT_REWARD_PREVIEW_TITLE = "Награды за задание",
    PVP_LAST_HUNT_SCORE_TITLE = "Очки рейтинга",
    PVP_LAST_HUNT_SEND_BUTTON_TITLE = "Отправить горн",
    PVP_LAST_HUNT_SEND_CHAT_DEFAULT_TEXT = "Братья, на помощь!",
    PVP_LAST_HUNT_SEND_DEFAULT_TIP_TEXT = "Призвать до %d игроков",
    PVP_LAST_HUNT_SEND_PANEL_TIPS = "Призвать до 14 игроков",
    PVP_LAST_HUNT_SEND_PANEL_TITLE = "Отправить горн",
    PVP_LAST_HUNT_SETTLE_MENT_ASSIST_NUM_TITLE = "Помощь",
    PVP_LAST_HUNT_SETTLE_MENT_CANCEL = "Отмена",
    PVP_LAST_HUNT_SETTLE_MENT_KILL_NUM_TITLE = "Убийства",
    PVP_LAST_HUNT_SETTLE_MENT_LEAVE = "Покинуть",
    PVP_LAST_HUNT_SETTLE_MENT_PROGRESS_NUM_TITLE = "Итоги охоты",
    PVP_LAST_HUNT_SETTLE_MENT_SCORE_NUM_TITLE = "Очки рейтинга",
    PVP_LAST_HUNT_SETTLE_MENT_TITLE = "Итоги охоты",
    PVP_LAST_HUNT_SUBMIT_CONTENT = "Сдайте материалы Алых реликвий в обмен на купоны охоты",
    PVP_LAST_HUNT_SUBMIT_REFRESH_DESC = "Дворецкий охоты меняет положение на карте каждые 30 минут. При ожесточенных боях появляется больше дворецких.",
    PVP_LAST_HUNT_SUBMIT_REFRESH_TITLE = "Правила обновления",
    PVP_LAST_HUNT_SUBMIT_TITLE = "Дворецкий охоты",
    PVP_LAST_HUNT_SUMMON_AUTHOER_FORMAT = "(Призвал: %s)",
    PVP_LAST_HUNT_SUMMON_MONSTER_GET_NUM = "Получено попыток",
    PVP_LAST_HUNT_SUMMON_MONSTER_LACK_NUM = "Попыток на этой неделе не осталось. Зарабатывайте купоны охоты, чтобы получить больше.",
    PVP_LAST_HUNT_TASK_BUFF_NAME = "Сила вздохов",
    PVP_LAST_HUNT_TASK_COMMIT_TEXT = "Сдать",
    PVP_LAST_HUNT_TASK_FINISH_TITLE_TEXT = "Завершено",
    PVP_LAST_HUNT_TASK_FRAGMENT_NAME = "Осколок добычи",
    PVP_LAST_HUNT_TASK_NOT_ACTIVE_CONTENT_TEXT = "Используйте Семя вздохов, побеждайте монстров или грабьте игроков, чтобы добыть осколки добычи, затем сдайте их Графу Порядка за награду.",
    PVP_LAST_HUNT_TASK_NOT_ACTIVE_FINISH_TEXT = "Задание завершено. Найдите Графа Порядка, чтобы сдать осколки и получить награду.",
    PVP_LAST_HUNT_TASK_NOT_ACTIVE_TEXT = "Неактивно",
    PVP_LAST_HUNT_TASK_PROGRESS_TEXT = "Прогресс охоты",
    PVP_LAST_HUNT_TASK_PROP_TEXT = "Семя вздохов",
    PVP_LAST_HUNT_TASK_QUICK_TEAM = "Быстрая группа",
    PVP_LAST_HUNT_TASK_TITLE_NAME = "Финальная охота",
    PVP_LAST_HUNT_TITLE_DETAIL_NAME = "Подробнее",
    PVP_LAST_HUNT_TITLE_FOLD_NAME = "Свернуть",
    PVP_LAST_HUNT_USE_ITEM_NOT_ACTIVITY_OPEN_FORMAT = "Нельзя использовать вне времени события. Время события: <highlight>%s-%s</>",
    PVP_LAST_HUNT_USE_ITEM_PROP_DESC = "Использование Семени вздохов...",
    PVP_LAST_HUNT_USE_TASK_TEXT_NAME = "Взять задание",
    RED_PACKET_ALREADY_RECEIVED = "Получено",
    SECRET_PARTNER_BTN_ALREADY_CHANGE_ACTOR_NAME = "Смена...",
    SECRET_PARTNER_BTN_CHANGE_ACTOR_NAME = "Сменить",
    SECRET_PARTNER_CANCEL_CHANGE_ACTOR = "Отменить смену",
    SECRET_PARTNER_CHANGE_ACTOR_TITLE = "Цель смены",
    SECRET_PARTNER_SKILL_TEXT = "Навык марионетки",
    SECRET_PARTNER_STAR_UP_TEXT_FORMAT = "Последовательность %d",
    SKILL_PRESET_TAB_1 = "Рекомендуемые схемы",
    TASK_TRACE_DISTANCE = "м",
    TRINITY_ALL_TREASURE_HAVE_CLAIMED = "Все награды получены",
    TEAM_INVITE_SECRET_PARTNER_TITLE = "Заявка иллюзии",
    UIAPPEARANCE_USE = "Использовать",
    UIAPPEARANCE_USING = "Используется",
}

-- This quest validates the literal Chinese chat input server-side. Keep only
-- the password Chinese so the surrounding quest instructions remain English.
local function shortenEnterWorldLabel(value)
    if value == "Enter the Extraordinary World" then
        return "Enter World"
    end
    return value
end

local function restoreQuestChatPassword(value)
    local pwEn = "The storm is stronger than spirits"
    local pwZh = "风暴比烈酒更烈"
    if type(value) ~= "string" or not value:find(pwEn, 1, true) then
        return value
    end
    return value:gsub(pwEn, function()
        return pwZh
    end)
end

-- These strings are emitted by Launch 1.2 dialogue/widgets without a stable
-- StringDB key. Keep the replacements exact or narrowly scoped so the
-- aggregate entry for 米 (which legitimately means "Rice" in chat/filter
-- data) is not changed globally.
local visibleTextExactOverrides = {
    -- Canonical faction & synergy aliases
    ["Bulwark"] = "Оплот",
    ["[Bulwark]"] = "[Оплот]",
    ["坚阵"] = "Оплот",
    ["【坚阵】"] = "【Оплот】",
    ["Crafted Bulwark"] = "Искусный оплот",
    ["[Crafted Bulwark]"] = "[Искусный оплот]",
    ["精工壁垒"] = "Искусный оплот",
    ["【精工壁垒】"] = "【Искусный оплот】",
    ["Evernight Goddess Church"] = "Церковь Богини Вечной Ночи",
    ["[Evernight Goddess Church]"] = "[Церковь Богини Вечной Ночи]",
    ["黑夜女神教会"] = "Церковь Богини Вечной Ночи",
    ["【黑夜女神教会】"] = "【Церковь Богини Вечной Ночи】",
    ["Evernight Goddess"] = "Богиня Вечной Ночи",
    ["[Evernight Goddess]"] = "[Богиня Вечной Ночи]",
    ["黑夜女神"] = "Богиня Вечной Ночи",
    ["【黑夜女神】"] = "【Богиня Вечной Ночи】",

    -- Relics tab labels
    ["Common"] = "Обычные",
    ["Special"] = "Особенные",
    ["特殊"] = "Особенные",
    ["Особенный"] = "Особенные",
    ["Attack Sealed Artifact"] = "Атакующий",
    ["攻击封印物"] = "Атакующий",
    ["Атаковать запечатанный объект"] = "Атакующий",
    ["Defense Sealed Artifact"] = "Защитный",
    ["防御封印物"] = "Защитный",
    ["Запечатанный Защитным Артефакт"] = "Защитный",
    ["Specialized Sealed Artifact"] = "Специальный",
    ["特化封印物"] = "Специальный",
    ["Специализированный запечатанный артефакт"] = "Специальный",
    ["Beyonder Knowledge"] = "Знания",
    ["非凡知识"] = "Знания",
    ["Потусторонние знания"] = "Знания",

    -- Marionettes tab labels
    ["上阵"] = "Установить",
    ["Deploy"] = "Установить",
    ["Развертывать"] = "Установить",
    ["Развёртывать"] = "Установить",
    ["基础"] = "Список",
    ["Basic"] = "Список",
    ["Базовый"] = "Список",
    ["旅行"] = "Путешествие",
    ["游历"] = "Путешествие",
    ["Путешествовать"] = "Путешествие",
    ["获取秘偶"] = "Приручить",
    ["获得秘偶"] = "Приручить",
    ["Obtain marionette"] = "Приручить",
    ["Obtain Marionette"] = "Приручить",
    ["Получить марионетку"] = "Приручить",
    ["Приручить марионетку"] = "Приручить",

    -- Equipment
    ["穿戴"] = "Надето",
    ["Wear"] = "Надето",
    ["Носить"] = "Надето",

    -- Shop category tabs
    ["百货"] = "Универсальный",
    ["General Store"] = "Универсальный",
    ["Универсальный магазин"] = "Универсальный",
    ["凯旋商店"] = "Триумф",
    ["Triumph Shop"] = "Триумф",
    ["Магазин Триумф"] = "Триумф",
    ["交易集市"] = "Базар",
    ["Trading Bazaar"] = "Базар",
    ["Торговый базар"] = "Базар",
    ["报销商店"] = "Возвратный",
    ["Reimbursement Shop"] = "Возвратный",
    ["Возвратный магазин"] = "Возвратный",
    ["同行商店"] = "Сопутствующий",
    ["Companion Shop"] = "Сопутствующий",
    ["Сопутствующий магазин"] = "Сопутствующий",
    ["冒险商店"] = "Приключения",
    ["Adventure Shop"] = "Приключения",
    ["Магазин приключений"] = "Приключения",
    ["药品百货"] = "Медикаменты",
    ["Medicine Department Store"] = "Медикаменты",
    ["Медицинский универмаг"] = "Медикаменты",
    ["转运商店"] = "Фортуна",
    ["Fortune Shop"] = "Фортуна",
    ["Магазин Фортуны"] = "Фортуна",
    ["往事陈列馆"] = "Зал воспоминаний",
    ["Past Exhibition Hall"] = "Зал воспоминаний",
    ["Прошлый выставочный зал"] = "Зал воспоминаний",
    ["外观转换"] = "Смена облика",
    ["Appearance Conversion"] = "Смена облика",
    ["Преобразование внешнего вида"] = "Смена облика",

    -- AutoChess roles, synergies, augments, items & UI
    ["Ranged Marksman"] = "Стрелок дальнего боя",
    ["Mid-row Support"] = "Поддержка среднего ряда",
    ["Melee Support"] = "Поддержка ближнего боя",
    ["Ranged Mage"] = "Маг дальнего боя",
    ["Melee Warrior"] = "Воин ближнего боя",
    ["Frontline Tank"] = "Передовой танк",
    ["Melee Tank"] = "Танк ближнего боя",
    ["Melee Assassin"] = "Убийца ближнего боя",
    ["Ranged Assassin"] = "Убийца дальнего боя",
    ["Ranged Support"] = "Поддержка дальнего боя",
    ["Frontline Warrior"] = "Передовой воин",
    ["Frontline Support"] = "Передовая поддержка",
    ["Frontline Assassin"] = "Убийца передовой",
    ["Backline Marksman"] = "Стрелок заднего ряда",
    ["Backline Mage"] = "Маг заднего ряда",
    ["Backline Support"] = "Поддержка заднего ряда",
    ["Backline Assassin"] = "Убийца заднего ряда",
    ["Mid-row Mage"] = "Маг среднего ряда",
    ["Mid-row Warrior"] = "Воин среднего ряда",
    ["Mid-row Marksman"] = "Стрелок среднего ряда",
    ["Mid-row Tank"] = "Танк среднего ряда",
    ["Mid-row Assassin"] = "Убийца среднего ряда",
    ["Starts [Extraordinary Quests], increasing the probability of Extraordinary Quests appearing each round; upon completing a quest, gain an [Extraordinary Chest]"] =
        "Начинает [Потусторонние задания], увеличивая вероятность появления Потусторонних заданий в каждом раунде; после выполнения задания вы получаете [Потусторонний сундук]",
    ["3 Starts [Extraordinary Quests], increasing the probability of Extraordinary Quests appearing each round; upon completing a quest, gain an [Extraordinary Chest]"] =
        "3 Начинает [Потусторонние задания], увеличивая вероятность появления Потусторонних заданий в каждом раунде; после выполнения задания вы получаете [Потусторонний сундук]",
    ["5 At the start of player combat: Restore 2 Health to the player."] =
        "5 В начале боя с игроком: восстанавливает 2 ед. здоровья игроку.",
    ["7 At the start of player combat: Restore 2 Health to the player. Gain 50 [Quest Points] upon victory."] =
        "7 В начале боя с игроком: восстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе.",
    ["Divinity Spread"] = "Распространение божественности",
    ["Economy"] = "Экономика",
    ["Iron and Blood Badge"] = "Знак Железа и Крови",
    ["Mutual Guard"] = "Взаимная защита",
    ["Mysticism Page"] = "Страница мистицизма",
    ["Rare · Life Crystal Pendant"] = "Редкий · Кулон кристалла жизни",
    ["Traction Spirit Pendant"] = "Кулон притяжения духов",
    ["Star Lotus Seal"] = "Печать Звездного Лотоса",
    ["Star Lotus Holy Seal"] = "Священная печать Звездного Лотоса",
    ["Star Lotus"] = "Звездный Лотос",
    ["12 seconds after the battle starts<HighLight></>, your pieces gain 35% Damage Deepening<HighLight></>."] =
        "Через 12 сек. после начала боя<HighLight></> ваши фигуры получают 35% к увеличению урона<HighLight></>.",
    ["Each Basic Attack restores <HighLight>3</> Mana; when dealing a Critical Hit, restore an additional <HighLight>4</> Mana."] =
        "Каждая базовая атака восстанавливает <HighLight>3</> ед. маны; при критическом ударе восстанавливает дополнительно <HighLight>4</> ед. маны.",
    ["Gain <HighLight> two 1-cost chess pieces </>, <HighLight> two 2-cost chess pieces </>, and <HighLight> one 3-cost chess piece </>."] =
        "Получите <HighLight> две фигуры стоимостью 1 </>, <HighLight> две фигуры стоимостью 2 </> и <HighLight> одну фигуру стоимостью 3 </>.",
    ["If there are exactly 2 ally pieces in the first row<HighLight></>, both gain 150 Health<HighLight></> and 20 Defense<HighLight></>."] =
        "Если в первом ряду ровно 2 союзные фигуры<HighLight></>, обе получают 150 ед. здоровья<HighLight></> и 20 ед. защиты<HighLight></>.",
    ["Randomly gain <HighLight> one basic equipment </>, and gain <HighLight> one Fine Equipment Casket </>, <HighLight> one Equipment Reforger </>, and <HighLight> 3 Gold Coins </>."] =
        "Случайным образом получите <HighLight> одно базовое снаряжение </>, а также <HighLight> один ларец с отличным снаряжением </>, <HighLight> один перековщик снаряжения </> и <HighLight> 3 золотые монеты </>.",
    ["保存阵容"] = "Сохранить состав",
    ["未编辑保存阵容"] = "Состав не сохранен",
    ["编辑阵容"] = "Изменить состав",
    ["槽位未解锁"] = "Ячейка заблокирована",
    ["卡牌名字七个字"] = "Имя карты семь букв",
    ["施法后的<HighLight>5</>秒内，下一次普攻额外造成相当于<HighLight>120%</>攻击的伤害，冷却时间为<HighLight>4</>秒。"] =
        "В течение <HighLight>5</> сек. после применения навыка следующая базовая атака дополнительно наносит урон в размере <HighLight>120%</> от атаки, время перезарядки — <HighLight>4</> сек.",
    ["每秒恢复<HighLight>4%</>最大生命值。"] =
        "Восстанавливает <HighLight>4%</> от максимального запаса здоровья в секунду.",
    ["获得【铁血】共鸣。每隔<HighLight>2</>秒，对<HighLight>1</>格内至多<HighLight>3</>名敌人造成相当于自身生命值<HighLight>1%</>的伤害。"] =
        "Получает резонанс 【Железо и Кровь】. Каждые <HighLight>2</> сек. наносит до <HighLight>3</> врагам в пределах <HighLight>1</> клетки урон, равный <HighLight>1%</> от собственного здоровья.",
    ["获得【铁血】共鸣。每隔2秒，对1格内至多3名敌人造成相当于自身生命值1%的伤害。"] =
        "Получает резонанс 【Железо и Кровь】. Каждые 2 сек. наносит до 3 врагам в пределах 1 клетки урон, равный 1% от собственного здоровья.",

    ["Exclusive Sequence Quest"] = "Особое задание Последовательности",
    ["Exclusive Sequence Quest "] = "Особое задание Последовательности",
    ["Quest description quest description quest description"] = "Описание задания...",
    ["Go to"] = "Перейти",
    ["Completed"] = "Завершено",
    ["剧情总览"] = "Обзор сюжета",
    ["Plot Overview"] = "Обзор сюжета",
    ["Plot Overview "] = "Обзор сюжета",
    ["PLOT OVERVIEW"] = "ОБЗОР СЮЖЕТА",
    [" PLOT OVERVIEW "] = "ОБЗОР СЮЖЕТА",
    ["命运道标"] = "Маяк Судьбы",
    ["Beacon of Destiny"] = "Маяк Судьбы",
    ["Bacon of Destiny"] = "Маяк Судьбы",
    ["“正义”和“倒吊人”开始默写记忆中的文字……"] =
        "«Справедливость» и «Висельник» начинают записывать по памяти текст...",
    ["两位先生离开了，不知何时才能看到这充满风采的照片……"] =
        "Оба джентльмена ушли. Кто знает, когда мне доведется увидеть эту великолепную фотографию...",
    ["机动"] = "Мобильность",
    ["射程"] = "Дальность",
    ["Win by Lying Down"] = "Легкая победа",
    ["在<h>【附近】/【世界】</>聊天栏中打字输入“<HyperLink stylename=\"h\">风暴比烈酒更烈</>”"] =
        "Напишите в чате <h>[Рядом]/[Мир]</> фразу: «<HyperLink stylename=\"h\">Буря крепче крепкого эля</>»",
    ["所向披靡，无往不利！{{player.name}}在<Chat_Highlight>{{gameMode.name}}</>中获得<Chat_Highlight>{{eventMessageParams.curWinStreak}}连胜</>，战场之上，新的神话已在书写！"] =
        "Непобедимый и неудержимый! {{player.name}} одерживает серию из <Chat_Highlight>{{eventMessageParams.curWinStreak}} побед</> в режиме <Chat_Highlight>{{gameMode.name}}</>! На поле боя пишется новая легенда!",
    ["Invincible and unstoppable! {{player.name}} has achieved a <Chat_Highlight>{{eventMessageParams.curWinStreak}} win streak in <Chat_Highlight>{{gameMode.name}}</>! On the battlefield, a new legend is being written!</>"] =
        "Непобедимый и неудержимый! {{player.name}} одерживает серию из <Chat_Highlight>{{eventMessageParams.curWinStreak}} побед</> в режиме <Chat_Highlight>{{gameMode.name}}</>! На поле боя пишется новая легенда!",
    ["推理检定"] = "Проверка дедукции",
    ["发现它变成了一份地图，还标注了奇迹降临的位置……"] =
        "Вы обнаружили, что она превратилась в карту с отметкой места, где свершится чудо...",
    ["沙利亚特"] = "Шариат",
    ["迪尼特"] = "Динит",
    ["罗、罗茜！你今天过得好吗？"] = "Р-Рози! Как твои дела сегодня?",
    ["罗、罗茜！你今天过得好吗?"] = "Р-Рози! Как твои дела сегодня?",
    ["啊，弗雷泽！我很好，这束花是……"] =
        "Ох, Фрейзер! Всё хорошо. Этот букет...",
    ["啊，弗雷泽！我很好，这束花是......"] =
        "Ох, Фрейзер! Всё хорошо. Этот букет...",
    ["啊，弗雷泽！我很好，这束花是..."] =
        "Ох, Фрейзер! Всё хорошо. Этот букет...",
    ["我想把它送给你，其实，我对你……"] =
        "Я хотел подарить его тебе. На самом деле, я к тебе...",
    ["我想把它送给你，其实，我对你......"] =
        "Я хотел подарить его тебе. На самом деле, я к тебе...",
    ["我想把它送给你，其实，我对你..."] =
        "Я хотел подарить его тебе. На самом деле, я к тебе...",
    ["跳过"] = "Пропустить",
    ["回顾"] = "История",
    ["截图"] = "Скриншот",
    ["点击空白区域关闭"] = "Нажмите в любом месте, чтобы закрыть",
    ["点击任意区域跳过"] = "Нажмите в любом месте, чтобы пропустить",
    ["恭喜获得"] = "Поздравляем с получением",
    ["转化"] = "Преобразовать",
    ["男子"] = "Мужчина",
    ["丑人"] = "Уродливый",
    ["愚者"] = "Шут",
    ["“愚者”"] = "«Шут»",
    ["塞巴斯蒂安"] = "Себастьян",
    ["寒巴斯蒂安"] = "Себастьян",
    ["非凡评分"] = "Оценка Потустороннего",
    ["再战·一号信徒"] = "Реванш: Верующий Номер Один",
    ["推荐非凡评分"] = "Рекомендуемая оценка",
    ["奖励预览"] = "Предпросмотр наград",
    ["目标点数"] = "Целевые очки",
    ["黎明降临"] = "Пришествие Рассвета",
    ["Dawn Arrival"] = "Пришествие Рассвета",
    ["仲裁烙印"] = "Клеймо Арбитража",
    ["Arbitration Brand"] = "Клеймо Арбитража",
    ["窥秘凝视"] = "Взор Подглядывающего",
    ["Mystery Pry Gaze"] = "Взор Подглядывающего",
    ["晨曦守护"] = "Защита Утреннего Света",
    ["Morning Light Protection"] = "Защита Утреннего Света",
    ["骑士誓约"] = "Клятва Рыцаря",
    ["Knight's Oath"] = "Клятва Рыцаря",
    ["蝶灵附身"] = "Одержимость Духа-Бабочки",
    ["Butterfly Spirit Possession"] = "Одержимость Духа-Бабочки",
    ["丧钟回响"] = "Эхо Похоронного Звона",
    ["Death Knell Echo"] = "Эхо Похоронного Звона",
    ["头狼连爪"] = "Серия Когтей Альфа-Волка",
    ["Alpha Wolf Claw Combo"] = "Серия Когтей Альфа-Волка",
    ["钻头守护"] = "Защитная Дрель",
    ["Drill Protection"] = "Защитная Дрель",
    ["未拥有"] = "Не получено",
    ["推荐方案"] = "Рекомендуемые схемы",
    ["Recommended Builds"] = "Рекомендуемые схемы",
    ["官方推荐方案"] = "Официальная рекомендуемая схема",
    ["Official Recommended Build"] = "Официальная рекомендуемая схема",
    ["我的方案"] = "Мои схемы",
    ["My Builds"] = "Мои схемы",
    ["我要变强"] = "Усиление",
    ["要变强"] = "Усиление",
    ["已领取"] = "Получено",
    ["今日已领取"] = "Получено сегодня",
    ["奖励已领取"] = "Награда получена",
    ["已领取全部奖励"] = "Все награды получены",
    ["使用"] = "Использовать",
    ["使用中"] = "Используется",
    ["图鉴"] = "Энциклопедия",
    ["跟随卡萝，来到了工厂区。"] = "Следуйте за Кэрол в Заводской район.",
    ["全部重置"] = "Сбросить всё",
    ["装备方案"] = "Схемы снаряжения",
    ["Equipment Builds"] = "Схемы снаряжения",
    ["自动分解"] = "Авторазбор",
    ["获得方式"] = "Способ получения",
    ["下一级效果"] = "Эффект следующего уровня",
    ["在目标位置召唤窥秘之眼，对目标造成持续伤害和减速。"] =
        "Призывает Око Тайны в указанной области, нанося цели периодический урон и замедляя ее.",
    ["感知灵界，观测星空，通过灵性物品启示的命运变化，解读其映射的现实空间异动、事态发展走向与潜在未知危险。"] =
        "Ощущайте духовный мир, наблюдайте за звездами. Толкуйте изменения судьбы, открываемые духовными предметами, чтобы распознавать отраженные ими возмущения в реальном мире, развитие событий и скрытые неведомые опасности.",
    ["占星启示期间，周围的玩家可以获得临时技能来获取占星指引。"] =
        "Во время Астрологического откровения окружающие игроки могут получить временный навык для получения астрологических указаний.",
    ["使自身获得武力加4，直觉加2。使用临时技能获取占星指引的玩家也可以获得武力加4，直觉加2。"] =
        "Дает персонажу +4 к Силе и +2 к Интуиции. Игроки, использующие временный навык для получения астрологических указаний, также получают +4 к Силе и +2 к Интуиции.",
    ["木桩训练"] = "Тренировочный манекен",
    ["Training Dummy"] = "Тренировочный манекен",
    ["一键辅助"] = "Автопомощь",
    ["家族任务"] = "Задания семьи",
    ["你尚未加入任何家族"] = "Вы еще не вступили ни в одну семью.",
    ["[队伍]"] = "[Группа]",
    ["【附身能力】"] = "【Способность вселения】",
    ["请选择要使用【灵体之线】的对象"] = "Выберите цель для использования [Нитей духовного тела]",
    ["附身剩余时间"] = "Оставшееся время вселения",
    ["秘偶属性生效总览"] = "Обзор действующих атрибутов марионетки",
    ["本频道可用传音发言"] = "В этом канале можно использовать голосовую передачу",
    ["本频道无法发言"] = "В этом канале нельзя отправлять сообщения",
    ["但我们的数据——"] = "Но наши данные...",
    ["哼唧！哼唧……"] = "Хрю-хрю! Хрю...",
    ["嗯……都行。"] = "Хм... пойдет.",
    ["坏了，我可能把<P_Yellow>生物催长剂</>当成椰蓉洒在蛋糕上了！"] =
        "Беда! Кажется, я насыпал на торт <P_Yellow>биостимулятор роста</> вместо кокосовой стружки!",
    ["培根……你真是救我于水火啊……"] = "Бэкон... ты правда спас меня из беды...",
    ["培根……培根怎么回事？？"] = "Бэкон... что с Бэконом?!",
    ["太好了！拿到数据了！"] = "Отлично! Данные получены!",
    ["好了。下次再来！"] = "Готово. Приходите еще!",
    ["情况有点失控了！跑啊！"] = "Ситуация выходит из-под контроля! Бежим!",
    ["第一次来吗？要什么口味？"] = "Впервые здесь? Какой вкус желаете?",
    ["等下我就买一大堆小蛋糕给你！"] = "Скоро я куплю тебе кучу пирожных!",
    ["那就给你最经典的那种吧。"] = "Тогда держи классический вариант.",
    ["霍伊大学赛艇队招新！"] = "Набор в команду по гребле Университета Хоя!",
    ["成员列表"] = "Список участников",
    ["俱乐部会长"] = "Президент клуба",
    ["正式成员"] = "Действительный член",
    ["候补成员"] = "Кандидат",
    ["可预存"] = "Доступно накопление",
    ["已预存"] = "Накоплено",
    ["新手"] = "Новичок",
    ["赛季剧情"] = "Сюжет сезона",
    ["提交可获得猎杀进度"] = "Сдайте для получения прогресса охоты",
    ["可获得猎杀进度"] = "Можно получить прогресс охоты",
    ["当前进度："] = "Текущий прогресс:",
    ["当前进度:"] = "Текущий прогресс:",
    ["击杀"] = "Убийства",
    ["助攻"] = "Помощь",
    ["排行榜"] = "Рейтинг",
    ["技能名称"] = "Название навыка",
    ["次数"] = "Количество",
    ["伤害量"] = "Урон",
    ["伤害来源"] = "Источник урона",
    ["寄售"] = "Комиссионка",
    ["终末猎杀"] = "Финальная охота",
    ["主宰争锋"] = "Битва владык",
    ["主宰之战"] = "Битва владык",
    ["副本"] = "Подземелье",
    ["秩序世界"] = "Мир Порядка",
    ["本周获取上限"] = "Недельный лимит",
    ["城市暗面"] = "Изнанка города",
    ["新"] = "Новое",
    ["同家族/俱乐部队员达到3人及以上"] = "3 и более участников из одной семьи/клуба",
    ["对比"] = "Сравнить",
    ["进攻模式·PVP"] = "Атакующий режим · PvP",
    ["随机获得2-4个词条"] = "Случайно дает 2-4 свойства",
    ["神圣之杖"] = "Священный посох",
    ["线索"] = "Улика",
    ["组队跟随中..."] = "Следование за группой...",
    ["组队跟随中…"] = "Следование за группой...",
    ["你在廷根的集体意识中失去了形态，意识正在退回现实..."] =
        "Вы потеряли форму в коллективном сознании Тингена, сознание возвращается в реальность...",
    ["界面返回"] = "Назад",
    ["灵体之线玩法"] = "Нити духовного тела",
    ["廷根第一市民"] = "Первый гражданин Тингена",
    ["[封]"] = "[Запечатано]",
    ["狂袭式"] = "Неистовый натиск",
    ["廷根守墓人"] = "Могильщик Тингена",
    ["机器加工厂坊"] = "Механический цех",
    ["非凡材料每有1条词条格挡 +200"] = "Каждое свойство материала Потусторонних дает блок +200",
    ["总探索度"] = "Общий прогресс исследования",
    ["上限可累计至下周"] = "Остаток лимита переносится на след. неделю",
    ["安迪哥努斯笔记"] = "Дневник Антигона",
    ["首通队伍"] = "Команда первого прохождения",
    ["男子：（癫狂）万物的“母亲”，赐予我们新生！"] =
        "Мужчина: (В безумии) «Мать» всего сущего, даруй нам новую жизнь!",
    ["“愚者”：拿上这个。"] = "«Шут»: Возьми это.",
    ["丑人：（有效期十四年？为什么要签这么久的合同……）"] =
        "Уродливый: (Срок действия четырнадцать лет? Зачем подписывать контракт на такой долгий срок...)",
    ["弗莱"] = "Фрай",
    ["伦纳德"] = "Леонард",
    ["罗珊"] = "Розанна",
    ["没有太大危险了，不用特别在意。"] =
        "Опасности больше нет, не стоит переживать.",
    ["罗珊小姐，这个铃铛是用来做什么的？"] =
        "Мисс Розанна, для чего этот колокольчик?",
    ["三律之背反"] = "Антиномия трех законов",
    ["镜像之自我"] = "Зеркальное я",
    ["技能增强提高<Mark>30</>。"] = "Усиление навыков увеличено на <Mark>30</>.",
    ["技能增强提高<Mark>30</>。\n激活套装<Mark>灵与知回响</>时不生效。"] =
        "Усиление навыков увеличено на <Mark>30</>.\nНе действует, пока активен комплект <Mark>Эхо Духа и Знания</>.",
    ["<CostRed>{1,2,（烙印已失效）}</>技能增强提高<Mark>30</>。\n激活套装<Mark>灵与知回响</>时不生效。"] =
        "<CostRed>{1,2,(Клеймо неактивно)}</>Усиление навыков увеличено на <Mark>30</>.\nНе действует, пока активен комплект <Mark>Эхо Духа и Знания</>.",
    ["技能增强提高30。\n激活套装灵与知回响时不生效。"] =
        "Усиление навыков увеличено на 30.\nНе действует, пока активен комплект Эхо Духа и Знания.",

    -- [AUTOCHESS / RESONANCE / SYNERGY OVERRIDES]
    ["Activate Resonance"] = "Активировать резонанс",
    ["* Activate Resonance"] = "* Активировать резонанс",
    ["Activated Resonance"] = "Активированный резонанс",
    ["Spellcraft"] = "Колдовство",
    ["Spellcasting"] = "Колдовство",
    ["[Spellcraft]"] = "[Колдовство]",
    ["[Spellcasting]"] = "[Колдовство]",
    ["All allies gain 10% Attack. [Spellcasting] stacks Attack after each skill cast."] =
        "Все союзники получают 10% атаки. [Колдовство] накапливает атаку после каждого применения навыка.",
    ["[Spellcasting] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack."] =
        "[Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки.",
    ["[Spellcasting] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack."] =
        "[Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки.",
    ["[Spellcasting] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack."] =
        "[Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки.",
    ["2 [Spellcasting] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack."] =
        "2 [Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки.",
    ["4 [Spellcasting] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack."] =
        "4 [Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки.",
    ["6 [Spellcasting] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack."] =
        "6 [Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки.",
    ["All allies gain <HighLight>10%</> Attack. [Spellcasting] stacks Attack after each skill cast."] =
        "Все союзники получают 10% атаки. [Колдовство] накапливает атаку после каждого применения навыка.",
    ["[Spellcasting] gains an additional <HighLight>15%</> Attack, and each time a skill is cast: self gains <HighLight>1%</> Attack."] =
        "[Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки.",
    ["[Spellcasting] gains an additional <HighLight>35%</> Attack, and each time a skill is cast: self gains <HighLight>1.5%</> Attack."] =
        "[Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки.",
    ["[Spellcasting] gains an additional <HighLight>55%</> Attack, and each time a skill is cast: self gains <HighLight>2%</> Attack."] =
        "[Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки.",
    ["2 [Spellcasting] gains an additional <HighLight>15%</> Attack, and each time a skill is cast: self gains <HighLight>1%</> Attack."] =
        "2 [Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки.",
    ["4 [Spellcasting] gains an additional <HighLight>35%</> Attack, and each time a skill is cast: self gains <HighLight>1.5%</> Attack."] =
        "4 [Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки.",
    ["6 [Spellcasting] gains an additional <HighLight>55%</> Attack, and each time a skill is cast: self gains <HighLight>2%</> Attack."] =
        "6 [Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки.",
    ["All allies gain <HighLight>10%</> Attack Speed. [Swift Hunt] stacks Attack Speed with each attack, up to <HighLight>10</> stacks. High tiers gain Damage Reduction."] =
        "Все союзники получают 10% к скорости атаки. [Быстрая охота] накапливает скорость атаки при каждом ударе (до 10 уровней). На высоких рангах дает снижение урона.",
    ["All allies recover <HighLight>4</> Mana per second. [Arcane] recovers more."] =
        "Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше.",
    ["2 [Arcane] All allies recover <HighLight>4</> Mana per second. [Arcane] recovers more."] =
        "2 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше.",
    ["4 [Arcane] All allies recover <HighLight>4</> Mana per second. [Arcane] recovers more."] =
        "4 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше.",
    ["For every <HighLight>1</> Resonance activated, all allies gain additional Attack, up to <HighLight>10</> Resonances."] =
        "За каждый 1 активированный резонанс все союзники получают дополнительную атаку, максимум до 10 резонансов.",
    ["All allies gain 10% Attack. [Spellcraft] stacks Attack after each skill cast."] =
        "Все союзники получают 10% атаки. [Колдовство] накапливает атаку после каждого применения навыка.",
    ["[Spellcraft] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack."] =
        "[Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки.",
    ["[Spellcraft] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack."] =
        "[Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки.",
    ["[Spellcraft] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack."] =
        "[Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки.",
    ["2 [Spellcraft] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack."] =
        "2 [Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки.",
    ["4 [Spellcraft] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack."] =
        "4 [Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки.",
    ["6 [Spellcraft] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack."] =
        "6 [Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки.",
    ["The Great Master"] = "Великий Мастер",
    ["[The Great Master]"] = "[Великий Мастер]",
    ["For every 1 Resonance activated, all allies gain additional Attack, up to 10 Resonances."] =
        "За каждый 1 активированный резонанс все союзники получают дополнительную атаку, максимум до 10 резонансов.",
    ["Wilderness Monster"] = "Монстр пустошей",
    ["[Wilderness Monster]"] = "[Монстр пустошей]",
    ["Each unique 3-star piece strengthens all allies. At high tiers, gain 1 random wild monster piece after each player combat."] =
        "Каждая уникальная 3-звёздочная фигура усиливает всех союзников. На высоких ступенях даёт 1 случайную фигуру дикого монстра после каждого боя с игроком.",
    ["Each unique 3-star piece: All allies +3% Attack and 5 Defense."] =
        "Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты.",
    ["2 Each unique 3-star piece: All allies +3% Attack and 5 Defense."] =
        "2 Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты.",
    ["Each unique 3-star piece: All allies +3% Attack and 5 Defense. Gain 1 random wild monster piece after each player combat."] =
        "Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты. Даёт 1 случайную фигуру дикого монстра после каждого боя с игроком.",
    ["3 Each unique 3-star piece: All allies +3% Attack and 5 Defense. Gain 1 random wild monster piece after each player combat."] =
        "3 Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты. Даёт 1 случайную фигуру дикого монстра после каждого боя с игроком.",
    ["Long-Shot"] = "Дальний выстрел",
    ["[Long-Shot]"] = "[Дальний выстрел]",
    ["Long-Range Strike"] = "Дальнобойный удар",
    ["[Long-Range Strike]"] = "[Дальнобойный удар]",
    ["[Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage."] =
        "[Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон.",
    ["2 [Long-Shot] [Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage."] =
        "2 [Дальний выстрел] [Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон.",
    ["4 [Long-Shot] [Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage."] =
        "4 [Дальний выстрел] [Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон.",
    ["Arcane"] = "Тайное знание",
    ["[Arcane]"] = "[Тайное знание]",
    ["All allies recover Mana per second. [Arcane] recovers more."] =
        "Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше.",
    ["2 [Arcane] All allies recover Mana per second. [Arcane] recovers more."] =
        "2 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше.",
    ["4 [Arcane] All allies recover Mana per second. [Arcane] recovers more."] =
        "4 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше.",
    ["Lawyer"] = "Юрист",
    ["[Lawyer]"] = "[Юрист]",
    ["Lucky One"] = "Счастливчик",
    ["[Lucky One]"] = "[Счастливчик]",
    ["Tarot Club"] = "Клуб Таро",
    ["[Tarot Club]"] = "[Клуб Таро]",
    ["К л у б   Т а р о"] = "К л у б   Т а р о",
    ["К л у б   Т а р..."] = "К л у б   Т а р...",
    ["К л у б  Т а р..."] = "К л у б  Т а р...",
    ["Hunter"] = "Охотник",
    ["[Hunter]"] = "[Охотник]",
    ["Giant Dragon Inheritance"] = "Наследие Дракона",
    ["[Giant Dragon Inheritance]"] = "[Наследие Дракона]",
    ["Life School of Thought"] = "Школа мысли Жизни",
    ["[Life School of Thought]"] = "[Школа мысли Жизни]",
    ["Iron Wall"] = "Железная стена",
    ["[Iron Wall]"] = "[Железная стена]",
    ["Evernight Goddess"] = "Богиня Вечной Ночи",
    ["[Evernight Goddess]"] = "[Богиня Вечной Ночи]",
    ["黑夜女神"] = "Богиня Вечной Ночи",
    ["【黑夜女神】"] = "【Богиня Вечной Ночи】",
    ["Evernight Goddess Church"] = "Церковь Богини Вечной Ночи",
    ["[Evernight Goddess Church]"] = "[Церковь Богини Вечной Ночи]",
    ["黑夜女神教会"] = "Церковь Богини Вечной Ночи",
    ["【黑夜女神教会】"] = "【Церковь Богини Вечной Ночи】",
    ["Forsaken Land of the Gods"] = "Заброшенная земля богов",
    ["[Forsaken Land of the Gods]"] = "[Заброшенная земля богов]",
    ["神弃之地"] = "Заброшенная земля богов",
    ["【神弃之地】"] = "【Заброшенная земля богов】",
    ["Aurora Order"] = "Орден Авроры",
    ["[Aurora Order]"] = "[Орден Авроры]",
    ["极光会"] = "Орден Авроры",
    ["【极光会】"] = "【Орден Авроры】",
    ["Seer"] = "Провидец",
    ["[Seer]"] = "[Провидец]",
    ["占卜家"] = "Провидец",
    ["【占卜家】"] = "【Провидец】",
    ["Rock"] = "Скала",
    ["[Rock]"] = "[Скала]",
    ["岩石"] = "Скала",
    ["【岩石】"] = "【Скала】",
    ["Monster"] = "Монстр",
    ["[Monster]"] = "[Монстр]",
    ["怪物"] = "Монстр",
    ["【怪物】"] = "【Монстр】",
    ["Bulwark"] = "Оплот",
    ["[Bulwark]"] = "[Оплот]",
    ["坚阵"] = "Оплот",
    ["【坚阵】"] = "【Оплот】",
    ["Crafted Bulwark"] = "Искусный оплот",
    ["[Crafted Bulwark]"] = "[Искусный оплот]",
    ["精工壁垒"] = "Искусный оплот",
    ["【精工壁垒】"] = "【Искусный оплот】",
    ["Randomly gain 2 pieces of Defensive Fine Equipment."] =
        "Случайным образом даёт 2 предмета добротного защитного снаряжения.",
    ["Critical Hit Amplification"] = "Усиление критического удара",
    ["Your pieces gain 15% Critical Hit Rate and 25% Critical Damage."] =
        "Ваши фигуры получают +15% к шансу крит. удара и +25% к крит. урону.",
    ["When a match round is lost, gain 2 Experience . If on a losing streak , gain an additional 1 Experience ."] =
        "При поражении в раунде матча даёт 2 ед. опыта. При серии поражений даёт дополнительно 1 ед. опыта.",
    ["When a match round is lost, gain 2 Experience. If on a losing streak, gain an additional 1 Experience."] =
        "При поражении в раунде матча даёт 2 ед. опыта. При серии поражений даёт дополнительно 1 ед. опыта.",
    ["losing streak"] = "серия поражений",
    ["Notes on Victory"] = "Заметки о победах",
    ["Ranking"] = "Место",
    ["Player"] = "Игрок",
    ["Piece"] = "Фигура",
    ["Pieces"] = "Фигуры",
    ["piece"] = "фигура",
    ["pieces"] = "фигуры",
    ["К у с о к"] = "Ф и г у р а",
    ["Кусок"] = "Фигура",
    ["Highlight Data"] = "Ключевые данные",
    ["Total Money"] = "Всего монет",
    ["Total Money:"] = "Всего монет:",
    ["Total Money: "] = "Всего монет: ",
    ["对战总数据"] = "Общая статистика боя",
    ["阵容思路"] = "Тактика отряда",
    ["阵容思路："] = "Тактика отряда:",
    ["添加阵容"] = "Добавить состав",
    ["添加阵容："] = "Добавить состав:",
    ["弈棋试炼"] = "Шахматные испытания",
    ["弈棋试炼："] = "Шахматные испытания:",
    ["弈子列表"] = "Список фигур",
    ["弈子列表："] = "Список фигур:",
    ["Add Lineup"] = "Добавить состав",
    ["Lineup Strategy"] = "Тактика отряда",
    ["Chess Trials"] = "Шахматные испытания",
    ["Chess Trial"] = "Шахматные испытания",
    ["Piece List"] = "Список фигур",
    ["Pieces List"] = "Список фигур",
    ["Chess Piece List"] = "Список фигур",
    ["Gain 10 Experience Points ."] = "Получите 10 очков опыта.",
    ["Gain 10 Experience Points."] = "Получите 10 очков опыта.",
    ["Blood Fire Heavy Cannon"] = "Тяжелое орудие кровавого пламени",
    ["[Blood Fire Heavy Cannon]"] = "[Тяжелое орудие кровавого пламени]",
    ["血火重炮"] = "Тяжелое орудие кровавого пламени",
    ["【血火重炮】"] = "【Тяжелое орудие кровавого пламени】",
    ["Chess pieces in the back two rows start combat with 80% of their current Health and gain 17% Damage Amplification ."] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +17% к увеличению урона.",
    ["Chess pieces in the back two rows start combat with 80% of their current Health and gain 17% Damage Amplification."] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +17% к увеличению урона.",
    ["在己方后两排开始战斗的弈子获得17%伤害增幅，并在战斗开始时损失20%当前生命值。"] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +17% к увеличению урона.",
    ["Chess pieces in the back two rows start combat with 80% of their current Health and gain 25% Damage Amplification ."] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +25% к увеличению урона.",
    ["Chess pieces in the back two rows start combat with 80% of their current Health and gain 25% Damage Amplification."] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +25% к увеличению урона.",
    ["在己方后两排开始战斗的弈子获得25%伤害增幅，并在战斗开始时损失20%当前生命值。"] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +25% к увеличению урона.",
    ["Chess pieces in the back two rows start combat with 80% of their current Health and gain 30% Damage Amplification ."] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +30% к увеличению урона.",
    ["Chess pieces in the back two rows start combat with 80% of their current Health and gain 30% Damage Amplification."] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +30% к увеличению урона.",
    ["在己方后两排开始战斗的弈子获得30%伤害增幅，并在战斗开始时损失20%当前生命值。"] =
        "Фигуры в двух задних рядах начинают бой с 80% от текущего здоровья и получают +30% к увеличению урона.",
    ["Night Watch Seal"] = "Печать Ночного Стража",
    ["[Night Watch Seal]"] = "[Печать Ночного Стража]",
    ["At the start of combat, chess pieces adjacent to allies gain 200 Shield , lasting for 8 seconds ."] =
        "В начале боя фигуры, находящиеся рядом с союзниками, получают щит прочностью 200 на 8 сек.",
    ["At the start of combat, chess pieces adjacent to allies gain 200 Shield, lasting for 8 seconds."] =
        "В начале боя фигуры, находящиеся рядом с союзниками, получают щит прочностью 200 на 8 сек.",
    ["Double-Sided Healing"] = "Двустороннее исцеление",
    ["[Double-Sided Healing]"] = "[Двустороннее исцеление]",
    ["Your pieces restore 4% of their maximum Health every 5 seconds."] =
        "Ваши фигуры восстанавливают 4% от макс. здоровья каждые 5 сек.",
    ["Your pieces restore 4% of their maximum Health every 5 seconds ."] =
        "Ваши фигуры восстанавливают 4% от макс. здоровья каждые 5 сек.",
    ["Greed Factory"] = "Фабрика жадности",
    ["[Greed Factory]"] = "[Фабрика жадности]",
    ["Immediately gain 10 Gold Coins, and thereafter gain 9 more Gold Coins at the start of each round."] =
        "Мгновенно дает 10 монет и дополнительно 9 монет в начале каждого раунда.",
    ["Immediately gain 10 Gold Coins , and thereafter gain 9 more Gold Coins at the start of each round ."] =
        "Мгновенно дает 10 монет и дополнительно 9 монет в начале каждого раунда.",
    ["Absolute Shield"] = "Абсолютный щит",
    ["[Absolute Shield]"] = "[Абсолютный щит]",
    ["[Absolute Shield] Gains a Max Health shield when Health is below 40%, and gains Damage Reduction for 10 seconds."] =
        "[Абсолютный щит] Получает щит от макс. здоровья при снижении здоровья ниже 40% и снижает получаемый урон на 10 сек.",
    ["Absolute Shield Gains a Max Health shield when Health is below 40%, and gains Damage Reduction for 10 seconds."] =
        "Абсолютный щит Получает щит от макс. здоровья при снижении здоровья ниже 40% и снижает получаемый урон на 10 сек.",
    ["Blood-Thirst"] = "Кровожадность",
    ["[Blood-Thirst]"] = "[Кровожадность]",
    ["Blood Thirst"] = "Кровожадность",
    ["[Blood Thirst]"] = "[Кровожадность]",
    ["噬血"] = "Кровожадность",
    ["【噬血】"] = "【Кровожадность】",
    ["【 噬血 】"] = "【 Кровожадность 】",
    ["【 噬血 】获得30%吸血。造成伤害时追加伤害，目标生命值低于50%时翻倍。"] =
        "【 Кровожадность 】 Дает 30% вампиризма. Наносит дополнительный урон при атаках; если здоровье цели ниже 50%, дополнительный урон удваивается.",
    ["【噬血】获得30%吸血。造成伤害时追加伤害，目标生命值低于50%时翻倍。"] =
        "【 Кровожадность 】 Дает 30% вампиризма. Наносит дополнительный урон при атаках; если здоровье цели ниже 50%, дополнительный урон удваивается.",
    ["Crimson Belie..."] = "Багряная вера",
    ["Crimson Belief"] = "Багряная вера",
    ["[Crimson Belief]"] = "[Багряная вера]",
    ["绯红信仰"] = "Багряная вера",
    ["【绯红信仰】"] = "【Багряная вера】",
    ["【 绯红信仰 】"] = "【 Багряная вера 】",
    ["8 seconds after combat starts, [Radiance of the Crimson Moon] deals True Damage to all enemies and grants all allies Attack Speed."] =
        "Через 8 сек. после начала боя [Сияние Багряной Луны] наносит чистый урон всем врагам и повышает скорость атаки всех союзников.",
    ["Swift-Hunt"] = "Быстрая охота",
    ["[Swift-Hunt]"] = "[Быстрая охота]",
    ["Swift Hunt"] = "Быстрая охота",
    ["[Swift Hunt]"] = "[Быстрая охота]",
    ["迅猎"] = "Быстрая охота",
    ["【迅猎】"] = "【Быстрая охота】",
    ["【 迅猎 】"] = "【 Быстрая охота 】",
    ["All allies gain 10% Attack Speed. [Swift Hunt] stacks Attack Speed with each attack, up to 10 stacks. High tiers gain Damage Reduction."] =
        "Все союзники получают 10% к скорости атаки. [Быстрая охота] накапливает скорость атаки при каждом ударе (до 10 уровней). На высоких рангах дает снижение урона.",
    ["Summons [Moon Corruption] to assist in combat; star level increases with tier."] =
        "Призывает [Лунное осквернение] на помощь в бою; звездный уровень растет с рангом.",
    ["Each unique 3-star piece strengthens all allies. At high tiers, gain 1 random wild monster piece after each player combat."] =
        "Каждая уникальная 3-звездочная фигура усиливает всех союзников. На высоких рангах дает 1 случайную фигуру дикого монстра после каждого боя с игроком.",
    ["Each unique 3-star piece: All allies +3% Attack and 5 Defense."] =
        "Каждая уникальная 3-звездочная фигура: все союзники +3% к атаке и 5 к защите.",
    ["Gain 1 random wild monster piece after each player combat."] =
        "Получите 1 случайную фигуру дикого монстра после каждого боя с игроком.",
    ["Wilderness Monster"] = "Дикий монстр",
    ["[Wilderness Monster]"] = "[Дикий монстр]",
    ["The Great Master"] = "Великий Мастер",
    ["[The Great Master]"] = "[Великий Мастер]",
    ["Moon Corruption"] = "Лунное осквернение",
    ["[Moon Corruption]"] = "[Лунное осквернение]",
    ["Radiance of the Crimson Moon"] = "Сияние Багряной Луны",
    ["[Radiance of the Crimson Moon]"] = "[Сияние Багряной Луны]",
    ["Highest Win Streak: "] = "Макс. серия побед: ",
    ["Highest Win Streak:"] = "Макс. серия побед:",
    ["Highest Win Streak"] = "Макс. серия побед",
    ["Highest Losing Streak: "] = "Макс. серия поражений: ",
    ["Highest Losing Streak:"] = "Макс. серия поражений:",
    ["Highest Losing Streak"] = "Макс. серия поражений",
    ["Highest Lose Streak: "] = "Макс. серия поражений: ",
    ["Highest Lose Streak:"] = "Макс. серия поражений:",
    ["Highest Lose Streak"] = "Макс. серия поражений",
    ["Самая высокая серия побед: "] = "Макс. серия побед: ",
    ["Самая высокая серия побед:"] = "Макс. серия побед:",
    ["Самая высокая серия побед"] = "Макс. серия побед",
    ["Самая высокая серия поражений: "] = "Макс. серия поражений: ",
    ["Самая высокая серия поражений:"] = "Макс. серия поражений:",
    ["Самая высокая серия поражений"] = "Макс. серия поражений",
    ["最高连胜："] = "Макс. серия побед:",
    ["最高连胜"] = "Макс. серия побед",
    ["最高连败："] = "Макс. серия поражений:",
    ["最高连败"] = "Макс. серия поражений",
    ["Current Win Streak"] = "Текущая серия побед",
    ["Current Losing Streak"] = "Текущая серия поражений",
    ["Обзор боевых записей"] = "Записи боев",
    ["Данные о матче"] = "Данные матча",
}

-- Nearby NPC chat can prepend a channel and translated speaker name to the
-- authored line inside the same widget. Replace only the exact Chinese body
-- and preserve that live prefix.
visibleTextExactOverrides.__translateNearbyConfessionDialogue = function(value)
    for _, replacement in ipairs({
        { "罗、罗茜！你今天过得好吗？", "Р-Рози! Как твои дела сегодня?" },
        { "罗、罗茜！你今天过得好吗?", "Р-Рози! Как твои дела сегодня?" },
        { "啊，弗雷泽！我很好，这束花是……", "Ох, Фрейзер! Всё хорошо. Этот букет..." },
        { "啊，弗雷泽！我很好，这束花是......", "Ох, Фрейзер! Всё хорошо. Этот букет..." },
        { "啊，弗雷泽！我很好，这束花是...", "Ох, Фрейзер! Всё хорошо. Этот букет..." },
        { "我想把它送给你，其实，我对你……", "Я хотел подарить его тебе. На самом деле, я к тебе..." },
        { "我想把它送给你，其实，我对你......", "Я хотел подарить его тебе. На самом деле, я к тебе..." },
        { "我想把它送给你，其实，我对你...", "Я хотел подарить его тебе. На самом деле, я к тебе..." },
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
        return "Ключевой материал для создания броши мифического качества (<Highlight>Состязание</>).\n\n"
            .. "Для создания требуется <Highlight>15</> шт. кристаллической крошки Серого Тумана. Создается брошь мифического качества 64 ур. предмета (<Highlight>Состязание</>).\n\n"
            .. "По ходу сезона откроется повышение уровня предмета мифической броши (Состязание). Каждое улучшение требует определенное количество кристаллической крошки Серого Тумана.\n\n"
            .. "Каждую неделю можно получить до <Highlight>3</> шт. кристаллической крошки Серого Тумана в «Финальной охоте», «Лиге четырех сторон», «Битве за Город охоты / Высокогорье» и «Военных трофеях». Неполученное количество переносится на следующую неделю, максимум до <Highlight>15</>."
    end
    if plain:find("铸造神话品质胸针（冒险倾向）的关键材料。", 1, true)
        and plain:find("灰雾尘埃", 1, true)
    then
        return "Ключевой материал для создания броши мифического качества (<Highlight>Приключение</>).\n\n"
            .. "Для создания требуется <Highlight>15</> шт. пыли Серого Тумана. Создается брошь мифического качества 64 ур. предмета (<Highlight>Приключение</>).\n\n"
            .. "По ходу сезона откроется повышение уровня предмета мифической броши (Приключение). Каждое улучшение требует определенное количество пыли Серого Тумана.\n\n"
            .. "Каждую неделю можно получить до <Highlight>3</> шт. пыли Серого Тумана в групповых подземельях, командных подземельях и трофеях приключений мира. Неполученное количество переносится на следующую неделю, максимум до <Highlight>15</>."
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
    return "1. <Highlight>Заявка в семью:</> Любой Потусторонний, не состоящий в семье, может подать заявку для поиска подходящей семьи. Заявка автоматически отзывается через "
        .. expiryDays .. " дн. после публикации или после успешного вступления в семью.\n"
        .. "2. <Highlight>Отклик на набор:</> Потусторонние без семьи могут начать набор или присоединиться к чужому набору. Инициатор по умолчанию становится <Highlight>Главой семьи</>.\n"
        .. "3. <Highlight>Создание семьи:</> Семья может быть создана, как только откликнется не менее <Highlight>3 человек</>. При создании глава может изменить название семьи и должности участников.\n"
        .. "4. <Highlight>Вступление в семью:</> Если в семье менее <Highlight>14 участников</>, глава может проводить набор. Другие игроки могут подать заявку и вступить после одобрения главой."
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
        prefix = "<CostRed>{1,2,(Клеймо неактивно)}</>"
    end
    local inactive = "\nНе действует, пока активен комплект <Mark>Эхо Духа и Знания</>."

    if plain:find("技能增强提高30。", 1, true) then
        return prefix .. "Усиление навыков увеличено на <Mark>30</>." .. inactive
    end
    if plain:find("释放解控技能后，获得50点技能抵挡", 1, true)
        and plain:find("每30秒最多触发一次。", 1, true)
    then
        return prefix
            .. "После применения навыка снятия контроля дает <Mark>50</> ед. блокирования навыков на <Mark>10</> сек. "
            .. "Срабатывает не чаще одного раза в <Mark>30</> сек."
            .. inactive
    end
    if plain:find("破防提高80。", 1, true)
        and plain:find("获得60点防御", 1, true)
        and plain:find("每10秒最多触发一次。", 1, true)
    then
        return prefix
            .. "Пробивание брони увеличено на <Mark>80</>. При получении урона есть шанс получить "
            .. "<Mark>60</> ед. защиты на <Mark>5</> сек. Срабатывает не чаще одного раза в <Mark>10</> сек."
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

    local translated = "<Yellow>Энергия жизни</>: Владелец получает 1 ед. Энергии жизни каждые <Yellow>"
        .. interval .. " сек.</>, вплоть до <Yellow>" .. energyLimit .. "</>. Когда суммарное "
        .. "эффективное исцеление владельца себе или союзнику превышает <Yellow>" .. healingThreshold
        .. "%</> от макс. ОЗ владельца, расходуется 1 ед. Энергии жизни, накладывая <Yellow>"
        .. growthStacks .. "</> ур. эффекта <Yellow>Бурный рост</> на цель на <Yellow>"
        .. growthDuration .. " сек.</>. Владелец также получает 1 <Yellow>Семя жизни</>, вплоть до <Yellow>"
        .. seedLimit .. "</>.\n\n<Yellow>Бурный рост</>: Пока ОЗ не полные, расходует 1 уровень эффекта "
        .. "в секунду для восстановления <Yellow>" .. healingAmount .. "</> ед. ОЗ.\n<Yellow>Семя жизни</>: "
        .. "Когда ОЗ владельца опускается ниже <Yellow>" .. lowHealthThreshold
        .. "%</>, автоматически расходует 1 Семя жизни для восстановления <Yellow>"
        .. seedRecovery .. "%</> от максимального ОЗ."
    if plain:find("主宰争锋", 1, true) then
        translated = translated
            .. "\nВ «Битве владык» эффекты Жезла Жизни снижены."
    end
    return translated
end

-- Brass Book bounty descriptions are formatted with live progress before display.
visibleTextExactOverrides.__translateBrassBookBounty = function(value)
    if type(value) ~= "string" then return value end
    local plain = value:gsub("（", "("):gsub("）", ")"):gsub("　", " "):gsub(" ", " ")
    local current, target = plain:match("^获取城市暗面玩法悬赏值%s*([%d,]+)/([%d,]+)。%s*%(黄铜书挑战开启后计数%)%s*$")
    if current == nil then return value end
    return "Получите " .. current .. "/" .. target
        .. " очков награды на «Изнанке города». (Учитывается после начала испытания Латунной книги.)"
end


local visibleTextReplacements = {
    {
        "绯红月辉？难道是这张红月纸牌？用它试试。",
        "Багряное сияние луны? Может, эта карта Красной Луны подойдет? Попробуем ее.",
    },
    { "点击空白区域关闭", "Нажмите в любом месте, чтобы закрыть" },
    { "跳过", "Пропустить" },
    { "推荐非凡评分", "Рекомендуемая оценка" },
    { "非凡评分", "Оценка Потустороннего" },
    { "塞巴斯蒂安", "Себастьян" },
    { "寒巴斯蒂安", "Себастьян" },
    { "男子：", "Мужчина: " },
    { "丑人：", "Уродливый: " },
    { "“愚者”：", "«Шут»: " },
    { "愚者", "Шут" },
    { "（癫狂）", "(В безумии) " },
    { "万物的“母亲”", "«Мать» всего сущего" },
    { "赐予我们新生", "даруй нам новую жизнь" },
    { "拿上这个", "Возьми это" },
    { "有效期十四年？为什么要签这么久的合同……", "Срок действия четырнадцать лет? Зачем подписывать контракт на такой долгий срок..." },
    {
        "感知灵界，观测星空，通过灵性物品启示的命运变化，解读其映射的现实空间异动、事态发展走向与潜在未知危险。",
        "Ощущайте духовный мир, наблюдайте за звездами. Толкуйте изменения судьбы, открываемые духовными предметами, чтобы распознавать отраженные ими возмущения в реальном мире, развитие событий и скрытые неведомые опасности.",
    },
    {
        "占星启示期间，周围的玩家可以获得临时技能来获取占星指引。",
        "Во время Астрологического откровения окружающие игроки могут получить временный навык для получения астрологических указаний.",
    },
    {
        "使自身获得武力加4，直觉加2。使用临时技能获取占星指引的玩家也可以获得武力加4，直觉加2。",
        "Дает персонажу +4 к Силе и +2 к Интуиции. Игроки, использующие временный навык для получения астрологических указаний, также получают +4 к Силе и +2 к Интуиции.",
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
    [87303350] = "Пришествие Рассвета",
    [87303360] = "Клеймо Арбитража",
    [87303370] = "Взор Подглядывающего",
    [87303380] = "Защита Утреннего Света",
    [87303390] = "Клятва Рыцаря",
    [87303400] = "Одержимость Духа-Бабочки",
    [87303410] = "Нисходящая Тень",
    [87303420] = "Эхо Похоронного Звона",
    [87303430] = "Серия Когтей Альфа-Волка",
    [87303440] = "Защитная Дрель",
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
    Fashion = "Стиль",
    Pastime = "Исслед.",
    Dungeon = "Данж",
    PVP = "Арена",
    Equip = "Снаряж.",
    Skill = "Навыки",
    Talent = "Таланты",
    Promotion = "Путь",
    Sealed = "Релик.",
    SecretPartner = "Марион.",
    Fellow = "Связи",
    Paotuan = "НРИ",
    Guild = "Клуб",
    Home = "Замок",
    Task = "Задания",
    Family = "Семья",
    Qingyuan = "Связи",
    Achievement = "Награды",
    Strategy = "Гайд",
    VideoCreation = "Творец",
    Friend = "Друзья",
    ShadowCity = "Тень",
    Character = "Профиль",
    HomePage = "Главная",
    Bag = "Сумка",
    Notice = "Новости",
    Email = "Почта",
    Rank = "Рейтинг",
    Detach = "Снять",
    Setting = "Настройки",
    QuitGame = "Выход",
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

local function sceneTextVector2D(x, y)
    if type(FVector2D) == "function" then
        local ok, value = pcall(FVector2D, x, y)
        if ok and value ~= nil then
            return value
        end
    end
    return { X = x, Y = y }
end

function runtimeFixes.utf8Len(str)
    if type(str) ~= "string" then return 0 end
    local _, count = str:gsub("[^\128-\191]", "")
    return count
end

function runtimeFixes.isCinematicWidgetName(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    return lower:find("aside") ~= nil
        or lower:find("chapter") ~= nil
        or lower:find("taskdesc") ~= nil
        or lower:find("targetdesc") ~= nil
        or lower:find("cinematic") ~= nil
        or lower:find("subtitle") ~= nil
        or lower:find("blackscreen") ~= nil
        or lower:find("mimewhite") ~= nil
        or lower:find("border_panel") ~= nil
        or lower:find("contenten") ~= nil
        or lower:find("mistery") ~= nil
        or lower:find("mystery") ~= nil
        or lower:find("ecclesia") ~= nil
        or lower:find("hermes") ~= nil
        or lower:find("theleon") ~= nil
end

function runtimeFixes.isCinematicFontObject(fontObj)
    if fontObj == nil then return false end
    if runtimeFixes.CinematicFontObject ~= nil and fontObj == runtimeFixes.CinematicFontObject then
        return true
    end
    local name = ""
    local path = ""
    pcall(function()
        if fontObj.GetName ~= nil then name = tostring(fontObj:GetName()):lower() end
        if fontObj.GetPathName ~= nil then path = tostring(fontObj:GetPathName()):lower() end
    end)
    local full = name .. " " .. path
    if full:find("song") or full:find("serif") or full:find("cinema") or full:find("book")
        or full:find("chapter") or full:find("aside") or full:find("baosong") or full:find("fzb")
        or full:find("simsun") or full:find("kaishu") or full:find("hwzs") or full:find("stsong")
        or full:find("mistery") or full:find("mystery") or full:find("theleon")
        or full:find("hermes") or full:find("runic") then
        return true
    end
    return false
end

function runtimeFixes.isStandardFontObject(fontObj)
    if fontObj == nil then return false end
    if runtimeFixes.StandardFontObject ~= nil and fontObj == runtimeFixes.StandardFontObject then
        return true
    end
    if runtimeFixes.isCinematicFontObject(fontObj) then
        return false
    end
    local name = ""
    local path = ""
    pcall(function()
        if fontObj.GetName ~= nil then name = tostring(fontObj:GetName()):lower() end
        if fontObj.GetPathName ~= nil then path = tostring(fontObj:GetPathName()):lower() end
    end)
    local full = name .. " " .. path
    if full:find("mistery") or full:find("mystery") or full:find("theleon") or full:find("hermes") or full:find("runic") then
        return false
    end
    if full:find("sans") or full:find("default") or full:find("common") or full:find("roboto")
        or full:find("noto") or full:find("yahei") or full:find("lan_ting") or full:find("lanting")
        or full:find("simhei") or full:find("regular") or full:find("ui") or full:find("body")
        or full:find("aleo") then
        return true
    end
    return false
end

function runtimeFixes.registerFontCandidate(fontObj, typefaceName, sourceWidgetName)
    if fontObj == nil then return end
    local fontPath = ""
    local fontName = ""
    pcall(function()
        if fontObj.GetName ~= nil then fontName = tostring(fontObj:GetName()):lower() end
        if fontObj.GetPathName ~= nil then fontPath = tostring(fontObj:GetPathName()) end
    end)
    local full = (fontName .. " " .. fontPath):lower()

    -- 1. Explicitly protect against stylized/runic Hermes fonts (Font_Mistery, etc.)
    if full:find("mistery") or full:find("mystery") or full:find("theleon") or full:find("hermes") or full:find("runic") then
        if runtimeFixes.CinematicFontObject == nil then
            runtimeFixes.CinematicFontObject = fontObj
            pcall(function() if fontObj.AddToRoot ~= nil then fontObj:AddToRoot() end end)
            report("identified CinematicFontObject (stylized Hermes) from " .. tostring(sourceWidgetName) .. " path=" .. fontPath)
        end
        return
    end

    if runtimeFixes.isCinematicWidgetName(sourceWidgetName) or runtimeFixes.isCinematicFontObject(fontObj) then
        if runtimeFixes.CinematicFontObject == nil then
            runtimeFixes.CinematicFontObject = fontObj
            pcall(function() if fontObj.AddToRoot ~= nil then fontObj:AddToRoot() end end)
            report("identified CinematicFontObject from " .. tostring(sourceWidgetName) .. " path=" .. fontPath)
        end
        return
    end

    -- 2. Only allow fonts that actually qualify as standard fonts (Aleo, Sans, Noto, etc.)
    local isStandard = runtimeFixes.isStandardFontObject(fontObj) or full:find("aleo") ~= nil

    -- 3. Check if current StandardFontObject is alive and valid
    local currentValid = false
    if runtimeFixes.StandardFontObject ~= nil then
        pcall(function()
            if runtimeFixes.StandardFontObject.GetName ~= nil and runtimeFixes.StandardFontObject:GetName() ~= nil then
                currentValid = true
            end
        end)
    end

    if (not currentValid or runtimeFixes.isCinematicFontObject(runtimeFixes.StandardFontObject)) and isStandard then
        runtimeFixes.StandardFontObject = fontObj
        -- CRITICAL: Prevent Unreal Engine GC from garbage-collecting StandardFontObject during level transitions!
        pcall(function()
            if fontObj.AddToRoot ~= nil then
                fontObj:AddToRoot()
            end
        end)
        if typefaceName ~= nil then
            runtimeFixes.StandardTypefaceFontName = typefaceName
        end
        report("registered StandardFontObject from " .. tostring(sourceWidgetName) .. " path=" .. fontPath .. " typeface=" .. tostring(typefaceName))
    end
end

pcall(function()
    if slua and type(slua.loadObject) == "function" then
        local aleoObj = slua.loadObject("/Game/Arts/UI_2/Resource/Font/Font_Aleo.Font_Aleo")
        if aleoObj ~= nil then
            runtimeFixes.registerFontCandidate(aleoObj, "Font_Aleo", "Slua_Preload")
        end
    end
end)
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

local SHARD_PREFIXES = {}
for i = 0, 1023 do
    SHARD_PREFIXES[i] = string.format("%03x", i)
end

local function getShardPrefix(value)
    local hash = bit.tobit(2166136261)
    local len = #value
    for index = 1, len do
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
    return SHARD_PREFIXES[bit.band(bit.rshift(hash, 22), 0x3ff)]
end

local geminiTextCache = {
    Shards = {},
    Missing = {},
    Lookups = {},
}

local function lookupGeminiText(value)
    if type(value) ~= "string" or value == "" then return nil end
    local cached = geminiTextCache.Lookups[value]
    if cached ~= nil then
        runtimeMetrics.GeminiLookupCacheHits = runtimeMetrics.GeminiLookupCacheHits + 1
        return cached ~= false and cached or nil
    end
    runtimeMetrics.GeminiLookupCacheMisses = runtimeMetrics.GeminiLookupCacheMisses + 1

    local prefix = getShardPrefix(value)
    if prefix == nil or geminiTextCache.Missing[prefix] then
        geminiTextCache.Lookups[value] = false
        return nil
    end

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
            geminiTextCache.Lookups[value] = false
            report("Gemini runtime text shard unavailable " .. prefix .. ": " .. tostring(loaded))
            return nil
        end
        shard = loaded
        geminiTextCache.Shards[prefix] = shard
        runtimeMetrics.GeminiLoads = runtimeMetrics.GeminiLoads + 1
    end

    local translated = shard[value]
    geminiTextCache.Lookups[value] = translated ~= nil and translated or false
    return translated
end

runtimeFixes.hasCyrillic = function(str)
    return type(str) == "string" and str:find("[\208-\209][\128-\191]") ~= nil
end

runtimeFixes.utf8Len = function(s)
    if type(s) ~= "string" then return 0 end
    local _, count = s:gsub("[^\128-\191]", "")
    return count
end

runtimeFixes.lookupGeminiTextFuzzy = function(value)
    if type(value) ~= "string" or value == "" then return nil end
    local direct = lookupGeminiText(value)
    if direct ~= nil then return direct end

    -- Normalize CRLF to LF for multi-line text (dialogs, descriptions, hints)
    if value:find("\r", 1, true) then
        local normalized = value:gsub("\r\n", "\n"):gsub("\r", "\n")
        local normDirect = lookupGeminiText(normalized)
        if normDirect ~= nil then return normDirect end
        local normLeading, normTrimmed, normTrailing = normalized:match("^(%s*)(.-)(%s*)$")
        if normTrimmed ~= "" and normTrimmed ~= normalized then
            local t = lookupGeminiText(normTrimmed)
            if t ~= nil then return normLeading .. t .. normTrailing end
        end
    end

    -- 1. Trim leading and trailing whitespace / newlines
    local leading, trimmed, trailing = value:match("^(%s*)(.-)(%s*)$")
    if trimmed ~= "" and trimmed ~= value then
        local t = lookupGeminiText(trimmed)
        if t ~= nil then
            return leading .. t .. trailing
        end
    end

    -- 2. Outer RichText tags: e.g. <Highlight>Text</>, <Text.Red>Text</>
    local openTag, tagInner, closeTag = value:match("^(<[^>]+>)(.-)(</>)$")
    if openTag and tagInner and tagInner ~= "" then
        local t = runtimeFixes.lookupGeminiTextFuzzy(tagInner)
        if t ~= nil then
            return openTag .. t .. closeTag
        end
    end

    -- 3. Trailing punctuation: colons (: / ：), dashes (- / —), question marks (?), dots (...)
    local stem, punct = value:match("^(.-)([:：%-%?%.]+)%s*$")
    if stem and stem ~= "" and stem ~= value then
        local t = runtimeFixes.lookupGeminiTextFuzzy(stem)
        if t ~= nil then
            return t .. punct
        end
    end

    -- 4. Bracketed text: [Text], (Text), {Text}, 【Text】
    local openBr, brInner, closeBr = value:match("^([%[%{%(【])(.-)([%]%}%)】])$")
    if openBr and brInner and brInner ~= "" then
        local t = runtimeFixes.lookupGeminiTextFuzzy(brInner)
        if t ~= nil then
            return openBr .. t .. closeBr
        end
    end

    -- 5. Level patterns: "Level 15" -> "Уровень 15", "Lv. 10" -> "Ур. 10", "Lv: 5" -> "Ур: 5"
    local lvlNum = value:match("^[Ll]evel%s*(%d+)$")
    if lvlNum then return "Уровень " .. lvlNum end
    local lvNum = value:match("^[Ll]v%.?%s*(%d+)$")
    if lvNum then return "Ур. " .. lvNum end
    local lvColonNum = value:match("^[Ll]v%.?[:：]%s*(%d+)$")
    if lvColonNum then return "Ур: " .. lvColonNum end

    return nil
end

runtimeFixes.reflowSingleLineToTwo = function(text, minChars)
    return text
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

function runtimeFixes.translateDigestionTask(value)
    if type(value) ~= "string" or value == "" then return nil end

    -- 1. Complete acting story: <Name>(x/y)
    local storyName, progress = value:match("^[Cc]omplete acting story:%s*(.-)%s*%((%d+/%d+)%)$")
    if storyName and progress then
        local storyRu = lookupGeminiText(storyName) or storyName
        return "Завершите историю отыгрыша: " .. storyRu .. " (" .. progress .. ")"
    end

    -- 2. Defeat/Complete <Diff> difficulty <Target>, pick up <Item>(x/y)
    local act, diff, target, item, p2 = value:match("^([CcDd][a-z]+)%s+([NnHh][a-z]+)%s+difficulty%s+(.-),%s*pick up%s+(.-)%s*%((%d+/%d+)%)$")
    if act and diff and target and item and p2 then
        local diffRu = (diff:lower() == "normal") and "обычн. сл." or "высок. сл."
        local targetLower = target:lower()
        local targetRu = target
        if targetLower == "clown" then targetRu = "Клоуна"
        elseif targetLower == "riel bieber" then targetRu = "Риэля Бибера"
        elseif targetLower == "viscountess" then targetRu = "Виконтессу"
        elseif targetLower == "alienated hound" then targetRu = "Отчужденного пса"
        elseif targetLower == "ancestor armor" then targetRu = "Доспехи предка"
        elseif targetLower == "believer number one" then targetRu = "Верующего номер один"
        elseif targetLower == "sylvia" then targetRu = "Сильвию"
        elseif targetLower == "astrolabe user" then targetRu = "Пользователя астролябии"
        elseif targetLower == "offspring protection" then targetRu = "Защиту потомства"
        elseif targetLower == "escort carriage" then targetRu = "Эскорт экипажа"
        elseif targetLower == "misfortune water giant turtle" then targetRu = "Водную гигантскую черепаху несчастий"
        elseif targetLower == "dancing king baboon brother" then targetRu = "Брата Бабуина — Короля танцев"
        else targetRu = lookupGeminiText(target) or target end

        local itemLower = item:lower()
        local itemRu = item
        if itemLower == "loose note pages" or itemLower == "loose notes" then itemRu = "страницы дневника"
        elseif itemLower == "hound's claw" then itemRu = "коготь пса"
        elseif itemLower == "residual spirituality fragments" then itemRu = "осколки остаточной духовности"
        elseif itemLower == "corrupted beyonder characteristic" then itemRu = "загрязненную Потустороннюю характеристику"
        elseif itemLower == "a bookmark" then itemRu = "закладку"
        elseif itemLower == "broken weapon" then itemRu = "сломанное оружие"
        elseif itemLower == "fairy tale book" then itemRu = "книгу сказок"
        elseif itemLower == "tattered diary" then itemRu = "ветхий дневник"
        elseif itemLower == "old notebook" then itemRu = "старый блокнот"
        elseif itemLower == "damaged spirituality traces" then itemRu = "поврежденные следы духовности"
        elseif itemLower == "beyonder characteristic fragment" then itemRu = "осколок Потусторонней характеристики"
        else itemRu = lookupGeminiText(item) or item end

        local actRu = (act:lower():find("defeat") or act:lower():find("побед")) and "Победите" or "Пройдите"
        return actRu .. " " .. targetRu .. " (" .. diffRu .. "), соберите " .. itemRu .. " (" .. p2 .. ")"
    end

    -- 3. In competitive mode, kill/assist in killing x/y <Target>
    local killAction, p3, compTarget = value:match("^[Ii]n competitive mode,%s*(.-)%s+(%d+/%d+)%s+(.+)$")
    if killAction and p3 and compTarget then
        local isAssist = killAction:lower():find("assist") ~= nil
        local actPrefix = isAssist and "В соревновательном режиме помогите победить " or "В соревновательном режиме победите "
        local lowerTarget = compTarget:lower()
        local targetRu = compTarget
        if lowerTarget == "seers" then targetRu = "Провидцев"
        elseif lowerTarget == "clowns" then targetRu = "Клоунов"
        elseif lowerTarget == "magicians" then targetRu = "Магов"
        elseif lowerTarget == "warriors" then targetRu = "Воинов"
        elseif lowerTarget == "spectators" then targetRu = "Зрителей"
        elseif lowerTarget == "mind readers" then targetRu = "Чтецов мыслей"
        elseif lowerTarget == "psychologists" then targetRu = "Психологов"
        elseif lowerTarget == "apprentices" then targetRu = "Учеников"
        elseif lowerTarget == "bards" then targetRu = "Бардов"
        elseif lowerTarget == "astrologers" then targetRu = "Астрологов"
        elseif lowerTarget == "witches" then targetRu = "Ведьм"
        elseif lowerTarget == "mystery pryers" then targetRu = "Жрецов тайн"
        elseif lowerTarget == "pugilists" then targetRu = "Бойцов"
        elseif lowerTarget == "sun priests" then targetRu = "Жрецов Солнца"
        elseif lowerTarget == "weapon masters" then targetRu = "Мастеров оружия"
        elseif lowerTarget == "scholars of forethought" then targetRu = "Учёных предвидения"
        else targetRu = lookupGeminiText(compTarget) or compTarget end
        return actPrefix .. p3 .. " " .. targetRu
    end

    -- 4. Complete x/y explorations: <Exploration>
    local expProgress, expTarget = value:match("^[Cc]omplete%s+(%d+/%d+)%s+explorations?:%s*(.+)$")
    if expProgress and expTarget then
        local targetRu = lookupGeminiText(expTarget) or expTarget
        if expTarget:lower() == "spirit body threads" then targetRu = "Нити духовного тела" end
        return "Пройдите исследование " .. expProgress .. ": " .. targetRu
    end

    -- 5. Visit other Beyonders' Castle x/y times
    local castleTimes = value:match("^[Vv]isit other [Bb]eyonders'%s+[Cc]astle%s+(%d+/%d+)%s+times$")
    if castleTimes then
        return "Посетите замок других Потусторонних " .. castleTimes .. " раз"
    end
    local castleTimesSingle = value:match("^[Vv]isit other [Bb]eyonders'%s+[Cc]astle%s+(%d+)%s+times$")
    if castleTimesSingle then
        return "Посетите замок других Потусторонних " .. castleTimesSingle .. " раз"
    end

    return nil
end

function runtimeFixes.normalizeShopLotLimit(value)
    if type(value) ~= "string" or value == "" then return value end
    local prefix, cur, max = value:match("^(.-)%s*(%d+)/(%d+)$")
    if prefix and cur and max then
        local clean = prefix:gsub("%s+", "")
        local prefixMap = {
            ["ПодземельеНеделя"] = "В неделю ",
            ["DungeonWeek"] = "В неделю ",
            ["副本周"] = "В неделю ",
            ["Неделя"] = "В неделю ",
            ["Week"] = "В неделю ",
            ["周"] = "В неделю ",
            ["ПодземельеДень"] = "В день ",
            ["DungeonDay"] = "В день ",
            ["副本天"] = "В день ",
            ["День"] = "В день ",
            ["Day"] = "В день ",
            ["日"] = "В день ",
            ["天"] = "В день ",
            ["ПодземельеСезон"] = "В сезон ",
            ["DungeonSeason"] = "В сезон ",
            ["副本赛季"] = "В сезон ",
            ["Сезон"] = "В сезон ",
            ["Season"] = "В сезон ",
            ["赛季"] = "В сезон ",
        }
        local mapped = prefixMap[clean]
        if mapped then
            return mapped .. cur .. "/" .. max
        end
    end
    if value:find("Подземелье%s*Неделя") or value:find("Dungeon%s*Week") or value:find("副本%s*周") then
        local replaced = value:gsub("Подземелье%s*Неделя%s*(%d+)/(%d+)", "В неделю %1/%2")
        replaced = replaced:gsub("Dungeon%s*Week%s*(%d+)/(%d+)", "В неделю %1/%2")
        replaced = replaced:gsub("副本%s*周%s*(%d+)/(%d+)", "В неделю %1/%2")
        if replaced ~= value then return replaced end
    end
    return value
end

runtimeFixes.AutoChessSkillTemplates = {
    -- [131015]
    ["Brands the target with a Necrotic Mark, dealing {0} attack damage."] = "Клеймит цель Меткой некроза, нанося {0} ед. урона от атаки.",
    -- [131016]
    ["Cause blood roses to bloom around you, dealing {0} Attack damage to nearby enemies."] = "Заставляет кровавые розы расцвести вокруг себя, нанося {0} ед. урона от атаки ближайшим врагам.",
    -- [131019]
    ["Continuously spit flames forward; nine attacks deal a total of {0} Attack damage. Hits apply a {1}-second Burn, causing enemies to lose {2} Health per second."] = "Непрерывно извергает пламя вперед; девять ударов наносят в сумме {0} ед. урона от атаки. Попадания накладывают Горение на {1} сек., заставляя врагов терять {2} ед. здоровья в секунду.",
    -- [131021]
    ["Dance and sweep surrounding enemies with blood flames, dealing {0} Attack damage, and increase your own Attack Speed by {1} for {2} seconds."] = "Кружится в танце и сметает окружающих врагов кровавым пламенем, нанося {0} ед. урона от атаки и повышая собственную скорость атаки на {1} на {2} сек.",
    -- [131022]
    ["Drop Dark Mushrooms, detonating them three times in the target area, dealing a total of {0} Attack damage."] = "Сбрасывает темные грибы, трижды подрывая их в целевой области и нанося в сумме {0} ед. урона от атаки.",
    -- [131023]
    ["Enter Super Armor for {0} seconds and continuously sweep surrounding enemies six times with a Blade Storm, dealing a total of {1} Attack damage."] = "Получает Неудержимость на {0} сек. и шесть раз подряд рассекает окружающих врагов Бурей клинков, нанося в сумме {1} ед. урона от атаки.",
    -- [131025]
    ["Fire a gear beam, dealing {0} Attack damage to targets within {1} grids."] = "Выпускает луч из шестеренок, нанося {0} ед. урона от атаки целям в пределах {1} клеток.",
    -- [131026]
    ["Fire five phantom energy projectiles in succession to pursue the target, dealing a total of {0} Attack damage."] = "Выпускает пять призрачных энергетических снарядов подряд, преследующих цель и наносящих в сумме {0} ед. урона от атаки.",
    -- [131027]
    ["Fire two Air Cannons forward in succession, each hit dealing {0} Attack damage."] = "Выпускает две Воздушные пушки вперед подряд, каждое попадание наносит {0} ед. урона от атаки.",
    -- [131030]
    ["Issue an arrest warrant for the furthest enemy, dealing {0} Attack damage and pulling them in front of you."] = "Выписывает ордер на арест самого дальнего врага, нанося {0} ед. урона от атаки и притягивая его к себе.",
    -- [131031]
    ["Jump and Ground Fracture, dealing {0} Attack damage to surrounding enemies and stunning them for {1} seconds."] = "Прыгает и раскалывает землю, нанося {0} ед. урона от атаки окружающим врагам и оглушая их на {1} сек.",
    -- [131032]
    ["Launch three consecutive slashes forward, dealing a total of {0} Attack damage."] = "Совершает три последовательных рассекающих удара вперед, нанося в сумме {0} ед. урона от атаки.",
    -- [131033]
    ["Launch three waves of Spirit World Bombardment, dealing a total of {0} Attack damage. The second wave applies a {1}-second Grievous Injury Burn, causing enemies to lose {2} of their maximum health per second, and reducing incoming healing effects by {3}."] = "Вызывает три волны Бомбардировки Мира Духов, нанося в сумме {0} ед. урона от атаки. Вторая волна накладывает Тяжелое горение на {1} сек., заставляя врагов терять {2} от максимального здоровья в секунду и снижая получаемое исцеление на {3}.",
    -- [131036]
    ["Pass judgment on the furthest enemy, dealing {0} Attack damage and stunning them for {1} seconds, while reducing their mana regeneration by {2} points for {3} seconds."] = "Выносит приговор самому дальнему врагу, нанося {0} ед. урона от атаки и оглушая его на {1} сек., а также снижая регенерацию его маны на {2} ед. на {3} сек.",
    -- [131037]
    ["Play the Spirit Mediumship trio, impacting surrounding enemies three times in succession, dealing a total of {0} Attack damage."] = "Исполняет трио спиритизма, трижды подряд поражая окружающих врагов и нанося в сумме {0} ед. урона от атаки.",
    -- [131038]
    ["Pounce on the enemy with the lowest health, dealing {0} Attack damage. When the target's health is no higher than {1}, the damage increases to {2}, and you restore {3} of your own Health."] = "Бросается на врага с наименьшим здоровьем, нанося {0} ед. урона от атаки. Если здоровье цели не превышает {1}, урон увеличивается до {2}, а вы восстанавливаете себе {3} ед. здоровья.",
    -- [131039]
    ["Rain down Miracle Cards, dealing {0} Attack damage to enemies in the target area."] = "Обрушивает дождь Карт чудес, нанося {0} ед. урона от атаки врагам в целевой области.",
    -- [131040]
    ["Raise a wall of waves to sweep the front, dealing {0} Attack damage and knocking back enemies. Then, a Lightning Strike bombards the same area, dealing an additional {1} Attack damage."] = "Поднимает стену волн, сметающую врагов впереди, нанося {0} ед. урона от атаки и отбрасывая их назад. Затем Удар молнии поражает ту же область, нанося дополнительно {1} ед. урона от атаки.",
    -- [131041]
    ["Release a Fear Ripple, dealing {0} Attack damage to surrounding enemies; this increases to {1} when enemy health is no higher than {2}. Upon hitting, reduce their Defense by {3} for {4} seconds."] = "Выпускает Волну страха, нанося {0} ед. урона от атаки окружающим врагам; урон возрастает до {1}, если здоровье врага не превышает {2}. При попадании снижает защиту врагов на {3} на {4} сек.",
    -- [131042]
    ["Restores {0} health to self and allies within {1} tiles, and increases defense by {2} for {3} seconds. Self randomly gains one of the following effects for {4} seconds: Attack and Attack Speed increased by {5}; or gain {6} Shield and {7} defense; or restore {8} health and {9} energy, and gain {10} Shield."] = "Восстанавливает {0} ед. здоровья себе и союзникам в пределах {1} клетки и повышает защиту на {2} ед. на {3} сек. Сам заклинатель случайно получает один из следующих эффектов на {4} сек.: атака и скорость атаки увеличены на {5}; либо получает щит прочностью {6} ед. и {7} ед. защиты; либо восстанавливает {8} ед. здоровья и {9} ед. энергии, а также получает щит прочностью {10} ед.",
    -- [131044]
    ["Spin jump and shock surrounding enemies, dealing {0} Attack damage, and gain {1} Shield and {2} Damage Reduction for {3} seconds."] = "Прыгает с вращением и сотрясает окружающих врагов, нанося {0} ед. урона от атаки, а также получает щит прочностью {1} ед. и {2} снижения урона на {3} сек.",
    -- [131046]
    ["Stomp the front with the power of civilization, dealing {0} Attack damage and knocking back enemies, while gaining {1} Damage Reduction for {2} seconds."] = "Обрушивает топот силы цивилизации вперед, нанося {0} ед. урона от атаки и отбрасывая врагов назад, при этом получает {1} снижения урона на {2} сек.",
    -- [131047]
    ["Strike surrounding enemies with a three-hit Torrent, dealing a total of {0} Attack damage. The final hit knocks up enemies for {1} seconds, and you gain {2} Shield for {3} seconds."] = "Поражает окружающих врагов трехударным Потоком, нанося в сумме {0} ед. урона от атаки. Последний удар подбрасывает врагов в воздух на {1} сек., а вы получаете щит прочностью {2} ед. на {3} сек.",
    -- [131048]
    ["Summon Holy Light to gain {0} Shield for {1} seconds. After {2} seconds, shock surrounding enemies, dealing {3} Attack damage and restoring {4} Health for nearby allies."] = "Призывает Святой Свет, получая щит прочностью {0} ед. на {1} сек. Спустя {2} сек. сотрясает окружающих врагов, нанося {3} ед. урона от атаки и восстанавливая {4} ед. здоровья ближайшим союзникам.",
    -- [131049]
    ["Summons a Cookie Rain, dealing {0} attack damage to enemies in the target area and restoring {1} health to the {2} ally with the lowest health."] = "Призывает Дождь из печенья, нанося {0} ед. урона от атаки врагам в целевой области и восстанавливая {1} ед. здоровья {2} союзнику с наименьшим здоровьем.",
    -- [131050]
    ["Swing the Black Scythe to sweep the front, dealing {0} Attack damage. When the enemy's health is no higher than {1}, the damage increases to {2}."] = "Взмахивает Черной косой, рассекая пространство перед собой и нанося {0} ед. урона от атаки. Если здоровье врага не превышает {1}, урон возрастает до {2}.",
    -- [131051]
    ["Swing the rage hammer to shock surrounding enemies, dealing {0} Attack damage. Then, within {1} seconds, each time you are hit, gain {2} Attack Speed, stacking up to {3} times."] = "Взмахивает молотом ярости, сотрясая окружающих врагов и нанося {0} ед. урона от атаки. Затем в течение {1} сек. при каждом получении удара увеличивает скорость атаки на {2} (суммируется до {3} раз).",
    -- [131053]
    ["Throw two doom cards to strike the target continuously, dealing a total of {0} Attack damage. Then randomly increase Attack Speed by {1} or Attack by {2} for {3} seconds."] = "Бросает две карты рока, непрерывно поражающие цель и наносящие в сумме {0} ед. урона от атаки. Затем случайно увеличивает скорость атаки на {1} или атаку на {2} на {3} сек.",
    -- [131056]
    ["以巨龙威压横扫前方，造成{0}点攻击伤害，并施加{1}秒重伤灼烧：每秒损失{2}点生命，受治疗效果降低{3}。同时为生命最低的{4}名友军各恢复{5}点生命。三星时：以巨龙威压横扫前方，造成{6}点攻击伤害，并施加{7}秒重伤灼烧：每秒损失{8}点生命，受治疗效果降低{9}。同时为生命最低的{10}名友军各恢复{11}点生命。"] = "Сметает врагов впереди сокрушительным давлением дракона, нанося {0} ед. урона от атаки и накладывая Тяжелое горение на {1} сек.: теряется {2} ед. здоровья в секунду, получаемое исцеление снижается на {3}. Одновременно восстанавливает {4} ед. здоровья {5} союзникам с наименьшим здоровьем. На 3 звездах: сметает врагов впереди сокрушительным давлением дракона, нанося {6} ед. урона от атаки и накладывая Тяжелое горение на {7} сек.: теряется {8} ед. здоровья в секунду, получаемое исцеление снижается на {9}. Одновременно восстанавливает {10} ед. здоровья {11} союзникам с наименьшим здоровьем.",
    -- [131057]
    ["以知识辉耀对敌方全体造成{0}点攻击伤害。随后随机获得{1}攻击，持续{2}秒，或立即恢复{3}点法力。"] = "Озаряет поле Сиянием знаний, нанося {0} ед. урона от атаки всем врагам. Затем случайно получает +{1} к атаке на {2} сек. или мгновенно восстанавливает {3} ед. маны.",
    -- [131058]
    ["以蛛肢绞杀前方敌人，造成{0}点攻击伤害。施法时恢复自身{1}最大生命，防御提高{2}点，持续{3}秒。"] = "Сдавливает паучьими лапами врагов впереди, нанося {0} ед. урона от атаки. При применении восстанавливает себе {1} от максимального здоровья и повышает защиту на {2} ед. на {3} сек.",
    -- [131059]
    ["以闪电射线连续贯穿前方敌人，并在目标区域引爆，全部命中共造成{0}点攻击伤害。三星时：以闪电射线连续贯穿前方敌人，并在目标区域引爆，全部命中共造成{1}点攻击伤害。"] = "Пронизывает врагов впереди непрерывными лучами молний и взрывает их в целевой области, нанося при полном попадании в сумме {0} ед. урона от атаки. На 3 звездах: пронизывает врагов впереди непрерывными лучами молний и взрывает их в целевой области, нанося при полном попадании в сумме {1} ед. урона от атаки.",
    -- [131060]
    ["先轰击前方较小的矩形区域，造成{0}点攻击伤害。随后对目标及其周围{1}格内的敌人造成{2}点攻击伤害，并使其眩晕{3}秒。最后轰击前方更大的矩形区域，造成{4}点攻击伤害。"] = "Сначала обстреливает небольшую прямоугольную область перед собой, нанося {0} ед. урона от атаки. Затем наносит цели и окружающим врагам в пределах {1} клетки {2} ед. урона от атаки, оглушая их на {3} сек. Напоследок обстреливает большую прямоугольную область впереди, нанося {4} ед. урона от атаки.",
    -- [131061]
    ["发出三次死灵怒嚎，震击周围敌人，共造成{0}点攻击伤害，自身获得{1}点护盾，持续{2}秒。三星时：发出三次死灵怒嚎，震击周围敌人，共造成{3}点攻击伤害，自身获得{4}点护盾，持续{5}秒。"] = "Издает три яростных вопля нежити, сотрясая окружающих врагов и нанося в сумме {0} ед. урона от атаки, а также получает щит прочностью {1} ед. на {2} сек. На 3 звездах: издает три яростных вопля нежити, сотрясая окружающих врагов и нанося в сумме {3} ед. урона от атаки, а также получает щит прочностью {4} ед. на {5} сек.",
    -- [131062]
    ["发出四次狼嚎冲击前方，共造成{0}点攻击伤害。自身每损失{1}最大生命，获得{2}攻速和吸血，至多{3}，生命恢复时重新计算。"] = "Издает четыре волчьих воя, обрушивая ударную волну вперед и нанося в сумме {0} ед. урона от атаки. За каждые потерянные {1} максимального здоровья получает {2} к скорости атаки и вампиризму (до {3}), значение пересчитывается при восстановлении здоровья.",
    -- [131063]
    ["向前方释放两次音波冲击，共造成{0}点攻击伤害，自身及附近{1}格内友军获得{2}点护盾，持续{3}秒。三星时：向前方释放两次音波冲击，共造成{4}点攻击伤害，自身及附近{5}格内友军获得{6}点护盾，持续{7}秒。"] = "Выпускает вперед две звуковые волны, нанося в сумме {0} ед. урона от атаки; заклинатель и союзники в пределах {1} клеток получают щит прочностью {2} ед. на {3} сек. На 3 звездах: выпускает вперед две звуковые волны, нанося в сумме {4} ед. урона от атаки; заклинатель и союзники в пределах {5} клеток получают щит прочностью {6} ед. на {7} сек.",
    -- [131064]
    ["向目标区域释放三重怨念，共造成{0}点攻击伤害。三星时：向目标区域释放三重怨念，共造成{1}点攻击伤害。"] = "Обрушивает на целевую область тройную злобу призраков, нанося в сумме {0} ед. урона от атаки. На 3 звездах: обрушивает на целевую область тройную злобу призраков, нанося в сумме {1} ед. урона от атаки.",
    -- [131065]
    ["吟诵午夜诗篇，对周围敌人造成{0}点攻击伤害并使其安眠{1}秒，自身攻速提高{2}，持续{3}秒。三星时：吟诵午夜诗篇，对周围敌人造成{4}点攻击伤害并使其安眠{5}秒，自身攻速提高{6}，持续{7}秒。"] = "Декламирует Полуночную поэму, нанося окружающим врагам {0} ед. урона от атаки и погружая их в сон на {1} сек., при этом собственная скорость атаки повышается на {2} на {3} сек. На 3 звездах: декламирует Полуночную поэму, нанося окружающим врагам {4} ед. урона от атаки и погружая их в сон на {5} сек., при этом собственная скорость атаки повышается на {6} на {7} сек.",
    -- [131066]
    ["在敌人密集处接连绽放三圈藤棘，共造成{0}点攻击伤害，并使敌人攻击降低{1}，持续{2}秒。"] = "В месте скопления врагов последовательно распускает три кольца шипастых лоз, нанося в сумме {0} ед. урона от атаки и снижая атаку врагов на {1} на {2} сек.",
    -- [131067]
    ["在敌人密集处由外向内引爆三环蔓袭，三环全中共造成{0}点攻击伤害，内圈使命中的敌人眩晕{1}秒。"] = "В месте скопления врагов подрывает снаружи внутрь три кольца стелющихся лоз, нанося при попадании всеми тремя кольцами в сумме {0} ед. урона от атаки; внутреннее кольцо оглушает пораженных врагов на {1} сек.",
    -- [131068]
    ["对周围敌人造成{0}点攻击伤害，并随机获得{1}最大生命护盾或{2}伤害减免，持续{3}秒。"] = "Наносит окружающим врагам {0} ед. урона от атаки и случайно получает щит прочностью {1} от максимального здоровья либо {2} снижения урона на {3} сек.",
    -- [131069]
    ["对自身周围{0}格内的敌人造成{1}点攻击伤害。自身获得{2}伤害减免，持续{3}秒。"] = "Наносит врагам в пределах {0} клеток вокруг себя {1} ед. урона от атаки. Заклинатель получает {2} снижения урона на {3} сек.",
    -- [131070]
    ["射出星辉贯穿箭，对直线上的敌人造成{0}点攻击伤害，并在目标位置引爆，造成{1}点范围伤害。"] = "Выпускает стрелу звездного света, пронзающую врагов на прямой линии и наносящую {0} ед. урона от атаки, а затем взрывающуюся в точке попадания с нанесением {1} ед. урона по площади.",
    -- [131071]
    ["挥出断岳重斧，对前方敌人造成{0}点攻击伤害。获得{1}最大生命护盾，持续{2}秒。"] = "Обрушивает тяжелый сокрушающий горы топор, нанося врагам впереди {0} ед. урона от атаки. Получает щит прочностью {1} от максимального здоровья на {2} сек.",
    -- [131072]
    ["攻击目标，造成{0}点攻击伤害。目标生命不高于{1}时，改为{2}点攻击伤害。自身吸血提高{3}，持续{4}秒。三星时：攻击目标，造成{5}点攻击伤害。目标生命不高于{6}时，改为{7}点攻击伤害。自身吸血提高{8}，持续{9}秒。"] = "Атакует цель, нанося {0} ед. урона от атаки. Если здоровье цели не превышает {1}, урон возрастает до {2}. Собственный вампиризм повышается на {3} на {4} сек. На 3 звездах: атакует цель, нанося {5} ед. урона от атаки. Если здоровье цели не превышает {6}, урон возрастает до {7}. Собственный вампиризм повышается на {8} на {9} сек.",
    -- [131074]
    ["突袭最远的敌人，连斩目标周围并留下黑焰，全部命中共造成{0}点攻击伤害。自身击杀本次技能选中的目标后，恢复{1}点法力值。"] = "Внезапно атакует самого дальнего врага, совершая серию ударов вокруг цели и оставляя черное пламя; при попадании всех ударов наносит в сумме {0} ед. урона от атаки. Если заклинатель убивает выбранную данным навыком цель, он восстанавливает {1} ед. маны.",
    -- [131075]
    ["舞王狒哥旋身震荡周围，对自身{0}格圆形范围内的敌人造成{1}点攻击伤害，并恢复自身{2}最大生命。"] = "Король танцев Павиан кружится, сотрясая пространство вокруг и нанося врагам в пределах {0} клеток {1} ед. урона от атаки, а также восстанавливает себе {2} от максимального здоровья.",
    -- [131076]
    ["连发三枚星辉弹，共造成{0}点攻击伤害。命中后为生命比例最低的友军恢复{1}最大生命。"] = "Выпускает три снаряда звездного света подряд, нанося в сумме {0} ед. урона от атаки. При попадании восстанавливает союзнику с наименьшей долей здоровья {1} от максимального здоровья.",
    -- [131077]
    ["连续重击目标{0}次，共造成{1}点攻击伤害，最后一击使其眩晕{2}秒。施法时获得{3}伤害减免，持续{4}秒。"] = "Обрушивает на цель {0} мощных удара подряд, нанося в сумме {1} ед. урона от атаки; последний удар оглушает цель на {2} сек. При применении навыка получает {3} снижения урона на {4} сек.",
    -- [131078]
    ["释放两次星界洪流，横扫前方扇形区域，共造成{0}点攻击伤害。"] = "Дважды выпускает астральный поток, сметающий конусную область впереди и наносящий в сумме {0} ед. урона от атаки.",
    -- [131079]
    ["释放恐惧回声，对周围敌人造成{0}点攻击伤害。三星时：释放恐惧回声，对周围敌人造成{1}点攻击伤害。"] = "Выпускает Эхо страха, нанося окружающим врагам {0} ед. урона от атаки. На 3 звездах: выпускает Эхо страха, нанося окружающим врагам {1} ед. урона от атаки.",
    -- [131080]
    ["释放恶意冲击，对前方敌人造成{0}点攻击伤害，自身攻击提高{1}、防御提高{2}点，持续{3}秒。三星时：释放恶意冲击，对前方敌人造成{4}点攻击伤害，自身攻击提高{5}、防御提高{6}点，持续{7}秒。"] = "Выпускает Злобный импульс, нанося врагам впереди {0} ед. урона от атаки, а также повышает собственную атаку на {1} и защиту на {2} ед. на {3} сек. На 3 звездах: выпускает Злобный импульс, нанося врагам впереди {4} ед. урона от атаки, а также повышает собственную атаку на {5} и защиту на {6} ед. на {7} сек.",
    -- [131267, 131268]
    ["Deals an additional {0} Attack damage."] = "Наносит дополнительно {0} ед. урона от атаки.",
    ["造成额外{0}攻击伤害。"] = "Наносит дополнительно {0} ед. урона от атаки.",
    -- AutoChess equipment & augments (batch 28: 131153-131219)
    -- [131153]
    ["{0} seconds after the battle starts, your pieces gain {1} Damage Deepening."] = "Через {0} сек. после начала боя ваши фигуры получают {1} к увеличению урона.",
    -- [131154]
    ["Each Basic Attack restores {0} Mana; when dealing a Critical Hit, restore an additional {1} Mana."] = "Каждая базовая атака восстанавливает {0} ед. маны; при критическом ударе восстанавливает дополнительно {1} ед. маны.",
    -- [131156]
    ["If there are exactly {0} ally pieces in the first row, both gain {1} Health and {2} Defense."] = "Если в первом ряду ровно {0} союзные фигуры, обе получают {1} ед. здоровья и {2} ед. защиты.",
    -- [131163]
    ["施法后的{0}秒内，下一次普攻额外造成相当于{1}攻击的伤害，冷却时间为{2}秒。"] = "В течение {0} сек. после применения навыка следующая базовая атака дополнительно наносит урон в размере {1} от атаки, время перезарядки — {2} сек.",
    ["Within {0} seconds after casting, next basic attack deals additional damage equal to {1} Attack, cooldown {2} seconds."] = "В течение {0} сек. после применения навыка следующая базовая атака дополнительно наносит урон в размере {1} от атаки, время перезарядки — {2} сек.",
    -- [131164]
    ["每秒恢复{0}最大生命值。"] = "Восстанавливает {0} от максимального запаса здоровья в секунду.",
    ["Restores {0} max health per second."] = "Восстанавливает {0} от максимального запаса здоровья в секунду.",
    -- [131165]
    ["获得【铁血】共鸣。每隔{0}秒，对{1}格内至多{2}名敌人造成相当于自身生命值{3}的伤害。"] = "Получает резонанс 【Железо и Кровь】. Каждые {0} сек. наносит до {2} врагам в пределах {1} клетки урон, равный {3} от собственного здоровья.",
    ["Gain [Iron-Blood] resonance. Every {0} seconds, deals damage equal to {1} max health to up to {2} enemies within {3} tile."] = "Получает резонанс 【Железо и Кровь】. Каждые {0} сек. наносит до {2} врагам в пределах {3} клетки урон, равный {1} от собственного здоровья.",
    ["Gain [Iron-Blood] resonance. Every {0} seconds, deals damage equal to {1} max health to up to {2} enemies within {3} tiles."] = "Получает резонанс 【Железо и Кровь】. Каждые {0} сек. наносит до {2} врагам в пределах {3} клеток урон, равный {1} от собственного здоровья.",
    -- [131177, 131178]
    ["+{0} Attack Speed per stack."] = "+{0} к скорости атаки за уровень.",
    -- [131179, 131180]
    ["{0} seconds after the battle starts, your pieces restore {1} of their lost Health."] = "Через {0} сек. после начала боя ваши фигуры восстанавливают {1} от потерянного здоровья.",
    -- [131191]
    ["Lose {0} Player Health, and after {1} combat rounds, gain {2} Gold Coins."] = "Теряет {0} ед. здоровья игрока, а через {1} боевых раундов получает {2} золотые монеты.",
    -- [131192]
    ["Maximum units on board +{0}, and randomly gain one {1}-cost chess piece."] = "Лимит фигур на доске +{0}, и случайным образом даёт одну фигуру за {1} золотых.",
    -- [131193]
    ["Maximum units on board +{0}, your chess pieces gain {1} Damage Reduction, but the player's maximum Health is reduced by {2} points."] = "Лимит фигур на доске +{0}, ваши фигуры получают {1} снижения урона, но макс. здоровье игрока снижается на {2} ед.",
    -- [131194, 131195, 131196]
    ["{0} Max Health Shield, {1} Damage Reduction."] = "Щит в размере {0} от макс. здоровья, {1} снижения урона.",
    -- [131201]
    ["After {0} seconds of combat, your chess pieces gain {1} Damage Amplification."] = "Через {0} секунд боя ваши фигуры получают {1} увеличения урона.",
    -- [131204, 131205]
    ["After dealing a Critical Hit, Critical Damage increases by {0} for {1} seconds."] = "После нанесения критического удара крит. урон увеличивается на {0} на {1} сек.",
    -- [131206, 131207]
    ["After dealing a Critical Hit, damage increases by {0} for {1} seconds, stacking up to {2} times."] = "После нанесения критического удара урон увеличивается на {0} на {1} сек., максимум {2} ур.",
    -- [131208, 131209]
    ["After dealing damage, reduce the target's Defense by {0} for {1} seconds."] = "После нанесения урона снижает защиту цели на {0} на {1} сек.",
    ["After dealing damage, the target's Defense is reduced by {0} for {1} seconds."] = "После нанесения урона защита цели снижается на {0} на {1} сек.",
    -- [131210, 131211]
    ["After each Basic Attack, Attack Speed increases by {0}, stacking up to {1} times."] = "После каждой базовой атаки скорость атаки увеличивается на {0}, максимум {1} ур.",
    ["After each Basic Attack, gain {0} Attack Speed, stacking up to {1} times."] = "После каждой базовой атаки даёт {0} скорости атаки, максимум {1} ур.",
    -- [131212, 131213]
    ["After each Basic Attack, restore {0} Mana."] = "После каждой базовой атаки восстанавливает {0} ед. маны.",
    -- [131215, 131216]
    ["After receiving damage, deal {0} damage to enemies within {1} tile(s), with a Cooldown of {2} seconds."] = "При получении урона наносит {0} ед. урона врагам в пределах {1} клетки. Перезарядка: {2} сек.",
    ["After receiving damage, deal {0} damage to enemies within {1} tile; Cooldown is {2} seconds."] = "При получении урона наносит {0} ед. урона врагам в пределах {1} клетки. Перезарядка: {2} сек.",
    -- [131218, 131219]
    ["After the first skill cast in each battle, Mana recovery increases by {0} for {1} seconds."] = "После первого применения навыка в каждом бою восстановление маны увеличивается на {0} ед. на {1} сек.",
}

runtimeFixes.translateAutoChessSkill = function(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    -- If string already contains Cyrillic, it is already translated
    if value:find("[\208\209][\128-\191]") then
        return nil
    end
    -- Must have at least a markup tag or a digit to match a dynamic skill template
    if value:find("<", 1, true) == nil and value:find("%d") == nil then
        return nil
    end

    local templates = runtimeFixes.AutoChessSkillTemplates
    if not templates then
        return nil
    end

    local function matchTemplate(templated, tokens)
        local ruTemplate = templates[templated]
        if ruTemplate == nil and templated:find("\r", 1, true) then
            local norm = templated:gsub("\r\n", "\n"):gsub("\r", "\n")
            ruTemplate = templates[norm]
        end
        if ruTemplate == nil then
            local trimmed = templated:match("^%s*(.-)%s*$")
            if trimmed ~= nil and trimmed ~= templated then
                ruTemplate = templates[trimmed]
            end
        end

        if ruTemplate ~= nil then
            local result = ruTemplate:gsub("{(%d+)}", function(idxStr)
                local idx = tonumber(idxStr)
                if idx ~= nil and tokens[idx + 1] ~= nil then
                    return tokens[idx + 1]
                end
                return "{" .. idxStr .. "}"
            end)
            return result
        end
        return nil
    end

    -- Pass 1: Universal UMG tag extraction (supports <Yellow>, <HighLight>, <Text.Red>, etc.)
    -- Strip empty tags like <HighLight></> so they do not pollute token sequence
    local cleanValue = value:gsub("<[^/>][^>]*>%s*</>", "")

    local tokens = {}
    local templated = cleanValue:gsub("<([^/>][^>]*)>([^<]+)</>", function(tag, content)
        table.insert(tokens, "<" .. tag .. ">" .. content .. "</>")
        return "{" .. (#tokens - 1) .. "}"
    end)

    if #tokens > 0 then
        local res = matchTemplate(templated, tokens)
        if res ~= nil then
            return res
        end
    end

    -- Pass 2: Tag + raw dynamic numbers and percentages (for untagged or mixed formatting)
    local tokens2 = {}
    local intermediate = cleanValue:gsub("<([^/>][^>]*)>([^<]+)</>", function(tag, content)
        table.insert(tokens2, "<" .. tag .. ">" .. content .. "</>")
        return "{" .. (#tokens2 - 1) .. "}"
    end)
    local templated2 = intermediate:gsub("(%d+%.?%d*%%?)", function(num)
        table.insert(tokens2, num)
        return "{" .. (#tokens2 - 1) .. "}"
    end)

    if #tokens2 > 0 then
        local res2 = matchTemplate(templated2, tokens2)
        if res2 ~= nil then
            return res2
        end
    end

    return nil
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

    -- Preserve leading asterisk prefix (e.g. "* Activate Resonance", "* Получить талант")
    local starPrefix, starBody = value:match("^(%*%s*)(.+)$")
    if starPrefix ~= nil and starBody ~= nil then
        local translatedStar = translateVisibleText(starBody)
        if translatedStar ~= starBody then
            local result = starPrefix .. translatedStar
            visibleTextCache[value] = result
            return result
        end
    end

    -- AutoChess dynamic resonance count (e.g. "Activated Resonance: 1")
    local actResCount = value:match("^Activated%s+Resonance:%s*(%d+)$") or value:match("^Activate%s+Resonance:%s*(%d+)$")
    if actResCount ~= nil then
        local result = "Активированный резонанс: " .. actResCount
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess dynamic "For every X Resonance activated..."
    local everyCount, maxRes = value:match("For every.-(%d+).-Resonance activated, all allies gain additional Attack, up to.-(%d+).-Resonances")
    if everyCount ~= nil and maxRes ~= nil then
        local result = "За каждый " .. everyCount .. " активированный резонанс все союзники получают дополнительную атаку, максимум до " .. maxRes .. " резонансов."
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess numbered synergy tier prefix (e.g. "2 [Spellcasting]...", "2 Each unique 3-star piece...", multiline tiers)
    local tierPrefix, tierBody = value:match("^(%d+)%s+([%s%S]+)$")
    if tierPrefix ~= nil and tierBody ~= nil then
        local translatedTier = translateVisibleText(tierBody)
        if translatedTier == tierBody and tierBody:find("\r", 1, true) then
            local normalizedBody = tierBody:gsub("\r\n", "\n")
            local normTrans = translateVisibleText(normalizedBody)
            if normTrans ~= normalizedBody then
                translatedTier = normTrans
            end
        end
        if translatedTier ~= tierBody then
            local result = tierPrefix .. " " .. translatedTier
            visibleTextCache[value] = result
            return result
        end
    end

    -- AutoChess Tarot Club seat bonus description in Chinese (supports <HighLight> tags and plain text)
    if value:find("每上阵1名成员", 1, true)
        or value:find("每上阵<HighLight>1</>名成员", 1, true)
        or value:find("每上阵<highlight>1</>名成员", 1, true)
        or (value:find("每上阵", 1, true) and value:find("名成员", 1, true))
    then
        local result = "За каждого выставленного участника все получают свойства его места:\nФорс: 💧+1 оч.\nДеррик: 🌿+2% | Хью Дилча: 🔥+7%\nЭлджер: ⚡+8% | Одри: 🥊+5%\nЛеонард: ❤️+5% | Клейн: 📣+10%"
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: piece skill template matcher with dynamic numbers
    local skillResult = runtimeFixes.translateAutoChessSkill(value)
    if skillResult ~= nil then
        visibleTextCache[value] = skillResult
        return skillResult
    end

    -- AutoChess: Blood Fire Heavy Cannon talent description (English & Chinese dynamic regex with tag tolerance)
    local bfHp, bfDmg = value:match("Chess pieces in the back two rows start combat with.-(%d+)%%.-of their current Health and gain.-(%d+)%%.-Damage Amplification")
    if bfHp and bfDmg then
        local result = "Фигуры в двух задних рядах начинают бой с <HighLight>" .. bfHp .. "%</> от текущего здоровья и получают <HighLight>+" .. bfDmg .. "%</> к увеличению урона."
        visibleTextCache[value] = result
        return result
    end
    local cnBfDmg, cnBfLoss = value:match("在己方后两排开始战斗的弈子获得.-(%d+)%%.-伤害增幅.-损失.-(%d+)%%.-当前生命值")
    if cnBfDmg and cnBfLoss then
        local result = "Фигуры в двух задних рядах получают <HighLight>+" .. cnBfDmg .. "%</> к увеличению урона и теряют <HighLight>" .. cnBfLoss .. "%</> здоровья в начале боя."
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess dynamic piece roles (e.g. "Ranged Marksman", "Mid-row Support", "Frontline Tank", etc.)
    local rolePos, roleClass = value:match("^([A-Za-z%-]+)%s+([A-Za-z]+)$")
    if rolePos ~= nil and roleClass ~= nil then
        local posMap = {
            ["Frontline"] = "Передовой",
            ["Melee"] = "Ближнего боя",
            ["Mid-row"] = "Среднего ряда",
            ["Mid-line"] = "Среднего ряда",
            ["Middle"] = "Среднего ряда",
            ["Backline"] = "Заднего ряда",
            ["Ranged"] = "Дальнего боя",
        }
        local classMap = {
            ["Marksman"] = "Стрелок",
            ["Mage"] = "Маг",
            ["Warrior"] = "Воин",
            ["Tank"] = "Танк",
            ["Assassin"] = "Убийца",
            ["Support"] = "Поддержка",
            ["Defense"] = "Танк",
            ["DPS"] = "Боец",
        }
        local p = posMap[rolePos]
        local c = classMap[roleClass]
        if p and c then
            local res
            if rolePos == "Frontline" then
                if roleClass == "Support" then
                    res = "Передовая поддержка"
                else
                    res = p .. " " .. c:lower()
                end
            elseif rolePos == "Melee" or rolePos == "Ranged" or rolePos == "Mid-row" or rolePos == "Mid-line" or rolePos == "Middle" or rolePos == "Backline" then
                res = c .. " " .. p:lower()
            else
                res = c .. " " .. p
            end
            visibleTextCache[value] = res
            return res
        end
    end

    local hasHighlight = value:find("<", 1, true) ~= nil
    local cleanEquipText = value:gsub("<.->", "")

    -- AutoChess: dynamic battle starts damage augment
    local dSec, dPct = cleanEquipText:match("(%d+)%s*seconds after the battle starts.-(%d+%%)%s*Damage Deepening")
    if dSec and dPct then
        local result
        if hasHighlight then
            result = "Через " .. dSec .. " сек. после начала боя<HighLight></> ваши фигуры получают " .. dPct .. " к увеличению урона<HighLight></>."
        else
            result = "Через " .. dSec .. " сек. после начала боя ваши фигуры получают " .. dPct .. " к увеличению урона."
        end
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: basic attack mana restore augment
    local bAtkMana, critMana = cleanEquipText:match("Each Basic Attack restores.-(%d+).-Mana.-when dealing a Critical Hit.-(%d+).-Mana")
    if bAtkMana and critMana then
        local result
        if hasHighlight then
            result = "Каждая базовая атака восстанавливает <HighLight>" .. bAtkMana .. "</> ед. маны; при критическом ударе восстанавливает дополнительно <HighLight>" .. critMana .. "</> ед. маны."
        else
            result = "Каждая базовая атака восстанавливает " .. bAtkMana .. " ед. маны; при критическом ударе восстанавливает дополнительно " .. critMana .. " ед. маны."
        end
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: first row pieces bonus augment
    local rowCount, rowHp, rowDef = cleanEquipText:match("If there are exactly%s*(%d+)%s*ally pieces in the first row.-(%d+)%s*Health.-(%d+)%s*Defense")
    if rowCount and rowHp and rowDef then
        local result
        if hasHighlight then
            result = "Если в первом ряду ровно " .. rowCount .. " союзные фигуры<HighLight></>, обе получают " .. rowHp .. " ед. здоровья<HighLight></> и " .. rowDef .. " ед. защиты<HighLight></>."
        else
            result = "Если в первом ряду ровно " .. rowCount .. " союзные фигуры, обе получают " .. rowHp .. " ед. здоровья и " .. rowDef .. " ед. защиты."
        end
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: Chinese after cast extra attack skill
    local cSec, cDmg, cCd = cleanEquipText:match("施法后的%s*(%d+)%s*秒内.-(%d+%%)%s*攻击的伤害.-(%d+)%s*秒")
    if cSec and cDmg and cCd then
        local result
        if hasHighlight then
            result = "В течение <HighLight>" .. cSec .. "</> сек. после применения навыка следующая базовая атака дополнительно наносит урон в размере <HighLight>" .. cDmg .. "</> от атаки, время перезарядки — <HighLight>" .. cCd .. "</> сек."
        else
            result = "В течение " .. cSec .. " сек. после применения навыка следующая базовая атака дополнительно наносит урон в размере " .. cDmg .. " от атаки, время перезарядки — " .. cCd .. " сек."
        end
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: Chinese hp regen per second
    local hpRegen = cleanEquipText:match("每秒恢复%s*(%d+%%)%s*最大生命值")
    if hpRegen then
        local result
        if hasHighlight then
            result = "Восстанавливает <HighLight>" .. hpRegen .. "</> от максимального запаса здоровья в секунду."
        else
            result = "Восстанавливает " .. hpRegen .. " от максимального запаса здоровья в секунду."
        end
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: Chinese/English iron-blood resonance skill
    local ibSec, ibRad, ibTargets, ibDmg = cleanEquipText:match("获得【铁血】共鸣.-每隔%s*(%d+)%s*秒.-对%s*(%d+)%s*格内至多%s*(%d+)%s*名敌人造成相当于自身生命值%s*(%d+%%?)%s*的伤害")
    if ibSec and ibRad and ibTargets and ibDmg then
        local result
        if hasHighlight then
            result = "Получает резонанс 【Железо и Кровь】. Каждые <HighLight>" .. ibSec .. "</> сек. наносит до <HighLight>" .. ibTargets .. "</> врагам в пределах <HighLight>" .. ibRad .. "</> клетки урон, равный <HighLight>" .. ibDmg .. "</> от собственного здоровья."
        else
            result = "Получает резонанс 【Железо и Кровь】. Каждые " .. ibSec .. " сек. наносит до " .. ibTargets .. " врагам в пределах " .. ibRad .. " клетки урон, равный " .. ibDmg .. " от собственного здоровья."
        end
        visibleTextCache[value] = result
        return result
    end
    local ibSecEn, ibDmgEn, ibTargetsEn, ibRadEn = cleanEquipText:match("Gain %[Iron%-Blood%] resonance.-Every%s*(%d+)%s*seconds?.-deals damage equal to%s*(%d+%%?)%s*max health to up to%s*(%d+)%s*enemies within%s*(%d+)%s*tile")
    if ibSecEn and ibDmgEn and ibTargetsEn and ibRadEn then
        local result
        if hasHighlight then
            result = "Получает резонанс 【Железо и Кровь】. Каждые <HighLight>" .. ibSecEn .. "</> сек. наносит до <HighLight>" .. ibTargetsEn .. "</> врагам в пределах <HighLight>" .. ibRadEn .. "</> клетки урон, равный <HighLight>" .. ibDmgEn .. "</> от собственного здоровья."
        else
            result = "Получает резонанс 【Железо и Кровь】. Каждые " .. ibSecEn .. " сек. наносит до " .. ibTargetsEn .. " врагам в пределах " .. ibRadEn .. " клетки урон, равный " .. ibDmgEn .. " от собственного здоровья."
        end
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess: Extraordinary World synergy tier 3 description
    if value:find("Starts [Extraordinary Quests]", 1, true) and value:find("probability of Extraordinary Quests", 1, true) then
        local result = "Начинает [Потусторонние задания], увеличивая вероятность появления Потусторонних заданий в каждом раунде; после выполнения задания вы получаете [Потусторонний сундук]"
        visibleTextCache[value] = result
        return result
    end

    -- AutoChess rank formatting repair: STRICT matching for explicit rank titles only
    local rankTitle, rankNum, rankRest = value:match("^([%a-zA-Z\128-\255]+)%s*[Уу]ровень%s*(%w+)%s*(.*)$")
    if not rankTitle then
        rankTitle, rankNum, rankRest = value:match("^([%a-zA-Z\128-\255]+)%s*[Ll]evel%s*(%w+)%s*(.*)$")
    end
    if rankTitle ~= nil and rankNum ~= nil then
        local validRanks = {
            ["Viscount"] = "Виконт", ["Knight"] = "Рыцарь", ["Baron"] = "Барон",
            ["Earl"] = "Граф", ["Marquis"] = "Маркиз", ["Duke"] = "Герцог",
            ["Виконт"] = "Виконт", ["Рыцарь"] = "Рыцарь", ["Барон"] = "Барон",
            ["Граф"] = "Граф", ["Маркиз"] = "Маркиз", ["Герцог"] = "Герцог",
            ["子爵"] = "Виконт", ["骑士"] = "Рыцарь", ["男爵"] = "Барон",
            ["伯爵"] = "Граф", ["侯爵"] = "Маркиз", ["公爵"] = "Герцог",
        }
        local canonicalRank = validRanks[rankTitle]
        if canonicalRank then
            if rankNum == "b" then rankNum = "2" end
            local result = canonicalRank .. " | Уровень " .. rankNum
            if rankRest ~= nil and rankRest ~= "" then
                rankRest = rankRest:match("^%s*|?%s*(.-)%s*$")
                if rankRest ~= "" then
                    result = result .. " | " .. rankRest
                end
            end
            visibleTextCache[value] = result
            return result
        end
    end

    -- Win / Loss streak formatting repair to prevent widget text overlap
    local hiWin = value:match("^Самая высокая серия побед:%s*(.*)$")
        or value:match("^Highest Win Streak:%s*(.*)$")
        or value:match("^最高连胜[：:]%s*(.*)$")
    if hiWin ~= nil then
        hiWin = hiWin:match("^%s*(.-)%s*$")
        local result = hiWin ~= "" and ("Макс. серия побед: " .. hiWin) or "Макс. серия побед:"
        visibleTextCache[value] = result
        return result
    end

    local hiLose = value:match("^Самая высокая серия поражений:%s*(.*)$")
        or value:match("^Highest Losing Streak:%s*(.*)$")
        or value:match("^Highest Lose Streak:%s*(.*)$")
        or value:match("^最高连败[：:]%s*(.*)$")
    if hiLose ~= nil then
        hiLose = hiLose:match("^%s*(.-)%s*$")
        local result = hiLose ~= "" and ("Макс. серия поражений: " .. hiLose) or "Макс. серия поражений:"
        visibleTextCache[value] = result
        return result
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
    local shopLimit = runtimeFixes.normalizeShopLotLimit(value)
    if shopLimit ~= value then
        visibleTextCache[value] = shopLimit
        return shopLimit
    end
    local reviewedExact = visibleTextExactOverrides[value]
    if reviewedExact ~= nil then
        visibleTextCache[value] = reviewedExact
        return reviewedExact
    end

    -- AutoChess synergy & exact text normalization for UMG tags (<HighLight>, <Yellow>, <Text.Red>, etc.)
    if value:find("<", 1, true) then
        local plain = value:gsub("<[^>]+>", "")
        if plain ~= value and plain ~= "" then
            local plainOverride = visibleTextExactOverrides[plain]
            if plainOverride ~= nil then
                visibleTextCache[value] = plainOverride
                return plainOverride
            end
            local plainGemini = runtimeFixes.lookupGeminiTextFuzzy(plain)
            if plainGemini ~= nil then
                visibleTextCache[value] = plainGemini
                return plainGemini
            end
        end
    end
    local gemini = runtimeFixes.lookupGeminiTextFuzzy(value)
    if gemini ~= nil then
        gemini = preserveMovableAnswerMarkup(value, gemini)
        gemini = runtimeFixes.normalizeDefenseBreakTerminology(gemini)
        visibleTextCache[value] = gemini
        local onIntercept = rawget(_G, "__LOM_OnTextIntercepted")
        if onIntercept then pcall(onIntercept, "visible", value, gemini) end
        return gemini
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

    local digestionTask = runtimeFixes.translateDigestionTask(value)
    if digestionTask ~= nil and digestionTask ~= value then
        visibleTextCache[value] = digestionTask
        return digestionTask
    end

    if hasCjk and not hasCjk(value) then
        -- If already localized (contains Cyrillic), safe to cache
        if runtimeFixes.hasCyrillic(value) then
            visibleTextCache[value] = value
            return value
        end

        -- AutoChess: piece/seal bonus dynamic handler (supports "Your chess pieces gain" and "Your pieces gain", extra spaces, trailing punctuation)
        local bonusClean = value:gsub("<.->", "")
        local bonusVal, bonusStat = bonusClean:match("^[Yy]our%s+chess%s+pieces%s+gain%s+(%d+%%?)%s+(.-)%s*%.?$")
        if not bonusVal then
            bonusVal, bonusStat = bonusClean:match("^[Yy]our%s+pieces%s+gain%s+(%d+%%?)%s+(.-)%s*%.?$")
        end
        if bonusVal and bonusStat then
            bonusStat = bonusStat:gsub("%s+", " "):match("^%s*(.-)%s*$")
            local statLower = bonusStat:lower()
            local bonusResult = nil
            if statLower == "critical hit rate" or statLower == "critical strike chance" then
                bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к шансу крит. удара."
            elseif statLower == "damage amplification" or statLower == "damage increase" or statLower == "damage deepening" then
                bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к увеличению урона."
            elseif statLower == "damage reduction" then
                bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к снижению урона."
            elseif statLower == "defense" then
                if bonusVal:find("%%") then
                    bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к защите."
                else
                    bonusResult = "Ваши фигуры получают +" .. bonusVal .. " ед. защиты."
                end
            elseif statLower == "health" or statLower == "max health" then
                if bonusVal:find("%%") then
                    bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к максимальному здоровью."
                else
                    bonusResult = "Ваши фигуры получают +" .. bonusVal .. " ед. здоровья."
                end
            elseif statLower == "life steal" or statLower == "lifesteal" then
                bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к вампиризму."
            elseif statLower == "attack speed" then
                bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к скорости атаки."
            elseif statLower == "attack" then
                if bonusVal:find("%%") then
                    bonusResult = "Ваши фигуры получают +" .. bonusVal .. " к атаке."
                else
                    bonusResult = "Ваши фигуры получают +" .. bonusVal .. " ед. атаки."
                end
            end
            if bonusResult then
                visibleTextCache[value] = bonusResult
                return bonusResult
            end
        end

        -- For English strings (especially in AutoChess context):
        -- Attempt dynamic skill template matching and normalized shard lookup before returning raw text
        local skillFallback = runtimeFixes.translateAutoChessSkill(value)
        if skillFallback ~= nil then
            visibleTextCache[value] = skillFallback
            return skillFallback
        end

        if value:find("\r", 1, true) or value:find("^%s+") or value:find("%s+$") then
            local normText = value:gsub("\r\n", "\n"):gsub("\r", "\n"):match("^%s*(.-)%s*$")
            if normText and normText ~= "" and normText ~= value then
                local normGemini = runtimeFixes.lookupGeminiTextFuzzy(normText)
                if normGemini ~= nil then
                    visibleTextCache[value] = normGemini
                    return normGemini
                end
            end
        end

        -- CRITICAL: DO NOT cache untranslated English strings into visibleTextCache!
        -- Caching raw English freezes missing translations for the entire session.
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
        local result = "<GreenVoice>" .. voiceChatCount .. "</> чел. в голосовом чате..."
        visibleTextCache[value] = result
        return result
    end

    local obtainableQuantity = value:match("^可获得数量：(%d+)$")
        or value:match("^可获得数量:(%d+)$")
    if obtainableQuantity ~= nil then
        local result = "Доступное количество: " .. obtainableQuantity
        visibleTextCache[value] = result
        return result
    end

    local physicalBlock, magicalBlock = value:match(
        "^提高角色格挡物理伤害或魔法伤害的几率。格挡后，角色仅受到30%%伤害，且此次伤害不会触发暴击（格挡率不会高于75%%）。%s*"
            .. "角色物理格挡：(<Mark>.-</>)%s*角色魔法格挡：(<Mark>.-</>)$"
    )
    if physicalBlock ~= nil then
        local result = "Повышает шанс персонажа заблокировать физический или магический урон. "
            .. "После блокирования персонаж получает только 30% урона, и этот удар "
            .. "не может быть критическим (шанс блока не превышает 75%).\n\n"
            .. "Физ. блок: " .. physicalBlock .. "\n"
            .. "Маг. блок: " .. magicalBlock
        visibleTextCache[value] = result
        return result
    end

    local sharedOpenCurrent, sharedOpenMaximum = value:match(
        "^今日剩余共享开启次数：<Remaining>(%d+)/(%d+)次</>$"
    )
    if sharedOpenCurrent ~= nil then
        local result = "Осталось общих открытий на сегодня: <Remaining>"
            .. sharedOpenCurrent .. "/" .. sharedOpenMaximum .. "</>"
        visibleTextCache[value] = result
        return result
    end

    local newMessageCount = value:match("^新消息(%d+)条$")
    if newMessageCount ~= nil then
        local result = newMessageCount .. " новых сообщений"
        visibleTextCache[value] = result
        return result
    end

    local aggregateCount = value:match("^本次一键聚合累计聚合(%d+)次，共消耗$")
    if aggregateCount ~= nil then
        local result = "При этом быстром объединении выполнено " .. aggregateCount
            .. " слияний, потрачено:"
        visibleTextCache[value] = result
        return result
    end

    local probabilityRate = value:match("^概率(<Rate>.-</>)$")
    if probabilityRate ~= nil then
        local result = "Вероятность " .. probabilityRate
        visibleTextCache[value] = result
        return result
    end

    local fashionValue = value:match("^风尚值：(%d+)$")
        or value:match("^风尚值:(%d+)$")
    if fashionValue ~= nil then
        local result = "Очки стиля: " .. fashionValue
        visibleTextCache[value] = result
        return result
    end

    local ratingValue = value:match("^非凡评分%s*([%d].*)$")
    if ratingValue ~= nil then
        local result = "Оценка " .. ratingValue
        visibleTextCache[value] = result
        return result
    end

    local shieldCurrent, shieldMaximum = value:match("^米尔贡根之盾%((%d+)/(%d+)%)$")
    if shieldCurrent ~= nil then
        local result = "Щит Мильгонгена (" .. shieldCurrent .. "/" .. shieldMaximum .. ")"
        visibleTextCache[value] = result
        return result
    end

    local mergeCurrent, mergeMaximum = value:match("^选择需要聚合的非凡物质(%d+)/(%d+)$")
    if mergeCurrent ~= nil then
        local result = "Выберите материалы Потусторонних для слияния " .. mergeCurrent .. "/" .. mergeMaximum
        visibleTextCache[value] = result
        return result
    end

    local distributionTime = value:match("^分配中(<Time>.-</>)$")
    if distributionTime ~= nil then
        local result = "Распределение " .. distributionTime
        visibleTextCache[value] = result
        return result
    end

    local recollectionLevel = value:match("^回想(%d+)级$")
    if recollectionLevel ~= nil then
        local result = "Воспоминание ур. " .. recollectionLevel
        visibleTextCache[value] = result
        return result
    end

    local awakeningLevel = value:match("^觉醒等级Lv(%d+)$")
    if awakeningLevel ~= nil then
        local result = "Уровень пробуждения Lv. " .. awakeningLevel
        visibleTextCache[value] = result
        return result
    end

    local unlockDays, unlockHours, unlockMinutes = value:match(
        "^解冻剩余时间：(%d+)天(%d+)小时(%d+)分$"
    )
    if unlockDays ~= nil then
        local result = "До разморозки: " .. unlockDays .. " д. "
            .. unlockHours .. " ч. " .. unlockMinutes .. " мин."
        visibleTextCache[value] = result
        return result
    end

    local dailyRefreshHour = value:match("^每日(%d+)点自动刷新$")
    if dailyRefreshHour ~= nil then
        local result = "Ежедневное обновление в " .. dailyRefreshHour .. ":00"
        visibleTextCache[value] = result
        return result
    end

    local noticeHours, noticeMinutes = value:match("^公示期(%d+)小时(%d+)分$")
    if noticeHours ~= nil then
        local result = "Срок показа: " .. noticeHours .. " ч. " .. noticeMinutes .. " мин."
        visibleTextCache[value] = result
        return result
    end

    local countdownHours, countdownMinutes = value:match(
        "^公示期倒计时：(%d+)小时(%d+)分钟$"
    )
    if countdownHours ~= nil then
        local result = "До окончания показа: " .. countdownHours
            .. " ч. " .. countdownMinutes .. " мин."
        visibleTextCache[value] = result
        return result
    end

    local historyPoints = value:match("^达成奖励：获得历史研究积分%+(%d+)$")
    if historyPoints ~= nil then
        local result = "Награда за выполнение: Очки исторических исследований +" .. historyPoints
        visibleTextCache[value] = result
        return result
    end

    local stackCount = value:match("^(%d+)层$")
    if stackCount ~= nil then
        local result = stackCount .. " ур."
        visibleTextCache[value] = result
        return result
    end

    local selectedCount, selectedMaximum = value:match(
        "^当前已选择%s*<Yellow>(%d+)</>/(%d+)$"
    )
    if selectedCount ~= nil then
        local result = "Выбрано: <Yellow>" .. selectedCount .. "</>/" .. selectedMaximum
        visibleTextCache[value] = result
        return result
    end

    if value:find("【半神】", 1, true) == 1 and value:find("真神：序列0", 1, true) then
        local result = "【Полубог】\n"
            .. "Описание: Общее обозначение для Святых и Ангелов с Последовательности 4 по Последовательность 1. "
            .. "Их жизнь и дух претерпевают качественное перерождение, они обретают 50% божественности, а их способности выходят за пределы смертных. "
            .. "Полубоги могут продолжить продвижение к Истинному Богу. Полубоги делятся на Святых и Ангелов; Последовательность 0, стоящая выше Последовательности 1, именуется Истинным Богом.\n"
            .. "Истинный Бог: Последовательность 0, обладающая завершенной формой Мифического Существа.\n"
            .. "Где найти: Меню -> Последовательность для продвижения.\n"
            .. "Связано: Развитие персонажа -> Усиление"
        visibleTextCache[value] = result
        return result
    end

    local interval, damage, slowPercent, duration = value:match(
        "^在目标位置召唤窥秘之眼链接目标，每([%d%.]+)秒对目标造成([%d%.]+)伤害并使目标减速([%d%.]+)%%。链接最多持续([%d%.]+)秒，目标远离窥秘之眼一定距离后链接会提前断开。$"
    )
    if interval ~= nil then
        local result = "Призывает Око Тайны в указанной области, связывая его с целью, нанося "
            .. damage .. " ед. урона каждые " .. interval .. " сек. и замедляя цель на "
            .. slowPercent .. "%. Связь длится до " .. duration
            .. " сек. и разрывается раньше, если цель отойдет слишком далеко от Ока Тайны."
        visibleTextCache[value] = result
        return result
    end

    local gemini = runtimeFixes.lookupGeminiTextFuzzy(value)
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

runtimeFixes.collapseSpacedCharacters = function(text)
    if type(text) ~= "string" or text == "" then return text end
    if #text >= 60 then return text end

    -- Strict check: no punctuation or markup tags
    if text:find("[%p<>«»—–\r\n\t]") then return text end

    -- String length must be < 20 characters
    local _, charCount = text:gsub("[^\128-\191]", "")
    if charCount >= 20 then return text end

    -- If any word has more than 1 character, the string is definitely not spaced text
    local tokenCount = 0
    for word in text:gmatch("%S+") do
        local _, wLen = word:gsub("[^\128-\191]", "")
        if wLen > 1 then
            return text
        end
        tokenCount = tokenCount + 1
    end
    if tokenCount < 2 then
        return text
    end

    local uchar = "[%z\1-\127\194-\244][\128-\191]*"
    local isSpaced = text:match("^%s*" .. uchar .. "%s+" .. uchar .. "%s*$")
        or text:match("^%s*" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s*$")
        or text:match("^%s*" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s*$")
        or text:match("^%s*" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s*$")
        or text:match("^%s*" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s*$")
        or text:match("^%s*" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s+" .. uchar .. "%s*$")
        or text:match("^%s*%S%s+%S%s*$")
        or text:match("^%s*%S%s+%S%s+%S%s*$")
        or text:match("^%s*%S%s+%S%s+%S%s+%S%s*$")

    if isSpaced then
        local placeholder = "\31"
        local preserved = text:gsub("(%S)%s%s+(%S)", "%1" .. placeholder .. "%2")
        local collapsed = preserved
        local prev = nil
        local iterations = 0
        while prev ~= collapsed and iterations < 50 do
            prev = collapsed
            collapsed = collapsed:gsub("(%S)%s(%S)", "%1%2")
            iterations = iterations + 1
        end
        collapsed = collapsed:gsub(placeholder, " ")
        return collapsed:match("^%s*(.-)%s*$") or text
    end
    return text
end

runtimeFixes.widgetOriginalFontSizes = {}
runtimeFixes.getAdjustedFontSize = function(widget, currentSize, wName, isEscLocked)
    if isEscLocked or (ESC_MENU_LOCKED and wName and (wName:find("menubtn") or wName:find("escape") or wName:find("menu_panel"))) then
        return tonumber(currentSize) or 18
    end
    local key = nil
    pcall(function()
        if widget.GetPathName ~= nil then
            key = tostring(widget:GetPathName())
        end
    end)
    if key == nil or key == "" then
        key = tostring(widget)
    end
    local orig = runtimeFixes.widgetOriginalFontSizes[key]
    if orig == nil then
        orig = tonumber(currentSize) or 18
        if orig > 36 then
            orig = 18
        end
        runtimeFixes.widgetOriginalFontSizes[key] = orig
    end
    return orig + 2
end

local function translateTextWidget(widget, discoveryContext)
    if widget == nil or (type(widget) ~= "userdata" and type(widget) ~= "table") then
        return 0
    end

    local current = nil
    local getText = nil
    local methodOk = pcall(function() getText = widget.GetText end)
    if methodOk and type(getText) == "function" then
        local ok, val = pcall(getText, widget)
        if ok and val ~= nil then
            local sVal = tostring(val)
            if sVal ~= "" then
                current = sVal
            end
        end
    end
    if current == nil or current == "" then
        pcall(function()
            local propVal = widget.Text
            if propVal ~= nil then
                local sVal = tostring(propVal)
                if sVal ~= "" then
                    current = sVal
                end
            end
        end)
    end

    local currentText = (type(current) == "string" and current ~= "") and current or nil
    local widgetName = "Text"
    pcall(function()
        widgetName = tostring(widget:GetName())
    end)
    local wName = widgetName:lower()
    local isEscLocked = false
    pcall(function() isEscLocked = (widget.__cpddEscMenuLocked == true) end)
    if wName:find("talkcontent") or isEscLocked or (ESC_MENU_LOCKED and wName:find("menubtn")) then
        return 0
    end

    local repairedCount = 0
    local translated = nil

    if currentText ~= nil then
        local collapsedCurrent = runtimeFixes.collapseSpacedCharacters(currentText)
        local candidate = translateVisibleText(collapsedCurrent)
        if candidate ~= nil and candidate ~= collapsedCurrent and (runtimeFixes.hasCyrillic(candidate) or candidate ~= currentText) then
            translated = candidate
        elseif repairLiveString then
            local repaired = repairLiveString("WidgetText", widgetName, widgetName, collapsedCurrent)
            if repaired ~= nil and repaired ~= collapsedCurrent and (runtimeFixes.hasCyrillic(repaired) or repaired ~= currentText) then
                translated = repaired
            end
        end
        if translated == nil then
            translated = (candidate ~= nil and candidate ~= collapsedCurrent) and candidate or collapsedCurrent
        end
        if translated == collapsedCurrent and collapsedCurrent ~= currentText then
            translated = collapsedCurrent
        end

        if translated ~= currentText then
            local changed = pcall(function()
                if widget.SetText ~= nil then
                    widget:SetText(translated)
                end
            end)
            -- KGTextBlock / RichTextBlock can repaint its serialized Text property after a
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
    end

    -- STRICT UNIVERSAL RULE: Enforce 0 letter spacing and standard font on ALL widgets,
    -- even if currently empty, to ensure subsequent C++/Blueprint updates inherit proper styling.
    pcall(function()
        local textToCheck = translated or currentText or ""
        local isCinematicName = runtimeFixes.isCinematicWidgetName(wName)
        local isSynergyWidget = (wName:find("fetter") ~= nil or wName:find("bond") ~= nil or wName:find("synergy") ~= nil
            or widgetName == "Text_FetterName" or widgetName == "WBP_Title_Fetter" or widgetName == "Text_Bond")
        local isBodyName = not isCinematicName and not isSynergyWidget and (wName:find("desc") or wName:find("content") or wName:find("detail")
            or wName:find("tips") or wName:find("message") or wName:find("info")
            or (type(textToCheck) == "string" and #textToCheck > 40))
        local isTitleName = not isCinematicName and not isSynergyWidget and (wName:find("title") or wName:find("btn") or wName:find("tab")
            or wName:find("header") or wName:find("name") or wName:find("sub") or wName:find("choice")
            or wName:find("server") or wName:find("chapter") or wName:find("rank"))

        local hasCyrillic = (type(textToCheck) == "string") and (textToCheck:find("[\208\209]") ~= nil)
        local targetLs = 0
        if isSynergyWidget then
            targetLs = 0
        elseif hasCyrillic then
            targetLs = isTitleName and -120 or -60
        end

        if widget.SetLetterSpacing ~= nil then widget:SetLetterSpacing(targetLs) end
        if widget.LetterSpacing ~= nil then widget.LetterSpacing = targetLs end

        if isSynergyWidget and (wName:find("title_fetter") or wName:find("wbp_title_fetter") or widgetName == "WBP_Title_Fetter") then
            pcall(function()
                if widget.SetRenderScale ~= nil then
                    widget:SetRenderScale(sceneTextVector2D(0.7, 0.7))
                end
            end)
        end

        local font = widget.GetFont and widget:GetFont() or widget.Font
        if font ~= nil then
            if font.FontObject ~= nil then
                if isCinematicName or runtimeFixes.isCinematicFontObject(font.FontObject) then
                    if runtimeFixes.CinematicFontObject == nil then
                        runtimeFixes.CinematicFontObject = font.FontObject
                        local fPath = ""
                        pcall(function() if font.FontObject.GetPathName ~= nil then fPath = tostring(font.FontObject:GetPathName()) end end)
                        report("identified CinematicFontObject from " .. tostring(wName) .. " path=" .. fPath)
                    end
                elseif isBodyName and not isTitleName then
                    runtimeFixes.registerFontCandidate(font.FontObject, font.TypefaceFontName, wName)
                end
            end

            -- STRICT UNIVERSAL RULE: Replace font object with StandardFontObject whenever known!
            -- Strictly eliminates Cinematic font across all UI widgets, scene text, task boards, and subtitles.
            if runtimeFixes.StandardFontObject ~= nil and font.FontObject ~= runtimeFixes.StandardFontObject then
                local fPath = ""
                pcall(function() if font.FontObject.GetPathName ~= nil then fPath = tostring(font.FontObject:GetPathName()):lower() end end)
                local isRunic = fPath:find("mistery") or fPath:find("mystery") or fPath:find("theleon") or fPath:find("hermes")
                local hasCyrillicText = (type(textToCheck) == "string" and textToCheck:find("[\208-\209][\128-\191]") ~= nil)
                -- Only preserve decorative/runic Hermes fonts if the widget strictly has non-Cyrillic text.
                -- All other UI widgets receive StandardFontObject immediately so the old font does not return.
                if not (isRunic and not hasCyrillicText) then
                    font.FontObject = runtimeFixes.StandardFontObject
                    if runtimeFixes.StandardTypefaceFontName ~= nil then
                        font.TypefaceFontName = runtimeFixes.StandardTypefaceFontName
                    end
                end
            end

            font.LetterSpacing = targetLs

            local baseSize = runtimeFixes.getAdjustedFontSize(widget, font.Size, wName, isEscLocked)
            if isSynergyWidget then
                local textLen = (type(textToCheck) == "string") and runtimeFixes.utf8Len(textToCheck) or 0
                if textLen > 14 then
                    font.Size = 10.5
                elseif textLen > 8 then
                    font.Size = 12
                else
                    font.Size = math.min(baseSize, 14)
                end
                if widget.SetAutoWrapText ~= nil then
                    widget:SetAutoWrapText(false)
                elseif widget.AutoWrapText ~= nil then
                    widget.AutoWrapText = false
                end
            elseif isTitleName then
                local textLen = (type(textToCheck) == "string") and runtimeFixes.utf8Len(textToCheck) or 0
                if textLen > 14 then
                    font.Size = math.min(baseSize, 14)
                elseif textLen > 10 then
                    font.Size = math.min(baseSize, 15)
                elseif textLen > 6 then
                    font.Size = math.min(baseSize, 16)
                elseif baseSize > 20 then
                    font.Size = 18
                else
                    font.Size = baseSize
                end
                if widget.SetAutoWrapText ~= nil then
                    widget:SetAutoWrapText(false)
                elseif widget.AutoWrapText ~= nil then
                    widget.AutoWrapText = false
                end
            elseif baseSize > 22 then
                font.Size = 20
            else
                font.Size = baseSize
            end

            widget.Font = font
            if widget.SetFont ~= nil then widget:SetFont(font) end
        end

        -- RichTextBlock candidate harvesting only.
        -- NEVER override DefaultTextStyleOverride or swap FontObject on RichTextBlock:
        -- RichTextBlock is driven by its authored TextStyleSet (DataTable). Overriding it
        -- corrupts Slate font materials and triggers UE5 fallback magenta/purple rendering.
        local style = (widget.GetDefaultTextStyleOverride and widget:GetDefaultTextStyleOverride())
            or widget.DefaultTextStyleOverride
            or (widget.GetDefaultTextStyle and widget:GetDefaultTextStyle())
            or widget.DefaultTextStyle

        if style ~= nil and style.Font ~= nil then
            if style.Font.FontObject ~= nil then
                if isCinematicName or runtimeFixes.isCinematicFontObject(style.Font.FontObject) then
                    if runtimeFixes.CinematicFontObject == nil then
                        runtimeFixes.CinematicFontObject = style.Font.FontObject
                    end
                elseif isBodyName and not isTitleName then
                    runtimeFixes.registerFontCandidate(style.Font.FontObject, style.Font.TypefaceFontName, wName)
                end
            end
        end
        if widget.SynchronizeProperties ~= nil then widget:SynchronizeProperties() end
        if widget.InvalidateLayoutAndVolatility ~= nil then widget:InvalidateLayoutAndVolatility() end
    end)
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

    if runtimeFixes.StandardFontObject == nil or runtimeFixes.isCinematicFontObject(runtimeFixes.StandardFontObject) then
        pcall(function()
            local seedNames = { "Server_Name_Text", "Server_Name_Text1", "Text_ServerName", "Text_BtnName", "Text_Name", "Text_Content", "Text_Desc", "Text_Tips", "Text_Detail", "Text_Info" }
            for _, sName in ipairs(seedNames) do
                if not runtimeFixes.isCinematicWidgetName(sName) then
                    local w = (type(view) == "table" and view[sName]) or (userWidget ~= nil and getNamedWidget(userWidget, sName))
                    if w ~= nil then
                        local f = w.GetFont and w:GetFont() or w.Font
                        if f == nil then
                            local st = (w.GetDefaultTextStyleOverride and w:GetDefaultTextStyleOverride()) or w.DefaultTextStyleOverride or w.DefaultTextStyle
                            if st ~= nil then f = st.Font end
                        end
                        if f ~= nil and f.FontObject ~= nil and not runtimeFixes.isCinematicFontObject(f.FontObject) then
                            runtimeFixes.registerFontCandidate(f.FontObject, f.TypefaceFontName, sName)
                            if runtimeFixes.StandardFontObject ~= nil and not runtimeFixes.isCinematicFontObject(runtimeFixes.StandardFontObject) then
                                break
                            end
                        end
                    end
                end
            end
        end)
    end

    local function translateWidgetTree(owner)
        walkWidgetDescendants(owner, visited, function(widget)
            local wName = ""
            pcall(function() wName = tostring(widget:GetName()):lower() end)
            if wName:find("wbp_title_fetter") or wName:find("title_fetter") then
                pcall(function()
                    if widget.SetRenderScale ~= nil then
                        widget:SetRenderScale(sceneTextVector2D(0.7, 0.7))
                    end
                end)
            end
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

local SOURCE_SHARD_CACHE_LIMIT = 256
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
    local shopLimit = runtimeFixes.normalizeShopLotLimit(value)
    if shopLimit ~= value then
        return shopLimit
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
    -- Exact generated translations are authoritative for a complete source
    -- value. Consult them before either cache: an earlier fragment repair may
    -- have cached a mixed result such as "你在做What?", which must never mask
    -- the reviewed whole-string translation on KSBC rows.
    local geminiExact = runtimeFixes.lookupGeminiTextFuzzy(value)
    if type(geminiExact) == "string" and geminiExact ~= ""
        and not hasCjk(geminiExact)
    then
        local result = runtimeFixes.normalizeDefenseBreakTerminology(
            preserveMovableAnswerMarkup(value, geminiExact)
        )
        local onIntercept = rawget(_G, "__LOM_OnTextIntercepted")
        if onIntercept then pcall(onIntercept, tableName or "live", value, result) end
        return result
    end

    if not hasCjk(value) then
        local onIntercept = rawget(_G, "__LOM_OnTextIntercepted")
        if onIntercept then pcall(onIntercept, tableName or "untranslated", value, value) end
        return value
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
    if speakerPrefix ~= nil then
        local exactSpoken = runtimeFixes.lookupGeminiTextFuzzy(spokenText)
            or visibleTextExactOverrides[spokenText]
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
        if hasCjk(spokenText) then
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

local function sceneTextVector2D(x, y)
    if type(FVector2D) == "function" then
        local ok, value = pcall(FVector2D, x, y)
        if ok then
            return value
        end
    end
    return { X = x, Y = y }
end

do
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
    local hasLetters = plain:find("[A-Za-z]") ~= nil or plain:find("[\208-\209]") ~= nil
    local charLen = runtimeFixes.utf8Len(plain)
    return hasLetters and (charLen > SCENE_TEXT_PRIMARY_ROW_MAX or plain:find("[\r\n]") ~= nil)
end

local function isPlainAsciiSceneTitle(value)
    if type(value) ~= "string" or value == "" then
        return false
    end
    if runtimeFixes.utf8Len(value) > SCENE_TEXT_TITLE_MAX then
        return false
    end
    if value:find("[\r\n]") or value:find("<", 1, true) or value:find(">", 1, true) then
        return false
    end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 32 then
            return false
        end
    end
    return true
end

local function reflowEnglishSceneTitle(displayText, leonSubTitle)
    if not isPlainAsciiSceneTitle(displayText)
        or (leonSubTitle ~= nil and leonSubTitle ~= "")
        or runtimeFixes.utf8Len(displayText) <= SCENE_TEXT_PRIMARY_ROW_MAX then
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
        local overflow = math.max(0, runtimeFixes.utf8Len(primary) - SCENE_TEXT_PRIMARY_ROW_MAX)
        local score = overflow * 100 + math.abs(runtimeFixes.utf8Len(primary) - runtimeFixes.utf8Len(continuation))
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
    local longestLen = 0
    for line in value:gmatch("[^\r\n]+") do
        local plain = line:gsub("<.->", "")
        if isPlainAsciiSceneTitle(plain) then
            local lLen = runtimeFixes.utf8Len(plain)
            if longest == nil or lLen > longestLen then
                longest = plain
                longestLen = lLen
            end
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
    local changed = false
    if type(cppEntity.KAPI_Actor_UpdateFontLetterSpacing) == "function" then
        changed = pcall(cppEntity.KAPI_Actor_UpdateFontLetterSpacing, cppEntity, 0) or changed
    end
    local longestLine = longestPlainAsciiSceneLine(displayText)
    if longestLine == nil then
        return changed
    end
    local fontInfo = self.SceneConf and self.SceneConf.FontInfo
    local baseSize = fontInfo and tonumber(fontInfo.Size)
    if not baseSize or baseSize <= 0 then
        return changed
    end
    local charCount = runtimeFixes.utf8Len(longestLine)
    local targetSize = baseSize
    if charCount > SCENE_TEXT_PRIMARY_ROW_MAX then
        targetSize = math.min(targetSize, SCENE_TEXT_MAX_ENGLISH_FONT_SIZE)
        if charCount > SCENE_TEXT_MAIN_LINE_CHAR_BUDGET then
            targetSize = math.min(
                targetSize,
                math.max(
                    SCENE_TEXT_MIN_FONT_SIZE,
                    math.floor(
                        baseSize * SCENE_TEXT_MAIN_LINE_CHAR_BUDGET / charCount + 0.5
                    )
                )
            )
        end
    end
    if type(cppEntity.KAPI_Actor_UpdateFontSize) == "function" then
        changed = pcall(cppEntity.KAPI_Actor_UpdateFontSize, cppEntity, targetSize) or changed
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
        pcall(translateTextWidget, textDetail)
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
end

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
        [2] = "Второе место",
        [3] = "Третье место",
        [4] = "Четвертое место",
        [5] = "Пятое место",
        [6] = "Шестое место",
        [7] = "Седьмое место",
        [8] = "Восьмое место",
        [9] = "Девятое место",
        [10] = "Десятое место",
        [11] = "Одиннадцатое место",
        [12] = "Двенадцатое место",
        [13] = "Тринадцатое место",
        [14] = "Четырнадцатое место",
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

do
    local CIRCUIT_BREAKER_TIPS_ID = 6427242
    local CIRCUIT_BREAKER_TEXT = "If the server is too crowded, it will enter a circuit-breaker state, temporarily preventing new accounts that have not created a character on the current server from queuing. Please choose another server that is not under a circuit-breaker to experience the game."

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
end

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
            font.Size = math.min(currentSize + 2, 20)
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
        font.Size = math.min(currentSize + 2, 20)
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
    runtimeFixes.setPanelWidgetText(self, "Text_Title_2", "Эффект след. уровня")
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
    local view = self.view
    local root = self.userWidget or self.widget or self.WidgetTree or (type(view) == "userdata" and view) or (type(self) == "userdata" and self)
    local repaired = translateViewTextWidgets(view, root)
    if taskInfoRepairReports[self] ~= true then
        taskInfoRepairReports[self] = true
        report("Task Info targeted repair active labels=" .. tostring(repaired))
        pcall(function()
            if type(view) == "table" then
                for k, v in pairs(view) do
                    if type(v) == "userdata" then
                        local cls = (v.GetClass and v:GetClass():GetName()) or "unknown"
                        local fPath, tsPath = "", ""
                        local f = v.GetFont and v:GetFont() or v.Font
                        if f and f.FontObject and f.FontObject.GetPathName then fPath = tostring(f.FontObject:GetPathName()) end
                        if v.TextStyleSet and v.TextStyleSet.GetPathName then tsPath = tostring(v.TextStyleSet:GetPathName()) end
                        report(">>> TASK_INFO_MEMBER: name=" .. tostring(k) .. " class=" .. tostring(cls) .. " font=" .. fPath .. " ts=" .. tsPath)
                    end
                end
            end
        end)
    end
    return repaired
end

local taskListItemRepairReports = setmetatable({}, { __mode = "k" })
local function repairTaskListItemLabels(self)
    if self == nil then return 0 end
    local view = self.view
    local root = self.userWidget or self.widget or self.WidgetTree or (type(view) == "userdata" and view) or (type(self) == "userdata" and self)
    local repaired = translateViewTextWidgets(view, root)
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
        repaired = repaired + translateViewTextWidgets(view, root)
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
        { "OnRefresh", "Refresh", "SetData", "setData", "setServerInfo", "setServerInfoUI", "InitUIView", "UpdateUI", "OnInit" },
        function(self)
            local view = self and (self.view or self.WidgetTree or self.userWidget or self)
            local serverWidget = getNamedWidget(view, "Server_Name_Text") or (self and getNamedWidget(self, "Server_Name_Text"))
                or getNamedWidget(view, "Server_Name_Text1") or (self and getNamedWidget(self, "Server_Name_Text1"))
            if serverWidget ~= nil then
                local f = serverWidget.GetFont and serverWidget:GetFont() or serverWidget.Font
                if f ~= nil and f.FontObject ~= nil and not runtimeFixes.isCinematicFontObject(f.FontObject) then
                    runtimeFixes.registerFontCandidate(f.FontObject, f.TypefaceFontName, "LoginServerItem")
                end
            end
            local function adaptServerWidget(w)
                if w == nil then return end
                translateTextWidget(w)
                pcall(function()
                    if w.SetLetterSpacing ~= nil then w:SetLetterSpacing(0) end
                    if w.LetterSpacing ~= nil then w.LetterSpacing = 0 end
                    local font = w.GetFont and w:GetFont() or w.Font
                    if font ~= nil then
                        font.LetterSpacing = 0
                        local text = nil
                        if w.GetText ~= nil then text = w:GetText() end
                        if (text == nil or text == "") and w.Text ~= nil then text = w.Text end
                        local textLen = (type(text) == "string") and runtimeFixes.utf8Len(text) or 0
                        local baseSize = runtimeFixes.getAdjustedFontSize(w, font.Size, "Server_Name_Text", false)
                        if textLen > 14 then
                            font.Size = math.min(baseSize, 16)
                        elseif textLen > 10 then
                            font.Size = math.min(baseSize, 17)
                        elseif textLen > 6 then
                            font.Size = math.min(baseSize, 18)
                        else
                            font.Size = math.min(baseSize, 19)
                        end
                        w.Font = font
                        if w.SetFont ~= nil then w:SetFont(font) end
                    end
                    if w.SetAutoWrapText ~= nil then
                        w:SetAutoWrapText(false)
                    elseif w.AutoWrapText ~= nil then
                        w.AutoWrapText = false
                    end
                    if w.SynchronizeProperties ~= nil then w:SynchronizeProperties() end
                    if w.InvalidateLayoutAndVolatility ~= nil then w:InvalidateLayoutAndVolatility() end
                end)
            end
            adaptServerWidget(getNamedWidget(view, "Server_Name_Text") or (self and getNamedWidget(self, "Server_Name_Text")))
            adaptServerWidget(getNamedWidget(view, "Server_Name_Text1") or (self and getNamedWidget(self, "Server_Name_Text1")))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.Login.LoginServerSelect_Panel",
        "LoginServerSelect_Panel",
        { "OnOpen", "OnRefresh", "Refresh", "InitUIView", "OnShow", "UpdateUI", "OnInit" },
        function(self)
            local view = self and (self.view or self.WidgetTree or self.userWidget or self)
            local root = self and (self.userWidget or self.widget or self.WidgetTree)
            translateViewTextWidgets(view, root)
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.Login.LoginPanel",
        "LoginPanel",
        { "setServerInfoUI", "OnRefresh", "Refresh", "InitUIView" },
        function(self)
            translateTextWidget(getNamedWidget(self and self.view, "Text_ServerName"))
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.Dialogue.DialogueScreenTextComp",
        "DialogueScreenTextComp",
        { "OnSectionInit", "OnRefresh", "Refresh" },
        function(self)
            local function doRepair()
                local target = self and (self.usingScreenText or (self.view and self.view.usingScreenText))
                local w = getNamedWidget(target, "RTB_Aside1_lua")
                    or (self and self.view and getNamedWidget(self.view, "RTB_Aside1_lua"))
                if w ~= nil then translateTextWidget(w) end
            end
            doRepair()
            scheduleRepairAfter(self, 0.05, doRepair)
            scheduleRepairAfter(self, 0.20, doRepair)
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.Border_Panel",
        "Border_Panel",
        { "SetBlackScreenText", "OnOpen", "OnRefresh", "Refresh", "InitUIView" },
        function(self)
            local function doRepair()
                local view = self and self.view
                local root = self and (self.userWidget or self.widget or self.WidgetTree or (type(view) == "userdata" and view) or (type(self) == "userdata" and self))
                local w = (view and (view.RTB_Aside1_lua or getNamedWidget(view, "RTB_Aside1_lua") or getNamedWidget(view.WidgetRoot, "RTB_Aside1_lua")))
                    or (root and getNamedWidget(root, "RTB_Aside1_lua"))
                if w ~= nil then translateTextWidget(w) end
                translateViewTextWidgets(view, root)
            end
            doRepair()
            scheduleRepairAfter(self, 0.05, doRepair)
            scheduleRepairAfter(self, 0.20, doRepair)
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.NPC.MimeWhite_Panel",
        "MimeWhite_Panel",
        { "SetBlackScreenText", "OnOpen", "OnRefresh", "Refresh", "InitUIView" },
        function(self)
            local function doRepair()
                local view = self and self.view
                local root = self and (self.userWidget or self.widget or self.WidgetTree or (type(view) == "userdata" and view) or (type(self) == "userdata" and self))
                local w = (view and (view.RTB_Aside1_lua or getNamedWidget(view, "RTB_Aside1_lua") or getNamedWidget(view.WidgetRoot, "RTB_Aside1_lua")))
                    or (root and getNamedWidget(root, "RTB_Aside1_lua"))
                if w ~= nil then translateTextWidget(w) end
                translateViewTextWidgets(view, root)
            end
            doRepair()
            scheduleRepairAfter(self, 0.05, doRepair)
            scheduleRepairAfter(self, 0.20, doRepair)
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
                runtimeFixes.setNamedWidgetText({ caption = caption }, "caption", "Оценка")
                return
            end
            local function repairCaption(widget)
                local name
                pcall(function() name = tostring(widget:GetName()) end)
                if name == "C7TextBlock_100" then
                    runtimeFixes.setNamedWidgetText({ caption = widget }, "caption", "Оценка")
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
        { "OnRefresh", "Refresh", "SetData", "setData" },
        repairTaskListItemLabels,
        true,
    },
    {
        "Gameplay.LogicSystem.Task.New.Task_Info",
        "Task_Info",
        { "RefreshInfo", "OnRefresh", "Refresh", "InitUIView", "OnOpen", "OnShow", "UpdateUI", "SetData" },
        function(self)
            local function doRepair()
                repairTaskInfoLabels(self)
            end
            doRepair()
            scheduleRepairAfter(self, 0.05, doRepair)
            scheduleRepairAfter(self, 0.20, doRepair)
        end,
        true,
    },
    {
        "Gameplay.LogicSystem.Task.New.TaskBoardPanel",
        "TaskBoardPanel",
        { "OnOpen", "OnRefresh", "Refresh", "InitUIView", "OnShow", "UpdateUI", "OnInit" },
        function(self)
            local function doRepair()
                local view = self and self.view
                local root = self and (self.userWidget or self.widget or self.WidgetTree or (type(view) == "userdata" and view) or (type(self) == "userdata" and self))
                translateViewTextWidgets(view, root)
            end
            doRepair()
            scheduleRepairAfter(self, 0.05, doRepair)
            scheduleRepairAfter(self, 0.20, doRepair)
        end,
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

-- ============================================================================
-- [FROZEN / LOCKED COMPONENT]: ESC MENU (MenuBtn_Item / Menu_Panel)
-- USER DIRECTIVE: DO NOT TOUCH, REVERT, OR MODIFY THIS ESC MENU LOGIC UNLESS
-- EXPLICITLY DIRECTED BY THE USER IN A DEDICATED PROMPT!
-- ============================================================================
local ESC_MENU_LOCKED = true

local function repairMenuBtnItem(self, params)
    if self == nil then return end
    self.__cpddEscMenuLocked = true
    local view = self.view
    if view ~= nil and type(view) == "table" then
        view.__cpddEscMenuLocked = true
    end

    local widget = (view and getNamedWidget(view, "Text_Name"))
        or (view and view.Text_Name)
        or getNamedWidget(self.userWidget or self.widget, "Text_Name")
    if widget == nil then return end
    pcall(function() widget.__cpddEscMenuLocked = true end)

    local buttonEnum = self.ButtonEnum or self.buttonEnum
        or (params and type(params) == "table" and (params.ButtonEnum or params.buttonEnum))
        or (self.Data and (self.Data.ButtonEnum or self.Data.buttonEnum))
        or (self.data and (self.data.ButtonEnum or self.data.buttonEnum))
    if not buttonEnum then
        local menuId = self.MenuID or self.menuId or self.MenuId or self.menuID
            or (self.Data and (self.Data.MenuID or self.Data.menuId or self.Data.MenuId or self.Data.id or self.Data.Id))
            or (self.data and (self.data.MenuID or self.data.menuId or self.data.MenuId or self.data.id or self.data.Id))
            or (params and type(params) == "table" and (params.MenuID or params.menuId or params.MenuId or params.id or params.Id))
            or (type(params) == "number" and params)
        local menuData = menuId and Game and Game.TableData and Game.TableData.GetMenuDataRow(menuId)
        buttonEnum = menuData and (menuData.ButtonEnum or menuData.buttonEnum)
    end
    local label = buttonEnum and shortMenuLabels[buttonEnum]

    if not label then
        local current = nil
        pcall(function()
            if widget.GetText ~= nil then current = widget:GetText() end
            if (current == nil or current == "") and widget.Text ~= nil then current = widget.Text end
        end)
        if type(current) == "string" and current ~= "" then
            label = runtimeFixes.collapseSpacedCharacters(current)
        end
    end

    if label then
        runtimeFixes.setNamedWidgetText(view or self, "Text_Name", label)
    end

    -- Strict zero letter-spacing: eliminates "С т и л ь" wide tracking in Esc menu grid
    pcall(function()
        if widget.SetLetterSpacing ~= nil then widget:SetLetterSpacing(0) end
        if widget.LetterSpacing ~= nil then widget.LetterSpacing = 0 end
    end)

    pcall(function()
        local font = nil
        if widget.GetFont ~= nil then
            font = widget:GetFont()
        elseif widget.Font ~= nil then
            font = widget.Font
        end
        if font ~= nil then
            if runtimeFixes.StandardFontObject ~= nil and font.FontObject ~= runtimeFixes.StandardFontObject then
                font.FontObject = runtimeFixes.StandardFontObject
                if runtimeFixes.StandardTypefaceFontName ~= nil then
                    font.TypefaceFontName = runtimeFixes.StandardTypefaceFontName
                end
            elseif font.FontObject ~= nil and not runtimeFixes.isCinematicFontObject(font.FontObject) then
                runtimeFixes.registerFontCandidate(font.FontObject, font.TypefaceFontName, "MenuBtnItem")
            end
            font.LetterSpacing = 0
            local effectiveText = label
            if not effectiveText then
                if widget.GetText ~= nil then effectiveText = widget:GetText() end
                if (effectiveText == nil or effectiveText == "") and widget.Text ~= nil then
                    effectiveText = widget.Text
                end
            end
            local textLen = (type(effectiveText) == "string") and runtimeFixes.utf8Len(effectiveText) or 0
            local baseSize = tonumber(font.Size) or 18
            if textLen > 6 then
                font.Size = math.min(baseSize, 14)
            else
                font.Size = math.min(baseSize, 15)
            end
            widget.Font = font
            if widget.SetFont ~= nil then widget:SetFont(font) end
        end
    end)

    pcall(function()
        if widget.SetAutoWrapText ~= nil then
            widget:SetAutoWrapText(false)
        elseif widget.AutoWrapText ~= nil then
            widget.AutoWrapText = false
        end
    end)

    pcall(function()
        if widget.SynchronizeProperties ~= nil then widget:SynchronizeProperties() end
        if widget.InvalidateLayoutAndVolatility ~= nil then widget:InvalidateLayoutAndVolatility() end
    end)
end

local function installShortMenuLabels(value, environment)
    local class = getSymbol(value, environment, "MenuBtn_Item")
    if type(class) ~= "table" then
        return false
    end
    if class.__cpddShortMenuLabels == VERSION then
        return true
    end

    for _, methodName in ipairs({ "OnRefresh", "Refresh", "SetData", "OnOpen" }) do
        local original = class[methodName]
        if type(original) == "function" then
            class[methodName] = function(self, params, ...)
                local results = { original(self, params, ...) }
                pcall(repairMenuBtnItem, self, params)
                return unpack(results)
            end
        end
    end
    class.__cpddShortMenuLabels = VERSION
    report("installed compact Russian menu labels with zero letter-spacing (LOCKED)")
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

local function installMenuPanelRepair(value, environment)
    local class = getSymbol(value, environment, "Menu_Panel")
    if type(class) ~= "table" then
        return false
    end
    if class.__cpddMenuPanelFix == VERSION then
        return true
    end

    local function repairPanelButtons(self)
        if not self then return end
        self.__cpddEscMenuLocked = true
        if type(self._childComponents) == "table" then
            for _, child in pairs(self._childComponents) do
                pcall(repairMenuBtnItem, child)
            end
        end
    end

    for _, methodName in ipairs({ "OnOpen", "OnRefresh", "Refresh" }) do
        local original = class[methodName]
        if type(original) == "function" then
            class[methodName] = function(self, ...)
                local results = { original(self, ...) }
                pcall(repairPanelButtons, self)
                return unpack(results)
            end
        end
    end
    class.__cpddMenuPanelFix = VERSION
    report("installed Menu_Panel layout repair (LOCKED)")
    return true
end

Loader.AfterLoad(
    "Gameplay.LogicSystem.Menu.Menu_Panel",
    function(value, environment)
        installMenuPanelRepair(value, environment)
        return value
    end,
    1000000,
    "cpdd.runtime-fix.menu-panel-repair"
)

-- Item tooltips are reused for subsequent hovered items without closing their
-- UIComponent. Rescan only this proven dynamic panel on Refresh; the pending
-- delayed pass coalesces bursts so this does not restore the global sweep.
local dynamicPanelRescanUids = {
    ActivityMain_Panel = true,
    AutoChess_Hud_Panel = true,
    AutoChessHudPanel = true,
    AutoChess_Hud = true,
    AutoChess_CardDescription_Panel = true,
    AutoChess_GameDetail_Panel = true,
    AutoChess_OutSideMain_Panel = true,
    Border_Panel = true,
    FashionStation_Details_Panel = true,
    GuildInside_Panel = true,
    LoginServerSelect_Panel = true,
    MimeWhite_Panel = true,
    NewbieGuide_MainPanel = true,
    Sealed_Fuse_Main_Panel = true,
    Sealed_Fuse_Select_Panel = true,
    Shops_Panel = true,
    Sequence_Panel = true,
    Task_Panel = true,
    TaskBoardPanel = true,
    TrainTrade_Hud_Panel = true,
}

local extendedPanelRepairDelays = {
    AutoChess_Hud_Panel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChessHudPanel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChess_Hud = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChess_CardDescription_Panel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChessCardDescriptionPanel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChess_GameDetail_Panel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChessGameDetailPanel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChess_OutSideMain_Panel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    AutoChessOutSideMainPanel = { 0.05, 0.15, 0.35, 0.80, 1.50 },
    Border_Panel = { 0.05, 0.20 },
    FashionStation_Details_Panel = { 0.25, 0.75, 1.50 },
    GuildInside_Panel = { 0.25, 0.75 },
    LoginServerSelect_Panel = { 0.15, 0.50, 1.00 },
    MimeWhite_Panel = { 0.05, 0.20 },
    NewbieGuide_MainPanel = { 0.25, 0.75, 1.50, 3.00 },
    Sealed_Fuse_Main_Panel = { 0.25, 0.75, 1.50, 3.00, 6.00, 10.00, 20.00 },
    Sealed_Fuse_Select_Panel = { 0.25, 0.75, 1.50 },
    Sequence_Panel = { 0.50, 1.50, 3.00, 6.00, 10.00, 20.00 },
    Shops_Panel = { 0.25, 0.50, 1.00, 2.00 },
    TaskBoardPanel = { 0.10, 0.35, 0.80 },
}

-- Current-session telemetry showed that these panels translated useful text
-- during their completed root Open pass, then spent 9-37 ms per delayed pass
-- revisiting 209-2162 widgets without changing a label. Their dynamic rows
-- already have dedicated data/view hooks above.
runtimeFixes.SinglePassPanelUids = {
    Menu_Panel = true,
    Sealed_Equip_Panel = true,
    SequencePromotion_Panel = true,
}

-- These high-frequency panels have dedicated data/view hooks above. A generic
-- recursive UIComponent pass only duplicates that work and was measured at up
-- to 80 ms for item previews and 26 ms every 0.2 seconds for the task board.
local targetedPanelRepairUids = {
    BagItemTips_Panel = true,
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
        if current.__cpddEscMenuLocked or (tostring(current.uid or current.__cname) == "Menu_Panel" or tostring(current.uid or current.__cname) == "MenuBtn_Item") then
            return
        end
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
        if tostring(componentUid):find("AutoChess") ~= nil then
            runtimeFixes.repairAutoChessHudAttributes(current)
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

do
    local autoChessExcludedKeyNames = {
        Attr = true, attr = true, Attrs = true, attrs = true,
        Stats = true, stats = true, Stat = true, stat = true,
        PropertyMap = true, propertyMap = true, Properties = true, properties = true, Property = true, property = true,
        BaseAttr = true, baseAttr = true, FightAttr = true, fightAttr = true,
        CombatStats = true, combatStats = true, CombatData = true, combatData = true,
        Actor = true, actor = true, ActorData = true, actorData = true, ActorState = true, actorState = true,
        Component = true, component = true, Components = true, components = true,
        Buff = true, buff = true, Buffs = true, buffs = true, BuffMap = true, buffMap = true,
        SkillMap = true, skillMap = true, SkillId = true, skillId = true,
        Numeric = true, numeric = true, Values = true, values = true,
        Hp = true, hp = true, MaxHp = true, maxHp = true,
        Mp = true, mp = true, MaxMp = true, maxMp = true,
        Attack = true, attack = true, Def = true, def = true, Defense = true, defense = true,
        Speed = true, speed = true, AtkSpeed = true, atkSpeed = true, AttackSpeed = true, attackSpeed = true,
        Crit = true, crit = true, Critical = true, critical = true,
        Range = true, range = true, AttackRange = true, attackRange = true,
        Level = true, level = true, Star = true, star = true, Cost = true, cost = true, Price = true, price = true,
        Id = true, id = true, ID = true, CardId = true, cardId = true, PieceId = true, pieceId = true,
        Guid = true, guid = true, UID = true, uid = true, EntityId = true, entityId = true,
    }

    local autoChessSafeTextFieldNames = {
        Name = true, name = true, CardName = true, cardName = true, PieceName = true, pieceName = true,
        Title = true, title = true, SubTitle = true, subTitle = true,
        Desc = true, desc = true, Description = true, description = true, CardDesc = true, cardDesc = true,
        Detail = true, detail = true, Info = true, info = true, Content = true, content = true,
        Tip = true, tip = true, Tips = true, tips = true,
        Effect = true, effect = true, SkillDesc = true, skillDesc = true, SkillName = true, skillName = true,
        FetterName = true, fetterName = true, FetterDesc = true, fetterDesc = true,
        SynergyName = true, synergyName = true, SynergyDesc = true, synergyDesc = true,
        BondName = true, bondName = true, BondDesc = true, bondDesc = true,
        Role = true, role = true, RoleName = true, roleName = true,
        Race = true, race = true, RaceName = true, raceName = true,
        Profession = true, profession = true, ProfessionName = true, professionName = true,
        Header = true, header = true, Summary = true, summary = true,
        Text = true, text = true, Label = true, label = true,
        Msg = true, msg = true, Message = true, message = true,
        Str = true, str = true, String = true, string = true,
        Story = true, story = true, Lore = true, lore = true,
    }

    local function isAutoChessExcluded(k)
        if k == nil then return false end
        if autoChessExcludedKeyNames[k] then return true end
        if type(k) == "string" then
            local l = k:lower()
            if l:find("attr") or l:find("stat") or l:find("propertymap") or l:find("actor") or l:find("combat") then
                return true
            end
        end
        return false
    end

    local function isAutoChessSafeText(k)
        if k == nil then return false end
        if autoChessSafeTextFieldNames[k] then return true end
        if type(k) == "string" then
            local l = k:lower()
            if l:find("desc") or l:find("name") or l:find("title") or l:find("tips") or l:find("synergy") or l:find("fetter") or l:find("role") or l:find("bond") then
                return true
            end
        end
        return false
    end

    local function safeTranslateAutoChessData(target, seen, depth)
        if target == nil then return target end
        local tType = type(target)
        if tType ~= "table" and tType ~= "userdata" then
            return target
        end
        depth = depth or 0
        if depth > 15 then return target end
        seen = seen or {}
        if seen[target] then return target end
        seen[target] = true

        pcall(function()
            if type(target.Num) == "function" and type(target.Get) == "function" then
                local count = target:Num()
                if type(count) == "number" and count > 0 and count <= 500 then
                    for idx = 0, count - 1 do
                        local item = target:Get(idx)
                        if type(item) == "table" or type(item) == "userdata" then
                            safeTranslateAutoChessData(item, seen, depth + 1)
                        end
                    end
                end
            end
        end)

        if tType == "table" then
            for k, v in pairs(target) do
                if not isAutoChessExcluded(k) then
                    local vType = type(v)
                    if vType == "string" then
                        if isAutoChessSafeText(k) or type(k) == "number" then
                            local t = translateVisibleText(v)
                            if t ~= nil and t ~= v then
                                target[k] = t
                            end
                        end
                    elseif vType == "table" or vType == "userdata" then
                        safeTranslateAutoChessData(v, seen, depth + 1)
                    end
                end
            end
        end
        return target
    end

    runtimeFixes.repairAutoChessHudAttributes = function(comp)
        if comp == nil then return false end
        local root = comp.userWidget or comp.widget
        local view = comp.view
        if root == nil and view == nil then return false end

        local lifeWidget = getNamedWidget(view, "WBP_AutoChess_Tips_LifeSchedule")
            or getNamedWidget(root, "WBP_AutoChess_Tips_LifeSchedule")
        local vitalityWidget = getNamedWidget(view, "WBP_AutoChess_Tips_VitalitySchedule")
            or getNamedWidget(root, "WBP_AutoChess_Tips_VitalitySchedule")
        local distanceWidget = getNamedWidget(view, "WBP_AutoChess_Tips_Distance")
            or getNamedWidget(root, "WBP_AutoChess_Tips_Distance")
        local positionWidget = getNamedWidget(view, "WBP_AutoChess_Tips_Position")
            or getNamedWidget(root, "WBP_AutoChess_Tips_Position")

        if lifeWidget == nil and root ~= nil then
            local idx = getWidgetNameIndex(root)
            if idx then
                lifeWidget = idx["WBP_AutoChess_Tips_LifeSchedule"]
                vitalityWidget = idx["WBP_AutoChess_Tips_VitalitySchedule"]
                distanceWidget = distanceWidget or idx["WBP_AutoChess_Tips_Distance"]
                positionWidget = positionWidget or idx["WBP_AutoChess_Tips_Position"]
                if lifeWidget == nil then
                    for name, w in pairs(idx) do
                        if name:find("Tips_LifeSchedule") then
                            lifeWidget = w
                        elseif name:find("Tips_VitalitySchedule") then
                            vitalityWidget = w
                        elseif name:find("Tips_Distance") then
                            distanceWidget = distanceWidget or w
                        elseif name:find("Tips_Position") then
                            positionWidget = positionWidget or w
                        end
                    end
                end
            end
        end

        if lifeWidget == nil and vitalityWidget == nil then
            return false
        end

        local function getWidgetParent(w)
            if w == nil then return nil end
            local p = nil
            pcall(function()
                if w.GetParent ~= nil then p = w:GetParent() end
            end)
            if p ~= nil then return p end
            pcall(function() p = w.Parent end)
            return p
        end

        local parent = getWidgetParent(lifeWidget) or getWidgetParent(vitalityWidget)
        local grandParent = getWidgetParent(parent)
        local greatGrandParent = getWidgetParent(grandParent)

        local function unclip(w)
            if w == nil then return end
            pcall(function() w.bClipToBounds = false end)
            pcall(function()
                if w.SetClipping ~= nil then
                    w:SetClipping(0)
                end
            end)
            pcall(function()
                if w.SetClipToBounds ~= nil then
                    w:SetClipToBounds(false)
                end
            end)
        end

        unclip(lifeWidget)
        unclip(vitalityWidget)
        unclip(distanceWidget)
        unclip(positionWidget)
        unclip(parent)
        unclip(grandParent)
        unclip(greatGrandParent)

        local function fixOffsetsAndPadding(w)
            if w == nil then return end
            pcall(function()
                local slot = w.Slot
                if slot ~= nil then
                    if slot.SetPosition ~= nil and slot.GetPosition ~= nil then
                        local pos = slot:GetPosition()
                        if pos ~= nil and (pos.Y or 0) < 0 then
                            pos.Y = 0
                            slot:SetPosition(pos)
                        end
                    end
                    if slot.SetOffsets ~= nil and slot.GetOffsets ~= nil then
                        local off = slot:GetOffsets()
                        if off ~= nil and (off.Top or 0) < 0 then
                            off.Top = 0
                            slot:SetOffsets(off)
                        end
                    end
                    if slot.SetPadding ~= nil and slot.GetPadding ~= nil then
                        local pad = slot:GetPadding()
                        if pad ~= nil and (pad.Top or 0) < 0 then
                            slot:SetPadding(FMargin(pad.Left or 0, 0, pad.Right or 0, pad.Bottom or 0))
                        end
                    end
                    if slot.SetAutoSize ~= nil then
                        slot:SetAutoSize(true)
                    end
                end
            end)
            pcall(function()
                if w.SetRenderTranslation ~= nil then
                    w:SetRenderTranslation(sceneTextVector2D(0, 0))
                end
            end)
        end

        fixOffsetsAndPadding(parent)
        fixOffsetsAndPadding(grandParent)
        fixOffsetsAndPadding(lifeWidget)
        fixOffsetsAndPadding(vitalityWidget)

        local ATTR_VISIBLE = 4
        do
            local ok, vis = pcall(function()
                return rawget(_G, "ESlateVisibility") or import("ESlateVisibility")
            end)
            if ok and vis ~= nil then
                ATTR_VISIBLE = vis.SelfHitTestInvisible or vis.Visible or 4
            end
        end

        local function makeVisible(w)
            if w == nil then return end
            pcall(function()
                if w.SetVisibility ~= nil then
                    w:SetVisibility(ATTR_VISIBLE)
                elseif w.Visibility ~= nil then
                    w.Visibility = ATTR_VISIBLE
                end
            end)
            pcall(function()
                if w.SetRenderOpacity ~= nil then
                    w:SetRenderOpacity(1)
                end
            end)
        end

        makeVisible(parent)
        makeVisible(grandParent)
        makeVisible(lifeWidget)
        makeVisible(vitalityWidget)
        makeVisible(distanceWidget)
        makeVisible(positionWidget)

        if parent ~= nil then
            pcall(function()
                if parent.GetChildrenCount ~= nil then
                    local count = tonumber(parent:GetChildrenCount()) or 0
                    for i = 0, count - 1 do
                        local child = parent:GetChildAt(i)
                        if child ~= nil then
                            makeVisible(child)
                            unclip(child)
                            if child.GetChildrenCount ~= nil then
                                local subCount = tonumber(child:GetChildrenCount()) or 0
                                for j = 0, subCount - 1 do
                                    local subChild = child:GetChildAt(j)
                                    makeVisible(subChild)
                                    unclip(subChild)
                                end
                            end
                        end
                    end
                end
            end)
        end

        for _, attrName in ipairs({
            "Text_Hp", "Text_HP", "Text_Life", "Text_Attack", "Text_Atk",
            "Text_Defense", "Text_Def", "Text_Speed", "Text_AtkSpeed", "Text_AttackSpeed",
            "Text_Distance", "Text_Position", "Canvas_Attr", "Attr_Panel", "Attr_Box",
            "Canvas_Tips", "Canv_Tips", "CanvasTips", "WBP_AutoChess_Tips_LifeSchedule",
            "WBP_AutoChess_Tips_VitalitySchedule"
        }) do
            local w = getNamedWidget(view, attrName) or getNamedWidget(root, attrName)
            if w ~= nil then
                makeVisible(w)
                unclip(w)
            end
        end

        pcall(function()
            if parent ~= nil then
                if parent.SynchronizeProperties ~= nil then parent:SynchronizeProperties() end
                if parent.InvalidateLayoutAndVolatility ~= nil then parent:InvalidateLayoutAndVolatility() end
            end
        end)

        return true
    end

    runtimeFixes.AutoChessHookedWrappers = setmetatable({}, { __mode = "k" })
    function runtimeFixes.hookAutoChessMethod(origMethod, methodName)
        if type(origMethod) ~= "function" or runtimeFixes.AutoChessHookedWrappers[origMethod] then
            return origMethod
        end
        local function hookChildCardItem(item)
            if type(item) ~= "table" or item.__cpddCardItemHooked then return end
            item.__cpddCardItemHooked = true
            for _, m in ipairs({ "OnListItemObjectSet", "SetData", "InitView", "InitData", "UpdateView", "SetCardData", "UpdateCard" }) do
                local orig = item[m]
                if type(orig) == "function" then
                    item[m] = runtimeFixes.hookAutoChessMethod(orig, m)
                end
            end
        end

        local function wrapper(comp, ...)
            local diag = runtimeFixes.autoChessDiag
            if diag ~= nil then
                pcall(diag.OnMethodCall, comp, methodName, "translate-hook", ...)
            end
            local argCount = select("#", ...)
            local args = { ... }
            local seen = {}
            for i = 1, argCount do
                local arg = args[i]
                if type(arg) == "table" or type(arg) == "userdata" then
                    hookChildCardItem(arg)
                    pcall(safeTranslateAutoChessData, arg, seen)
                elseif type(arg) == "string" then
                    pcall(function()
                        args[i] = translateVisibleText(arg)
                    end)
                end
            end
            if type(comp) == "table" then
                hookChildCardItem(comp)
                pcall(function()
                    if comp.GetDisplayedEntryWidgets then
                        local entries = comp:GetDisplayedEntryWidgets()
                        if type(entries) == "table" then
                            for _, entry in pairs(entries) do hookChildCardItem(entry) end
                        end
                    end
                    if comp.m_ItemList and type(comp.m_ItemList) == "table" then
                        for _, item in pairs(comp.m_ItemList) do hookChildCardItem(item) end
                    end
                    if comp.ItemList and type(comp.ItemList) == "table" then
                        for _, item in pairs(comp.ItemList) do hookChildCardItem(item) end
                    end
                    if comp.CardItems and type(comp.CardItems) == "table" then
                        for _, item in pairs(comp.CardItems) do hookChildCardItem(item) end
                    end
                end)
                pcall(function()
                    if comp.data ~= nil then safeTranslateAutoChessData(comp.data, seen) end
                    if comp.Data ~= nil then safeTranslateAutoChessData(comp.Data, seen) end
                    if comp.m_Data ~= nil then safeTranslateAutoChessData(comp.m_Data, seen) end
                    if comp.Cards ~= nil then safeTranslateAutoChessData(comp.Cards, seen) end
                    if comp.CardList ~= nil then safeTranslateAutoChessData(comp.CardList, seen) end
                    if comp.m_Cards ~= nil then safeTranslateAutoChessData(comp.m_Cards, seen) end
                    if comp.m_CardList ~= nil then safeTranslateAutoChessData(comp.m_CardList, seen) end
                    if comp.Fetters ~= nil then safeTranslateAutoChessData(comp.Fetters, seen) end
                    if comp.FetterList ~= nil then safeTranslateAutoChessData(comp.FetterList, seen) end
                    if comp.m_Fetters ~= nil then safeTranslateAutoChessData(comp.m_Fetters, seen) end
                    if comp.m_FetterList ~= nil then safeTranslateAutoChessData(comp.m_FetterList, seen) end
                    if comp.FetterData ~= nil then safeTranslateAutoChessData(comp.FetterData, seen) end
                    if comp.m_FetterData ~= nil then safeTranslateAutoChessData(comp.m_FetterData, seen) end
                end)
            end
            local results = { origMethod(comp, unpack(args, 1, argCount)) }
            pcall(function()
                translateDirectViewTextWidgets(comp and comp.view)
                if comp then
                    local root = comp.userWidget or comp.widget
                    translateViewTextWidgets(comp.view, root)
                    runtimeFixes.repairAutoChessHudAttributes(comp)
                end
            end)
            return unpack(results)
        end
        runtimeFixes.AutoChessHookedWrappers[wrapper] = true
        return wrapper
    end
end

-- AutoChess diagnostics. The AutoChess module list above is guessed, and the
-- encyclopedia's nested components are never matched by it. This pass records
-- the real module keys, component classes, method names and view widget names,
-- so the next fix can target them. It only observes: it never changes text
-- or widgets. Output goes to Warning level (PerformanceMode keeps it) and to
-- Saved/Mods/cpdd-autochess-diag.log. Disable with AutoChessDiagnostics=false.
do
    local diag = {
        Enabled = not (type(Loader.Features) == "table"
            and Loader.Features.AutoChessDiagnostics == false),
        FileName = "cpdd-autochess-diag.log",
        Lines = {},
        MaxLines = 20000,
        Truncated = false,
        Dirty = false,
        SeenModuleKeys = {},
        SeenClassNames = {},
        DumpedLevels = setmetatable({}, { __mode = "k" }),
        DumpedComponents = {},
        ViewDumpsPerClass = {},
        WrappedClasses = setmetatable({}, { __mode = "k" }),
        EventCounts = {},
        CallCounts = {},
        MaxEventsPerKey = 60,
        MaxCallsPerKey = 30,
    }

    local function isChessName(value)
        return type(value) == "string" and value:lower():find("chess", 1, true) ~= nil
    end

    local function timestamp()
        if type(os) == "table" and type(os.date) == "function" then
            local ok, value = pcall(os.date, "%H:%M:%S")
            if ok then return tostring(value) .. " " end
        end
        return ""
    end

    function diag.Log(message)
        if not diag.Enabled then return end
        local line = "[CPDDAutoChessDiag] " .. tostring(message)
        local nativeLogger = LuaCLogger
        if nativeLogger ~= nil and type(nativeLogger.Warning) == "function" then
            pcall(nativeLogger.Warning, line)
        else
            local logger = Log or LaunchLog
            if logger and logger.Warning then
                pcall(logger.Warning, line)
            elseif logger and logger.Info then
                pcall(logger.Info, line)
            end
        end
        if #diag.Lines < diag.MaxLines then
            diag.Lines[#diag.Lines + 1] = timestamp() .. line
            diag.Dirty = true
        elseif not diag.Truncated then
            diag.Truncated = true
            diag.Lines[#diag.Lines + 1] = "[CPDDAutoChessDiag] file line limit reached; see game log"
            diag.Dirty = true
        end
    end

    local fileLibrary = nil
    function diag.Flush()
        if not diag.Dirty then return end
        diag.Dirty = false
        local root = tostring(Loader.Root or ""):gsub("\\", "/"):gsub("/+$", "")
        if root == "" then return end
        if fileLibrary == nil then
            local ok, library = pcall(import, "LuaFunctionLibrary")
            fileLibrary = (ok and library) or false
        end
        if not fileLibrary or type(fileLibrary.SaveStringContentToFile) ~= "function" then return end
        pcall(fileLibrary.SaveStringContentToFile,
            table.concat(diag.Lines, "\n") .. "\n", root .. "/" .. diag.FileName)
    end

    local function logList(prefix, names)
        if #names == 0 then
            diag.Log(prefix .. " <none>")
            return
        end
        local chunk = {}
        for i, name in ipairs(names) do
            chunk[#chunk + 1] = tostring(name)
            if #chunk == 40 or i == #names then
                diag.Log(prefix .. " [" .. tostring(i - #chunk + 1) .. "-" .. tostring(i)
                    .. "/" .. tostring(#names) .. "] " .. table.concat(chunk, ", "))
                chunk = {}
            end
        end
    end

    local function componentKey(comp)
        return tostring(comp.__cname) .. "|" .. tostring(comp.uid or comp.UID)
    end

    local function parentChain(comp)
        local parts = {}
        local current = comp.parentComponent
        while type(current) == "table" and #parts < 8 do
            parts[#parts + 1] = componentKey(current)
            current = current.parentComponent
        end
        return parts
    end

    local function isRelevant(comp)
        local current, depth = comp, 0
        while type(current) == "table" and depth < 9 do
            if isChessName(current.__cname) or isChessName(current.uid) or isChessName(current.UID) then
                return true
            end
            current = current.parentComponent
            depth = depth + 1
        end
        return false
    end

    local function describeArg(value)
        local valueType = type(value)
        if valueType == "string" then
            local text = value:gsub("[\r\n]", "\\n")
            if #text > 80 then text = text:sub(1, 80) .. "..." end
            return '"' .. text .. '"'
        elseif valueType == "number" or valueType == "boolean" or valueType == "nil" then
            return tostring(value)
        elseif valueType == "table" then
            local keys, count = {}, 0
            for k in pairs(value) do
                count = count + 1
                if #keys < 12 then keys[#keys + 1] = tostring(k) end
            end
            local cname = value.__cname
            return "table{" .. (cname ~= nil and ("cname=" .. tostring(cname) .. " ") or "")
                .. "n=" .. tostring(count) .. " " .. table.concat(keys, ",") .. "}"
        end
        return valueType
    end

    -- Instance, then metatable/__index/super chain. Each class level is listed
    -- once per session; later components only reference it.
    local function classLevels(comp)
        local levels, visited = {}, {}
        local function push(t, how)
            if type(t) == "table" and not visited[t] and #levels < 16 then
                visited[t] = true
                levels[#levels + 1] = { Table = t, How = how }
            end
        end
        push(comp, "instance")
        local i = 1
        while i <= #levels do
            local t = levels[i].Table
            local mtOk, mt = pcall(getmetatable, t)
            if mtOk and type(mt) == "table" then
                push(rawget(mt, "__index"), "__index")
                push(mt, "metatable")
            end
            push(rawget(t, "super"), "super")
            push(rawget(t, "__super"), "__super")
            push(rawget(t, "class"), "class")
            i = i + 1
        end
        return levels
    end

    local function dumpView(indent, view)
        if type(view) ~= "table" then
            diag.Log(indent .. "view type=" .. type(view))
            return
        end
        local names, nested = {}, {}
        for k, v in pairs(view) do
            if type(k) == "string" then
                local desc = k
                if type(v) == "userdata" then
                    local ok, className = pcall(function() return v:GetClass():GetName() end)
                    if ok and className ~= nil then desc = k .. ":" .. tostring(className) end
                elseif type(v) == "table" then
                    desc = k .. ":table"
                    nested[#nested + 1] = k
                end
                names[#names + 1] = desc
            end
        end
        table.sort(names)
        logList(indent .. "view widgets", names)
        table.sort(nested)
        for _, k in ipairs(nested) do
            local sub = {}
            for subKey in pairs(view[k]) do
                if type(subKey) == "string" and #sub < 80 then sub[#sub + 1] = subKey end
            end
            table.sort(sub)
            logList(indent .. "view." .. k .. " keys", sub)
        end
    end

    function diag.DumpComponent(comp, indent)
        local cname = tostring(comp.__cname)
        diag.Log(indent .. "component " .. componentKey(comp)
            .. " parents=[" .. table.concat(parentChain(comp), " < ") .. "]")
        -- Generic classes (UIComponent, list items) share methods but not
        -- widgets, so views are dumped per instance, capped per class.
        local viewDumps = (diag.ViewDumpsPerClass[cname] or 0) + 1
        diag.ViewDumpsPerClass[cname] = viewDumps
        if viewDumps <= 5 then
            pcall(function()
                local widget = comp.userWidget or comp.widget
                if widget ~= nil and widget.GetName then
                    diag.Log(indent .. "  userWidget=" .. tostring(widget:GetName()))
                end
            end)
            dumpView(indent .. "  ", comp.view)
        elseif viewDumps == 6 then
            diag.Log(indent .. "  (further views of class " .. cname .. " omitted)")
        end
        if diag.SeenClassNames[cname] then
            return
        end
        diag.SeenClassNames[cname] = true
        for i, level in ipairs(classLevels(comp)) do
            local t = level.Table
            local levelName = tostring(rawget(t, "__cname") or "?")
            local prefix = indent .. "  level" .. tostring(i) .. " " .. levelName .. " (" .. level.How .. ")"
            if diag.DumpedLevels[t] then
                diag.Log(prefix .. " already listed")
            else
                diag.DumpedLevels[t] = true
                local methods, fields = {}, {}
                for k, v in pairs(t) do
                    if type(k) == "string" then
                        if type(v) == "function" then
                            methods[#methods + 1] = k
                        elseif i == 1 then
                            fields[#fields + 1] = k .. ":" .. type(v)
                        end
                    end
                end
                table.sort(methods)
                logList(prefix .. " methods", methods)
                if i == 1 then
                    table.sort(fields)
                    logList(prefix .. " fields", fields)
                end
            end
        end
    end

    local function dumpChildren(comp, indent, depth, visited)
        local children = comp._childComponents
        if type(children) ~= "table" or depth > 5 then return end
        local labels = {}
        for k, child in pairs(children) do
            if type(child) == "table" then
                labels[#labels + 1] = tostring(k) .. "=" .. componentKey(child)
            end
        end
        table.sort(labels)
        if #labels > 0 then
            logList(indent .. "children of " .. componentKey(comp), labels)
        end
        for _, child in pairs(children) do
            if type(child) == "table" and not visited[child] then
                visited[child] = true
                local key = componentKey(child)
                if not diag.DumpedComponents[key] then
                    diag.DumpedComponents[key] = true
                    diag.DumpComponent(child, indent .. "  ")
                end
                dumpChildren(child, indent .. "  ", depth + 1, visited)
            end
        end
    end

    -- Observe-only wrappers on real AutoChess classes found by the module scan.
    -- UIComponent.Open/Refresh misses subclasses that override them without
    -- calling super. Click handlers are left alone because listeners may be
    -- removed by function identity.
    local diagWrapNames = {
        "Open", "Refresh", "OnOpen", "OnRefresh", "OnShow", "OnCreate", "OnInit",
        "InitView", "InitData", "OnListItemObjectSet", "SetData", "UpdateView",
        "RefreshView", "RefreshUI", "UpdateData",
    }
    local function wrapClassForDiag(classTable, label)
        if type(classTable) ~= "table" or diag.WrappedClasses[classTable] then return 0 end
        diag.WrappedClasses[classTable] = true
        local wrapped = {}
        for _, name in ipairs(diagWrapNames) do
            local original = rawget(classTable, name)
            if type(original) == "function" then
                local assigned = pcall(function()
                    classTable[name] = function(self, ...)
                        pcall(diag.OnMethodCall, self, name, "class:" .. label, ...)
                        return original(self, ...)
                    end
                end)
                if assigned then wrapped[#wrapped + 1] = name end
            end
        end
        if #wrapped > 0 then
            diag.Log("  observe-wrapped " .. tostring(rawget(classTable, "__cname"))
                .. " from " .. label .. ": " .. table.concat(wrapped, ","))
        end
        return #wrapped
    end

    local function collectClasses(value, out)
        if type(value) ~= "table" then return end
        if rawget(value, "__cname") ~= nil then
            out[#out + 1] = value
            return
        end
        local scanned = 0
        for _, v in pairs(value) do
            scanned = scanned + 1
            if scanned > 500 then break end
            if type(v) == "table" and rawget(v, "__cname") ~= nil then
                out[#out + 1] = v
            end
        end
    end

    local function scanTable(label, source)
        if type(source) ~= "table" then
            diag.Log("scan " .. label .. ": unavailable (" .. type(source) .. ")")
            return
        end
        local fresh, total = {}, 0
        for k in pairs(source) do
            if isChessName(k) then
                total = total + 1
                local seenKey = label .. "|" .. k
                if not diag.SeenModuleKeys[seenKey] then
                    diag.SeenModuleKeys[seenKey] = true
                    fresh[#fresh + 1] = k
                end
            end
        end
        table.sort(fresh)
        diag.Log("scan " .. label .. ": chess keys total=" .. tostring(total) .. " new=" .. tostring(#fresh))
        for _, k in ipairs(fresh) do
            local value = source[k]
            local classes, cnames = {}, {}
            collectClasses(value, classes)
            for _, cls in ipairs(classes) do
                cnames[#cnames + 1] = tostring(rawget(cls, "__cname"))
            end
            diag.Log("  " .. label .. "[" .. k .. "] type=" .. type(value)
                .. " classes=" .. table.concat(cnames, ","))
            for _, cls in ipairs(classes) do
                wrapClassForDiag(cls, k)
            end
        end
    end

    function diag.ScanModules(stage)
        if not diag.Enabled then return end
        diag.Log("module scan stage=" .. tostring(stage))
        scanTable("package.loaded", type(package) == "table" and package.loaded or nil)
        local gameOk, gameLoaded = pcall(function() return Game and Game.loaded end)
        scanTable("Game.loaded", gameOk and gameLoaded or nil)
        scanTable("_G", _G)
        -- kg_require keeps its own module cache; find it through upvalues.
        local privateRequire = rawget(_G, "kg_require")
        if type(privateRequire) == "function" and type(debug) == "table"
            and type(debug.getupvalue) == "function" then
            for i = 1, 60 do
                local ok, name, value = pcall(debug.getupvalue, privateRequire, i)
                if not ok or name == nil then break end
                if type(value) == "table" then
                    local hasChess = false
                    for k in pairs(value) do
                        if isChessName(k) then hasChess = true break end
                    end
                    if hasChess then
                        scanTable("kg_require.upvalue[" .. tostring(name) .. "]", value)
                    end
                end
            end
        else
            diag.Log("scan kg_require: unavailable")
        end
        diag.Flush()
    end

    function diag.OnComponentEvent(comp, event, source)
        if not diag.Enabled or type(comp) ~= "table" or not isRelevant(comp) then return end
        local key = componentKey(comp)
        local cname = tostring(comp.__cname)
        if not diag.SeenClassNames[cname] then
            diag.ScanModules("new component " .. key)
        end
        local count = (diag.EventCounts[key] or 0) + 1
        diag.EventCounts[key] = count
        if count <= diag.MaxEventsPerKey then
            diag.Log("event " .. key .. "." .. tostring(event) .. " via " .. tostring(source)
                .. " #" .. tostring(count)
                .. " parents=[" .. table.concat(parentChain(comp), " < ") .. "]")
        end
        if not diag.DumpedComponents[key] then
            diag.DumpedComponents[key] = true
            diag.DumpComponent(comp, "  ")
        end
        if count <= diag.MaxEventsPerKey then
            dumpChildren(comp, "  ", 1, {})
        end
        diag.Flush()
    end

    function diag.OnMethodCall(comp, methodName, source, ...)
        if not diag.Enabled or type(comp) ~= "table" then return end
        local key = componentKey(comp) .. "." .. tostring(methodName or "?")
        local count = (diag.CallCounts[key] or 0) + 1
        diag.CallCounts[key] = count
        if count > diag.MaxCallsPerKey then return end
        local args = {}
        for i = 1, math.min(select("#", ...), 6) do
            args[#args + 1] = describeArg((select(i, ...)))
        end
        diag.Log("call " .. key .. " via " .. tostring(source) .. " #" .. tostring(count)
            .. " args=(" .. table.concat(args, "; ") .. ")")
        if count == 1 and not diag.DumpedComponents[componentKey(comp)] then
            diag.DumpedComponents[componentKey(comp)] = true
            diag.DumpComponent(comp, "  ")
        end
        diag.Flush()
    end

    function diag.OnModuleLoaded(modName, value, panelClass)
        diag.Log("AfterLoad " .. tostring(modName) .. " value=" .. type(value)
            .. " class=" .. tostring(type(panelClass) == "table" and panelClass.__cname or nil))
        diag.Flush()
    end

    if diag.Enabled then
        runtimeFixes.autoChessDiag = diag
        diag.Log("AutoChess diagnostics enabled v" .. VERSION .. " file=Saved/Mods/" .. diag.FileName)
        local scanOk, scanErr = pcall(diag.ScanModules, "module-load")
        if not scanOk then diag.Log("module-load scan failed: " .. tostring(scanErr)) end
        if type(Loader.On) == "function" then
            Loader.On("after_main", function()
                pcall(diag.ScanModules, "after_main")
            end, 1000000, "cpdd.runtime-fix.autochess-diagnostics")
        end
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
                local uid = tostring(self and (self.uid or self.UID or self.__cname) or "")
                local isAutoChess = (uid == "AutoChess_Hud_Panel" or uid == "AutoChessHudPanel" or uid == "AutoChess_Hud"
                    or uid == "AutoChess_GameDetail_Panel" or uid == "AutoChess_CardDescription_Panel" or uid == "AutoChess_OutSideMain_Panel"
                    or uid:find("AutoChess", 1, true) ~= nil or uid:find("autochess", 1, true) ~= nil)
                if isAutoChess and not self.__cpddAutoChessHooked then
                    self.__cpddAutoChessHooked = true
                    for _, method in ipairs({
                        "OnListItemObjectSet", "SetData", "InitView",
                        "Update", "UpdateData", "UpdateView", "UpdateList", "RefreshList",
                        "InitData", "UpdateCards", "RefreshCards", "UpdateMatchInfo",
                        "UpdatePlayerCards", "UpdateContent", "UpdateGameDetail", "SetGameDetail",
                        "ShowDetail", "RefreshUI", "OnShow", "UpdateDetails", "ShowCardDetail",
                        "SetCardData", "UpdateCardInfo", "OnOpen", "SetCard",
                        "ShowCard", "UpdateCard", "Show", "UpdateFetter", "UpdateFetters",
                        "UpdateBond", "UpdateBonds", "RefreshFetters", "SetFetterData",
                        "UpdateSynergy", "UpdateSynergies", "RefreshSynergy",
                        "SelectCard", "OnSelectCard", "SelectPiece", "OnSelectPiece",
                        "ShowTips", "UpdateTips", "SetTips"
                    }) do
                        local origMethod = self[method]
                        if type(origMethod) == "function" then
                            self[method] = runtimeFixes.hookAutoChessMethod(origMethod, method)
                        end
                    end
                end
                local results = { original(self, ...) }
                local diag = runtimeFixes.autoChessDiag
                if diag ~= nil then
                    pcall(diag.OnComponentEvent, self, methodName, "UIComponent")
                end
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

do
    local autoChessModuleCandidates = {
        "Gameplay.LogicSystem.AutoChess.AutoChess_Hud_Panel",
        "Gameplay.LogicSystem.AutoChess.AutoChessHudPanel",
        "Gameplay.LogicSystem.AutoChess.AutoChess_Hud",
        "Gameplay.LogicSystem.AutoChess.AutoChess_GameDetail_Panel",
        "Gameplay.LogicSystem.AutoChess.AutoChessGameDetailPanel",
        "Gameplay.LogicSystem.AutoChess.AutoChess_GameDetail",
        "Gameplay.LogicSystem.AutoChess.GameDetail_Panel",
        "Gameplay.LogicSystem.AutoChess.AutoChess_CardDescription_Panel",
        "Gameplay.LogicSystem.AutoChess.AutoChessCardDescriptionPanel",
        "Gameplay.LogicSystem.AutoChess.CardDescription_Panel",
        "Gameplay.LogicSystem.AutoChess.AutoChess_CardDescription",
        "Gameplay.LogicSystem.AutoChess.AutoChess_OutSideMain_Panel",
        "Gameplay.LogicSystem.AutoChess.AutoChessOutSideMainPanel",
        "Gameplay.LogicSystem.AutoChess.AutoChess_OutSideMain",
        "Gameplay.LogicSystem.AutoChess.AutoChess_Card_Item",
        "Gameplay.LogicSystem.AutoChess.AutoChess_CardItem",
        "Gameplay.LogicSystem.AutoChess.AutoChessCardItem",
        "Gameplay.LogicSystem.AutoChess.AutoChess_Card",
        "Gameplay.LogicSystem.AutoChess.AutoChessCard",
        "Gameplay.LogicSystem.AutoChess.AutoChess_Piece_Item",
        "Gameplay.LogicSystem.AutoChess.AutoChess_PieceItem",
        "Gameplay.LogicSystem.AutoChess.AutoChessPieceItem",
        "Gameplay.LogicSystem.AutoChess.AutoChess_ListItem",
        "Gameplay.LogicSystem.AutoChess.AutoChessListItem",
        "Gameplay.LogicSystem.AutoChess.AutoChess_Fetter_Item",
        "Gameplay.LogicSystem.AutoChess.AutoChess_FetterItem",
        "Gameplay.LogicSystem.AutoChess.AutoChessFetterItem",
        "Gameplay.LogicSystem.AutoChess.AutoChess_OutSide_Card_Item",
        "Gameplay.LogicSystem.AutoChess.AutoChessOutSideCardItem",
        "Gameplay.LogicSystem.AutoChess.AutoChess_GameDetail_Card_Item",
        "Gameplay.LogicSystem.AutoChess.AutoChessGameDetailCardItem",
        "Gameplay.LogicSystem.AutoChess.AutoChess_CardDescription_Item",
        "Gameplay.LogicSystem.AutoChess.AutoChessCardDescriptionItem",
    }
    for _, modName in ipairs(autoChessModuleCandidates) do
        Loader.AfterLoad(modName, function(value, environment)
            local panelClass = getSymbol(value, environment, "AutoChess_Hud_Panel")
                or getSymbol(value, environment, "AutoChessHudPanel")
                or getSymbol(value, environment, "AutoChess_Hud")
                or getSymbol(value, environment, "AutoChess_GameDetail_Panel")
                or getSymbol(value, environment, "GameDetail_Panel")
                or getSymbol(value, environment, "AutoChess_CardDescription_Panel")
                or getSymbol(value, environment, "CardDescription_Panel")
                or getSymbol(value, environment, "AutoChess_OutSideMain_Panel")
                or getSymbol(value, environment, "AutoChessOutSideMainPanel")
                or value
            if type(panelClass) == "table" and panelClass.__cpddAutoChessPanelHooked ~= VERSION then
                panelClass.__cpddAutoChessPanelHooked = VERSION
                for _, m in ipairs({
                    "OnListItemObjectSet", "SetData", "InitView",
                    "Open", "Refresh", "Update", "UpdateData", "UpdateView", "UpdateList",
                    "RefreshList", "InitData", "UpdateCards", "RefreshCards",
                    "UpdateMatchInfo", "UpdatePlayerCards", "UpdateContent", "UpdateGameDetail",
                    "SetGameDetail", "ShowDetail", "RefreshUI", "OnShow", "UpdateDetails",
                    "ShowCardDetail", "SetCardData", "UpdateCardInfo", "OnOpen",
                    "SetCard", "ShowCard", "UpdateCard", "Show", "UpdateFetter", "UpdateFetters",
                    "UpdateBond", "UpdateBonds", "RefreshFetters", "SetFetterData",
                    "UpdateSynergy", "UpdateSynergies", "RefreshSynergy",
                    "SelectCard", "OnSelectCard", "SelectPiece", "OnSelectPiece",
                    "ShowTips", "UpdateTips", "SetTips"
                }) do
                    local origM = panelClass[m]
                    if type(origM) == "function" then
                        panelClass[m] = runtimeFixes.hookAutoChessMethod(origM, m)
                    end
                end
                report("installed AutoChess lifecycle hooks on " .. modName)
            end
            local diag = runtimeFixes.autoChessDiag
            if diag ~= nil then
                pcall(diag.OnModuleLoaded, modName, value, panelClass)
            end
            return value
        end, 1000000, "cpdd.runtime-fix.autochess-panels")
    end
end

runtimeFixes.statisticsEverywhereEnabled = function()
    local loader = rawget(_G, "LOMModLoader")
    local features = loader and loader.Features
    if type(features) ~= "table" then
        return true
    end
    return features.StatisticsEverywhere ~= false
end

runtimeFixes.setStatisticsEverywhere = function(enabled)
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

do
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
            if runtimeFixes.statisticsEverywhereEnabled() then
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

    Loader.AfterLoad(
        "Gameplay.LogicSystem.HUD.HUD_MiddleBtnContent.HUDMiddleMenuCheck",
        installStatisticsEverywhere,
        1000000,
        "cpdd.runtime-fix.statistics-everywhere"
    )
end

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

-- Guard against ChatModel string.format crashes on system messages
pcall(function()
    if type(Loader.AfterLoad) == "function" then
        for _, chatModelName in ipairs({
            "Gameplay.LogicSystem.Chat.System.ChatModel",
            "Gameplay.LogicSystem.Chat.Model.ChatModel",
            "Gameplay.LogicSystem.Chat.ChatModel",
        }) do
            Loader.AfterLoad(chatModelName, function(model)
                if type(model) == "table" and type(model.processSystemTextMessage) == "function" then
                    local originalProcess = model.processSystemTextMessage
                    model.processSystemTextMessage = function(...)
                        local ok, res = pcall(originalProcess, ...)
                        if ok then return res end
                        report("protected ChatModel.processSystemTextMessage from crash: " .. tostring(res))
                        return nil
                    end
                end
                return model
            end, 100, "cpdd.chat_model.format_guard")
        end
    end
end)

-- Register database translation hook for bootstrap.lua merge_overlay
-- This translates the Excel StringDB database in memory at load time (0ms runtime latency).
Loader.TranslateDatabaseString = function(enValue, cnValue, rowId, moduleName)
    local hasEn = type(enValue) == "string" and enValue ~= ""
    local hasCn = type(cnValue) == "string" and cnValue ~= ""
    if not hasEn and not hasCn then
        return nil
    end

    -- 1. Explicit row ID overrides
    if rowId ~= nil then
        local explicit = aggregateOverrides[rowId]
        if explicit ~= nil then return explicit end
    end

    -- 2. Tag-specific split overrides
    if type(moduleName) == "string" and rowId ~= nil then
        local tag = moduleName:match("StringDB_CN_Data_([A-Za-z0-9_]+)$")
        if tag and splitOverrides[tag] and splitOverrides[tag][rowId] then
            return splitOverrides[tag][rowId]
        end
    end

    -- 3. Exact direct shard lookup for Chinese original string (primary canonical source in shards)
    if hasCn then
        local ruCn = lookupGeminiText(cnValue) or runtimeFixes.lookupGeminiTextFuzzy(cnValue)
        if ruCn ~= nil then return ruCn end
    end

    -- 4. Direct shard lookup for English reference string
    if hasEn then
        local ruEn = lookupGeminiText(enValue) or runtimeFixes.lookupGeminiTextFuzzy(enValue)
        if ruEn ~= nil then return ruEn end
    end

    -- 5. Exact review overrides
    if hasCn and visibleTextExactOverrides[cnValue] then
        return visibleTextExactOverrides[cnValue]
    end
    if hasEn and visibleTextExactOverrides[enValue] then
        return visibleTextExactOverrides[enValue]
    end

    return nil
end

pcall(function()
    if type(Loader.ReapplyOverlays) == "function" then
        local count = Loader.ReapplyOverlays(true)
        local logger = Log or LaunchLog
        if logger and logger.Info then
            logger.Info("[LOMModLoader] Database Russian overlay applied to " .. tostring(count or 0) .. " modules")
        end
    end
end)

report("registered v" .. VERSION)
return {
    Version = VERSION,
    PerformanceModeApplied = Loader.Telemetry.PerformanceModeApplied == true,
    RepairLiveText = repairLiveString,
    TranslateVisibleText = translateVisibleText,
    LookupGeminiText = lookupGeminiText,
    SetRuntimeRowRepair = setRuntimeRowRepair,
    IsRuntimeRowRepairEnabled = runtimeRowRepairEnabled,
    SetRuntimeUIRepair = setRuntimeUIRepair,
    IsRuntimeUIRepairEnabled = runtimeUIRepairEnabled,
    SetStatisticsEverywhere = runtimeFixes.setStatisticsEverywhere,
    IsStatisticsEverywhereEnabled = runtimeFixes.statisticsEverywhereEnabled,
    ResolveAuthoritativeAggregate = runtimeFixes.authoritativeAggregateLookup,
    PerformanceMetrics = runtimeMetrics,
    RepairPanel = function(component) return panelTextRepair:Repair(component, "manual") end,
}

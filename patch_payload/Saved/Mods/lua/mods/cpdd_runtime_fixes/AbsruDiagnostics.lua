-- AbsoluteRU development diagnostics (docs/DIAGNOSTICS.md, TASK-005).
--
-- Init.lua loads this module only when Saved/Mods/lua/absoluteru_dev.lua
-- returns { Enabled = true }. The module only observes: it never sets text,
-- fonts, letter spacing or layout. Hooks record counters and enqueue cheap
-- references; measuring, widget walks, JSON encoding and file writes run in
-- D.Tick() within FrameBudgetMs. Files go to Saved/Mods/logs/ (or Saved/Mods/
-- when the folder cannot be created) as absru-s<slot>-*.json / *.jsonl.

local D = {}

local DEFAULTS = {
    Hooks = true,
    Untranslated = true,
    Overflow = true,
    Fonts = true,
    Images = true,
    PanelWalk = true,
    FrameBudgetMs = 2.0,
    TickSeconds = 0.05,
    FlushSeconds = 30,
    PartKB = 512,
    SessionMB = 32,
    Slots = 5,
    PanelWalksPerUid = 3,
    -- SaveStringContentToFile encoding of non-ASCII text is unverified, so
    -- JSON escapes every non-ASCII character as \uXXXX by default.
    AsciiJson = true,
}
local LIMITS = {
    FrameBudgetMs = { 0.2, 50 },
    TickSeconds = { 0.01, 5 },
    FlushSeconds = { 5, 600 },
    PartKB = { 16, 512 },
    SessionMB = { 1, 512 },
    Slots = { 1, 20 },
    PanelWalksPerUid = { 0, 20 },
}

local QUEUE_MAX = 5000
local DEDUP_MAX = 20000
local DB_MISS_MAX = 100000
local DATA_MAX = 20000
local DELAYED_MAX = 200
local WALK_JOBS_MAX = 20
local WALK_NODE_MAX = 20000
local HOOKS_MAX = 1800
local FONTS_MAX = 2000
local TITLE_CYR_MAX = 500
local TITLE_CYR_TEXT = 60
local LIST_MAX = 20
local TEXT_MAX = 400
local WRITE_MAX = 512 * 1024
local IDLE_TICK_SECONDS = 1.0
local PUMP_STALE_MS = 3000
local FLUSH_SOON_MS = 5000
local ERRORS_MAX = 2000
local ERRORS_LOGGED = 3

local CJK = "[\228-\233][\128-\191][\128-\191]"
local CYR = "[\208\209][\128-\191]"
local Q = string.char(34)

local clock = os.clock

local cfg = {}
local S = {
    started = false,
    disabled = false,
    afterMain = false,
    inTick = false,
    timerPending = false,
    gen = 0,
    sid = "unknown",
    slot = 0,
    dir = nil,
    prefix = "",
    hooks = {},
    hookCount = 0,
    panels = {},
    panelCount = 0,
    stack = {},
    enterT = {},
    depth = 0,
    noteSeq = 0,
    queue = {},
    qhead = 1,
    qtail = 0,
    refs = setmetatable({}, { __mode = "v" }),
    refSeq = 0,
    pendingText = setmetatable({}, { __mode = "k" }),
    delayed = {},
    walkJobs = {},
    walkCounts = {},
    data = {},
    dataDone = 0,
    db = {},
    dbCount = 0,
    dbDone = 0,
    dbSeen = {},
    seen = {},
    seenCount = 0,
    fonts = {},
    fontCount = 0,
    composite = {},
    compositeNext = 1,
    titleCyr = {},
    titleCyrCount = 0,
    streams = {},
    sessionBytes = 0,
    lastTick = 0,
    lastFlush = 0,
    lastFlushStamp = nil,
    flushSoon = false,
    api = {},
    gauges = {},
    writes = {},
    unscoped = { text_changes = 0, text_writes = 0, data_changes = 0 },
    counters = {
        walks = 0, walk_nodes = 0, walks_skipped = 0, text_items = 0, gone = 0,
        roots_view = 0, roots_cache = 0, roots_tree = 0, roots_named = 0,
        hooks_writes = 0, hooks_unchanged = 0,
    },
    budget = {
        ticks = 0, ms_total = 0, tick_ms_max = 0, queue_peak = 0,
        io_ms_max = 0, io_ms_total = 0, writes = 0, flushes = 0, flush_ms_max = 0,
        -- Heaviest single unit of tick work (os.clock has ~1 ms steps on Windows).
        max_item_ms = 0, max_item_kind = "",
    },
    hooksJob = nil,
    hooksPending = nil,
    hooksSignature = nil,
    dropped = {
        queue = 0, dedup = 0, session_cap = 0, db = 0, data = 0,
        delayed = 0, walk_jobs = 0, walk_nodes = 0, hooks = 0, fonts = 0, title_cyrillic = 0,
    },
    errors = { measure = 0, walk = 0, io = 0, item = 0, tick = 0, timer = 0, oversize = 0 },
    errorTotal = 0,
}

local fontPre = setmetatable({}, { __mode = "k" })
-- widget -> { x, y, wrap }: desired size and AutoWrapText of the original text,
-- read by Init.lua right before its first SetText (TASK-011).
local sizePre = setmetatable({}, { __mode = "k" })
local pathCache = setmetatable({}, { __mode = "k" })
local ARRAY_MT = {}

local function nowMs()
    return clock() * 1000
end

local function stamp(format)
    local ok, value = pcall(os.date, format)
    if ok and type(value) == "string" then
        return value
    end
    return nil
end

-- Log.Info reaches C7.log as "LuaLog: ReleaseLog:" even under PerformanceMode;
-- LuaCLogger.Warning output does not appear in C7.log (first session, 2026-09-25).
local function warn(message)
    local text = tostring(message)
    local okLog, gameLog = pcall(function() return Log or LaunchLog end)
    if okLog and gameLog ~= nil and type(gameLog.Info) == "function" then
        if pcall(gameLog.Info, text) then
            return
        end
    end
    local ok, logger = pcall(function() return LuaCLogger end)
    if ok and logger ~= nil and type(logger.Warning) == "function" then
        pcall(logger.Warning, text)
    end
end

local function noteApi(name, ok)
    if ok then
        S.api[name] = true
    elseif S.api[name] == nil then
        S.api[name] = false
    end
end

-- kind: measure | walk | font | image | encode | db
local function track(kind, started)
    local elapsed = nowMs() - started
    local budget = S.budget
    if elapsed > budget.max_item_ms then
        budget.max_item_ms = elapsed
        budget.max_item_kind = kind
    end
end

local function disable(reason)
    S.disabled = true
    warn("[AbsruDiag] disabled: " .. tostring(reason))
    return false
end

local function noteError(stage, err)
    S.errors[stage] = (S.errors[stage] or 0) + 1
    S.errorTotal = S.errorTotal + 1
    if S.errors[stage] <= ERRORS_LOGGED then
        warn("[AbsruDiag] error stage=" .. tostring(stage) .. ": " .. tostring(err))
    end
    if S.errorTotal >= ERRORS_MAX and not S.disabled then
        disable("too many internal errors (" .. tostring(S.errorTotal) .. ")")
    end
end

local function array(values)
    return setmetatable(values or {}, ARRAY_MT)
end

-- JSON --------------------------------------------------------------------

local jsonEscapes = {
    [Q] = "\\" .. Q,
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}
local ESCAPE_PATTERN = "[%c\\" .. Q .. "]"

local function escapeControl(char)
    return jsonEscapes[char] or string.format("\\u%04x", char:byte())
end

local function escapeUtf8(sequence)
    local b1 = sequence:byte(1)
    local length = #sequence
    local code = nil
    if b1 >= 240 and length == 4 then
        code = (b1 - 240) * 262144 + (sequence:byte(2) - 128) * 4096
            + (sequence:byte(3) - 128) * 64 + (sequence:byte(4) - 128)
    elseif b1 >= 224 and b1 < 240 and length == 3 then
        code = (b1 - 224) * 4096 + (sequence:byte(2) - 128) * 64 + (sequence:byte(3) - 128)
    elseif b1 >= 192 and b1 < 224 and length == 2 then
        code = (b1 - 192) * 64 + (sequence:byte(2) - 128)
    end
    if code == nil or code > 1114111 then
        return "\\ufffd"
    end
    if code >= 65536 then
        code = code - 65536
        return string.format("\\u%04x\\u%04x", 55296 + math.floor(code / 1024), 56320 + code % 1024)
    end
    return string.format("\\u%04x", code)
end

local function encodeString(value)
    local text = value:gsub(ESCAPE_PATTERN, escapeControl)
    if cfg.AsciiJson ~= false and text:find("[\128-\255]") then
        text = text:gsub("[\192-\247][\128-\191]*", escapeUtf8)
        text = text:gsub("[\128-\255]", "\\ufffd")
    end
    return Q .. text .. Q
end

local function encodeNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then
        return "null"
    end
    if value == math.floor(value) and math.abs(value) < 9007199254740992 then
        return string.format("%.0f", value)
    end
    local text = string.format("%.3f", value)
    text = text:gsub("0+$", "")
    text = text:gsub("%.$", "")
    return text
end

local encodeValue

local function encodeObject(value, depth, order)
    local parts = {}
    local used = nil
    if order ~= nil then
        used = {}
        for _, key in ipairs(order) do
            local item = value[key]
            if item ~= nil then
                used[key] = true
                parts[#parts + 1] = encodeString(key) .. ":" .. encodeValue(item, depth + 1)
            end
        end
    end
    local keys = {}
    for key in pairs(value) do
        if (used == nil or not used[key]) and (type(key) == "string" or type(key) == "number") then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local item = value[key]
        if item == nil then
            item = value[tonumber(key)]
        end
        parts[#parts + 1] = encodeString(key) .. ":" .. encodeValue(item, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encodeValue = function(value, depth, order)
    depth = depth or 0
    local valueType = type(value)
    if valueType == "string" then
        return encodeString(value)
    elseif valueType == "number" then
        return encodeNumber(value)
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType ~= "table" or depth > 10 then
        return "null"
    end
    if getmetatable(value) == ARRAY_MT or value[1] ~= nil then
        local parts = {}
        for index = 1, #value do
            parts[index] = encodeValue(value[index], depth + 1)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    return encodeObject(value, depth, order)
end

D.EncodeJson = encodeValue

-- Text helpers -------------------------------------------------------------

local function utf8Len(text)
    local _, continuation = text:gsub("[\128-\191]", "")
    return #text - continuation
end

local function clip(text, limit)
    if #text <= limit then
        return text
    end
    local cut = limit
    while cut > 0 do
        local byte = text:byte(cut + 1)
        if byte == nil or byte < 128 or byte >= 192 then
            break
        end
        cut = cut - 1
    end
    return text:sub(1, cut)
end

local function normalize(text)
    local value = text:gsub("%d+", "#")
    value = value:gsub("%s+", " ")
    value = value:match("^ ?(.-) ?$") or value
    return clip(value, TEXT_MAX)
end

local function classify(text)
    local cjk = text:find(CJK) ~= nil
    local cyrillic = text:find(CYR) ~= nil
    local latin = false
    if not cyrillic and not cjk then
        local stripped = text
        if text:find("<", 1, true) then
            stripped = text:gsub("<[^>]*>", " ")
        end
        latin = stripped:find("%a%a") ~= nil
    end
    return cjk, cyrillic, latin
end

local function isPowerOfTwo(count)
    while count > 1 and count % 2 == 0 do
        count = count / 2
    end
    return count == 1
end

local function round1(value)
    value = tonumber(value) or 0
    return math.floor(value * 10 + 0.5) / 10
end

-- Unreal helpers (all calls protected) -------------------------------------

local function objectPath(object)
    if object == nil then
        return nil
    end
    local cached = pathCache[object]
    if cached ~= nil then
        return cached or nil
    end
    local path = nil
    local ok = pcall(function()
        path = tostring(object:GetPathName())
    end)
    noteApi("GetPathName", ok)
    pcall(function() pathCache[object] = path or false end)
    return path
end

local function objectName(object)
    local name = nil
    pcall(function() name = tostring(object:GetName()) end)
    return name
end

local function className(object)
    local name = nil
    local ok = pcall(function() name = tostring(object:GetClass():GetName()) end)
    noteApi("GetClass", ok)
    return name
end

local function componentUid(component)
    local uid = nil
    pcall(function() uid = component.uid or component.UID or component.__cname end)
    return tostring(uid or "?")
end

local function panelFromPath(path)
    if type(path) ~= "string" then
        return nil
    end
    return path:match("([%w_]+)_C_%d+%.WidgetTree")
end

local slateLibrary = nil
local function slate()
    if slateLibrary == nil then
        local ok, library = pcall(import, "SlateBlueprintLibrary")
        slateLibrary = ok and library or false
    end
    return slateLibrary or nil
end

local function vector2(x, y)
    local ok, value = pcall(function() return FVector2D(x, y) end)
    if ok and value ~= nil then
        return value
    end
    return { X = x, Y = y }
end

local function snapFont(font)
    if font == nil then
        return nil
    end
    local snap = {}
    pcall(function()
        local object = font.FontObject
        if object ~= nil then
            snap.path = objectPath(object)
        end
    end)
    pcall(function()
        local typeface = font.TypefaceFontName
        if typeface ~= nil then
            snap.typeface = tostring(typeface)
        end
    end)
    pcall(function() snap.size = tonumber(font.Size) end)
    pcall(function() snap.ls = tonumber(font.LetterSpacing) end)
    return snap
end

local function readFont(widget)
    local font = nil
    pcall(function()
        if widget.GetFont ~= nil then
            font = widget:GetFont()
        end
    end)
    if font == nil then
        pcall(function() font = widget.Font end)
    end
    return snapFont(font)
end

-- RichTextBlock / KGRichTextBlock have no GetFont: their font comes from the
-- default text style (override or TextStyleSet). Read-only, nil if unreadable.
local function readRichFont(widget)
    local font, source = nil, nil
    pcall(function()
        if widget.bOverrideDefaultStyle == true then
            font = widget.DefaultTextStyleOverride.Font
            source = "override"
        end
    end)
    if font == nil then
        pcall(function()
            font = widget:GetDefaultTextStyle().Font
            source = "style"
        end)
    end
    if font == nil then
        pcall(function()
            font = widget:GetCurrentDefaultTextStyle().Font
            source = "current"
        end)
    end
    local snap = snapFont(font)
    if snap ~= nil then
        snap.source = source
    end
    return snap
end

-- Output streams -------------------------------------------------------------

local function writeFile(name, content)
    if S.dir == nil or S.save == nil then
        return false
    end
    if #content > WRITE_MAX then
        S.errors.oversize = S.errors.oversize + 1
        return false
    end
    local started = nowMs()
    local ok, result = pcall(S.save, content, S.dir .. S.prefix .. name)
    local elapsed = nowMs() - started
    local budget = S.budget
    budget.writes = budget.writes + 1
    budget.io_ms_total = budget.io_ms_total + elapsed
    if elapsed > budget.io_ms_max then
        budget.io_ms_max = elapsed
    end
    if not ok or result == false then
        noteError("io", ok and "write returned false" or result)
        return false
    end
    return true
end

local function stream(name)
    local current = S.streams[name]
    if current == nil then
        current = { name = name, part = 1, lines = {}, bytes = 0, dirty = false, count = 0 }
        S.streams[name] = current
    end
    return current
end

local function partName(current, part)
    return string.format("%s-%03d.jsonl", current.name, part)
end

local function closePart(current)
    if #current.lines > 0 then
        writeFile(partName(current, current.part), table.concat(current.lines, "\n") .. "\n")
    end
    current.part = current.part + 1
    current.lines = {}
    current.bytes = 0
    current.dirty = false
end

local function appendRow(name, row, order)
    local line = encodeValue(row, 0, order)
    local size = #line + 1
    if S.sessionBytes + size > cfg.SessionMB * 1048576 then
        S.dropped.session_cap = S.dropped.session_cap + 1
        return false
    end
    local current = stream(name)
    if current.bytes > 0 and current.bytes + size > cfg.PartKB * 1024 then
        closePart(current)
    end
    current.lines[#current.lines + 1] = line
    current.bytes = current.bytes + size
    current.dirty = true
    current.count = current.count + 1
    S.sessionBytes = S.sessionBytes + size
    return true
end

local function partsSummary()
    local parts, lines = {}, {}
    for name, current in pairs(S.streams) do
        parts[name] = current.bytes > 0 and current.part or (current.part - 1)
        lines[name] = current.count
    end
    return parts, lines
end

-- Dedup: returns the record and whether it should be (re)emitted.
local function dedup(key)
    local record = S.seen[key]
    if record ~= nil then
        record.count = record.count + 1
        return record, isPowerOfTwo(record.count)
    end
    if S.seenCount >= DEDUP_MAX then
        S.dropped.dedup = S.dropped.dedup + 1
        return nil, false
    end
    record = { count = 1 }
    S.seen[key] = record
    S.seenCount = S.seenCount + 1
    return record, true
end

-- Hook and scope counters ---------------------------------------------------

local OVERFLOW_HOOK = {
    id = "overflow:hooks", kind = "overflow", calls = 0, text_changes = 0,
    text_writes = 0, data_changes = 0, errors = 0, ms_total = 0, ms_max = 0,
}

local function normalizeModule(module)
    if module == nil then
        return nil
    end
    local text = tostring(module):gsub(" %(.*%)$", "")
    return text
end

local function hookRecord(id, kind, meta)
    local record = S.hooks[id]
    if record == nil then
        if S.hookCount >= HOOKS_MAX then
            S.dropped.hooks = S.dropped.hooks + 1
            return OVERFLOW_HOOK
        end
        record = {
            id = id, kind = tostring(kind or "fix"), declared = false, installed = false,
            wraps = 0, calls = 0, text_changes = 0, text_writes = 0, data_changes = 0,
            errors = 0, ms_total = 0, ms_max = 0,
        }
        S.hooks[id] = record
        S.hookCount = S.hookCount + 1
    end
    if type(meta) == "table" then
        if meta.module ~= nil and record.module == nil then
            record.module = normalizeModule(meta.module)
        end
        if meta.light then
            record.light = true
        end
    end
    return record
end

local function panelRecord(id)
    local record = S.panels[id]
    if record == nil then
        if S.panelCount >= HOOKS_MAX then
            S.dropped.hooks = S.dropped.hooks + 1
            return OVERFLOW_HOOK
        end
        record = {
            id = id, kind = "panel", uid = id:match("^panel:(.-):[^:]*$") or id,
            calls = 0, labels = 0, widgets = 0, text_changes = 0, text_writes = 0,
            data_changes = 0, errors = 0, ms_total = 0, ms_max = 0,
        }
        S.panels[id] = record
        S.panelCount = S.panelCount + 1
    end
    return record
end

local function credit(field)
    local depth = S.depth
    if depth <= 0 then
        S.unscoped[field] = S.unscoped[field] + 1
        return
    end
    local seq = S.noteSeq + 1
    S.noteSeq = seq
    local stack = S.stack
    for index = 1, depth do
        local record = stack[index]
        if record ~= nil and record.seq ~= seq then
            record.seq = seq
            record[field] = (record[field] or 0) + 1
        end
    end
end

local function scopeId()
    local depth = S.depth
    if depth <= 0 then
        return nil
    end
    local record = S.stack[depth]
    return record and record.id or nil
end

local function scopePanel()
    for index = S.depth, 1, -1 do
        local record = S.stack[index]
        if record ~= nil and record.kind == "panel" then
            return record.uid
        end
    end
    return nil
end

local function finishCall(record, previous, started, ok, ...)
    S.depth = previous
    local elapsed = nowMs() - started
    record.ms_total = record.ms_total + elapsed
    if elapsed > record.ms_max then
        record.ms_max = elapsed
    end
    if not ok then
        record.errors = record.errors + 1
        error((...), 0)
    end
    return ...
end

-- Returns a counting wrapper. Errors raised by fn are counted and re-raised.
function D.Wrap(id, kind, fn, meta)
    if type(fn) ~= "function" then
        return fn
    end
    local record = hookRecord(tostring(id), kind, meta)
    record.installed = true
    record.wraps = (record.wraps or 0) + 1
    if not cfg.Hooks then
        return fn
    end
    if record.light then
        return function(...)
            record.calls = record.calls + 1
            return fn(...)
        end
    end
    return function(...)
        record.calls = record.calls + 1
        local previous = S.depth
        local depth = previous + 1
        S.depth = depth
        S.stack[depth] = record
        local started = nowMs()
        return finishCall(record, previous, started, pcall(fn, ...))
    end
end

function D.Declare(id, kind, meta)
    local record = hookRecord(tostring(id), kind, meta)
    record.declared = true
end

-- spec = { moduleName, symbolName, { methodNames... }, ... } from Init.lua.
function D.DeclareSpec(kind, spec)
    if type(spec) ~= "table" or type(spec[3]) ~= "table" then
        return
    end
    for _, method in ipairs(spec[3]) do
        D.Declare(kind .. ":" .. tostring(spec[2]) .. "." .. tostring(method), kind, { module = spec[1] })
    end
end

-- Enter/Leave bracket code without its own function. Leave(previous, labels,
-- widgets) restores the scope depth returned by Enter.
function D.Enter(id, kind)
    local previous = S.depth
    if previous > 64 then
        previous = 0
    end
    local record
    if kind == "panel" then
        record = panelRecord(tostring(id))
    else
        record = hookRecord(tostring(id), kind or "branch")
        record.installed = true
    end
    record.calls = record.calls + 1
    local depth = previous + 1
    S.depth = depth
    S.stack[depth] = record
    S.enterT[depth] = nowMs()
    return previous
end

function D.Leave(previous, labels, widgets)
    if type(previous) ~= "number" then
        return
    end
    if S.depth > previous then
        local record = S.stack[previous + 1]
        local started = S.enterT[previous + 1]
        if record ~= nil and started ~= nil then
            local elapsed = nowMs() - started
            record.ms_total = record.ms_total + elapsed
            if elapsed > record.ms_max then
                record.ms_max = elapsed
            end
            if record.kind == "panel" then
                record.labels = record.labels + (tonumber(labels) or 0)
                record.widgets = record.widgets + (tonumber(widgets) or 0)
            end
        end
    end
    S.depth = previous
end

function D.CurrentScope()
    local depth = S.depth
    if depth <= 0 then
        return nil
    end
    local scope = {}
    for index = 1, depth do
        scope[index] = S.stack[index]
    end
    return scope
end

local function finishScope(previous, ok, ...)
    S.depth = previous
    if not ok then
        error((...), 0)
    end
    return ...
end

function D.RunInScope(scope, fn, ...)
    if type(scope) ~= "table" then
        return fn(...)
    end
    local previous = S.depth
    for index = 1, #scope do
        S.stack[previous + index] = scope[index]
    end
    S.depth = previous + #scope
    return finishScope(previous, pcall(fn, ...))
end

-- Deferred repairs are credited to the hook that scheduled them.
function D.Bind(fn)
    local scope = D.CurrentScope()
    if scope == nil or type(fn) ~= "function" then
        return fn
    end
    return function(...)
        return D.RunInScope(scope, fn, ...)
    end
end

function D.NoteTextChange(widget, before, after)
    credit("text_changes")
end

function D.NoteTextWrite(site)
    credit("text_writes")
    local key = tostring(site)
    S.writes[key] = (S.writes[key] or 0) + 1
end

function D:Gauge(category, name, value)
    S.gauges[tostring(category) .. "." .. tostring(name)] = value
end

-- Queue ----------------------------------------------------------------------

local function keep(object)
    S.refSeq = S.refSeq + 1
    S.refs[S.refSeq] = object
    return S.refSeq
end

local function take(ref)
    local object = S.refs[ref]
    S.refs[ref] = nil
    return object
end

local function push(item)
    local size = S.qtail - S.qhead + 1
    if size >= QUEUE_MAX then
        S.dropped.queue = S.dropped.queue + 1
        return false
    end
    item.gen = S.gen
    S.qtail = S.qtail + 1
    S.queue[S.qtail] = item
    if size + 1 > S.budget.queue_peak then
        S.budget.queue_peak = size + 1
    end
    return true
end

function D.FontSnapshot(widget)
    if S.disabled or widget == nil or not (cfg.Fonts or cfg.Overflow) then
        return nil
    end
    local snap = fontPre[widget]
    if snap == nil then
        local ok, value = pcall(readFont, widget)
        snap = ok and value or false
        pcall(function() fontPre[widget] = snap end)
    end
    return snap or nil
end

-- Init.lua TextFit seams (TASK-011): values it already measured, no calls here.
function D.PreMeasure(widget, x, y, wrap)
    if S.disabled or widget == nil or not cfg.Overflow then
        return
    end
    pcall(function() sizePre[widget] = { x = tonumber(x), y = tonumber(y), wrap = wrap == true } end)
end

function D.NoteApi(name, ok)
    noteApi(tostring(name), ok == true)
end

-- row: kind (shrunk | fail | noeffect), text, size_pre, size, min, steps, slot,
-- axis, budget, need, need0, need_pre, reason. Encoded in the tick.
function D.NoteFit(widget, row)
    if S.disabled or widget == nil or not cfg.Overflow or type(row) ~= "table" then
        return
    end
    local ok = pcall(function()
        local item = { k = "fit", row = row, scope = scopeId(), panel = scopePanel() }
        item.ref = keep(widget)
        if not push(item) then
            take(item.ref)
        end
    end)
    if not ok then
        noteError("item", "NoteFit")
    end
end

function D.OnTextWidget(widget, text, name, pre)
    if S.disabled or widget == nil or type(text) ~= "string" or text == "" then
        return
    end
    if not (cfg.Untranslated or cfg.Overflow or cfg.Fonts) then
        return
    end
    local ok = pcall(function()
        local pending = S.pendingText[widget]
        if pending ~= nil then
            pending.text = text
            pending.scope = scopeId() or pending.scope
            pending.panel = scopePanel() or pending.panel
            return
        end
        local item = {
            k = "text", text = text, name = name, pre = pre,
            scope = scopeId(), panel = scopePanel(),
        }
        item.ref = keep(widget)
        if push(item) then
            S.pendingText[widget] = item
        else
            take(item.ref)
        end
    end)
    if not ok then
        noteError("item", "OnTextWidget")
    end
end

-- Replaces runtimeMetrics.CaptureDataAssignment (Init.lua development seam).
function D.CaptureDataAssignment(component, module, class, field, original, translated, record)
    if type(translated) ~= "string" then
        return false
    end
    if translated ~= original then
        credit("data_changes")
    end
    if cfg.Untranslated and not S.disabled then
        local flagged = translated:find(CJK) ~= nil
        if not flagged and translated == original and translated:find("%a%a") and not translated:find(CYR) then
            flagged = true
        end
        if flagged then
            local count = #S.data
            if count - S.dataDone >= DATA_MAX then
                S.dropped.data = S.dropped.data + 1
            else
                S.data[count + 1] = {
                    module = module, class = class, field = field, record = record,
                    original = original, translated = translated, scope = scopeId(),
                }
            end
        end
    end
    return false
end

-- Called synchronously while StringDB overlays merge: store references only.
function D.OnDbMiss(moduleName, rowId, en, cn)
    if not cfg.Untranslated or S.disabled then
        return
    end
    local moduleKey = moduleName or "?"
    local seen = S.dbSeen[moduleKey]
    if seen == nil then
        seen = {}
        S.dbSeen[moduleKey] = seen
    end
    local rowKey = rowId
    if rowKey == nil then
        rowKey = en or cn or "?"
    end
    if seen[rowKey] then
        return
    end
    local count = S.dbCount
    if count >= DB_MISS_MAX then
        S.dropped.db = S.dropped.db + 1
        return
    end
    seen[rowKey] = true
    local base = count * 4
    local db = S.db
    db[base + 1] = moduleName
    db[base + 2] = rowId
    db[base + 3] = en
    db[base + 4] = cn
    S.dbCount = count + 1
end

-- Processing (tick only) -----------------------------------------------------

local UNTRANSLATED_ORDER = {
    "sid", "src", "text", "norm", "panel", "widget", "path", "scope", "vis",
    "module", "class", "field", "record", "row", "original", "translated", "en", "cn",
    "count", "t",
}
local OVERFLOW_ORDER = {
    "sid", "panel", "widget", "path", "text", "len", "font", "typeface", "size", "size_pre", "cap",
    "ls", "ls_pre", "ls_negative", "wrap", "wrap_pre", "need", "need_pre", "have", "parent",
    "parent_have", "pexcess", "parent_grew", "kind", "count", "t",
}
local FIT_ORDER = {
    "sid", "kind", "mode", "panel", "widget", "path", "text", "len", "size_pre", "cap", "size", "min", "steps",
    "slot", "axis", "budget", "need", "need0", "need_pre", "reason", "scope", "count", "t",
}
local IMAGE_ORDER = { "sid", "panel", "widget", "resource", "class", "size", "count", "t" }

local function measure(widget)
    local library = slate()
    if library == nil then
        return nil
    end
    local m = {}
    local ok = pcall(function()
        local geometry = widget:GetCachedGeometry()
        local size = library.GetLocalSize(geometry)
        m.geometry = geometry
        m.haveX = tonumber(size.X) or 0
        m.haveY = tonumber(size.Y) or 0
    end)
    noteApi("GetCachedGeometry", ok)
    if not ok then
        S.errors.measure = S.errors.measure + 1
        return nil
    end
    if m.haveX <= 0 or m.haveY <= 0 then
        return nil
    end
    ok = pcall(function()
        local desired = widget:GetDesiredSize()
        m.needX = tonumber(desired.X) or 0
        m.needY = tonumber(desired.Y) or 0
    end)
    noteApi("GetDesiredSize", ok)
    if not ok then
        S.errors.measure = S.errors.measure + 1
        return nil
    end
    return m
end

local function isVisible(widget)
    local visible = nil
    local ok = pcall(function()
        if widget.IsVisible ~= nil then
            visible = widget:IsVisible() == true
        end
    end)
    noteApi("IsVisible", ok and visible ~= nil)
    return visible
end

local function absoluteRect(library, geometry, width, height)
    local topLeft = library.LocalToAbsolute(geometry, vector2(0, 0))
    local bottomRight = library.LocalToAbsolute(geometry, vector2(width, height))
    return tonumber(topLeft.X) or 0, tonumber(topLeft.Y) or 0,
        tonumber(bottomRight.X) or 0, tonumber(bottomRight.Y) or 0
end

local function checkOverflow(widget, m, info)
    local wrap = false
    pcall(function() wrap = widget.AutoWrapText == true end)
    local overX = wrap and 0 or (m.needX - m.haveX)
    local overY = m.needY - m.haveY
    local selfOver = overX > 1 or overY > 1
    local excess = math.max(overX, overY)

    -- Parent: pexcess = how far the text leaves the parent, in local px. Only
    -- more than 2 px counts (1-1.5 px layout offsets were 114 of 208 false
    -- "parent" rows in v2.9.6). Scroll boxes hold scrolling content: skipped.
    local parentOver, pexcess = false, nil
    local parentClass, parentHave = nil, nil
    local parent = nil
    local parentOk = pcall(function() parent = widget:GetParent() end)
    noteApi("GetParent", parentOk)
    if parent ~= nil then
        local library = slate()
        pcall(function()
            local parentGeometry = parent:GetCachedGeometry()
            local parentSize = library.GetLocalSize(parentGeometry)
            local pw, ph = tonumber(parentSize.X) or 0, tonumber(parentSize.Y) or 0
            if pw <= 0 or ph <= 0 then
                return
            end
            parentHave = array({ round1(pw), round1(ph) })
            local x1, y1, x2, y2 = absoluteRect(library, m.geometry, m.haveX, m.haveY)
            local scaleX = m.haveX > 0 and (x2 - x1) / m.haveX or 1
            local scaleY = m.haveY > 0 and (y2 - y1) / m.haveY or 1
            local needRight = x1 + math.max(m.haveX, wrap and m.haveX or m.needX) * scaleX
            local needBottom = y1 + math.max(m.haveY, m.needY) * scaleY
            local px1, py1, px2, py2 = absoluteRect(library, parentGeometry, pw, ph)
            local over = math.max(px1 - x1, py1 - y1, needRight - px2, needBottom - py2)
            local scale = math.max(scaleX, scaleY, 0.0001)
            if over > 0 then
                pexcess = over / scale
            end
        end)
        if parentHave ~= nil then
            parentClass = className(parent)
        end
    end
    if parentHave == nil or (parentClass ~= nil and parentClass:find("ScrollBox", 1, true)) then
        pexcess = nil
    end
    if pexcess ~= nil and pexcess > 2 then
        parentOver = true
        excess = math.max(excess, pexcess)
    end
    if not selfOver and not parentOver then
        return
    end
    local sp = sizePre[widget]
    local needPre = sp and sp.x and sp.x > 0 and array({ round1(sp.x), round1(sp.y) }) or nil
    local parentGrew = nil
    if needPre ~= nil then
        parentGrew = m.needX > sp.x + 2
    end

    local key = "overflow|" .. tostring(info.path or info.name) .. "|" .. info.norm
    local record, emit = dedup(key)
    if record == nil then
        return
    end
    if (record.excess or 0) + 2 < excess then
        record.excess = excess
        emit = true
    end
    if not emit then
        return
    end
    local post = info.post or {}
    local pre = info.pre or {}
    -- Legacy ceiling of TextFit "cap" (TASK-013), read from Init.lua's state.
    local cap = nil
    pcall(function()
        local st = S.fixes.TextFit.States[widget]
        cap = st and tonumber(st.cap) or nil
    end)
    appendRow("overflow", {
        sid = S.sid, panel = info.panel, widget = info.name, path = info.path,
        text = clip(info.text, TEXT_MAX), len = utf8Len(info.text),
        font = post.path, typeface = post.typeface, size = post.size, size_pre = pre.size, cap = cap,
        ls = post.ls, ls_pre = pre.ls, ls_negative = (tonumber(post.ls) or 0) < 0,
        wrap = wrap, wrap_pre = sp and sp.wrap,
        need = array({ round1(m.needX), round1(m.needY) }), need_pre = needPre,
        have = array({ round1(m.haveX), round1(m.haveY) }),
        parent = parentClass, parent_have = parentHave,
        pexcess = pexcess and round1(pexcess) or nil, parent_grew = parentGrew,
        kind = selfOver and (parentOver and "both" or "self") or "parent",
        count = record.count, t = stamp("%H:%M:%S"),
    }, OVERFLOW_ORDER)
end

local function noteFont(snap, role, name, panel, cjk, cyrillic, latin)
    if type(snap) ~= "table" then
        return
    end
    local key = role .. "|" .. tostring(snap.path) .. "|" .. tostring(snap.typeface)
    local record = S.fonts[key]
    if record == nil then
        if S.fontCount >= FONTS_MAX then
            S.dropped.fonts = S.dropped.fonts + 1
            return
        end
        record = {
            key = tostring(snap.path) .. "|" .. tostring(snap.typeface), role = role,
            path = snap.path, typeface = snap.typeface, count = 0,
            widgets = array(), widgetSet = {}, panels = array(), panelSet = {}, sizes = {},
            texts_cyrillic = 0, texts_cjk = 0, texts_latin = 0,
        }
        S.fonts[key] = record
        S.fontCount = S.fontCount + 1
    end
    record.count = record.count + 1
    if name ~= nil and not record.widgetSet[name] and #record.widgets < LIST_MAX then
        record.widgetSet[name] = true
        record.widgets[#record.widgets + 1] = name
    end
    if panel ~= nil and not record.panelSet[panel] and #record.panels < LIST_MAX then
        record.panelSet[panel] = true
        record.panels[#record.panels + 1] = panel
    end
    if snap.size ~= nil then
        local sizeKey = tostring(round1(snap.size))
        record.sizes[sizeKey] = (record.sizes[sizeKey] or 0) + 1
    end
    if cyrillic then record.texts_cyrillic = record.texts_cyrillic + 1 end
    if cjk then record.texts_cjk = record.texts_cjk + 1 end
    if latin then record.texts_latin = record.texts_latin + 1 end
end

local function clipChars(text, limit)
    local chars, cut = 0, #text
    for position in text:gmatch("()[^\128-\191]") do
        chars = chars + 1
        if chars > limit then
            cut = position - 1
            break
        end
    end
    return text:sub(1, cut)
end

-- TASK-007: Cyrillic still drawn by a Font_Aleo Title typeface (FZ Mincho,
-- 1.0 em). styled: the widget went through translateTextWidget; rich: the
-- font is the RichText default style (nil font_read = style unreadable).
local function noteTitleCyrillic(widget, snap, rich, styled, name, panel, path, text)
    if snap ~= nil then
        local typeface = snap.typeface or ""
        if not (tostring(snap.path):find("Font_Aleo.Font_Aleo", 1, true) and typeface:find("Title", 1, true)) then
            return
        end
    elseif not rich then
        return
    end
    local key = tostring(panel) .. "|" .. tostring(name) .. "|" .. tostring(snap and snap.typeface)
    local record = S.titleCyr[key]
    if record == nil then
        if S.titleCyrCount >= TITLE_CYR_MAX then
            S.dropped.title_cyrillic = S.dropped.title_cyrillic + 1
            return
        end
        record = {
            panel = panel, widget = name, class = className(widget), path = path,
            text = clipChars(text, TITLE_CYR_TEXT), typeface = snap and snap.typeface,
            size = snap and snap.size, font_read = snap ~= nil, font_src = snap and snap.source,
            styled = styled, rich = rich, count = 0,
        }
        S.titleCyr[key] = record
        S.titleCyrCount = S.titleCyrCount + 1
    end
    record.count = record.count + 1
    if styled then record.styled = true end
end

-- source: "hook" (translateTextWidget) or "walk" (panel walk).
local function processTextWidget(widget, text, name, pre, panel, scope, source)
    local path = objectPath(widget)
    panel = panel or panelFromPath(path)
    name = name or objectName(widget) or "?"
    local cjk, cyrillic, latin = classify(text)
    local m = nil
    local started = nowMs()
    if cfg.Overflow or cfg.Untranslated then
        m = measure(widget)
    end
    local visible = m ~= nil and isVisible(widget) ~= false
    track("measure", started)

    if cfg.Untranslated and (cjk or latin) then
        started = nowMs()
        local norm = normalize(text)
        local record, emit = dedup("widget|" .. norm)
        if record ~= nil and emit then
            appendRow("untranslated", {
                sid = S.sid, src = "widget", text = clip(text, TEXT_MAX), norm = norm,
                panel = panel, widget = name, path = path, scope = scope, vis = visible,
                count = record.count, t = stamp("%H:%M:%S"),
            }, UNTRANSLATED_ORDER)
        end
        track("encode", started)
    end

    started = nowMs()
    local post = nil
    if cfg.Fonts or cfg.Overflow then
        post = readFont(widget)
    end
    if cfg.Fonts then
        if source == "hook" then
            noteFont(pre, "pre", name, panel, cjk, cyrillic, latin)
            noteFont(post, "post", name, panel, cjk, cyrillic, latin)
        else
            -- Walk: a widget never styled by translateTextWidget keeps its
            -- authored font, which is what stage 4 needs.
            local styled = fontPre[widget]
            noteFont(post, styled and "post" or "pre", name, panel, cjk, cyrillic, latin)
        end
        if cyrillic then
            local styled = source == "hook" or fontPre[widget] ~= nil
            local snap, rich = post, false
            if snap == nil then
                local class = className(widget)
                rich = class ~= nil and class:find("RichText", 1, true) ~= nil
                if rich then snap = readRichFont(widget) end
            end
            noteTitleCyrillic(widget, snap, rich, styled, name, panel, path, text)
        end
    end
    track("font", started)

    if cfg.Overflow and m ~= nil and visible then
        started = nowMs()
        checkOverflow(widget, m, {
            path = path, name = name, panel = panel, text = text, norm = normalize(text),
            post = post, pre = pre or fontPre[widget] or nil,
        })
        track("measure", started)
    end
end

local function processItem(item)
    if item.k == "text" then
        local widget = take(item.ref)
        if widget == nil then
            S.counters.gone = S.counters.gone + 1
            return
        end
        pcall(function() S.pendingText[widget] = nil end)
        S.counters.text_items = S.counters.text_items + 1
        processTextWidget(widget, item.text, item.name, item.pre, item.panel, item.scope, "hook")
    elseif item.k == "fit" then
        local widget = take(item.ref)
        if widget == nil then
            S.counters.gone = S.counters.gone + 1
            return
        end
        local started = nowMs()
        local row = item.row
        local path = objectPath(widget)
        local text = tostring(row.text or "")
        local record, emit = dedup("fit|" .. tostring(row.kind) .. "|" .. tostring(path) .. "|" .. normalize(text))
        if record ~= nil and emit then
            appendRow("fit", {
                sid = S.sid, kind = row.kind, mode = row.mode, panel = item.panel or panelFromPath(path),
                widget = objectName(widget), path = path, text = clip(text, TEXT_MAX), len = utf8Len(text),
                size_pre = row.size_pre, cap = row.cap, size = row.size, min = row.min and round1(row.min) or nil,
                steps = row.steps, slot = row.slot, axis = row.axis,
                budget = row.budget and round1(row.budget) or nil, need = row.need and round1(row.need) or nil,
                need0 = row.need0 and round1(row.need0) or nil, need_pre = row.need_pre and round1(row.need_pre) or nil,
                reason = row.reason, scope = item.scope, count = record.count, t = stamp("%H:%M:%S"),
            }, FIT_ORDER)
        end
        track("encode", started)
    end
end

local function processData(entry)
    local translated = entry.translated
    local norm = normalize(translated)
    local record, emit = dedup("data|" .. tostring(entry.module) .. "|" .. tostring(entry.field) .. "|" .. norm)
    if record == nil or not emit then
        return
    end
    appendRow("untranslated", {
        sid = S.sid, src = "data", module = entry.module and tostring(entry.module) or nil,
        class = entry.class and tostring(entry.class) or nil,
        field = entry.field and tostring(entry.field) or nil,
        record = entry.record ~= nil and tostring(entry.record) or nil,
        original = type(entry.original) == "string" and clip(entry.original, TEXT_MAX) or nil,
        translated = clip(translated, TEXT_MAX), norm = norm, scope = entry.scope,
        count = record.count, t = stamp("%H:%M:%S"),
    }, UNTRANSLATED_ORDER)
end

local function processDb(index)
    local base = index * 4
    local db = S.db
    local moduleName, rowId, en, cn = db[base + 1], db[base + 2], db[base + 3], db[base + 4]
    db[base + 1], db[base + 2], db[base + 3], db[base + 4] = nil, nil, nil, nil
    appendRow("untranslated", {
        sid = S.sid, src = "stringdb", module = moduleName and tostring(moduleName) or nil,
        row = rowId,
        en = type(en) == "string" and clip(en, TEXT_MAX) or nil,
        cn = type(cn) == "string" and clip(cn, TEXT_MAX) or nil,
    }, UNTRANSLATED_ORDER)
end

-- Panel walks ------------------------------------------------------------------

-- Init.lua helpers update runtimeMetrics counters; keep them free of diagnostics work.
local function withMetricsKept(fn, ...)
    local metrics = S.metrics
    local calls, built, replaced
    if metrics ~= nil then
        calls, built, replaced = metrics.GetAllWidgetsCalls, metrics.WidgetIndexesBuilt, metrics.WidgetTreeReplacements
    end
    local ok, result = pcall(fn, ...)
    if metrics ~= nil then
        metrics.GetAllWidgetsCalls, metrics.WidgetIndexesBuilt, metrics.WidgetTreeReplacements = calls, built, replaced
    end
    return ok and result or nil
end

-- UserWidgets have no GetChildrenCount; their content hangs off WidgetTree.RootWidget.
-- Returns the tree root and whether WidgetTree.GetAllWidgets is callable.
local function treeRoot(owner)
    local root, getAll, hasTree = nil, false, false
    pcall(function()
        local tree = owner.WidgetTree
        if tree ~= nil then
            hasTree = true
            getAll = type(tree.GetAllWidgets) == "function"
            root = tree.RootWidget
        end
    end)
    if hasTree then
        noteApi("WidgetTree.RootWidget", root ~= nil)
        noteApi("WidgetTree.GetAllWidgets", getAll)
    end
    return root, getAll
end

local function listUserWidgets(owner, getAll)
    local getList = S.getWidgetList
    if getList == nil or not getAll then
        return nil
    end
    return withMetricsKept(getList, owner)
end

local function pushChildren(stack, owner)
    local count = nil
    pcall(function()
        if owner.GetChildrenCount ~= nil then
            count = tonumber(owner:GetChildrenCount())
        end
    end)
    if count ~= nil then
        for index = count - 1, 0, -1 do
            local child = nil
            pcall(function() child = owner:GetChildAt(index) end)
            if child ~= nil then
                stack[#stack + 1] = child
            end
        end
    end
    local content = nil
    pcall(function()
        if owner.GetContent ~= nil then
            content = owner:GetContent()
        end
    end)
    if content ~= nil then
        stack[#stack + 1] = content
    end
    local getEntries = nil
    pcall(function() getEntries = owner.GetDisplayedEntryWidgets end)
    if type(getEntries) == "function" then
        local entries = {}
        local ok, result = pcall(getEntries, owner, entries)
        if ok then
            for _, entry in pairs(type(result) == "table" and result or entries) do
                stack[#stack + 1] = entry
            end
        end
    end
    local root, getAll = treeRoot(owner)
    if root ~= nil then
        stack[#stack + 1] = root
    end
    local list = listUserWidgets(owner, getAll)
    if type(list) == "table" then
        for _, widget in pairs(list) do
            stack[#stack + 1] = widget
        end
    end
end

local function noteImage(job, widget, brush)
    local resource = nil
    local ok = pcall(function() resource = brush.ResourceObject end)
    noteApi("Brush.ResourceObject", ok)
    if resource == nil then
        return
    end
    local path = objectPath(resource) or "?"
    local record, emit = dedup("image|" .. job.uid .. "|" .. path)
    if record == nil or not emit then
        return
    end
    local sizeX, sizeY = nil, nil
    pcall(function()
        sizeX = tonumber(brush.ImageSize.X)
        sizeY = tonumber(brush.ImageSize.Y)
    end)
    appendRow("images", {
        sid = S.sid, panel = job.uid, widget = objectName(widget), resource = path,
        class = className(resource),
        size = sizeX and array({ round1(sizeX), round1(sizeY) }) or nil,
        count = record.count, t = stamp("%H:%M:%S"),
    }, IMAGE_ORDER)
end

local function visitWidget(job, widget)
    local getText = nil
    pcall(function() getText = widget.GetText end)
    if type(getText) == "function" then
        if cfg.Untranslated or cfg.Overflow or cfg.Fonts then
            local ok, value = pcall(getText, widget)
            local text = ok and value ~= nil and tostring(value) or nil
            if text ~= nil and text ~= "" then
                processTextWidget(widget, text, nil, nil, job.uid, "panel:" .. job.uid .. ":walk", "walk")
            end
        end
        return
    end
    if cfg.Images then
        local brush = nil
        pcall(function() brush = widget.Brush end)
        if brush ~= nil then
            local started = nowMs()
            noteImage(job, widget, brush)
            track("image", started)
        end
    end
end

local function isWidgetValue(value)
    local valueType = type(value)
    return valueType == "userdata" or valueType == "table"
end

-- Roots mirror Init.lua translateViewTextWidgets: generated view entries,
-- view._widgetCache, the UserWidget tree root and VisibleWidgetNames lookups.
-- WidgetTree.GetAllWidgets is unavailable in this build, so userWidget alone
-- yields only a handful of nodes. The FindWidget name probe is not repeated.
local function newWalkJob(component, uid)
    local roots = {}
    local seenComponents = {}
    local counters = S.counters
    local function addRoot(value, counter)
        if isWidgetValue(value) then
            roots[#roots + 1] = value
            counters[counter] = counters[counter] + 1
        end
    end
    local function addComponent(current, depth)
        if type(current) ~= "table" or seenComponents[current] or depth > 8 then
            return
        end
        seenComponents[current] = true
        if current.isDestroyed then
            return
        end
        local view = current.view
        if type(view) == "table" then
            for key, value in pairs(view) do
                if key ~= "_widgetCache" then
                    addRoot(value, "roots_view")
                end
            end
            if type(view._widgetCache) == "table" then
                for _, value in pairs(view._widgetCache) do
                    addRoot(value, "roots_cache")
                end
            end
        end
        local root = current.userWidget or current.widget
        if root ~= nil then
            roots[#roots + 1] = root
            addRoot((treeRoot(root)), "roots_tree")
            local getNamed = S.getNamedWidget
            local names = S.fixes and S.fixes.VisibleWidgetNames
            if getNamed ~= nil and type(names) == "table" then
                for _, name in ipairs(names) do
                    addRoot(withMetricsKept(getNamed, root, name), "roots_named")
                end
            end
        end
        if type(current._childComponents) == "table" then
            for _, child in pairs(current._childComponents) do
                addComponent(child, depth + 1)
            end
        end
    end
    pcall(addComponent, component, 0)
    return { uid = uid, stack = roots, visited = {}, nodes = 0 }
end

-- Returns true when the walk is finished.
local function stepWalk(job, deadline)
    local stack = job.stack
    local visited = job.visited
    while #stack > 0 do
        if nowMs() >= deadline then
            return false
        end
        local widget = stack[#stack]
        stack[#stack] = nil
        if widget ~= nil and not visited[widget] then
            visited[widget] = true
            job.nodes = job.nodes + 1
            if job.nodes > WALK_NODE_MAX then
                S.dropped.walk_nodes = S.dropped.walk_nodes + 1
                return true
            end
            local ok, err = pcall(visitWidget, job, widget)
            if not ok then
                noteError("walk", err)
            end
            local started = nowMs()
            pushChildren(stack, widget)
            track("walk", started)
        end
    end
    return true
end

local function processDelayed(now)
    if #S.delayed == 0 then
        return
    end
    local remaining = {}
    for _, entry in ipairs(S.delayed) do
        if entry.due <= now then
            local component = take(entry.ref)
            if component ~= nil then
                if #S.walkJobs < WALK_JOBS_MAX then
                    local started = nowMs()
                    S.walkJobs[#S.walkJobs + 1] = newWalkJob(component, entry.uid)
                    track("walk", started)
                else
                    S.dropped.walk_jobs = S.dropped.walk_jobs + 1
                end
            else
                S.counters.gone = S.counters.gone + 1
            end
        else
            remaining[#remaining + 1] = entry
        end
    end
    S.delayed = remaining
end

function D.OnPanelOpen(component)
    if S.disabled or component == nil then
        return
    end
    S.flushSoon = true
    -- Fallback pump: before after_main, or when the timer chain was dropped.
    if nowMs() - S.lastTick > PUMP_STALE_MS then
        S.timerPending = false
        D.Tick()
    end
    if not cfg.PanelWalk or not (cfg.Untranslated or cfg.Overflow or cfg.Images or cfg.Fonts) then
        return
    end
    local ok = pcall(function()
        local uid = componentUid(component)
        local walks = S.walkCounts[uid] or 0
        if walks >= cfg.PanelWalksPerUid then
            S.counters.walks_skipped = S.counters.walks_skipped + 1
            return
        end
        local now = nowMs()
        for _, delay in ipairs({ 500, 2000 }) do
            if walks < cfg.PanelWalksPerUid then
                if #S.delayed >= DELAYED_MAX then
                    S.dropped.delayed = S.dropped.delayed + 1
                else
                    walks = walks + 1
                    S.delayed[#S.delayed + 1] = { due = now + delay, ref = keep(component), uid = uid }
                end
            end
        end
        S.walkCounts[uid] = walks
    end)
    if not ok then
        noteError("walk", "OnPanelOpen")
    end
end

-- Summaries ------------------------------------------------------------------

local HOOK_ORDER = {
    "id", "kind", "status", "module", "declared", "installed", "wraps", "calls",
    "text_changes", "text_writes", "data_changes", "errors", "ms_total", "ms_max", "light",
}
local PANEL_ORDER = {
    "id", "uid", "runs", "labels", "widgets", "text_changes", "text_writes", "data_changes",
    "ms_total", "ms_max",
}

local function moduleApplied(module)
    local applied = S.loader and S.loader.Applied
    if module == nil or type(applied) ~= "table" then
        return 0
    end
    return tonumber(applied[module]) or 0
end

local function hookStatus(record)
    if not record.installed then
        return moduleApplied(record.module) > 0 and "NOT_INSTALLED" or "NOT_LOADED"
    end
    if record.calls == 0 then
        return "NEVER_CALLED"
    end
    if record.light then
        return "CALLED"
    end
    if record.text_changes + record.data_changes + record.text_writes == 0 then
        return "NO_EFFECT"
    end
    return "ACTIVE"
end

local function sortedValues(map)
    local list = {}
    for _, value in pairs(map) do
        list[#list + 1] = value
    end
    table.sort(list, function(a, b) return tostring(a.id or a.key) < tostring(b.id or b.key) end)
    return list
end

local function encodeHookRecord(record)
    return encodeValue({
        id = record.id, kind = record.kind, status = hookStatus(record), module = record.module,
        declared = record.declared, installed = record.installed, wraps = record.wraps,
        calls = record.calls, text_changes = record.text_changes, text_writes = record.text_writes,
        data_changes = record.data_changes, errors = record.errors,
        ms_total = record.ms_total, ms_max = record.ms_max, light = record.light,
    }, 0, HOOK_ORDER)
end

local function encodePanelRecord(record)
    return encodeValue({
        id = record.id, uid = record.uid, runs = record.calls, labels = record.labels,
        widgets = record.widgets, text_changes = record.text_changes,
        text_writes = record.text_writes, data_changes = record.data_changes,
        ms_total = record.ms_total, ms_max = record.ms_max,
    }, 0, PANEL_ORDER)
end

local AFTERLOAD_ORDER = { "id", "module", "applied" }

local function afterloadRows()
    local rows = {}
    local loader = S.loader
    if loader == nil or type(loader.Hooks) ~= "table" then
        return rows
    end
    local names = {}
    for name in pairs(loader.Hooks) do
        names[#names + 1] = tostring(name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local hooks = loader.Hooks[name]
        if type(hooks) == "table" then
            for _, hook in ipairs(hooks) do
                rows[#rows + 1] = { id = hook.Id and tostring(hook.Id) or nil, module = name, applied = moduleApplied(name) }
            end
        end
    end
    return rows
end

-- Cheap fingerprint: hooks.json is rewritten only when a counter changed.
local function hooksSignature()
    local parts = { S.hookCount, S.panelCount, S.noteSeq }
    local sum = 0
    for _, record in pairs(S.hooks) do
        sum = sum + record.calls + record.text_changes + record.text_writes + record.data_changes
            + record.errors + (record.wraps or 0) + (record.installed and 1 or 0)
    end
    for _, record in pairs(S.panels) do
        sum = sum + record.calls + record.labels + record.text_changes
    end
    parts[#parts + 1] = sum
    local applied = S.loader and S.loader.Applied
    local appliedSum = 0
    if type(applied) == "table" then
        for _, count in pairs(applied) do
            appliedSum = appliedSum + (tonumber(count) or 0)
        end
    end
    parts[#parts + 1] = appliedSum
    for key, count in pairs(S.writes) do
        parts[#parts + 1] = key .. "=" .. tostring(count)
    end
    table.sort(parts, function(a, b) return tostring(a) < tostring(b) end)
    local text = {}
    for index, value in ipairs(parts) do
        text[index] = tostring(value)
    end
    return table.concat(text, ",")
end

local function newHooksJob(signature)
    return {
        signature = signature,
        stages = {
            { list = afterloadRows(), encode = function(row) return encodeValue(row, 0, AFTERLOAD_ORDER) end, out = {} },
            { list = sortedValues(S.hooks), encode = encodeHookRecord, out = {} },
            { list = sortedValues(S.panels), encode = encodePanelRecord, out = {} },
        },
        stage = 1,
        index = 0,
    }
end

local function finishHooksJob(job)
    local stages = job.stages
    return "{" .. Q .. "schema" .. Q .. ":1," .. Q .. "sid" .. Q .. ":" .. encodeString(S.sid)
        .. "," .. Q .. "unscoped" .. Q .. ":" .. encodeValue(S.unscoped)
        .. "," .. Q .. "writes" .. Q .. ":" .. encodeValue(S.writes)
        .. ",\n" .. Q .. "afterload" .. Q .. ":[\n" .. table.concat(stages[1].out, ",\n") .. "]"
        .. ",\n" .. Q .. "hooks" .. Q .. ":[\n" .. table.concat(stages[2].out, ",\n") .. "]"
        .. ",\n" .. Q .. "panels" .. Q .. ":[\n" .. table.concat(stages[3].out, ",\n") .. "]}\n"
end

-- Encodes records until the deadline; returns true when the job is complete.
local function stepHooksJob(job, deadline)
    while job.stage <= #job.stages do
        local stage = job.stages[job.stage]
        while job.index < #stage.list do
            if deadline ~= nil and nowMs() >= deadline then
                return false
            end
            job.index = job.index + 1
            stage.out[job.index] = stage.encode(stage.list[job.index])
        end
        job.stage = job.stage + 1
        job.index = 0
    end
    return true
end

-- Synchronous encoding (after_main and forced flushes).
local function encodeHooks()
    local job = newHooksJob(nil)
    stepHooksJob(job, nil)
    return finishHooksJob(job)
end

local function fixesFontPath(field)
    local fixes = S.fixes
    local object = fixes and fixes[field]
    if object == nil then
        return nil
    end
    return objectPath(object)
end

local function encodeFonts()
    local fonts = {}
    for _, record in ipairs(sortedValues(S.fonts)) do
        fonts[#fonts + 1] = encodeValue({
            key = record.key, role = record.role, path = record.path, typeface = record.typeface,
            count = record.count, widgets = record.widgets, panels = record.panels, sizes = record.sizes,
            texts_cyrillic = record.texts_cyrillic, texts_cjk = record.texts_cjk,
            texts_latin = record.texts_latin,
        }, 0, {
            "key", "role", "path", "typeface", "count", "texts_cyrillic", "texts_cjk",
            "texts_latin", "sizes", "widgets", "panels",
        })
    end
    local titleRows = {}
    for _, record in pairs(S.titleCyr) do titleRows[#titleRows + 1] = record end
    table.sort(titleRows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.panel) .. tostring(a.widget) < tostring(b.panel) .. tostring(b.widget)
    end)
    local titleCyr = {}
    for index, record in ipairs(titleRows) do
        titleCyr[index] = encodeValue(record, 0, {
            "panel", "widget", "class", "typeface", "size", "styled", "rich", "font_read", "font_src",
            "count", "text", "path",
        })
    end
    local status = S.fixes and S.fixes.CyrillicFontStatus
    return "{" .. Q .. "schema" .. Q .. ":1," .. Q .. "sid" .. Q .. ":" .. encodeString(S.sid)
        .. "," .. Q .. "standard" .. Q .. ":" .. encodeValue(fixesFontPath("StandardFontObject"))
        .. "," .. Q .. "cinematic" .. Q .. ":" .. encodeValue(fixesFontPath("CinematicFontObject"))
        .. ",\n" .. Q .. "cyrillic_font" .. Q .. ":" .. encodeValue(type(status) == "table" and status or nil, 0, {
            "mode", "requested", "title_typeface", "typefaces", "title", "title_sdf", "title_sdf_headname",
            "source", "previous", "write", "via", "verify", "flush", "reason", "applied_at",
        })
        .. ",\n" .. Q .. "composite" .. Q .. ":" .. encodeValue(S.composite)
        .. ",\n" .. Q .. "title_cyrillic" .. Q .. ":[\n" .. table.concat(titleCyr, ",\n") .. "]"
        .. ",\n" .. Q .. "fonts" .. Q .. ":[\n" .. table.concat(fonts, ",\n") .. "]}\n"
end

-- CompositeFont probe (TASK-006, flag Fonts): read-only structure of the UI
-- fonts, one font per tick. Nothing is called on or written to game objects.
local COMPOSITE_PATHS = {
    "/Game/Arts/UI_2/Resource/Font/Font_Aleo.Font_Aleo",
    "/Game/Arts/UI_2/Resource/Font/Font_Mistery.Font_Mistery",
    "/Game/Arts/UI_Update/Resource/Font/Font_Aleo_Update.Font_Aleo_Update",
    "/Engine/EngineFonts/Roboto.Roboto",
}
local probeCompositeStep
do
    local function items(values)
        local output = {}
        if type(values) == "table" then
            for index, value in ipairs(values) do output[index] = value end
            return output
        end
        local ok, total = pcall(function() return values:Num() end)
        if not ok or type(total) ~= "number" then return output end
        for index = 0, math.min(total, 64) - 1 do
            local okItem, value = pcall(function() return values:Get(index) end)
            if okItem then output[#output + 1] = value end
        end
        return output
    end

    local function readEntries(fonts)
        local rows = {}
        for _, entry in ipairs(items(fonts)) do
            local row = {}
            pcall(function() row.name = tostring(entry.Name) end)
            pcall(function()
                local data = entry.Font
                local face = data.FontFaceAsset
                if face ~= nil then row.face = objectPath(face) or tostring(face) end
                pcall(function() row.loading = tostring(data.LoadingPolicy) end)
                pcall(function() row.hinting = tostring(data.Hinting) end)
                pcall(function() row.subface = tonumber(data.SubFaceIndex) end)
            end)
            rows[#rows + 1] = row
        end
        return array(rows)
    end

    local function probeCulture()
        local ok, library = pcall(import, "KismetInternationalizationLibrary")
        if not ok or library == nil then
            S.api["culture"] = "import=fail"
            return
        end
        for _, name in ipairs({ "GetCurrentCulture", "GetCurrentLanguage", "GetCurrentLocale" }) do
            local okCall, value = pcall(function() return library[name]() end)
            S.api["culture." .. name] = okCall and tostring(value) or "error"
        end
    end

    -- FInt32Range is opaque in slua (TASK-008): character ranges are only counted.
    local function probeComposite(path)
        local record = { loaded = false }
        local object = nil
        pcall(function() object = slua.loadObject(path) end)
        if object == nil then return record end
        record.loaded = true
        local ok, cf = pcall(function() return object.CompositeFont end)
        noteApi("UFont.CompositeFont", ok and cf ~= nil)
        if not ok or cf == nil then
            record.error = tostring(cf)
            return record
        end
        pcall(function() record.default = readEntries(cf.DefaultTypeface.Fonts) end)
        pcall(function()
            local fallback = cf.FallbackTypeface
            record.fallback = { scaling = tonumber(fallback.ScalingFactor), fonts = readEntries(fallback.Typeface.Fonts) }
        end)
        local subs = {}
        pcall(function()
            for _, sub in ipairs(items(cf.SubTypefaces)) do
                local row = {}
                pcall(function() row.cultures = tostring(sub.Cultures) end)
                pcall(function() row.scaling = tonumber(sub.ScalingFactor) end)
                pcall(function() row.ranges = tonumber(sub.CharacterRanges:Num()) end)
                pcall(function() row.fonts = readEntries(sub.Typeface.Fonts) end)
                subs[#subs + 1] = row
            end
        end)
        record.subs = array(subs)
        return record
    end

    -- The field is only read (its Lua type), never called.
    local function probeFontApi()
        local ok, library = pcall(import, "C7FunctionLibrary")
        noteApi("C7FunctionLibrary", ok and library ~= nil)
        local kind = "missing"
        if ok and library ~= nil then
            local okField, value = pcall(function() return library.FlushFontCache end)
            kind = okField and type(value) or "error"
        end
        S.api["C7FunctionLibrary.FlushFontCache"] = kind
        pcall(probeCulture)
    end

    probeCompositeStep = function()
        local index = S.compositeNext
        S.compositeNext = index + 1
        if index == 1 then pcall(probeFontApi) end
        local path = COMPOSITE_PATHS[index]
        local started = nowMs()
        local ok, record = pcall(probeComposite, path)
        track("font", started)
        if not ok then
            noteError("item", record)
            record = { error = tostring(record) }
        end
        S.composite[path] = record
        if S.compositeNext > #COMPOSITE_PATHS then
            S.flushSoon = true
        end
    end
end

local function metricsCopy()
    local copy = {}
    local metrics = S.metrics
    if type(metrics) == "table" then
        for key, value in pairs(metrics) do
            local valueType = type(value)
            if type(key) == "string" and (valueType == "number" or valueType == "boolean") then
                copy[key] = value
            end
        end
    end
    return copy
end

local function encodeSession()
    local parts, lines = partsSummary()
    local flags = {}
    for key, value in pairs(cfg) do
        flags[key] = value
    end
    return encodeValue({
        schema = 1, sid = S.sid, slot = S.slot, version = S.version, started = S.startedStamp,
        flags = flags, dir = S.dir, prefix = S.prefix, parts = parts, lines = lines, api = S.api,
        gauges = S.gauges, budget = S.budget, dropped = S.dropped, errors = S.errors,
        counters = S.counters, pending = {
            queue = S.qtail - S.qhead + 1, walks = #S.walkJobs, delayed = #S.delayed,
            data = #S.data - S.dataDone, stringdb = S.dbCount - S.dbDone,
        },
        session_bytes = S.sessionBytes, metrics = metricsCopy(), last_flush = S.lastFlushStamp,
        text_fit = type(S.fixes) == "table" and type(S.fixes.TextFit) == "table" and S.fixes.TextFit.Mode or nil,
    }, 0, {
        "schema", "sid", "slot", "version", "text_fit", "started", "last_flush", "flags", "dir", "prefix",
        "parts", "lines", "api", "gauges", "budget", "dropped", "errors", "counters", "pending",
        "session_bytes", "metrics",
    }) .. "\n"
end

function D.Flush(force)
    if S.dir == nil then
        return false
    end
    local started = nowMs()
    for _, current in pairs(S.streams) do
        if current.dirty and #current.lines > 0 then
            writeFile(partName(current, current.part), table.concat(current.lines, "\n") .. "\n")
            current.dirty = false
        end
    end
    if cfg.Hooks then
        local okSignature, signature = pcall(hooksSignature)
        if not okSignature then
            noteError("io", signature)
        elseif force then
            -- Forced flush (after_main): encode and write synchronously.
            S.hooksJob, S.hooksPending = nil, nil
            local ok, content = pcall(encodeHooks)
            if ok and writeFile("hooks.json", content) then
                S.hooksSignature = signature
                S.counters.hooks_writes = S.counters.hooks_writes + 1
            elseif not ok then
                noteError("io", content)
            end
        elseif signature ~= S.hooksSignature and S.hooksJob == nil then
            -- Periodic flush: hooks.json is encoded in ticks within FrameBudgetMs.
            S.hooksPending = signature
        else
            S.counters.hooks_unchanged = S.counters.hooks_unchanged + 1
        end
    end
    if cfg.Fonts then
        local ok, content = pcall(encodeFonts)
        if ok then writeFile("fonts.json", content) else noteError("io", content) end
    end
    S.budget.flushes = S.budget.flushes + 1
    S.lastFlush = nowMs()
    S.lastFlushStamp = stamp("%Y-%m-%d %H:%M:%S")
    local okSession, session = pcall(encodeSession)
    if okSession then writeFile("session.json", session) else noteError("io", session) end
    local elapsed = nowMs() - started
    if elapsed > S.budget.flush_ms_max then
        S.budget.flush_ms_max = elapsed
    end
    local parts = partsSummary()
    local partText = {}
    for name, count in pairs(parts) do
        partText[#partText + 1] = name .. ":" .. tostring(count)
    end
    table.sort(partText)
    warn(string.format("[AbsruDiag] flush #%.0f parts=%s queue=%.0f tick_ms_max=%.2f io_ms_max=%.2f flush_ms=%.2f",
        S.budget.flushes, table.concat(partText, ","), S.qtail - S.qhead + 1,
        S.budget.tick_ms_max, S.budget.io_ms_max, elapsed))
    return true
end

-- Tick -------------------------------------------------------------------------

local function busy()
    return S.qhead <= S.qtail or #S.walkJobs > 0 or #S.delayed > 0
        or S.dataDone < #S.data or S.dbDone < S.dbCount
        or S.hooksJob ~= nil or S.hooksPending ~= nil
end

local onTimer

local function schedule()
    if S.disabled or S.timerPending or not S.afterMain then
        return
    end
    local manager = nil
    pcall(function() manager = Game and Game.NewUIManager end)
    local addTimer = nil
    pcall(function() addTimer = manager and manager.AddTimerWithFunction end)
    if type(addTimer) ~= "function" then
        S.errors.timer = S.errors.timer + 1
        return
    end
    local delay = busy() and cfg.TickSeconds or IDLE_TICK_SECONDS
    S.timerPending = true
    local ok, result = pcall(addTimer, manager, delay, 1, onTimer)
    if not ok or result == false then
        S.timerPending = false
        S.errors.timer = S.errors.timer + 1
    end
end

local function tickBody()
    local started = nowMs()
    local deadline = started + cfg.FrameBudgetMs
    S.gen = S.gen + 1
    local gen = S.gen
    S.lastTick = started
    if S.depth > 64 then
        S.depth = 0
    end

    processDelayed(started)

    -- Items from the previous tick or earlier: at least one frame has passed.
    while S.qhead <= S.qtail and nowMs() < deadline do
        local item = S.queue[S.qhead]
        if item ~= nil and item.gen >= gen - 1 then
            break
        end
        S.queue[S.qhead] = nil
        S.qhead = S.qhead + 1
        if item ~= nil then
            local ok, err = pcall(processItem, item)
            if not ok then
                noteError("item", err)
            end
        end
    end
    if S.qhead > S.qtail then
        S.qhead, S.qtail = 1, 0
    end

    while #S.walkJobs > 0 and nowMs() < deadline do
        local job = S.walkJobs[1]
        local ok, done = pcall(stepWalk, job, deadline)
        if not ok then
            noteError("walk", done)
            done = true
        end
        if done then
            table.remove(S.walkJobs, 1)
            S.counters.walks = S.counters.walks + 1
            S.counters.walk_nodes = S.counters.walk_nodes + job.nodes
        end
    end

    while S.dataDone < #S.data and nowMs() < deadline do
        S.dataDone = S.dataDone + 1
        local entry = S.data[S.dataDone]
        S.data[S.dataDone] = nil
        if entry ~= nil then
            local itemStarted = nowMs()
            local ok, err = pcall(processData, entry)
            track("encode", itemStarted)
            if not ok then
                noteError("item", err)
            end
        end
    end
    if S.dataDone >= #S.data and S.dataDone > 0 then
        S.data = {}
        S.dataDone = 0
    end

    while S.dbDone < S.dbCount and nowMs() < deadline do
        local itemStarted = nowMs()
        local ok, err = pcall(processDb, S.dbDone)
        track("db", itemStarted)
        S.dbDone = S.dbDone + 1
        if not ok then
            noteError("item", err)
        end
    end
    if S.dbDone >= S.dbCount and S.dbCount > 0 then
        S.db = {}
        S.dbCount = 0
        S.dbDone = 0
    end

    -- hooks.json: build the job, encode records within the budget, write once.
    if S.hooksJob == nil and S.hooksPending ~= nil and nowMs() < deadline then
        local itemStarted = nowMs()
        local ok, job = pcall(newHooksJob, S.hooksPending)
        S.hooksPending = nil
        track("encode", itemStarted)
        if ok then S.hooksJob = job else noteError("io", job) end
    end
    if S.hooksJob ~= nil and nowMs() < deadline then
        local job = S.hooksJob
        local ok, done = pcall(stepHooksJob, job, deadline)
        if not ok then
            noteError("io", done)
            S.hooksJob = nil
        elseif done then
            S.hooksJob = nil
            local itemStarted = nowMs()
            local okText, content = pcall(finishHooksJob, job)
            track("encode", itemStarted)
            if okText and writeFile("hooks.json", content) then
                S.hooksSignature = job.signature
                S.counters.hooks_writes = S.counters.hooks_writes + 1
            elseif not okText then
                noteError("io", content)
            end
        end
    end

    if cfg.Fonts and S.compositeNext <= #COMPOSITE_PATHS and nowMs() < deadline then
        probeCompositeStep()
    end

    local now = nowMs()
    local elapsed = now - started
    local budget = S.budget
    budget.ticks = budget.ticks + 1
    budget.ms_total = budget.ms_total + elapsed
    if elapsed > budget.tick_ms_max then
        budget.tick_ms_max = elapsed
    end

    if S.dir ~= nil and (now - S.lastFlush >= cfg.FlushSeconds * 1000
        or (S.flushSoon and now - S.lastFlush >= FLUSH_SOON_MS))
    then
        S.flushSoon = false
        D.Flush(false)
    end
end

function D.Tick()
    if S.disabled or S.inTick or not S.started then
        return
    end
    S.inTick = true
    local ok, err = pcall(tickBody)
    S.inTick = false
    if not ok then
        noteError("tick", err)
    end
    schedule()
end

onTimer = function()
    S.timerPending = false
    D.Tick()
end

-- Lifecycle --------------------------------------------------------------------

local function readText(path)
    if S.load == nil then
        return nil
    end
    local ok, text = pcall(S.load, path)
    if ok and type(text) == "string" then
        return text
    end
    return nil
end

local function tryDirectory(directory, stateText)
    local ok, result = pcall(S.save, stateText, directory .. "absru-state.txt")
    if not ok or result == false then
        return false
    end
    if S.load == nil then
        return true
    end
    local back = readText(directory .. "absru-state.txt")
    return back ~= nil and back:find(S.sid, 1, true) ~= nil
end

local function flagSummary()
    local names = {}
    for _, key in ipairs({ "Hooks", "Untranslated", "Overflow", "Fonts", "Images", "PanelWalk" }) do
        if cfg[key] then
            names[#names + 1] = key
        end
    end
    return table.concat(names, ",") .. string.format(" budget_ms=%.2f flush_s=%.0f",
        cfg.FrameBudgetMs, cfg.FlushSeconds)
end

local function afterMain()
    S.afterMain = true
    S.flushSoon = false
    D.Flush(true)
    schedule()
end

function D.Start(loader, runtimeFixes, version)
    if S.started then
        return not S.disabled
    end
    S.started = true
    S.loader = loader
    S.fixes = runtimeFixes
    S.version = tostring(version)

    local flags = type(loader) == "table" and type(loader.DevFlags) == "table" and loader.DevFlags or {}
    for key, value in pairs(DEFAULTS) do
        cfg[key] = value
    end
    for key, value in pairs(flags) do
        if DEFAULTS[key] ~= nil and type(value) == type(DEFAULTS[key]) then
            cfg[key] = value
        end
    end
    for key, range in pairs(LIMITS) do
        cfg[key] = math.max(range[1], math.min(range[2], cfg[key]))
    end
    cfg.Slots = math.floor(cfg.Slots)

    S.sid = stamp("%Y%m%d-%H%M%S") or ("t" .. tostring(math.floor(nowMs())))
    S.startedStamp = stamp("%Y-%m-%d %H:%M:%S")

    local okLibrary, library = pcall(import, "LuaFunctionLibrary")
    if not okLibrary or library == nil or type(library.SaveStringContentToFile) ~= "function" then
        return disable("LuaFunctionLibrary.SaveStringContentToFile unavailable")
    end
    S.save = library.SaveStringContentToFile
    if type(library.LoadFile) == "function" then
        S.load = library.LoadFile
    end
    local root = type(loader) == "table" and loader.Root or nil
    if type(root) ~= "string" or root == "" then
        return disable("Loader.Root unavailable")
    end

    local logsDir = root .. "logs/"
    local previous = readText(logsDir .. "absru-state.txt") or readText(root .. "absru-state.txt") or ""
    local lastSlot = tonumber(previous:match("slot=(%d+)")) or 0
    S.slot = (lastSlot % cfg.Slots) + 1
    local stateText = "slot=" .. tostring(S.slot) .. "\nsid=" .. S.sid .. "\n"
    if tryDirectory(logsDir, stateText) then
        S.dir = logsDir
    elseif tryDirectory(root, stateText) then
        S.dir = root
    else
        return disable("cannot write to " .. logsDir .. " or " .. root)
    end
    S.prefix = "absru-s" .. tostring(S.slot) .. "-"
    S.lastTick = nowMs()
    S.lastFlush = nowMs()

    if loader.Diagnostics == nil then
        loader.Diagnostics = D
    end
    if type(loader.On) == "function" then
        loader.On("after_main", function()
            local ok, err = pcall(afterMain)
            if not ok then
                noteError("tick", err)
            end
        end, 2100000, "absru.diagnostics.start")
        -- The marker needs its own early slot: Log.Info before the game's logger
        -- is up never reaches C7.log (TASK-007), and the after_main hook
        -- cpdd.runtime-fix.performance-mode (2000000) lowers LuaLog to Warning
        -- until the game raises it again at login (TASK-008, session
        -- 2026-09-25_1046: no Lua lines between 10:38:19 and 10:38:54).
        -- 1501 = right after Init.lua's "active hooks_installed=" line (1500).
        loader.On("after_main", function()
            if S.sessionLine ~= nil then
                warn(S.sessionLine)
            end
        end, 1501, "absru.diagnostics.session-line")
    end
    -- Also logged at load, for early crashes.
    S.sessionLine = "[AbsruDiag] session=" .. S.sid .. " slot=" .. tostring(S.slot) .. " dir=" .. S.dir
        .. " version=" .. S.version .. " flags=" .. flagSummary()
    warn(S.sessionLine)
    return true
end

-- helpers = { getWidgetList = fn, runtimeMetrics = table } from Init.lua.
function D.Attach(helpers)
    if type(helpers) ~= "table" then
        return
    end
    S.getWidgetList = helpers.getWidgetList
    S.getNamedWidget = helpers.getNamedWidget
    S.metrics = helpers.runtimeMetrics
    if not S.disabled and type(S.metrics) == "table" and (cfg.Untranslated or cfg.Hooks) then
        S.metrics.CaptureDataAssignment = D.CaptureDataAssignment
        S.metrics.CaptureDataAssignmentsEnabled = true
    end
end

D.State = S
D.Config = cfg

return D

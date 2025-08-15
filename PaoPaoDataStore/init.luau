--!strict
--!optimize 2
--!native

-- ============================================================================
--  PPDBM  –  PaoPao's DataStore Module
--  A high-performance, caching, migration-friendly DataStore wrapper
-- ============================================================================

-- ==== Services ====
local DataStoreService   = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService        = game:GetService("HttpService")

-- ==== Signal Implementation ====
export type SignalConnection = { Disconnect: (self: SignalConnection) -> () }
export type Signal<T...>     = {
    Connect: (self: Signal<T...>, (T...) -> ()) -> SignalConnection,
    Fire:    (self: Signal<T...>, T...) -> (),
}

local Signal = {} :: any
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
    return setmetatable({ _listeners = {} }, Signal) :: any
end

function Signal:Fire(...)
    for _, fn in ipairs(self._listeners) do
        task.spawn(fn, ...)
    end
end

function Signal:Connect(fn)
    table.insert(self._listeners, fn)
    return {
        Disconnect = function()
            for i, v in ipairs(self._listeners) do
                if v == fn then
                    table.remove(self._listeners, i)
                    break
                end
            end
        end
    }
end

-- ==== Types ====
type HookFunction   = (key: string, data: any) -> ()
type HookTable      = {
    beforeInit: HookFunction?,
    afterInit:  HookFunction?,
    beforeSave: HookFunction?,
    afterSave:  HookFunction?
}
type MigrationFunction = (data: {[string]: any}) -> {[string]: any}

-- ==== Constants ====
local DEFAULT_RETRIES     = 3
local DEFAULT_EXPIRE      = 60 * 60 * 24 * 3   -- 3 days
local WRITE_DEBOUNCE_TIME = 1                  -- seconds
local POLL_INTERVALS      = {0.1, 0.5, 1, 2, 5}

_G._PPDBM = _G._PPDBM or {
    PRIVATE_DATA = {
        CORE = {
            CACHE_DB = {},
            CORE_CACHE = {
                WRITE_QUEUES = {},
                LOCKS = {},
                SUBSCRIBERS = { dbList = {}, subscribed = false },
                INSTANCE_REGISTRY = {},
				JSON_CACHE = {},
				PPDBM_HEALTH_MONITOR = false,
            }
        }
    }
}

-- ==== Global Shared State ====
local GLOBAL_CACHE     = _G._PPDBM.PRIVATE_DATA.CORE.CACHE_DB                        or {}
local WRITE_QUEUES     = _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.WRITE_QUEUES         or {}
local LOCKS            = _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.LOCKS                or {}
local SUBSCRIBERS      = _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.SUBSCRIBERS          or { dbList = {}, subscribed = false }
local INSTANCE_REGISTRY= _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.INSTANCE_REGISTRY    or {}
local JSON_CACHE       = _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.JSON_CACHE           or {}

_G._PPDBM.PRIVATE_DATA.CORE.CACHE_DB                     = GLOBAL_CACHE
_G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.WRITE_QUEUES      = WRITE_QUEUES
_G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.LOCKS             = LOCKS
_G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.SUBSCRIBERS       = SUBSCRIBERS
_G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.INSTANCE_REGISTRY = INSTANCE_REGISTRY
_G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.JSON_CACHE        = JSON_CACHE

local memoryQueue = MemoryStoreService:GetQueue("PPDBM_GlobalInvalidation")

-- ==== Logger ====
local function safeJSON(data: any): string
    local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return "{}" end
    if JSON_CACHE[json] then return JSON_CACHE[json] end
    JSON_CACHE[json] = json
    return json
end

local function sendDiscord(webhook: string, level: string, message: string, color: number?)
    if webhook == "" then return end
    local payload = safeJSON({
        embeds = {{
            title = "🧠 PPDBM Log",
            description = string.format("`[%s]` %s", level, message),
            color = color or 0x3498db,
            timestamp = DateTime.now():ToIsoDate(),
        }}
    })
    pcall(function()
        HttpService:PostAsync(webhook, payload, Enum.HttpContentType.ApplicationJson)
    end)
end

local function log(self: PPDBM, level: string, message: string, color: number?, sendWebhook: boolean?)
    local prefix = string.format("[PPDBM][%s][%s]", level, os.date("%Y-%m-%d %H:%M:%S"))
    print(prefix, message)
    if sendWebhook then sendDiscord(self.Webhook, level, message, color) end
end

-- ==== JSON Helpers ====
local serialize   = safeJSON
local deserialize = function(str: string?): any?
    if not str then return nil end
    local ok, t = pcall(HttpService.JSONDecode, HttpService, str)
    return ok and t or nil
end

-- ==== Migration System ====
local function migrateData(data: {[string]: any}, migrations: {MigrationFunction})
    if type(data) ~= "table" or #migrations == 0 then return data end
    if type(data._version) ~= "number" then data._version = 0 end
    local version = data._version
    while version < #migrations do
        version += 1
        local fn = migrations[version]
        local ok, new = pcall(fn, data)
        if ok and new then
            data = new
            data._version = version
        else
            break
        end
    end
    return data
end

-- ==== Lock System ====
local function acquireLock(name: string, key: string): boolean
    local k = name .. ":" .. key
    if LOCKS[k] then return false end
    LOCKS[k] = true
    return true
end
local function releaseLock(name: string, key: string)
    LOCKS[name .. ":" .. key] = nil
end

-- ==== Invalidation / Subscriber ====
local function publishInvalidation(name: string, key: string)
    pcall(function()
        memoryQueue:PushBack(serialize({name = name, key = key}), 60)
    end)
end

if not SUBSCRIBERS.subscribed then
    SUBSCRIBERS.subscribed = true
    task.spawn(function()
        local idx = 1
        while true do
            local ok, msgs = pcall(memoryQueue.ReadAsync, memoryQueue, 10, false, 5)
            if ok and msgs and #msgs > 0 then
                idx = 1
                for _, m in ipairs(msgs) do
                    local d = deserialize(m.Data)
                    if d and d.name and d.key then
                        local c = GLOBAL_CACHE[d.name]
                        if c then c[d.key] = nil end
                        for _, db in ipairs(SUBSCRIBERS.dbList) do
                            if db._name == d.name then db.OnInvalidate:Fire(d.key) end
                        end
                    end
                end
            else
                idx = math.min(idx + 1, #POLL_INTERVALS)
            end
            task.wait(POLL_INTERVALS[idx])
        end
    end)
end

-- ==== Health Monitor ====
if not _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.PPDBM_HEALTH_MONITOR then
    _G._PPDBM.PRIVATE_DATA.CORE.CORE_CACHE.PPDBM_HEALTH_MONITOR = true
    task.spawn(function()
        while true do
            for name, inst in pairs(INSTANCE_REGISTRY) do
                local cached = 0
                if GLOBAL_CACHE[name] then for _ in pairs(GLOBAL_CACHE[name]) do cached += 1 end end
                log(inst, "DEBUG",
                    ("Health → Cache Keys: %d | Write Queue: %d"):format(cached, inst._writeCount or 0),
                    0x3498db, inst.enabledSTD)
            end
            task.wait(30)
        end
    end)
end

-- ==== Cache / Queue Helpers ====
local function getCache(name: string)
    GLOBAL_CACHE[name] = GLOBAL_CACHE[name] or {}
    return GLOBAL_CACHE[name]
end
local function getWriteQueue(name: string)
    WRITE_QUEUES[name] = WRITE_QUEUES[name] or {}
    return WRITE_QUEUES[name]
end

-- ============================================================================
--  PPDBM Class
-- ============================================================================
local PPDBM = {}
PPDBM.__index = PPDBM

-- ------------------------------------------------------------------
--  Constructor
-- ------------------------------------------------------------------
function PPDBM.new(name: string, opts: {
    hooks: HookTable?,
    expire: number?,
    retries: number?,
    migrations: {MigrationFunction}?,
    debug: boolean?
}?)
    opts = opts or {}
    if INSTANCE_REGISTRY[name] then
        log(INSTANCE_REGISTRY[name], "INFO", ("Re-using instance for '%s'"):format(name))
        return INSTANCE_REGISTRY[name]
    end

    local self = setmetatable({}, PPDBM) :: any
    self._name        = name
    self._store       = DataStoreService:GetDataStore(name)
    self._hooks       = opts.hooks or {}
    self._expire      = opts.expire or DEFAULT_EXPIRE
    self._retries     = opts.retries or DEFAULT_RETRIES
    self._migrations  = opts.migrations or {}
    self._writeCount  = 0
    self.enabledSTD   = false
    self.Webhook      = ""
    self._debug       = opts.debug or false

    self._cache      = getCache(name)
    self._writeQueue = getWriteQueue(name)

    self.OnInit      = Signal.new()
    self.OnSave      = Signal.new()
    self.OnDelete    = Signal.new()
    self.OnInvalidate= Signal.new()

    INSTANCE_REGISTRY[name] = self
    table.insert(SUBSCRIBERS.dbList, self)
    log(self, "INFO", ("Created PPDBM instance for '%s'"):format(name))
    return self
end

-- ------------------------------------------------------------------
--  Internal helpers
-- ------------------------------------------------------------------
function PPDBM:_getQueueKey(key: string): string
    return self._name .. ":" .. key
end

local function scheduleWriteFlush(self: PPDBM, key: string)
    local qk = self:_getQueueKey(key)
    local entry = WRITE_QUEUES[qk]
    if not entry then
        self._writeCount += 1
        entry = {}
        WRITE_QUEUES[qk] = entry
    end
    entry.data = self._cache[key]

    task.delay(WRITE_DEBOUNCE_TIME, function()
        if not entry.data or entry.data ~= self._cache[key] then return end
        if not acquireLock(self._name, key) then return end

        if self._hooks.beforeSave then
            self._hooks.beforeSave(key, entry.data)
        end

        local ok, err
        for i = 1, self._retries do
            ok, err = pcall(function()
                self._store:SetAsync(key, entry.data)
            end)
            if ok then break end
            task.wait(0.5 * i)
        end
        releaseLock(self._name, key)

        if ok then
            publishInvalidation(self._name, key)
            if self._hooks.afterSave then self._hooks.afterSave(key, entry.data) end
            self.OnSave:Fire(key, entry.data)
        else
            log(self, "ERROR", ("Save failed: %s | %s"):format(key, tostring(err)), 0xe74c3c)
        end

        WRITE_QUEUES[qk] = nil
        self._writeCount -= 1
    end)
end

-- ------------------------------------------------------------------
--  Core API
-- ------------------------------------------------------------------
function PPDBM:init(key: string, defaultData: {[string]: any}, cb: ((boolean, any) -> ())?)
    if self._cache[key] then
        if cb then cb(true, self._cache[key]) end
        return
    end

    if self._hooks.beforeInit then self._hooks.beforeInit(key, nil) end

    local ok, data = pcall(function() return self._store:GetAsync(key) end)
    if not ok then if cb then cb(false, nil) end return end

    if not data then
        data = defaultData
        local setOk = pcall(function() self._store:SetAsync(key, data) end)
        if not setOk then
            log(self, "ERROR", "Initial save failed for key: "..key)
        end
    end

    data = migrateData(data, self._migrations) or data
    self._cache[key] = data

    if self._hooks.afterInit then self._hooks.afterInit(key, data) end
    self.OnInit:Fire(key, data)
    if cb then cb(true, data) end
end

function PPDBM:getOrInit(key: string, defaultData: {[string]: any})
    local cached = self._cache[key]
    if cached then return cached end

    local ok, data = pcall(function() return self._store:GetAsync(key) end)
    if ok and data then
        data = migrateData(data, self._migrations) or data
        self._cache[key] = data
        return data
    end

    self._cache[key] = defaultData
    local setOk = pcall(function() self._store:SetAsync(key, defaultData) end)
    if not setOk then log(self, "ERROR", "Set default failed for key: "..key) end
    publishInvalidation(self._name, key)
    return defaultData
end

function PPDBM:update(key: string, updateFn: (any) -> any, cb: ((boolean, any) -> ())?)
    local current = self._cache[key] or {}
    current = migrateData(current, self._migrations) or current
    local new = updateFn(current)
    if new == nil then if cb then cb(false, nil) end return end

    self._cache[key] = new
    scheduleWriteFlush(self, key)
    if cb then cb(true, new) end
end

function PPDBM:increment(key: string, field: string, amount: number)
    local v = (self._cache[key] and self._cache[key][field] or 0) + amount
    self:update(key, function(d)
        d[field] = (d[field] or 0) + amount
        return d
    end)
    return v
end

function PPDBM:batchUpdate(keys: {string}, updateFn: (any) -> any)
    local batch = {}
    for _, k in ipairs(keys) do
        local cur = self._cache[k] or {}
        cur = migrateData(cur, self._migrations) or cur
        local new = updateFn(cur)
        if new then
            self._cache[k] = new
            batch[k] = new
        end
    end
    for k in pairs(batch) do scheduleWriteFlush(self, k) end
end

function PPDBM:hasKey(key: string): boolean
    local ok, data = pcall(function() return self._store:GetAsync(key) end)
    return ok and data ~= nil
end

function PPDBM:delete(key: string, cb: ((boolean) -> ())?)
    local ok = pcall(function() self._store:RemoveAsync(key) end)
    if ok then
        self._cache[key] = nil
        publishInvalidation(self._name, key)
        self.OnDelete:Fire(key)
    end
    if cb then cb(ok) end
end

function PPDBM:leave(key: string)
    self._cache[key] = nil
end

function PPDBM:clearCache()
    self._cache = {}
    GLOBAL_CACHE[self._name] = {}
end

function PPDBM:flushWrites()
    for qk, entry in pairs(WRITE_QUEUES) do
        if string.sub(qk, 1, #self._name + 1) == self._name .. ":" and entry.data then
            local key = string.sub(qk, #self._name + 2)
            local ok, err
            for i = 1, self._retries do
                ok, err = pcall(function()
                    self._store:SetAsync(key, entry.data)
                end)
                if ok then break end
                task.wait(0.5 * i)
            end
            if not ok then
                log(self, "ERROR", ("Flush write failed: %s | %s"):format(key, tostring(err)))
            end
            self._cache[key] = entry.data
            self._writeCount -= 1
            WRITE_QUEUES[qk] = nil
        end
    end
end

function PPDBM:getCached(key: string): any
    return self._cache and self._cache[key]
end

function PPDBM:setCached(key: string, data: any)
    if not self._cache then
        self._cache = {}
        GLOBAL_CACHE[self._name] = self._cache
    end
    self._cache[key] = data
end

function PPDBM:setWebhook(url: string)
    self.Webhook = url
end

function PPDBM:sendToDiscord(enabled: boolean)
    self.enabledSTD = enabled
end

-- ------------------------------------------------------------------
--  EXTENDED API
-- ------------------------------------------------------------------
function PPDBM:keys(): {string}
    local out = {}
    for k in pairs(self._cache) do out[k] = true end

    if not self._allKeysCache or os.time() - self._allKeysCache.t > 60 then
        local ok, pages = pcall(function()
            return self._store.ListKeysAsync and self._store:ListKeysAsync() or nil
        end)
        if ok and pages then
            while true do
                for _, item in ipairs(pages:GetCurrentPage()) do
                    out[item.KeyName] = true
                end
                if pages.IsFinished then break end
                pages:AdvanceToNextPageAsync()
            end
            self._allKeysCache = { t = os.time() }
        end
    end

    local list = {}
    for k in pairs(out) do table.insert(list, k) end
    return list
end

function PPDBM:size(): number
    local n = 0
    for _ in pairs(self._cache) do n += 1 end
    return n
end

function PPDBM:exists(key: string): boolean
    local ok, data = pcall(function() return self._store:GetAsync(key) end)
    return ok and data ~= nil
end

function PPDBM:rawSet(key: string, value: any, cb: ((boolean, string?) -> ())?)
    local ok, err = pcall(function() self._store:SetAsync(key, value) end)
    if ok then
        self._cache[key] = value
        publishInvalidation(self._name, key)
        if cb then cb(true) end
    else
        log(self, "ERROR", ("RawSet failed: %s | %s"):format(key, tostring(err)))
        if cb then cb(false, tostring(err)) end
    end
end

function PPDBM:rawGet(key: string, cb: ((boolean, any?) -> ())?)
    local ok, data = pcall(function() return self._store:GetAsync(key) end)
    if cb then cb(ok, data) end
end

function PPDBM:export(): {[string]: any}
    return deserialize(serialize(self._cache)) or {}
end

function PPDBM:import(tbl: {[string]: any}, overwrite: boolean?)
    for k, v in pairs(tbl) do
        if overwrite or self._cache[k] == nil then
            self._cache[k] = v
            scheduleWriteFlush(self, k)
        end
    end
end

function PPDBM:stat()
    local cached, queued = 0, 0
    for _ in pairs(self._cache) do cached += 1 end
    for qk in pairs(WRITE_QUEUES) do
        if string.find(qk, self._name .. ":", 1, true) then queued += 1 end
    end
    return {
        name         = self._name,
        cachedKeys   = cached,
        queuedWrites = queued,
        writeCount   = self._writeCount
    }
end

function PPDBM:clearKey(key: string)
    self._cache[key] = nil
    self:delete(key)
end

function PPDBM:atomicIncrement(key: string, field: string, amount: number): number?
    local newValue
    local ok, err = pcall(function()
        newValue = self._store:UpdateAsync(key, function(old)
            old = old or {}
            old[field] = (old[field] or 0) + amount
            return old
        end)
    end)
    if ok and newValue then
        publishInvalidation(self._name, key)
        self._cache[key] = newValue
        return newValue[field]
    else
        log(self, "ERROR", ("Atomic increment failed: %s | %s"):format(key, tostring(err)))
        return nil
    end
end

return PPDBM
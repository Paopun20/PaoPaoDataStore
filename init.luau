--!strict
--!optimize 2
--!native

-- ==== Services ====
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

-- ==== Signal Implementation ====
export type SignalConnection = {
	Disconnect: () -> ()
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, (T...) -> ()) -> SignalConnection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({
		_handlers = {}
	}, Signal)
end

function Signal:Connect(fn: (T...) -> ()): SignalConnection
	table.insert(self._handlers, fn)
	return {
		Disconnect = function()
			for i, handler in ipairs(self._handlers) do
				if handler == fn then
					table.remove(self._handlers, i)
					break
				end
			end
		end
	}
end

function Signal:Fire(T...)
	for _, handler in pairs(self._handlers) do
		task.spawn(handler, T...)
	end
end

-- ==== Types ====
type HookFunction = (key: string, data: any) -> ()
type HookTable = {
    beforeInit: HookFunction?,
    afterInit: HookFunction?,
    beforeSave: HookFunction?,
    afterSave: HookFunction?
}
type MigrationFunction = (data: {[string]: any}) -> {[string]: any}

-- ==== Constants ====
local DEFAULT_RETRIES = 3
local DEFAULT_EXPIRE = 60 * 60 * 24 * 3
local WRITE_DEBOUNCE_TIME = 1
local POLL_INTERVALS = {0.1, 0.5, 1, 2, 5}

-- ==== Global Shared State ====
local GLOBAL_CACHE = _G.PPDBM_CACHE or {}
local WRITE_QUEUES = _G.PPDBM_WRITE_QUEUES or {}
local LOCKS = _G.PPDBM_LOCKS or {}
local SUBSCRIBERS = _G.PPDBM_SUBSCRIBERS or { dbList = {}, subscribed = false }
local INSTANCE_REGISTRY = _G.PPDBM_INSTANCES or {}
local JSON_CACHE = _G.PPDBM_JSON_CACHE or {}

_G.PPDBM_CACHE = GLOBAL_CACHE
_G.PPDBM_WRITE_QUEUES = WRITE_QUEUES
_G.PPDBM_LOCKS = LOCKS
_G.PPDBM_SUBSCRIBERS = SUBSCRIBERS
_G.PPDBM_INSTANCES = INSTANCE_REGISTRY
_G.PPDBM_JSON_CACHE = JSON_CACHE

local memoryQueue = MemoryStoreService:GetQueue("PPDBM_Channel")

-- ==== Logger ====
local function safeJSON(data)
    local dataStr = tostring(data)
    if JSON_CACHE[dataStr] then
        return JSON_CACHE[dataStr]
    end
    
    local ok, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    
    if ok then
        JSON_CACHE[dataStr] = result
        return result
    else
        return "{}"
    end
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

local function log(self, level: string, message: string, color: number?, sendWebhook: boolean?)
    local timeStr = os.date("%Y-%m-%d %H:%M:%S")
    local prefix = string.format("[PPDBM][%s][%s]", level, timeStr)
    print(prefix, message)
    if sendWebhook then
        sendDiscord(self.Webhook, level, message, color)
    end
end

-- ==== JSON Helpers ====
local function serialize(data)
    local dataStr = tostring(data)
    if JSON_CACHE[dataStr] then
        return JSON_CACHE[dataStr]
    end
    local result = HttpService:JSONEncode(data)
    JSON_CACHE[dataStr] = result
    return result
end

local function deserialize(str)
    if not str then return nil end
    local success, result = pcall(function()
        return HttpService:JSONDecode(str)
    end)
    return success and result or nil
end

-- ==== Migration System ====
local function migrateData(data, migrations)
    if not data or type(data) ~= "table" or #migrations == 0 then
        return data
    end

    local version = data._version or 0
    local latestVersion = #migrations

    while version < latestVersion do
        version += 1
        local migrationFn = migrations[version]
        if migrationFn then
            local ok, newData = pcall(migrationFn, data)
            if ok and newData then
                data = newData
                data._version = version
            else
                break -- migration error or invalid data
            end
        else
            break
        end
    end
    return data
end

-- ==== Lock system ====
local function acquireLock(name, key)
    local lockKey = name .. ":" .. key
    if LOCKS[lockKey] then return false end
    LOCKS[lockKey] = true
    return true
end

local function releaseLock(name, key)
    LOCKS[name .. ":" .. key] = nil
end

-- ==== Publish invalidation ====
local function publishInvalidation(name, key)
    local message = { name = name, key = key }
    pcall(function()
        memoryQueue:PushBack(serialize(message), 60)
    end)
end

-- ==== Subscriber loop with progressive backoff ====
if not SUBSCRIBERS.subscribed then
    SUBSCRIBERS.subscribed = true
    task.spawn(function()
        local currentInterval = 1
        while true do
            local success, messages = pcall(function()
                return memoryQueue:ReadAsync(10, false, 5)
            end)
            if success and messages and #messages > 0 then
                currentInterval = 1
                for _, msg in ipairs(messages) do
                    local decoded = deserialize(msg.Data)
                    if decoded and decoded.name and decoded.key then
                        local cache = GLOBAL_CACHE[decoded.name]
                        if cache then
                            cache[decoded.key] = nil
                            for _, db in ipairs(SUBSCRIBERS.dbList) do
                                if db._name == decoded.name then
                                    db.OnInvalidate:Fire(decoded.key)
                                end
                            end
                        end
                    end
                end
            else
                currentInterval = math.min(currentInterval + 1, #POLL_INTERVALS)
            end
            task.wait(POLL_INTERVALS[currentInterval])
        end
    end)
end

-- ==== Health Monitor ====
if not _G.PPDBM_HEALTH_MONITOR then
    _G.PPDBM_HEALTH_MONITOR = true
    task.spawn(function()
        while true do
            for name, instance in pairs(INSTANCE_REGISTRY) do
                local cacheCount = 0
                if GLOBAL_CACHE[name] then
                    for _ in pairs(GLOBAL_CACHE[name]) do cacheCount += 1 end
                end
                local writeCount = instance._writeCount or 0
                log(instance, "DEBUG", ("Health → Cache Keys: %d | Write Queue: %d"):format(cacheCount, writeCount), 0x3498db, instance.enabledSTD)
            end
            task.wait(30)
        end
    end)
end

-- ==== Cache helpers ====
local function getCache(name)
    GLOBAL_CACHE[name] = GLOBAL_CACHE[name] or {}
    return GLOBAL_CACHE[name]
end

local function getWriteQueue(name)
    WRITE_QUEUES[name] = WRITE_QUEUES[name] or {}
    return WRITE_QUEUES[name]
end

-- ==== PPDBM class ====
local PPDBM = {}
PPDBM.__index = PPDBM

function PPDBM.new(name: string, hooks: HookTable?, expire: number?, retries: number?, migrations: {MigrationFunction}?)
    if INSTANCE_REGISTRY[name] then
        log(INSTANCE_REGISTRY[name], "INFO", ("Reusing existing PPDBM instance for '%s'"):format(name))
        return INSTANCE_REGISTRY[name]
    end

    local self = setmetatable({}, PPDBM)
    self._name = name
    self._store = DataStoreService:GetDataStore(name)
    self._hooks = hooks or {}
    self._expire = expire or DEFAULT_EXPIRE
    self._retries = retries or DEFAULT_RETRIES
    self._migrations = migrations or {}
    self._writeCount = 0
    self.enabledSTD = false
    self.Webhook = ""

    self._cache = getCache(name)
    self._writeQueue = getWriteQueue(name)

    self.OnInit = Signal.new()
    self.OnSave = Signal.new()
    self.OnDelete = Signal.new()
    self.OnInvalidate = Signal.new()

    INSTANCE_REGISTRY[name] = self
    table.insert(SUBSCRIBERS.dbList, self)

    log(self, "INFO", ("Created new PPDBM instance for '%s'"):format(name))

    return self
end

function PPDBM:_getQueueKey(key)
    return self._name .. ":" .. key
end

local function scheduleWriteFlush(self, key)
    local queueKey = self:_getQueueKey(key)
    local queueEntry = WRITE_QUEUES[queueKey]
    
    if not queueEntry then
        self._writeCount += 1
        queueEntry = {}
        WRITE_QUEUES[queueKey] = queueEntry
    end
    
    queueEntry.data = self._cache[key]

    task.delay(WRITE_DEBOUNCE_TIME, function()
        if not queueEntry.data then return end
        if not acquireLock(self._name, key) then return end

        local ok, err = pcall(function()
            self._store:SetAsync(key, queueEntry.data)
        end)
        releaseLock(self._name, key)

        if ok then
            publishInvalidation(self._name, key)
            if self._hooks.afterSave then
                self._hooks.afterSave(key, queueEntry.data)
            end
            self.OnSave:Fire(key, queueEntry.data)
        else
            log(self, "ERROR", ("Failed save: %s | %s"):format(key, tostring(err)), 0xe74c3c)
        end

        WRITE_QUEUES[queueKey] = nil
        self._writeCount -= 1
    end)
end

-- ==== API ====

function PPDBM:init(key: string, defaultData: {[string]: any}, cb: ((boolean, any) -> ())?)
    if self._cache[key] then
        if cb then cb(true, self._cache[key]) end
        return
    end

    if self._hooks.beforeInit then
        self._hooks.beforeInit(key, nil)
    end

    local ok, data = pcall(function()
        return self._store:GetAsync(key)
    end)

    if not ok then
        if cb then cb(false, nil) end
        return
    end

    if not data then
        data = defaultData
        local setOk = pcall(function()
            self._store:SetAsync(key, data)
        end)
        if not setOk then
            log(self, "ERROR", "Failed initial save for key: "..key)
        end
    end

    data = migrateData(data, self._migrations) or data
    self._cache[key] = data

    if self._hooks.afterInit then
        self._hooks.afterInit(key, data)
    end

    self.OnInit:Fire(key, data)
    if cb then cb(true, data) end
end

function PPDBM:getOrInit(key: string, defaultData: {[string]: any})
    local cached = self._cache[key]
    if cached then return cached end

    local ok, data = pcall(function()
        return self._store:GetAsync(key)
    end)

    if ok and data then
        data = migrateData(data, self._migrations) or data
        self._cache[key] = data
        return data
    end

    self._cache[key] = defaultData
    local setOk = pcall(function()
        self._store:SetAsync(key, defaultData)
    end)
    if not setOk then
        log(self, "ERROR", "Failed set default for key: "..key)
    end
    publishInvalidation(self._name, key)
    return defaultData
end

function PPDBM:update(key: string, updateFn: (any) -> any, cb: ((boolean, any) -> ())?)
    local current = self._cache[key] or {}
    current = migrateData(current, self._migrations) or current
    local newData = updateFn(current)

    if not newData then
        if cb then cb(false, nil) end
        return
    end

    self._cache[key] = newData
    scheduleWriteFlush(self, key)
    if cb then cb(true, newData) end
end

function PPDBM:increment(key: string, field: string, amount: number)
    local current = self._cache[key]
    if not current then return nil end

    current[field] = (current[field] or 0) + amount
    self:update(key, function(data)
        data[field] = (data[field] or 0) + amount
        return data
    end)
    return current[field]
end

function PPDBM:batchUpdate(keys: {string}, updateFn: (any) -> any)
    local batch = {}

    for _, key in ipairs(keys) do
        local current = self._cache[key] or {}
        current = migrateData(current, self._migrations) or current
        local newData = updateFn(current)

        if newData then
            self._cache[key] = newData
            batch[key] = newData
        end
    end

    for key, _ in pairs(batch) do
        scheduleWriteFlush(self, key)
    end
end

function PPDBM:hasKey(key: string)
    local ok, data = pcall(function()
        return self._store:GetAsync(key)
    end)
    return ok and data ~= nil
end

function PPDBM:delete(key: string, cb: ((boolean) -> ())?)
    local ok = pcall(function()
        self._store:RemoveAsync(key)
    end)

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
    for queueKey, entry in pairs(WRITE_QUEUES) do
        if string.find(queueKey, self._name..":") and entry.data then
            local key = string.split(queueKey, ":")[2]
            self._store:SetAsync(key, entry.data)
            self._cache[key] = entry.data
            self._writeCount -= 1
            WRITE_QUEUES[queueKey] = nil
        end
    end
end

function PPDBM:getCached(key: string)
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

return PPDBM

--!strict
--!optimize 2
--!native

-- ============================================================================
--  PPDB  –  PaoPao's DataStore Module
--  A high-performance, caching, migration-friendly DataStore wrapper
-- ============================================================================

-- ==== Services ====
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

-- ==== Signal Implementation ====
export type SignalConnection = { Disconnect: (self: SignalConnection) -> () }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, (T...) -> ()) -> SignalConnection,
	Fire: (self: Signal<T...>, T...) -> (),
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
		end,
	}
end

-- ==== Types ====
type HookFunction = (key: string, data: any) -> ()
type HookTable = {
	beforeInit: HookFunction?,
	afterInit: HookFunction?,
	beforeSave: HookFunction?,
	afterSave: HookFunction?,
}
type MigrationFunction = (data: { [string]: any }) -> { [string]: any }

-- ==== Constants ====
local DEFAULT_RETRIES = 3
local DEFAULT_EXPIRE = 60 * 60 * 24 * 3 -- 3 days
local WRITE_DEBOUNCE_TIME = 1 -- seconds
local POLL_INTERVALS = { 0.1, 0.5, 1, 2, 5 }
local JSON_CACHE_SIZE = 1000
local LOG_LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

_G._PPDB = _G._PPDB
	or {
		PRIVATE_DATA = {
			CORE = {
				CACHE_DB = {},
				CORE_CACHE = {
					WRITE_QUEUES = {},
					LOCKS = {},
					SUBSCRIBERS = { dbList = {}, subscribed = false },
					INSTANCE_REGISTRY = {},
					JSON_CACHE = {},
					JSON_CACHE_ORDER = {},
					PPDB_HEALTH_MONITOR = false,
				},
			},
		},
	}

-- ==== Global Shared State ====
local GLOBAL_CACHE = _G._PPDB.PRIVATE_DATA.CORE.CACHE_DB or {}
local WRITE_QUEUES = _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.WRITE_QUEUES or {}
local LOCKS = _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.LOCKS or {}
local SUBSCRIBERS = _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.SUBSCRIBERS or { dbList = {}, subscribed = false }
local INSTANCE_REGISTRY = _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.INSTANCE_REGISTRY or {}
local JSON_CACHE = _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.JSON_CACHE or {}
local JSON_CACHE_ORDER = _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.JSON_CACHE_ORDER or {}

_G._PPDB.PRIVATE_DATA.CORE.CACHE_DB = GLOBAL_CACHE
_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.WRITE_QUEUES = WRITE_QUEUES
_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.LOCKS = LOCKS
_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.SUBSCRIBERS = SUBSCRIBERS
_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.INSTANCE_REGISTRY = INSTANCE_REGISTRY
_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.JSON_CACHE = JSON_CACHE
_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.JSON_CACHE_ORDER = JSON_CACHE_ORDER

local memoryQueue = MemoryStoreService:GetQueue("PPDB_GlobalInvalidation")

-- ==== Logger ====
local function safeJSON(data: any): string
	local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then
		return "{}"
	end
	if JSON_CACHE[json] then
		return JSON_CACHE[json]
	end
	if #JSON_CACHE_ORDER >= JSON_CACHE_SIZE then
		local oldest = table.remove(JSON_CACHE_ORDER, 1)
		JSON_CACHE[oldest] = nil
	end
	JSON_CACHE[json] = json
	table.insert(JSON_CACHE_ORDER, json)
	return json
end

local function sendDiscord(webhook: string, level: string, message: string, color: number?)
	if webhook == "" then
		return
	end
	local payload = safeJSON({
		embeds = {
			{
				title = "🧠 PPDB Log",
				description = string.format("`[%s]` %s", level, message),
				color = color or 0x3498db,
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	})
	pcall(function()
		HttpService:PostAsync(webhook, payload, Enum.HttpContentType.ApplicationJson)
	end)
end

local function log(self: PPDB, level: string, message: string, color: number?, sendWebhook: boolean?)
	if (LOG_LEVELS[level] or 1) < self._logLevel then
		return
	end
	local prefix = string.format("[PPDB][%s][%s]", level, os.date("%Y-%m-%d %H:%M:%S"))
	print(prefix, message)
	if sendWebhook and self.enabledSTD then
		sendDiscord(self.Webhook, level, message, color)
	end
end

local function handleError(self: PPDB, key: string, err: any, operation: string)
	local errorType = "Unknown"
	local errStr = tostring(err)
	if string.find(errStr, "403") then
		errorType = "RateLimit"
	elseif string.find(errStr, "Network") then
		errorType = "NetworkFailure"
	end
	log(self, "ERROR", string.format("%s failed for %s: %s (%s)", operation, key, errStr, errorType), 0xe74c3c)
end

-- ==== JSON Helpers ====
local serialize = safeJSON
local deserialize = function(str: string?): any?
	if not str then
		return nil
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, str)
	return ok and t or nil
end

-- ==== Migration System ====
local function migrateData(data: { [string]: any }, migrations: { MigrationFunction })
	if type(data) ~= "table" or #migrations == 0 then
		return data
	end
	if type(data._version) ~= "number" then
		data._version = 0
	end
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
	if LOCKS[k] then
		return false
	end
	LOCKS[k] = true
	return true
end
local function releaseLock(name: string, key: string)
	LOCKS[name .. ":" .. key] = nil
end

-- ==== Invalidation / Subscriber ====
local function publishInvalidation(name: string, key: string)
	pcall(function()
		memoryQueue:PushBack(serialize({ name = name, key = key }), 60)
	end)
end

local function publishBatchInvalidation(name: string, keys: {string})
	pcall(function()
		memoryQueue:PushBack(serialize({ name = name, keys = keys }), 60)
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
					if d and d.name then
						local c = GLOBAL_CACHE[d.name]
						if c then
							if d.key then
								c[d.key] = nil
							elseif d.keys then
								for _, k in ipairs(d.keys) do
									c[k] = nil
								end
							end
						end
						for _, db in ipairs(SUBSCRIBERS.dbList) do
							if db._name == d.name then
								if d.key then
									db.OnInvalidate:Fire(d.key)
								elseif d.keys then
									for _, k in ipairs(d.keys) do
										db.OnInvalidate:Fire(k)
									end
								end
							end
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
if not _G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.PPDB_HEALTH_MONITOR then
	_G._PPDB.PRIVATE_DATA.CORE.CORE_CACHE.PPDB_HEALTH_MONITOR = true
	task.spawn(function()
		while true do
			for name, inst in pairs(INSTANCE_REGISTRY) do
				local cached = 0
				if GLOBAL_CACHE[name] then
					for _ in pairs(GLOBAL_CACHE[name]) do
						cached += 1
					end
				end
				log(
					inst,
					"DEBUG",
					("Health → Cache Keys: %d | Write Queue: %d"):format(cached, inst._writeCount or 0),
					0x3498db,
					inst.enabledSTD
				)
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
--  PPDB Class
-- ============================================================================
local PPDB = {}
PPDB.__index = PPDB

--[[
	Creates a new PPDB instance.
	@param name The name of the DataStore.
	@param opts Optional configuration table.
]]
function PPDB.new(
	name: string,
	opts: {
		hooks: HookTable?,
		expire: number?,
		retries: number?,
		migrations: { MigrationFunction }?,
		debug: boolean?,
		logLevel: string?,
	}?
)
	opts = opts or {}
	if INSTANCE_REGISTRY[name] then
		log(INSTANCE_REGISTRY[name], "INFO", ("Re-using instance for '%s'"):format(name))
		return INSTANCE_REGISTRY[name]
	end

	local self = setmetatable({}, PPDB) :: any
	self._name = name
	self._store = DataStoreService:GetDataStore(name)
	local defaultHooks = {
		beforeSave = function(key, data) print("Saving", key) end,
		afterSave = function(key, data) print("Saved", key) end,
	}
	self._hooks = opts.hooks and table.clone(defaultHooks) or defaultHooks
	if opts.hooks then
		for k, v in pairs(opts.hooks) do
			self._hooks[k] = v
		end
	end
	self._expire = opts.expire or DEFAULT_EXPIRE
	self._retries = opts.retries or DEFAULT_RETRIES
	self._migrations = opts.migrations or {}
	self._writeCount = 0
	self.enabledSTD = false
	self.Webhook = ""
	self._debug = opts.debug or false
	self._logLevel = LOG_LEVELS[opts.logLevel or "DEBUG"] or LOG_LEVELS.DEBUG

	self._cache = getCache(name)
	self._writeQueue = getWriteQueue(name)

	self.OnInit = Signal.new()
	self.OnSave = Signal.new()
	self.OnDelete = Signal.new()
	self.OnInvalidate = Signal.new()

	INSTANCE_REGISTRY[name] = self
	table.insert(SUBSCRIBERS.dbList, self)
	log(self, "DEBUG", ("Initialized new PPDB instance: %s"):format(name))
	
	game:BindToClose(function(closeReason: Enum.CloseReason)
		self:flushWrites()
		log(self, "INFO", ("Server is closing for reason: (%s). Flushed writes."):format(tostring(closeReason)), 0x2ecc71, self.enabledSTD)
	end)

	task.spawn(function()
		while true do
			self:cleanCache()
			task.wait(self._expire / 10)
		end
	end)

	return self
end

--[[
	Sets the logging level.
	@param level The log level ("DEBUG", "INFO", "WARN", "ERROR").
]]
function PPDB:setLogLevel(level: string)
	self._logLevel = LOG_LEVELS[level] or LOG_LEVELS.DEBUG
end

-- ------------------------------------------------------------------
--  Internal helpers
-- ------------------------------------------------------------------
function PPDB:_getQueueKey(key: string): string
	return self._name .. ":" .. key
end

function PPDB:_retryOperation(operation: () -> (), maxRetries: number): (boolean, any?)
	local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetAsync)
	for i = 1, maxRetries do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		task.wait(math.min(0.1 * (2 ^ i), budget > 0 and 1 or 5))
	end
	return false, nil
end

local function scheduleWriteFlush(self: PPDB, key: string)
	local qk = self:_getQueueKey(key)
	local entry = WRITE_QUEUES[qk]
	if not entry then
		self._writeCount += 1
		entry = {}
		WRITE_QUEUES[qk] = entry
	end
	entry.data = self._cache[key]

	task.delay(WRITE_DEBOUNCE_TIME, function()
		if not entry.data or entry.data ~= self._cache[key] then
			return
		end
		if not acquireLock(self._name, key) then
			return
		end

		if self._hooks.beforeSave then
			self._hooks.beforeSave(key, entry.data)
		end

		local ok, err = self:_retryOperation(function()
			self._store:SetAsync(key, entry.data)
		end, self._retries)
		releaseLock(self._name, key)

		if ok then
			publishInvalidation(self._name, key)
			if self._hooks.afterSave then
				self._hooks.afterSave(key, entry.data)
			end
			self.OnSave:Fire(key, entry.data)
		else
			handleError(self, key, err, "Save")
		end

		WRITE_QUEUES[qk] = nil
		self._writeCount -= 1
	end)
end

-- ------------------------------------------------------------------
--  Core API
-- ------------------------------------------------------------------
--[[
	Initializes a key with default data if it doesn't exist.
	@param key The key to initialize.
	@param defaultData The default data to set if the key is new.
	@param cb Optional callback with (success, data).
]]
function PPDB:init(key: string, defaultData: { [string]: any }, cb: ((boolean, any) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false, nil) end
		return
	end
	if self._cache[key] then
		if cb then
			cb(true, self._cache[key].data)
		end
		return
	end

	if self._hooks.beforeInit then
		self._hooks.beforeInit(key, nil)
	end

	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	if not ok then
		if cb then
			cb(false, nil)
		end
		return
	end

	if not data then
		data = defaultData
		local setOk = pcall(function()
			self._store:SetAsync(key, data)
		end)
		if not setOk then
			log(self, "ERROR", "Initial save failed for key: " .. key)
		end
	end

	data = migrateData(data, self._migrations) or data
	self:setCached(key, data)

	if self._hooks.afterInit then
		self._hooks.afterInit(key, data)
	end
	self.OnInit:Fire(key, data)
	if cb then
		cb(true, data)
	end
end

--[[
	Gets or initializes a key with default data.
	@param key The key to get or initialize.
	@param defaultData The default data to set if the key is new.
	@param cb Optional callback with (success, data).
	@return The data.
]]
function PPDB:getOrInit(key: string, defaultData: { [string]: any }, cb: ((boolean, any) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false, nil) end
		return nil
	end
	local cached = self:getCached(key)
	if cached then
		if cb then cb(true, cached) end
		return cached
	end

	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	if ok and data then
		data = migrateData(data, self._migrations) or data
		self:setCached(key, data)
		if cb then cb(true, data) end
		return data
	end

	self:setCached(key, defaultData)
	local setOk = pcall(function()
		self._store:SetAsync(key, defaultData)
	end)
	if not setOk then
		log(self, "ERROR", "Set default failed for key: " .. key)
	end
	publishInvalidation(self._name, key)
	if cb then cb(setOk, defaultData) end
	return defaultData
end

--[[
	Updates a key with a function.
	@param key The key to update.
	@param updateFn The function to apply to the current data.
	@param cb Optional callback with (success, newData).
]]
function PPDB:update(key: string, updateFn: (any) -> any, cb: ((boolean, any) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false, nil) end
		return
	end
	local current = self:getCached(key) or {}
	current = migrateData(current, self._migrations) or current
	local new = updateFn(current)
	if new == nil then
		if cb then
			cb(false, nil)
		end
		return
	end

	self:setCached(key, new)
	scheduleWriteFlush(self, key)
	if cb then
		cb(true, new)
	end
end

--[[
	Increments a field in a key.
	@param key The key to update.
	@param field The field to increment.
	@param amount The amount to increment by.
	@param cb Optional callback with (success, newValue).
	@return The new value.
]]
function PPDB:increment(key: string, field: string, amount: number, cb: ((boolean, number?) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false, nil) end
		return nil
	end
	local v = (self:getCached(key) and self:getCached(key)[field] or 0) + amount
	self:update(key, function(d)
		d[field] = (d[field] or 0) + amount
		return d
	end)
	if cb then cb(true, v) end
	return v
end

--[[
	Updates multiple keys with a function.
	@param keys The keys to update.
	@param updateFn The function to apply to each current data.
]]
function PPDB:batchUpdate(keys: { string }, updateFn: (any) -> any)
	local batch = {}
	local invalidationKeys = {}
	for _, k in ipairs(keys) do
		if type(k) ~= "string" or k == "" then
			log(self, "WARN", "Invalid key in batch: " .. tostring(k))
			continue
		end
		local cur = self:getCached(k) or {}
		cur = migrateData(cur, self._migrations) or cur
		local new = updateFn(cur)
		if new then
			self:setCached(k, new)
			batch[k] = new
			table.insert(invalidationKeys, k)
		end
	end
	for k in pairs(batch) do
		scheduleWriteFlush(self, k)
	end
	if #invalidationKeys > 0 then
		publishBatchInvalidation(self._name, invalidationKeys)
	end
end

--[[
	Checks if a key exists in the DataStore.
	@param key The key to check.
	@return True if exists.
]]
function PPDB:hasKey(key: string): boolean
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		return false
	end
	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	return ok and data ~= nil
end

--[[
	Deletes a key.
	@param key The key to delete.
	@param cb Optional callback with (success).
]]
function PPDB:delete(key: string, cb: ((boolean) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false) end
		return
	end
	local ok = pcall(function()
		self._store:RemoveAsync(key)
	end)
	if ok then
		self._cache[key] = nil
		publishInvalidation(self._name, key)
		self.OnDelete:Fire(key)
	end
	if cb then
		cb(ok)
	end
end

function PPDB:leave(key: string)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		return
	end
	self._cache[key] = nil
end

function PPDB:clearCache()
	self._cache = {}
	GLOBAL_CACHE[self._name] = {}
end

function PPDB:flushWrites()
	for qk, entry in pairs(WRITE_QUEUES) do
		if string.sub(qk, 1, #self._name + 1) == self._name .. ":" and entry.data then
			local key = string.sub(qk, #self._name + 2)
			local ok, err = self:_retryOperation(function()
				self._store:SetAsync(key, entry.data)
			end, self._retries)
			if not ok then
				handleError(self, key, err, "Flush write")
			end
			self:setCached(key, entry.data)
			self._writeCount -= 1
			WRITE_QUEUES[qk] = nil
		end
	end
end

--[[
	Gets cached data for a key.
	@param key The key.
	@return The data or nil.
]]
function PPDB:getCached(key: string): any
	local entry = self._cache and self._cache[key]
	return entry and entry.data or nil
end

--[[
	Sets cached data for a key with timestamp.
	@param key The key.
	@param data The data.
]]
function PPDB:setCached(key: string, data: any)
	if not self._cache then
		self._cache = {}
		GLOBAL_CACHE[self._name] = self._cache
	end
	self._cache[key] = { data = data, timestamp = os.time() }
end

--[[
	Cleans expired cache entries.
]]
function PPDB:cleanCache()
	local now = os.time()
	for key, entry in pairs(self._cache) do
		if now - entry.timestamp > self._expire then
			self._cache[key] = nil
		end
	end
end

--[[
	Sets the Discord webhook URL.
	@param url The webhook URL.
]]
function PPDB:setWebhook(url: string)
	if not url:match("^https://discord%.com/api/webhooks/") then
		log(self, "ERROR", "Invalid webhook URL")
		return
	end
	self.Webhook = url
end

function PPDB:sendToDiscord(enabled: boolean)
	self.enabledSTD = enabled
end

-- ------------------------------------------------------------------
--  EXTENDED API
-- ------------------------------------------------------------------
function PPDB:keys(): { string }
	local out = {}
	for k in pairs(self._cache) do
		out[k] = true
	end

	if not self._allKeysCache or os.time() - self._allKeysCache.t > 60 then
		local ok, pages = pcall(function()
			return self._store.ListKeysAsync and self._store:ListKeysAsync() or nil
		end)
		if ok and pages then
			while true do
				for _, item in ipairs(pages:GetCurrentPage()) do
					out[item.KeyName] = true
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
			self._allKeysCache = { t = os.time() }
		end
	end

	local list = {}
	for k in pairs(out) do
		table.insert(list, k)
	end
	return list
end

function PPDB:size(): number
	local n = 0
	for _ in pairs(self._cache) do
		n += 1
	end
	return n
end

function PPDB:exists(key: string): boolean
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		return false
	end
	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	return ok and data ~= nil
end

--[[
	Sets a key directly in DataStore.
	@param key The key.
	@param value The value.
	@param cb Optional callback with (success, error?).
]]
function PPDB:rawSet(key: string, value: any, cb: ((boolean, string?) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false, "Invalid key") end
		return
	end
	local compressed = HttpService:JSONEncode(value):gsub("%s+", "")
	local ok, err = pcall(function()
		self._store:SetAsync(key, compressed)
	end)
	if ok then
		self:setCached(key, value)
		publishInvalidation(self._name, key)
		if cb then
			cb(true)
		end
	else
		handleError(self, key, err, "RawSet")
		if cb then
			cb(false, tostring(err))
		end
	end
end

--[[
	Gets a key directly from DataStore.
	@param key The key.
	@param cb Optional callback with (success, data?).
]]
function PPDB:rawGet(key: string, cb: ((boolean, any?) -> ())?)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		if cb then cb(false, nil) end
		return
	end
	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	if cb then
		cb(ok, data)
	end
end

function PPDB:export(): { [string]: any }
	return deserialize(serialize(self._cache)) or {}
end

function PPDB:import(tbl: { [string]: any }, overwrite: boolean?)
	for k, v in pairs(tbl) do
		if type(k) ~= "string" or k == "" then
			log(self, "WARN", "Invalid key in import: " .. tostring(k))
			continue
		end
		if overwrite or self:getCached(k) == nil then
			self:setCached(k, v)
			scheduleWriteFlush(self, k)
		end
	end
end

function PPDB:stat()
	local cached, queued = 0, 0
	for _ in pairs(self._cache) do
		cached += 1
	end
	for qk in pairs(WRITE_QUEUES) do
		if string.find(qk, self._name .. ":", 1, true) then
			queued += 1
		end
	end
	return {
		name = self._name,
		cachedKeys = cached,
		queuedWrites = queued,
		writeCount = self._writeCount,
	}
end

function PPDB:clearKey(key: string)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		return
	end
	self._cache[key] = nil
	self:delete(key)
end

--[[
	Atomically increments a field.
	@param key The key.
	@param field The field.
	@param amount The amount.
	@return The new value or nil on failure.
]]
function PPDB:atomicIncrement(key: string, field: string, amount: number): number?
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		return nil
	end
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
		self:setCached(key, newValue)
		return newValue[field]
	else
		handleError(self, key, err, "Atomic increment")
		return nil
	end
end

--[[
	Performs a transaction on multiple keys with rollback on failure.
	@param keys The keys.
	@param fn The transaction function.
	@return The new data or nil on failure.
]]
function PPDB:transaction(keys: { string }, fn: ({ [string]: any }) -> { [string]: any })
	local batch = {}
	local original = {}
	local invalidationKeys = {}
	for _, k in ipairs(keys) do
		if type(k) ~= "string" or k == "" then
			log(self, "WARN", "Invalid key in transaction: " .. tostring(k))
			continue
		end
		batch[k] = self:getCached(k) or {}
		original[k] = self:getCached(k) or {}
		table.insert(invalidationKeys, k)
	end
	local new = fn(batch)
	local failed = false
	for k, v in pairs(new) do
		self:setCached(k, v)
		local ok = pcall(function()
			self._store:SetAsync(k, v)
		end)
		if not ok then
			failed = true
			break
		end
	end
	if failed then
		for k in pairs(new) do
			self:setCached(k, original[k])
		end
		log(self, "ERROR", "Transaction failed, rolled back")
		return nil
	end
	if #invalidationKeys > 0 then
		publishBatchInvalidation(self._name, invalidationKeys)
	end
	return new
end

--[[
	Backups a key with a timestamped version.
	@param key The key to backup.
]]
function PPDB:backup(key: string)
	if type(key) ~= "string" or key == "" then
		log(self, "ERROR", "Invalid key")
		return
	end
	local data = self:getCached(key)
	if data then
		local backupKey = key .. ":backup:" .. os.time()
		pcall(function()
			self._store:SetAsync(backupKey, data)
		end)
	end
end

--[[
	Gets multiple keys in batch.
	@param keys The keys to get.
	@return A dictionary of key to data.
]]
function PPDB:batchGet(keys: {string}): { [string]: any }
	local results = {}
	local invalidationKeys = {}
	for _, key in ipairs(keys) do
		if type(key) ~= "string" or key == "" then
			log(self, "WARN", "Invalid key in batchGet: " .. tostring(key))
			continue
		end
		if self._cache[key] then
			results[key] = self:getCached(key)
		else
			local ok, data = pcall(function()
				return self._store:GetAsync(key)
			end)
			if ok and data then
				data = migrateData(data, self._migrations) or data
				self:setCached(key, data)
				results[key] = data
				table.insert(invalidationKeys, key)
			end
		end
	end
	if #invalidationKeys > 0 then
		publishBatchInvalidation(self._name, invalidationKeys)
	end
	return results
end

return PPDB
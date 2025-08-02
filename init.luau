--!strict
--!optimize 2
--!native

-- ==== Services ====
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

-- ==== Signal Implementation ====
local Signal = require(script.Signal)

-- ==== Types ====
export type HookFunction = (key: string, data: any) -> ()
export type HookTable = {
	beforeInit: HookFunction?,
	afterInit: HookFunction?,
	beforeSave: HookFunction?,
	afterSave: HookFunction?
}
export type MigrationFunction = (data: {[string]: any}) -> {[string]: any}
export type SignalConnection = { Disconnect: () -> () }
export type PPDBM = typeof(setmetatable({} :: {
	_name: string,
	_store: DataStore,
	_hooks: HookTable,
	_expire: number,
	_retries: number,
	_migrations: {MigrationFunction},
	_writeCount: number,
	_cache: {[string]: any},
	_writeQueue: {[string]: any},
	OnInit: Signal.Signal<string, any>,
	OnSave: Signal.Signal<string, any>,
	OnDelete: Signal.Signal<string>,
	OnInvalidate: Signal.Signal<string>,
	Webhook: string
}, {}))

-- ==== Constants ====
local DEFAULT_RETRIES = 3
local DEFAULT_EXPIRE = 60 * 60 * 24 * 3
local WRITE_DEBOUNCE_TIME = 1
local POLL_INTERVALS = {0.1, 0.5, 1, 2, 5} -- Progressive backoff for MemoryStore polling

-- ==== Shared Globals ====
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

-- ==== MemoryStore Channel ====
local memoryQueue = MemoryStoreService:GetQueue("PPDBM_Channel")

-- ==== Logging ====
function safeJSON(data)
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

local function log(self: PPDBM, level: string, message: string, color: number?, sendWebhook: boolean?)
	local timeStr = os.date("%Y-%m-%d %H:%M:%S")
	local prefix = string.format("[PPDBM][%s][%s]", level, timeStr)
	print(prefix, message)
	sendWebhook = sendWebhook or false
	if sendWebhook then
		sendDiscord(self.Webhook, level, message, color)
	end
end

-- ==== JSON Helpers ====
local function serialize(data: any): string
	local dataStr = tostring(data)
	if JSON_CACHE[dataStr] then
		return JSON_CACHE[dataStr]
	end
	
	local result = HttpService:JSONEncode(data)
	JSON_CACHE[dataStr] = result
	return result
end

local function deserialize(str: string?): any?
	if not str then return nil end
	local success, result = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	return if success then result else nil
end

-- ==== Migration ====
local function migrateData(data: {[string]: any}?, migrations: {MigrationFunction}): {[string]: any}?
	if not data or type(data) ~= "table" or #migrations == 0 then 
		return data 
	end
	
	local version = data._version or 0
	local latestVersion = #migrations
	
	while version < latestVersion do
		version += 1
		local migrationFn = migrations[version]
		if migrationFn then
			data = migrationFn(data)
			data._version = version
		else
			break
		end
	end
	return data
end

-- ==== Lock ====
local function acquireLock(name: string, key: string): boolean
	local lockKey = name .. ":" .. key
	if LOCKS[lockKey] then return false end
	LOCKS[lockKey] = true
	return true
end

local function releaseLock(name: string, key: string)
	LOCKS[name .. ":" .. key] = nil
end

-- ==== Publish Invalidation ====
local function publishInvalidation(name: string, key: string)
	local message = { name = name, key = key }
	pcall(function()
		memoryQueue:PushBack(serialize(message), 60)
	end)
end

-- ==== Optimized Subscriber with Progressive Backoff ====
if not SUBSCRIBERS.subscribed then
	SUBSCRIBERS.subscribed = true
	task.spawn(function()
		local currentInterval = 1
		
		while true do
			local success, messages = pcall(function()
				return memoryQueue:ReadAsync(10, false, 5) -- Shorter timeout
			end)
			
			if success and messages and #messages > 0 then
				currentInterval = 1 -- Reset on activity
				
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

local function countKeys(tbl)
	if type(tbl) ~= "table" then return 0 end
	local count = 0
	for _ in pairs(tbl) do
		count += 1
	end
	return count
end

-- ==== Centralized Health Monitor ====
if not _G.PPDBM_HEALTH_MONITOR then
	_G.PPDBM_HEALTH_MONITOR = true
	task.spawn(function()
		while true do
			for name, instance in pairs(INSTANCE_REGISTRY) do
				local cacheCount = countKeys(GLOBAL_CACHE[name])
				local writeCount = instance._writeCount or 0
				log(instance, "DEBUG", 
					("Health → Cache Keys: %d | Write Queue: %d"):format(cacheCount, writeCount), 
					0x3498db, instance.enabledSTD)
			end
			task.wait(30)
		end
	end)
end

-- ==== Class ====
local PPDBM = {}
PPDBM.__index = PPDBM

function PPDBM.new(name: string, hooks: HookTable?, expire: number?, retries: number?, migrations: {MigrationFunction}?): PPDBM
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
	self._writeCount = 0 -- Track writes for this instance
	self.enabledSTD = false
	self.Webhook = ""

	-- Initialize and cache references
	GLOBAL_CACHE[name] = GLOBAL_CACHE[name] or {}
	WRITE_QUEUES[name] = WRITE_QUEUES[name] or {}
	
	self._cache = GLOBAL_CACHE[name]
	self._writeQueue = WRITE_QUEUES[name]

	self.OnInit = Signal.new()
	self.OnSave = Signal.new()
	self.OnDelete = Signal.new()
	self.OnInvalidate = Signal.new()

	INSTANCE_REGISTRY[name] = self
	table.insert(SUBSCRIBERS.dbList, self)

	log(self, "INFO", ("Created new PPDBM instance for '%s'"):format(name))
	return self
end

-- Helper method for queue key generation
function PPDBM:_getQueueKey(key: string): string
	return self._name .. ":" .. key
end

function PPDBM:setWebhook(url: string)
	self.Webhook = url
end

-- ==== Optimized Write Flush ====
local function scheduleWriteFlush(self: PPDBM, key: string)
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
		
		if WRITE_QUEUES[queueKey] then
			self._writeCount -= 1
			WRITE_QUEUES[queueKey] = nil
		end
	end)
end

-- ==== API ====
function PPDBM:init(key: string, defaultData: {[string]: any}, cb: ((boolean, any) -> ())?)
	if self._cache[key] then 
		if cb then cb(true, self._cache[key]) end 
		return 
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
		self._store:SetAsync(key, data)
	end
	
	data = migrateData(data, self._migrations) or data
	self._cache[key] = data
	self.OnInit:Fire(key, data)
	if cb then cb(true, data) end
end

function PPDBM:getOrInit(key: string, defaultData: {[string]: any})
	local cached = self:getCached(key)
	if cached then return cached end
	
	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	
	if ok and data then
		data = migrateData(data, self._migrations) or data
		self:setCached(key, data)
		return data
	end
	
	self:setCached(key, defaultData)
	self._store:SetAsync(key, defaultData)
	publishInvalidation(self._name, key)
	return defaultData
end

function PPDBM:update(key: string, updateFn, cb)
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
	local current = self:getCached(key)
	if not current then return nil end
	
	current[field] = (current[field] or 0) + amount
	self:update(key, function(data)
		data[field] = (data[field] or 0) + amount
		return data
	end)
	return current[field]
end

-- ==== Optimized Batch Update ====
function PPDBM:batchUpdate(keys, updateFn)
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
	
	-- Single batched write flush
	for key, data in pairs(batch) do
		scheduleWriteFlush(self, key)
	end
end

function PPDBM:hasKey(key: string)
	local ok, data = pcall(function()
		return self._store:GetAsync(key)
	end)
	return ok and data ~= nil
end

function PPDBM:delete(key: string, cb)
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
		if string.find(queueKey, self._name .. ":") and entry.data then
			local key = queueKey:split(":")[2]
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

function PPDBM:sendToDiscord(Enabled)
	self.enabledSTD = Enabled
end

return function(name: string, hooks: HookTable?, expire: number?, retries: number?, migrations: {MigrationFunction}?): PPDBM
	return PPDBM.new(name, hooks, expire, retries, migrations)
end
--!strict
--!optimize 2
--!native
-- ============================================================================
-- PPDB – PaoPao's DataStore Module
-- High-performance, caching, migration-friendly DataStore wrapper
-- ============================================================================
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

local PPDB = {}
PPDB.__index = PPDB

-- ==== Global shared state ====
local GLOBAL_CACHE = {}
local MEMORY_QUEUE = MemoryStoreService:GetQueue("PPDB_GlobalInvalidation")
local JSON_CACHE = {}
local WRITE_QUEUE = {}

-- ==== Signals ====
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
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
function Signal:Fire(...)
	for _, fn in ipairs(self._listeners) do
		task.spawn(fn, ...)
	end
end

-- ==== Helpers ====
local function _serialize(data)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then
		return "{}"
	end
	JSON_CACHE[json] = JSON_CACHE[json] or json
	return JSON_CACHE[json]
end

local function _deserialize(json)
	if not json then return nil end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	return ok and data or nil
end

local function _retryOperation(fn, retries, debug)
	retries = retries or 3
	local base = 0.5
	for i = 1, retries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		if debug then
			warn(string.format("Retry %d failed: %s", i, tostring(res)))
		end
		task.wait(base * 2 ^ (i - 1) * (0.9 + math.random() * 0.2))
	end
	return false, "Retry failed"
end

local function _migrateData(data: { [string]: any }, migrations: { [any]: ({ [string]: any }) -> ({ [string]: any | nil }) })
	if type(data) ~= "table" or #migrations == 0 then return data end
	data._version = data._version or 0
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

-- ==== Constructor ====
function PPDB.new(name: string, opts: { [string]: any }?)
	opts = opts or {}
	local self = setmetatable({}, PPDB)
	self._name = name
	self._store = DataStoreService:GetDataStore(name)
	self._cache = GLOBAL_CACHE[name] or {}
	GLOBAL_CACHE[name] = self._cache
	self._migrations = opts.migrations or {}
	self._debug = opts.debug or false
	self.Webhook = ""
	self.enabledSTD = false

	-- Signals
	self.OnInit = Signal.new()
	self.OnSave = Signal.new()
	self.OnDelete = Signal.new()
	self.OnInvalidate = Signal.new()

	-- Bind flush on close
	game:BindToClose(function()
		self:flushWrites()
	end)

	return self
end

-- ==== Core Methods ====
function PPDB:init(key: string, defaultData: { [string]: any }, cb: ((boolean, any) -> ())?)
	if self._cache[key] then
		if cb then cb(true, self._cache[key]) end
		return self._cache[key]
	end
	task.spawn(function()
		local ok, data = _retryOperation(function()
			return self._store:GetAsync(key)
		end, 3, self._debug)
		data = (ok and data) or defaultData
		data = _migrateData(data, self._migrations)
		data._t = tick()
		self._cache[key] = data
		self.OnInit:Fire(key, data)
		if cb then cb(true, data) end
	end)
	return nil
end

function PPDB:get(key: string, default: any?, ttl: number?)
	local cached = self._cache[key]
	if cached and ttl and cached._t and tick() - cached._t > ttl then cached = nil end
	if cached then return cached end

	local ok, data = _retryOperation(function()
		return self._store:GetAsync(key)
	end, 3, self._debug)
	data = (ok and data) or default
	data = _migrateData(data, self._migrations)
	data._t = tick()
	self._cache[key] = data
	self.OnInit:Fire(key, data)
	return data
end

function PPDB:set(key: string, value)
	value._t = tick()
	self._cache[key] = value
	self:_scheduleWriteFlush(key)
end

function PPDB:update(key: string, fn)
	local cur = self:get(key, {})
	local new = fn(cur)
	if new then
		new._t = tick()
		self:set(key, new)
	end
end

function PPDB:increment(key: string, field: string, amount: number)
	self:update(key, function(d)
		d[field] = (d[field] or 0) + amount
		return d
	end)
end

function PPDB:leave(key: string)
	self:update(key, function(d) return d end)
	self:flushWrites()
	self._cache[key] = nil
	self.OnDelete:Fire(key)
end

function PPDB:cleanCache(ttl: number?)
	ttl = ttl or 3600
	for k, v in pairs(self._cache) do
		if v._t and tick() - v._t > ttl then
			self._cache[k] = nil
		end
	end
end

-- ==== Locks (Cross-server safe) ====
function PPDB:_acquireLock(key: string)
	local lockKey = self._name .. ":" .. key .. ":" .. HttpService:GenerateGUID(false)
	local ok, _ = _retryOperation(function()
		return MEMORY_QUEUE:PushBack(_serialize({ lock = lockKey }), 10)
	end, 3, self._debug)
	return ok, lockKey
end

function PPDB:_releaseLock(lockKey: string)
	local ok, _ = _retryOperation(function()
		local item = MEMORY_QUEUE:PopFront()
		if item then
			local data = _deserialize(item)
			if data and data.lock == lockKey then
				return true
			else
				MEMORY_QUEUE:PushBack(item, 10)
			end
		end
		return false
	end, 3, self._debug)
	return ok
end

-- ==== Write Flush ====
function PPDB:_scheduleWriteFlush(key: string)
	if WRITE_QUEUE[key] then return end
	WRITE_QUEUE[key] = true
	task.delay(1, function()
		local data = self._cache[key]
		if not data then
			WRITE_QUEUE[key] = nil
			return
		end
		local ok, lockKey = self:_acquireLock(key)
		if not ok then
			WRITE_QUEUE[key] = nil
			return
		end

		local success, err = _retryOperation(function()
			self._store:SetAsync(key, data)
		end, 3, self._debug)

		self:_releaseLock(lockKey)
		if success then
			MEMORY_QUEUE:PushBack(_serialize({ name = self._name, key = key }), 60)
			self.OnSave:Fire(key, data)
			self:_logToDiscord(string.format("Saved key: %s", key))
		else
			warn("Write failed for key:", key, err)
		end
		WRITE_QUEUE[key] = nil
	end)
end

function PPDB:flushWrites()
	for key, _ in pairs(self._cache) do
		self:_scheduleWriteFlush(key)
	end
end

-- ==== Export / Import ====
function PPDB:export()
	return _deserialize(_serialize(self._cache))
end
function PPDB:import(tbl: { [string]: any }, overwrite: boolean?)
	for k, v in pairs(tbl) do
		if overwrite or self._cache[k] == nil then
			self:set(k, v)
		end
	end
end

-- ==== Discord Logging ====
function PPDB:setWebhook(url: string)
	self.Webhook = url
end

function PPDB:sendToDiscord(enabled: boolean)
	self.enabledSTD = enabled
end

function PPDB:_logToDiscord(message: string)
	if not self.enabledSTD or self.Webhook == "" then return end
	task.spawn(function()
		local ok = pcall(function()
			HttpService:PostAsync(
				self.Webhook,
				HttpService:JSONEncode({ content = message }),
				Enum.HttpContentType.ApplicationJson
			)
		end)
		if not ok and self._debug then
			warn("Discord log failed")
		end
	end)
end

return PPDB

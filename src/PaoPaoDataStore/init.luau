--!strict
--!optimize 2
--!native
-- ============================================================================
-- PPDB – PaoPao's DataStore Module
-- A high-performance, caching, migration-friendly DataStore wrapper, and some sh*t code
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
function _serialize(data)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then
		return "{}"
	end
	JSON_CACHE[json] = JSON_CACHE[json] or json
	return JSON_CACHE[json]
end

function _deserialize(json)
	if not json then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	return ok and data or nil
end

function _retryOperation(fn, retries)
	retries = retries or 3
	local base = 0.5
	for i = 1, retries do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		task.wait(base * 2 ^ (i - 1) * (0.9 + math.random() * 0.2))
	end
	return false, "Retry failed"
end

function _migrateData(data, migrations)
	if type(data) ~= "table" or #migrations == 0 then
		return data
	end
	data._version = data._version or 0
	local version = data._version
	while version < #migrations do
		version += 1
		local fn = migrations[version]
		local ok, new = pcall(fn, data)
		if ok and new then
			data, new._version = new, version
		else
			break
		end
	end
	return data
end

-- ==== Constructor ====
function PPDB.new(name, opts)
	opts = opts or {}
	local self = setmetatable({}, PPDB)
	self._name = name
	self._store = DataStoreService:GetDataStore(name)
	self._cache = GLOBAL_CACHE[name] or {}
	GLOBAL_CACHE[name] = self._cache
	self._migrations = opts.migrations or {}
	self._writeCount = 0
	self.Webhook = ""
	self.enabledSTD = false
	self._debug = opts.debug or false

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

-- Initialize a key in the DB (loads from cache or DataStore)
function PPDB:init(key: string, defaultData: { [string]: any }, cb: ((boolean, any) -> ())?)
	if self._cache[key] then
		if cb then
			cb(true, self._cache[key])
		end
		return self._cache[key]
	end
	task.spawn(function()
		local ok, data = _retryOperation(function()
			return self._store:GetAsync(key)
		end, 3)
		data = _migrateData(data, self._migrations)
		self._cache[key] = data
		self.OnInit:Fire(key, data)
		if cb then
			cb(true, data)
		end
	end)
	return nil
end

-- ==== Locks (Cross-server safe) ====
function PPDB:_acquireLock(key)
	local lockKey = self._name .. ":" .. key
	local ok, _ = _retryOperation(function()
		return MEMORY_QUEUE:PushBack(_serialize({ lock = lockKey }), 10)
	end, 1)
	return ok
end
function PPDB:_releaseLock(key) end -- optional cleanup

-- ==== Write Flush ====
function PPDB:_scheduleWriteFlush(key)
	task.delay(1, function()
		local data = self._cache[key]
		if not data then
			return
		end
		if not self:_acquireLock(key) then
			return
		end

		local ok, err = _retryOperation(function()
			self._store:SetAsync(key, data)
		end)
		self:_releaseLock(key)
		if ok then
			MEMORY_QUEUE:PushBack(_serialize({ name = self._name, key = key }), 60)
			self.OnSave:Fire(key, data)
		else
			warn("Write failed for key:", key, err)
		end
	end)
end

-- ==== Core API ====
function PPDB:get(key, default)
	if self._cache[key] then
		return self._cache[key]
	end
	local ok, data = _retryOperation(function()
		return self._store:GetAsync(key)
	end)
	data = (ok and data) or default
	data = _migrateData(data, self._migrations)
	self._cache[key] = data
	self.OnInit:Fire(key, data)
	return data
end

function PPDB:set(key, value)
	self._cache[key] = value
	self:_scheduleWriteFlush(key)
end

function PPDB:update(key, fn)
	local cur = self:get(key, {})
	local new = fn(cur)
	if new then
		self:set(key, new)
	end
end

function PPDB:increment(key, field, amount)
	self:update(key, function(d)
		d[field] = (d[field] or 0) + amount
		return d
	end)
end

-- ==== Cache Maintenance ====
function PPDB:cleanCache()
	for k, v in pairs(self._cache) do
		if v._t and tick() - v._t > 3600 then
			self._cache[k] = nil
		end
	end
end

-- ==== Export / Import ====
function PPDB:export()
	return _deserialize(_serialize(self._cache))
end
function PPDB:import(tbl, overwrite)
	for k, v in pairs(tbl) do
		if overwrite or self._cache[k] == nil then
			self:set(k, v)
		end
	end
end

-- ==== Flush all queued writes ====
function PPDB:flushWrites()
	for key, _ in pairs(self._cache) do
		self:_scheduleWriteFlush(key)
	end
end

-- ==== Logging / Discord ====
function PPDB:setWebhook(url)
	self.Webhook = url
end
function PPDB:sendToDiscord(enabled)
	self.enabledSTD = enabled
end

return PPDB

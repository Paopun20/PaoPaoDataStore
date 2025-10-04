--!strict
--!optimize 2
--!native

-- ============================================================================
-- PPDB – PaoPao's DataStore Module
-- High-performance, caching, migration-friendly DataStore wrapper
-- Copyright 2025 PaoPaoDev
-- Licensed under Apache 2.0
-- ============================================================================

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- ============================================================================
-- Helpers
-- ============================================================================

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- ============================================================================
-- Signal Class
-- ============================================================================

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { _connected = true }
	function connection:Disconnect()
		self._connected = false
	end
	table.insert(self._handlers, function(...)
		if connection._connected then
			fn(...)
		end
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in ipairs(self._handlers) do
		task.defer(handler, ...)
	end
end

-- ============================================================================
-- Main Module
-- ============================================================================

local PPDB = {}
PPDB.__index = PPDB

-- ============================================================================
-- Options Helper
-- ============================================================================

PPDB.DBOptions = {}
PPDB.DBOptions.__index = PPDB.DBOptions

function PPDB.DBOptions.new()
	return setmetatable({
		debug = false,
		cache = true,
		discordWebhook = "",
		enableDiscordLog = false,
		migrations = {},
	}, PPDB.DBOptions)
end

-- ============================================================================
-- Globals
-- ============================================================================

local GLOBAL_CACHE = {}
local WRITE_QUEUE = {}
local MEMORY_QUEUE = MemoryStoreService:GetQueue("PPDB_GlobalInvalidation")
local MAX_RETRIES = 5
local RETRY_DELAY = 0.5
local INSTANCES = {}
local _boundToClose = false

-- ============================================================================
-- Constructor
-- ============================================================================

function PPDB.new(name: string, DBOptions: PPDB.DBOptions?)
	DBOptions = DBOptions or PPDB.DBOptions.new()

	local self = setmetatable({
		_name = name,
		_store = DataStoreService:GetDataStore(name),
		_cache = {},
		debug = DBOptions.debug or false,
		_cacheEnabled = DBOptions.cache ~= false,
		discordWebhook = DBOptions.discordWebhook or "",
		enableDiscordLog = DBOptions.enableDiscordLog or false,
		OnInit = Signal.new(),
		OnSave = Signal.new(),
		OnDelete = Signal.new(),
		OnInvalidate = Signal.new(),
	}, PPDB)

	-- Shared global cache but isolated per instance
	if GLOBAL_CACHE[name] then
		self._cache = deepCopy(GLOBAL_CACHE[name])
	else
		GLOBAL_CACHE[name] = self._cache
	end

	-- Bind to close
	INSTANCES[self] = true
	if not _boundToClose then
		_boundToClose = true
		game:BindToClose(function()
			for inst, _ in pairs(INSTANCES) do
				task.spawn(function()
					pcall(function()
						inst:flushWrites()
					end)
				end)
			end
		end)
	end

	return self
end

-- ============================================================================
-- Private Helpers
-- ============================================================================

function PPDB:_retryOperation(fn)
	for i = 1, MAX_RETRIES do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if self.debug then
			warn(string.format("[PPDB Retry %d] %s", i, tostring(res)))
		end
		task.wait(RETRY_DELAY)
	end
	return false, "Retry failed"
end

function PPDB:_logToDiscord(message: string)
	if not self.enableDiscordLog or self.discordWebhook == "" then
		return
	end
	task.spawn(function()
		local ok, res = pcall(function()
			HttpService:PostAsync(
				self.discordWebhook,
				HttpService:JSONEncode({ content = message }),
				Enum.HttpContentType.ApplicationJson
			)
		end)
		if not ok and self.debug then
			warn("Discord log failed:", tostring(res))
		end
	end)
end

-- Queue-based lock acquire (wait until done)
function PPDB:_acquireLock(key: string)
	if RunService:IsStudio() then
		return true, "studio-lock"
	end

	local lockKey = self._name .. ":" .. key .. ":" .. HttpService:GenerateGUID(false)
	local startTime = tick()

	repeat
		local ok = false
		pcall(function()
			MEMORY_QUEUE:AddAsync(lockKey, 10)
			ok = true
		end)
		if ok then
			return true, lockKey
		end
		task.wait(0.1)
	until tick() - startTime > 5

	warn("Failed to acquire lock for key:", key)
	return false
end

-- ============================================================================
-- Core Methods
-- ============================================================================

function PPDB:init(key: string, defaultData: table?, cb: ((boolean, any) -> ())?)
	if self._cache[key] then
		if cb then
			cb(true, self._cache[key])
		end
		return self._cache[key]
	end

	task.spawn(function()
		local ok, data = self:_retryOperation(function()
			return self._store:GetAsync(key)
		end)
		data = (ok and data) or defaultData or {}
		data._t = tick()
		self._cache[key] = data
		self.OnInit:Fire(key, data)
		if cb then
			cb(true, data)
		end
	end)
	return defaultData
end

function PPDB:get(key: string, default: any?, ttl: number?)
	local cached = self._cache[key]
	if cached and ttl and cached._t and tick() - cached._t > ttl then
		cached = nil
	end
	if cached then
		return cached
	end

	local ok, data = self:_retryOperation(function()
		return self._store:GetAsync(key)
	end)
	data = (ok and data) or default
	if type(data) ~= "table" then
		data = default or {}
	end
	data._t = tick()
	self._cache[key] = data
	self.OnInit:Fire(key, data)
	return data
end

function PPDB:set(key: string, value)
	if type(value) ~= "table" then
		warn("PPDB:set expected table value for key:", key)
		return
	end
	value._t = tick()
	self._cache[key] = value
	self.OnSave:Fire(key, value)
	self:_scheduleWriteFlush(key)
	self:_logToDiscord(("Saved key: %s"):format(key))
end

function PPDB:update(key: string, fn)
	if type(fn) ~= "function" then
		return
	end
	local cur = self:get(key, {})
	local new = fn(cur)
	if new and type(new) == "table" then
		new._t = tick()
		self:set(key, new)
	end
end

function PPDB:increment(key: string, field: string, amount: number)
	amount = amount or 1
	self:update(key, function(d)
		d[field] = (d[field] or 0) + amount
		return d
	end)
end

-- ============================================================================
-- Write Flush with Queue Lock Wait
-- ============================================================================

function PPDB:_scheduleWriteFlush(key: string)
	if WRITE_QUEUE[key] then
		return
	end
	WRITE_QUEUE[key] = true

	task.spawn(function()
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

		local success, err = self:_retryOperation(function()
			self._store:SetAsync(key, data)
		end)
		if not success then
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

function PPDB:leave(key: string)
	if not self._cache[key] then
		return
	end
	local ok, lockKey = self:_acquireLock(key)
	if ok then
		local success, err = self:_retryOperation(function()
			self._store:SetAsync(key, self._cache[key])
		end)
		if not success then
			warn("Leave flush failed for key:", key, err)
		end
		self._cache[key] = nil
		self.OnDelete:Fire(key)
		self:_logToDiscord(("Deleted key: %s"):format(key))
	end
end

-- ============================================================================
-- Cache Cleanup
-- ============================================================================

function PPDB:cleanCache(ttl: number?)
	ttl = ttl or 3600
	for k, v in pairs(self._cache) do
		if v and v._t and tick() - v._t > ttl then
			self._cache[k] = nil
		end
	end
end

-- ============================================================================
-- Export / Import
-- ============================================================================

function PPDB:export()
	return deepCopy(self._cache)
end

function PPDB:import(tbl: { [string]: any }, overwrite: boolean?)
	if type(tbl) ~= "table" then
		return
	end
	for k, v in pairs(tbl) do
		if overwrite or self._cache[k] == nil then
			self:set(k, type(v) == "table" and v or { value = v })
		end
	end
end

return PPDB

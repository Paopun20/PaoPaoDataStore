--!strict
--!optimize 2
--!native

-- PPDB – PaoPao's DataStore Module
-- High-performance, caching, migration-friendly DataStore wrapper
-- Copyright 2025 PaoPaoDev
-- Licensed under MIT

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- Helpers

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

-- Signal Class

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

-- Main Module

local PPDB = {}
PPDB.__index = PPDB

-- Options Helper

PPDB.DBOptions = {}
PPDB.DBOptions.__index = PPDB.DBOptions

function PPDB.DBOptions.new()
	return setmetatable({
		debug = false,
		migrations = {},
	}, PPDB.DBOptions)
end

-- Globals

local GLOBAL_CACHE = {}
local WRITE_QUEUE = {}
local MEMORY_QUEUE = MemoryStoreService:GetQueue("PPDB_GlobalInvalidation")
local MAX_RETRIES = 5
local RETRY_DELAY = 0.5
local INSTANCES = {}
local _boundToClose = false

-- Constructor

function PPDB.new(name: string, DBOptions: PPDB.DBOptions?)
	DBOptions = DBOptions or PPDB.DBOptions.new()

	local self = setmetatable({
		_name = name,
		_store = DataStoreService:GetDataStore(name),
		_loading = {}, -- Track loading states
		debug = DBOptions.debug or false,
		migrations = DBOptions.migrations or {},
		OnInit = Signal.new(),
		OnSave = Signal.new(),
		OnDelete = Signal.new(),
		OnInvalidate = Signal.new(),
	}, PPDB)

	-- TRUE shared global cache - all instances reference the same table
	if not GLOBAL_CACHE[name] then
		GLOBAL_CACHE[name] = {}
	end
	self._cache = GLOBAL_CACHE[name] -- Reference, not copy

	-- Bind to close
	INSTANCES[self] = true
	if not _boundToClose then
		_boundToClose = true
		game:BindToClose(function()
			local threads = {}
			for inst, _ in pairs(INSTANCES) do
				table.insert(threads, task.spawn(function()
					pcall(function()
						inst:flushWritesSync() -- Use synchronous flush on shutdown
					end)
				end))
			end
			-- Wait for all flushes to complete
			for _, thread in ipairs(threads) do
				while coroutine.status(thread) ~= "dead" do
					task.wait(0.1)
				end
			end
		end)
	end

	return self
end

-- Private Helpers

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

-- Non-blocking lock acquire with callback
function PPDB:_acquireLockAsync(key: string, callback: (boolean, string?) -> ())
	if RunService:IsStudio() then
		task.defer(callback, true, "studio-lock")
		return
	end

	local lockKey = self._name .. ":" .. key .. ":" .. HttpService:GenerateGUID(false)
	local attempts = 0
	local maxAttempts = 50 -- 5 seconds total (50 * 0.1s)

	local function tryAcquire()
		attempts += 1
		local ok = false
		pcall(function()
			MEMORY_QUEUE:AddAsync(lockKey, 10)
			ok = true
		end)

		if ok then
			callback(true, lockKey)
		elseif attempts < maxAttempts then
			task.delay(0.1, tryAcquire)
		else
			if self.debug then
				warn("[PPDB] Failed to acquire lock for key:", key)
			end
			callback(false, nil)
		end
	end

	tryAcquire()
end

-- Synchronous lock for shutdown scenarios
function PPDB:_acquireLockSync(key: string): (boolean, string?)
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

	if self.debug then
		warn("[PPDB] Failed to acquire lock for key:", key)
	end
	return false, nil
end

-- Core Methods

function PPDB:init(key: string, defaultData: table?, cb: ((boolean, any) -> ())?)
	-- Return cached immediately if available
	if self._cache[key] then
		if cb then
			task.defer(cb, true, self._cache[key])
		end
		return self._cache[key]
	end

	-- If already loading, queue the callback
	if self._loading[key] then
		if cb then
			if type(self._loading[key]) ~= "table" then
				self._loading[key] = {}
			end
			table.insert(self._loading[key], cb)
		end
		return defaultData -- Return default while loading
	end

	-- Start loading
	self._loading[key] = cb and { cb } or {}

	task.spawn(function()
		local ok, data = self:_retryOperation(function()
			return self._store:GetAsync(key)
		end)
		data = (ok and data) or defaultData or {}

		-- Ensure data is a table
		if type(data) ~= "table" then
			data = defaultData or {}
		end

		data._t = tick()

		-- Run migrations
		for index, migrate in ipairs(self.migrations) do
			if type(migrate) == "function" then
				local success, newData = pcall(migrate, deepCopy(data))
				if success and type(newData) == "table" then
					data = newData
				else
					if self.debug then
						warn(string.format("[PPDB Migration %d] failed for key %s: %s", index, key, tostring(newData)))
					end
				end
			end
		end

		self._cache[key] = data
		self.OnInit:Fire(key, data)

		-- Call all queued callbacks
		if self._loading[key] and type(self._loading[key]) == "table" then
			for _, callback in ipairs(self._loading[key]) do
				task.defer(callback, true, data)
			end
		end
		self._loading[key] = nil
	end)

	return defaultData
end

function PPDB:get(key: string, default: any?, ttl: number?)
	local cached = self._cache[key]
	if cached then
		-- Check TTL if specified
		if ttl and cached._t and tick() - cached._t > ttl then
			cached = nil
			self._cache[key] = nil
		else
			return cached
		end
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
	return data
end

function PPDB:set(key: string, value)
	if type(value) ~= "table" then
		warn("[PPDB] set() expected table value for key:", key)
		return false
	end
	value._t = tick()
	self._cache[key] = value
	self.OnSave:Fire(key, value)
	self:_scheduleWriteFlush(key)
	return true
end

function PPDB:update(key: string, fn)
	if type(fn) ~= "function" then
		return false
	end
	local cur = self:get(key, {})
	local new = fn(deepCopy(cur)) -- Pass a copy to prevent accidental mutation
	if new and type(new) == "table" then
		new._t = tick()
		return self:set(key, new)
	end
	return false
end

function PPDB:increment(key: string, field: string, amount: number?)
	amount = amount or 1
	return self:update(key, function(d)
		-- Validate field is number or nil
		if d[field] ~= nil and type(d[field]) ~= "number" then
			warn(string.format("[PPDB] Cannot increment non-number field '%s' in key '%s'", field, key))
			return d
		end
		d[field] = (d[field] or 0) + amount
		return d
	end)
end

-- Non-blocking write flush with async lock

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

		-- Non-blocking lock acquisition
		self:_acquireLockAsync(key, function(ok, lockKey)
			if not ok then
				WRITE_QUEUE[key] = nil
				return
			end

			-- Make a copy to avoid race conditions during save
			local dataToSave = deepCopy(data)

			local success, err = self:_retryOperation(function()
				self._store:SetAsync(key, dataToSave)
			end)

			if not success then
				warn("[PPDB] Write failed for key:", key, err)
			end

			WRITE_QUEUE[key] = nil
		end)
	end)
end

function PPDB:flushWrites()
	for key, _ in pairs(self._cache) do
		self:_scheduleWriteFlush(key)
	end
end

-- Synchronous flush for shutdown
function PPDB:flushWritesSync()
	for key, data in pairs(self._cache) do
		if data and not WRITE_QUEUE[key] then
			local ok, lockKey = self:_acquireLockSync(key)
			if ok then
				local success, err = self:_retryOperation(function()
					self._store:SetAsync(key, data)
				end)
				if not success and self.debug then
					warn("[PPDB] Shutdown flush failed for key:", key, err)
				end
			end
		end
	end
end

function PPDB:leave(key: string, callback: ((boolean) -> ())?)
	if not self._cache[key] then
		if callback then
			task.defer(callback, false)
		end
		return
	end

	task.spawn(function()
		self:_acquireLockAsync(key, function(ok, lockKey)
			if ok then
				local dataToSave = deepCopy(self._cache[key])
				local success, err = self:_retryOperation(function()
					self._store:SetAsync(key, dataToSave)
				end)

				if not success then
					warn("[PPDB] Leave flush failed for key:", key, err)
				end

				self._cache[key] = nil
				self.OnDelete:Fire(key)

				if callback then
					callback(success)
				end
			else
				if callback then
					callback(false)
				end
			end
		end)
	end)
end

-- Cache Cleanup

function PPDB:cleanCache(ttl: number?)
	ttl = ttl or 3600
	local cleaned = 0
	for k, v in pairs(self._cache) do
		if v and v._t and tick() - v._t > ttl then
			self._cache[k] = nil
			cleaned += 1
		end
	end
	if self.debug and cleaned > 0 then
		print(string.format("[PPDB] Cleaned %d expired cache entries", cleaned))
	end
	return cleaned
end

-- Auto cleanup (optional - call this once to enable)
function PPDB:enableAutoCleanup(interval: number?, ttl: number?)
	interval = interval or 300 -- 5 minutes
	ttl = ttl or 3600 -- 1 hour

	task.spawn(function()
		while true do
			task.wait(interval)
			self:cleanCache(ttl)
		end
	end)
end

-- Export / Import

function PPDB:export()
	return deepCopy(self._cache)
end

function PPDB:import(tbl: { [string]: any }, overwrite: boolean?)
	if type(tbl) ~= "table" then
		return false
	end
	local imported = 0
	for k, v in pairs(tbl) do
		if overwrite or self._cache[k] == nil then
			local value = type(v) == "table" and v or { value = v }
			if self:set(k, value) then
				imported += 1
			end
		end
	end
	return imported
end

-- Utility: Wait for key to be loaded
function PPDB:waitForKey(key: string, timeout: number?): any?
	timeout = timeout or 10
	local startTime = tick()

	while not self._cache[key] and tick() - startTime < timeout do
		task.wait(0.1)
	end

	return self._cache[key]
end

-- Utility: Check if key is currently loading
function PPDB:isLoading(key: string): boolean
	return self._loading[key] ~= nil
end

return PPDB

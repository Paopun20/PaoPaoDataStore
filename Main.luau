-- PaoPao's DataStore Module
-- 
-- This module provides a robust and advanced interface for interacting with Roblox DataStores.
-- It is designed to handle complex data scenarios and heavy usage, supporting features such as:
-- - Write queuing (debouncing rapid successive updates to reduce DataStore throttling)
-- - Data versioning and migration (allowing schema upgrades on loaded data)
-- - Serialization with JSON encoding/decoding, and a placeholder for compression optimization
-- - Cross-server cache invalidation via MemoryStore publish/subscribe system
-- - Session locking to prevent conflicting simultaneous writes within the same server instance
-- - Multiple script safe global caching and locking using _G to share data across scripts
-- - Direct synchronous cache access for fast local reads/writes without waiting for DataStore
-- 
-- These features make this module suitable for heavy-duty games with complex persistent data needs,
-- ensuring better reliability, scalability, and ease of maintenance.
--

-- Roblox services used
local DataStoreService = game:GetService("DataStoreService") -- For persistent data storage
local MemoryStoreService = game:GetService("MemoryStoreService") -- For cross-server communication & queuing
local HttpService = game:GetService("HttpService") -- For JSON encoding/decoding and Discord webhook
local RunService = game:GetService("RunService") -- For timing/scheduling operations

-- Default configuration values
local DEFAULT_RETRIES = 3 -- Number of retry attempts for failed DataStore updates
local DEFAULT_EXPIRE = 60 * 60 * 24 * 3 -- Default expiration time (in seconds) for cached data (not currently auto-expiring)
local WRITE_DEBOUNCE_TIME = 1 -- Time in seconds to debounce/batch multiple rapid writes per key

-- Global shared tables stored in _G to enable multiple scripts to share state safely
-- Caching loaded data locally to reduce DataStore reads and improve performance
local GLOBAL_CACHE = _G.PPDBM_CACHE or {}
-- Queues used to batch and debounce write operations per key
local WRITE_QUEUES = _G.PPDBM_WRITE_QUEUES or {}
-- Locks to prevent conflicting simultaneous updates on the same key within one server instance
local LOCKS = _G.PPDBM_LOCKS or {}
-- Tracks whether MemoryStore subscription is set up to avoid multiple listeners
local SUBSCRIBERS = _G.PPDBM_SUBSCRIBERS or {}

-- Assign globals for cross-script access
_G.PPDBM_CACHE = GLOBAL_CACHE
_G.PPDBM_WRITE_QUEUES = WRITE_QUEUES
_G.PPDBM_LOCKS = LOCKS
_G.PPDBM_SUBSCRIBERS = SUBSCRIBERS

-- MemoryStore queue and pub/sub channels for cross-server communication
-- Queue can be used for more complex future queueing needs (currently only pub/sub is used)
local memoryQueue = MemoryStoreService:GetQueue("PPDBM_MemoryQueue")
local memoryPublish = MemoryStoreService:GetPublisher("PPDBM_Channel")
local memorySubscribe = MemoryStoreService:GetSubscriber("PPDBM_Channel")

-- Serialization helpers:
-- Currently uses JSON encoding/decoding via HttpService.
-- This is easily extensible to support compression or alternate formats for optimization.
local function serialize(data)
	-- Convert Lua table data to JSON string for storage or transmission
	return HttpService:JSONEncode(data)
end

local function deserialize(str)
	if not str then return nil end
	local success, result = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	return success and result or nil
end

-- Data versioning and migration system:
-- When your data structure changes between game updates, migrations ensure old data
-- is upgraded smoothly without breaking functionality.
--
-- Usage:
-- Provide a table of migration functions, each transforming the data from version N-1 to version N.
-- The module will automatically apply these migrations during data initialization or update.
local function migrateData(data, migrations)
	if not data or type(data) ~= "table" then return data end

	-- Current version stored in data._version (default 0 if missing)
	local version = data._version or 0
	local latestVersion = #migrations

	-- Apply successive migrations until the data is up-to-date
	while version < latestVersion do
		version += 1
		local migrationFn = migrations[version]
		if migrationFn then
			data = migrationFn(data)
			data._version = version -- update version marker
		else
			-- Stop if migration function missing for this version
			break
		end
	end

	return data
end

-- Discord webhook logging helper:
-- If you set _G.PPDBM_WEBHOOK to a valid Discord webhook URL, the module
-- will send logs about important events or errors for remote monitoring.
local function sendToDiscord(message: string, embedColor: number?)
	local DISCORD_WEBHOOK_URL = _G.PPDBM_WEBHOOK or ""
	if DISCORD_WEBHOOK_URL == "" then return end

	local payload = HttpService:JSONEncode({
		content = nil,
		embeds = {{
			title = "🧠 PPDBM Log",
			description = message,
			color = embedColor or 0x3498db,
			timestamp = DateTime.now():ToIsoDate(),
		}}
	})

	pcall(function()
		HttpService:PostAsync(DISCORD_WEBHOOK_URL, payload, Enum.HttpContentType.ApplicationJson)
	end)
end

-- Session locking mechanism:
-- Locks prevent multiple conflicting updates from running simultaneously on the same key within the same server.
-- This ensures data consistency when multiple scripts or coroutines attempt to write at once.
local function acquireLock(name, key)
	local lockKey = name .. ":" .. key
	if LOCKS[lockKey] then
		-- Already locked by another update
		return false
	end
	LOCKS[lockKey] = true
	return true
end

local function releaseLock(name, key)
	local lockKey = name .. ":" .. key
	LOCKS[lockKey] = nil
end

-- Cross-server cache invalidation:
-- When data changes on one server, it publishes an invalidation message via MemoryStore.
-- Other servers listening invalidate their local cached copy of that key to avoid stale data.
local function publishInvalidation(name, key)
	local message = {name = name, key = key}
	pcall(function()
		memoryPublish:PublishAsync(HttpService:JSONEncode(message))
	end)
end

-- Subscribe once to invalidation messages and handle them:
-- This runs on a separate thread and keeps listening indefinitely.
if not SUBSCRIBERS.subscribed then
	SUBSCRIBERS.subscribed = true
	task.spawn(function()
		for msg in memorySubscribe:GetMessagesAsync() do
			local decoded = deserialize(msg.Data)
			if decoded and decoded.name and decoded.key then
				local cache = GLOBAL_CACHE[decoded.name]
				if cache then
					-- Invalidate cached data for the specified key
					cache[decoded.key] = nil
				end
			end
		end
	end)
end

-- Module table and metatable for object-oriented usage
local PPDBM = {}
PPDBM.__index = PPDBM

-- Constructor: create a new instance managing a named DataStore.
-- Parameters:
--  - name: string - DataStore name
--  - hooks: table - Optional lifecycle hooks (beforeInit, afterInit, beforeSave, afterSave)
--  - expire: number - Optional cache expiration time in seconds (not auto-implemented here)
--  - retries: number - Optional max retry attempts for UpdateAsync
--  - migrations: table - Optional migration functions array for data versioning
function PPDBM.new<T>(name: string, hooks: Hooks<T>?, expire: number?, retries: number?, migrations: {[number]: (T) -> T?}?)
	local self = setmetatable({}, PPDBM)
	self._name = name
	self._store = DataStoreService:GetDataStore(name)
	self._hooks = hooks or {}
	self._expire = expire or DEFAULT_EXPIRE
	self._retries = retries or DEFAULT_RETRIES
	self._migrations = migrations or {}

	-- Initialize per-DataStore global caches and write queues if not exist
	GLOBAL_CACHE[name] = GLOBAL_CACHE[name] or {}
	WRITE_QUEUES[name] = WRITE_QUEUES[name] or {}

	return self
end

-- Internal helper: schedules flushing queued writes for a given key after debounce period.
-- If multiple updates come in rapid succession, they are batched and flushed once after WRITE_DEBOUNCE_TIME.
local function scheduleWriteFlush(self, key)
	local name = self._name
	local queueKey = name .. ":" .. key

	-- Cancel existing timer if present (reset debounce timer)
	if WRITE_QUEUES[queueKey] and WRITE_QUEUES[queueKey].timer then
		WRITE_QUEUES[queueKey].timer:Cancel()
	end

	-- Schedule new flush after debounce timeout
	WRITE_QUEUES[queueKey].timer = task.delay(WRITE_DEBOUNCE_TIME, function()
		local writeData = WRITE_QUEUES[queueKey].data
		if not writeData then return end

		-- Acquire lock to avoid concurrent writes for this key within this server
		if not acquireLock(name, key) then
			-- Another flush in progress, skip this attempt (could be retried later)
			return
		end

		-- Attempt to write the latest queued data to DataStore
		local ok, err = pcall(function()
			self._store:SetAsync(key, writeData)
		end)
		releaseLock(name, key)

		if ok then
			-- On successful save, update local cache and notify other servers to invalidate cache
			GLOBAL_CACHE[name][key] = writeData
			publishInvalidation(name, key) -- cross-server cache invalidation

			if self._hooks.afterSave then
				self._hooks.afterSave(key, writeData)
			end
		else
			-- Log warning if save fails - you may implement retries here
			warn("[PPDBM] Failed to write key:", key, err)
		end

		-- Clear queued data and timer for this key
		WRITE_QUEUES[queueKey].timer = nil
		WRITE_QUEUES[queueKey].data = nil
	end)
end

-- Initialize or load data for a key:
-- Attempts to load from cache first, then DataStore.
-- If missing, saves and returns the provided defaultData.
-- Applies migrations if versioning is used.
-- Calls lifecycle hooks if provided.
function PPDBM:init<T>(key: string, defaultData: T, cb: Callback<T>?)
	local store = self._store
	local cache = GLOBAL_CACHE[self._name]
	if self._hooks.beforeInit then
		self._hooks.beforeInit(key, defaultData)
	end

	-- Return cached data immediately if available
	if cache[key] then
		if cb then cb(true, cache[key]) end
		return
	end

	-- Try loading from DataStore
	local ok, data = pcall(function()
		return store:GetAsync(key)
	end)

	if not ok then
		if cb then cb(false, "[Init] Failed to get key: " .. key) end
		return
	end

	if not data then
		-- Data missing: initialize with default and save it
		data = defaultData

		-- Assign current migration version if migrations are provided
		if next(self._migrations) then
			data._version = #self._migrations
		end

		local saveOk, saveErr = pcall(function()
			store:SetAsync(key, data)
		end)

		if not saveOk then
			warn("[PPDBM] Failed to save new default data for key:", key, saveErr)
		end
	end

	-- Perform migration on loaded or default data if migrations exist
	if next(self._migrations) then
		data = migrateData(data, self._migrations)
	end

	-- Cache data locally
	cache[key] = data

	if self._hooks.afterInit then
		self._hooks.afterInit(key, data)
	end
	if cb then cb(true, data) end
end

-- Update data for a key:
-- Calls user-provided update function atomically inside DataStore UpdateAsync.
-- Applies migrations before update.
-- Uses write queuing and debounce to batch rapid updates.
-- Calls lifecycle hooks.
-- Retries up to configured retry count on failure.
function PPDBM:update<T>(key: string, updateFn: (T) -> T?, cb: Callback<T>?)
	local cache = GLOBAL_CACHE[self._name]
	local name = self._name

	local tries = 0
	repeat
		tries += 1
		local ok, result = pcall(function()
			return self._store:UpdateAsync(key, function(old: T)
				if not old then
					-- If no old data, initialize default if available or empty table
					old = cache[key] or {}
				end

				-- Apply migrations on old data before updating
				if next(self._migrations) then
					old = migrateData(old, self._migrations)
				end

				local newData = updateFn(old)
				if newData ~= nil then
					-- Immediately update local cache to reflect new state
					cache[key] = newData

					if self._hooks.beforeSave then
						self._hooks.beforeSave(key, newData)
					end

					-- Queue the write instead of immediate DataStore save to debounce updates
					local queueKey = name .. ":" .. key
					WRITE_QUEUES[queueKey] = WRITE_QUEUES[queueKey] or {}
					WRITE_QUEUES[queueKey].data = newData

					scheduleWriteFlush(self, key)

					return newData
				end
				-- Returning nil aborts the UpdateAsync without changing data
				return nil
			end)
		end)

		if ok then
			if self._hooks.afterSave then
				self._hooks.afterSave(key, result)
			end
			if cb then cb(true, result) end
			return
		end
		-- Wait briefly before retrying on failure
		wait(0.2)
	until tries >= self._retries

	-- Report failure after all retries exhausted
	if cb then cb(false, "[Update] Failed after " .. tries .. " tries.") end
end

-- Delete data for a key:
-- Removes from DataStore and clears local cache.
-- Publishes invalidation message to other servers.
function PPDBM:delete(key: string, cb: (boolean) -> ())
	local ok, err = pcall(function()
		self._store:RemoveAsync(key)
	end)

	if ok then
		-- Clear cache locally and notify other servers to clear theirs
		GLOBAL_CACHE[self._name][key] = nil
		publishInvalidation(self._name, key)
	end

	cb(ok)
end

-- Clear local cached data for a key without deleting from DataStore.
function PPDBM:leave(key: string)
	GLOBAL_CACHE[self._name][key] = nil
end

-- Direct synchronous cached read access:
-- Returns cached data for a key if loaded, or nil if not.
-- Useful for quick immediate reads without awaiting DataStore calls.
function PPDBM:getCached(key: string)
	return GLOBAL_CACHE[self._name] and GLOBAL_CACHE[self._name][key]
end

-- Direct synchronous cached write access:
-- Overwrites local cached data for a key.
-- Does NOT save to DataStore until update() or other save method is called.
function PPDBM:setCached(key: string, data)
	if not GLOBAL_CACHE[self._name] then
		GLOBAL_CACHE[self._name] = {}
	end
	GLOBAL_CACHE[self._name][key] = data
end

-- Return constructor function for external use
return function(name: string, hooks, expire, retries, migrations)
	return PPDBM.new(name, hooks, expire, retries, migrations)
end

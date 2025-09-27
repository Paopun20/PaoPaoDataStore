-- PPDB.lua
--!strict
--!optimize 2
--!native
-- ============================================================================
-- PPDB – PaoPao's DataStore Module (refactored)
-- High-performance, caching, migration-friendly DataStore wrapper
-- Copyright 2025 PaoPaoDev
-- Licensed under Apache 2.0
-- ============================================================================

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PPDB = {}
PPDB.__index = PPDB

-- ==== Global shared state ====
local GLOBAL_CACHE = {}
local JSON_CACHE = {}
local WRITE_QUEUE = {}
local MEMORY_QUEUE = MemoryStoreService:GetQueue("PPDB_GlobalInvalidation")
local _boundToClose = false

-- ==== Signals ====
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end
function Signal:Connect(fn)
	table.insert(self._listeners, fn)
	local listeners = self._listeners
	local disconnected = false
	return {
		Disconnect = function()
			if disconnected then return end
			for i, v in ipairs(listeners) do
				if v == fn then
					table.remove(listeners, i)
					disconnected = true
					break
				end
			end
		end,
	}
end
function Signal:Fire(...)
	local copy = {}
	for i = 1, #self._listeners do
		copy[i] = self._listeners[i]
	end
	for _, fn in ipairs(copy) do
		task.spawn(fn, ...)
	end
end

-- ==== Helpers ====
local function _serialize(data)
	local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
	if not ok or json == nil then return "{}" end
	JSON_CACHE[json] = JSON_CACHE[json] or json
	return JSON_CACHE[json]
end

local function _deserialize(json)
	if not json then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	return ok and data or nil
end

local function _retryOperation(fn, retries, debug)
	retries = retries or 3
	local base = 0.5
	for i = 1, retries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		if debug then warn(string.format("Retry %d failed: %s", i, tostring(res))) end
		local waitTime = base * (2 ^ (i - 1)) * (0.9 + math.random() * 0.2)
		task.wait(waitTime)
	end
	return false, "Retry failed"
end

local function _migrateData(data: { [string]: any }, migrations: { [any] : ({ [string]: any }) -> { [string]: any | nil } })
	if type(data) ~= "table" or type(migrations) ~= "table" or #migrations == 0 then return data end
	data._version = data._version or 0
	local version = data._version
	while version < #migrations do
		version += 1
		local fn = migrations[version]
		if type(fn) ~= "function" then break end
		local ok, new = pcall(fn, data)
		if ok and type(new) == "table" then
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

	self.OnInit = Signal.new()
	self.OnSave = Signal.new()
	self.OnDelete = Signal.new()
	self.OnInvalidate = Signal.new()

	if not _boundToClose then
		_boundToClose = true
		game:BindToClose(function()
			for nm, _ in pairs(GLOBAL_CACHE) do
				-- optional flush logic for all caches
			end
		end)
	end

	return self
end

-- ==== Core Methods ====
function PPDB:init(key: string, defaultData: { [string]: any }?, cb: ((boolean, any) -> ())?)
	if self._cache[key] then if cb then cb(true, self._cache[key]) end return self._cache[key] end
	task.spawn(function()
		local ok, data = _retryOperation(function() return self._store:GetAsync(key) end, 3, self._debug)
		data = (ok and data) or defaultData or {}
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

	local ok, data = _retryOperation(function() return self._store:GetAsync(key) end, 3, self._debug)
	data = (ok and data) or default
	data = _migrateData(data, self._migrations)
	if type(data) ~= "table" then data = default or {} end
	data._t = tick()
	self._cache[key] = data
	self.OnInit:Fire(key, data)
	return data
end

function PPDB:set(key: string, value)
	if type(value) ~= "table" then warn("PPDB:set expected table value for key:", key) return end
	value._t = tick()
	self._cache[key] = value
	self:_scheduleWriteFlush(key)
end

function PPDB:update(key: string, fn)
	if type(fn) ~= "function" then return end
	local cur = self:get(key, {})
	local new = fn(cur)
	if new and type(new) == "table" then
		new._t = tick()
		self:set(key, new)
	end
end

function PPDB:increment(key: string, field: string, amount: number)
	amount = amount or 1
	self:update(key, function(d) d[field] = (d[field] or 0) + amount return d end)
end

function PPDB:leave(key: string)
	self:update(key, function(d) return d end)
	self:flushWrites()
	self._cache[key] = nil
	self.OnDelete:Fire(key)
end

function PPDB:cleanCache(ttl: number?)
	ttl = ttl or 3600
	for k, v in pairs(self._cache) do if v and v._t and tick() - v._t > ttl then self._cache[k] = nil end end
end

-- ==== Locks ====
function PPDB:_acquireLock(key: string)
    if RunService:IsStudio() then
        -- Studio bypass: always succeed
        return true, "studio-lock"
    end

    local lockKey = self._name .. ":" .. key .. ":" .. HttpService:GenerateGUID(false)
    local serializedData = _serialize(self, { lock = lockKey })
    if not serializedData then
        if self._debug then warn("Serialized data is nil for lockKey: ", lockKey) end
        return false, nil
    end

    local ok, result = _retryOperation(function()
        return MEMORY_QUEUE:AddAsync(serializedData, 10)
    end, 3, self._debug)

    if not ok and self._debug then warn("Failed to acquire lock for key: ", key, "Error: ", result) end
    return ok, lockKey
end

function PPDB:_releaseLock(lockKey: string)
    if RunService:IsStudio() then
        -- Studio bypass: nothing to remove
        return true
    end

    local ok, _ = _retryOperation(function()
        local item = MEMORY_QUEUE:ReadAsync(1, true, 10) -- Read the first item
        if item and item[1] then
            local data = _deserialize(item[1])
            if data and data.lock == lockKey then
                MEMORY_QUEUE:RemoveAsync() -- Remove the item
                return true
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

    task.spawn(function()
        local data = self._cache[key]
        if not data then
            WRITE_QUEUE[key] = nil
            return
        end

        local lockKey
        if RunService:IsStudio() then
            lockKey = "studio-lock" -- skip waiting
        else
            -- Wait up to 5s for lock
            local startTime = tick()
            repeat
                local ok
                ok, lockKey = self:_acquireLock(key)
                if ok then break end
                task.wait(0.1)
            until tick() - startTime > 5
        end

        if not lockKey then
            warn("Failed to acquire lock for key:", key)
            WRITE_QUEUE[key] = nil
            return
        end

        -- Save to DataStore
        local success, err = _retryOperation(function()
            self._store:SetAsync(key, data)
        end, 3, self._debug)

        -- Release lock
        self:_releaseLock(lockKey)

        if success then
            if not RunService:IsStudio() then
                MEMORY_QUEUE:AddAsync(_serialize({ name = self._name, key = key }), 60)
            end
            self.OnSave:Fire(key, data)
            self:_logToDiscord(("Saved key: %s"):format(key))
        else
            warn("Write failed for key:", key, err)
        end

        WRITE_QUEUE[key] = nil
    end)
end

function PPDB:flushWrites()
	for key, _ in pairs(self._cache) do self:_scheduleWriteFlush(key) end
end

-- ==== Export / Import ====
function PPDB:export() return _deserialize(_serialize(self._cache)) end
function PPDB:import(tbl: { [string]: any }, overwrite: boolean?)
	if type(tbl) ~= "table" then return end
	for k, v in pairs(tbl) do
		if overwrite or self._cache[k] == nil then
			self:set(k, type(v) == "table" and v or { value = v })
		end
	end
end

-- ==== Discord Logging ====
function PPDB:setWebhook(url: string) self.Webhook = url or "" end
function PPDB:sendToDiscord(enabled: boolean) self.enabledSTD = enabled and true or false end
function PPDB:_logToDiscord(message: string)
	if not self.enabledSTD or self.Webhook == "" then return end
	task.spawn(function()
		local ok, res = pcall(function()
			HttpService:PostAsync(self.Webhook, HttpService:JSONEncode({ content = message }), Enum.HttpContentType.ApplicationJson)
		end)
		if not ok and self._debug then warn("Discord log failed:", tostring(res)) end
	end)
end

return PPDB

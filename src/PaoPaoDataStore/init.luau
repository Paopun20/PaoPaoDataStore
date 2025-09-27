--!strict
--!optimize 2
--!native
-- ============================================================================
-- PPDB – PaoPao's DataStore Module
-- High-performance, caching, migration-friendly DataStore wrapper
-- ============================================================================

--[[ License ]]
--
--[[
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright 2025 PaoPaoDev (Roblox @Paopun20, ID 2045005611)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
]]

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
	if not json then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	return ok and data or nil
end

local function _retryOperation(fn, retries, debug)
	retries = retries or 3
	local base = 0.5
	for i = 1, retries do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if debug then
			warn(string.format("Retry %d failed: %s", i, tostring(res)))
		end
		task.wait(base * 2 ^ (i - 1) * (0.9 + math.random() * 0.2))
	end
	return false, "Retry failed"
end

local function _migrateData(
	data: { [string]: any },
	migrations: { [any]: ({ [string]: any }) -> { [string]: any | nil } }
): { [string]: any }
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
		if cb then
			cb(true, self._cache[key])
		end
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
		if cb then
			cb(true, data)
		end
	end)
	return nil
end

function PPDB:get(key: string, default: any?, ttl: number?)
	local cached = self._cache[key]
	if cached and ttl and cached._t and tick() - cached._t > ttl then
		cached = nil
	end
	if cached then
		return cached
	end

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
	self:update(key, function(d)
		return d
	end) -- Flush any pending writes
	self:flushWrites() -- Ensure all writes are flushed
	self._cache[key] = nil -- Clear from local server cache
	self.OnDelete:Fire(key) -- Fire delete event
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
		return MEMORY_QUEUE:AddAsync(_serialize({ lock = lockKey }), 10)
	end, 3, self._debug)
	return ok, lockKey
end

function PPDB:_releaseLock(lockKey: string)
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
	if WRITE_QUEUE[key] then
		return
	end
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
			MEMORY_QUEUE:AddAsync(_serialize({ name = self._name, key = key }), 60)
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
	if not self.enabledSTD or self.Webhook == "" then
		return
	end
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

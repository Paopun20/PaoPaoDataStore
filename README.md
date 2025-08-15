PaoPao's DataStore Module (PPDB)

A modern, intelligent, and scalable DataStore wrapper for Roblox.
Built for developers who want fast, safe, and cross-server synced data management — perfect for large-scale games.

---

Features:

- Write Queue        :  Debounces saves to prevent hitting Roblox DataStore limits.
- Cross-Server Sync  :  Uses MemoryStore to invalidate caches instantly across all servers.
- Data Migrations    :  Seamlessly update stored data structures between versions.
- Discord Webhooks   :  Optional instant error and status reporting.
- In-Memory Cache    :  Reduces DataStore calls for faster performance.
- Event Hooks        :  Run custom code before saving or after loading.
- Lock System        :  Prevents simultaneous writes that could corrupt data.

---

Installation:

1. Put the PaoPaoDataStore ModuleScript into ServerStorage or ReplicatedStorage.
2. Require it in your script:
```luau
   local PPDB = require(path.to.PaoPaoDataStore)
```
---

Basic Usage:

Create a DataStore:
```luau
   local PlayerData = PPDB.new("PlayerData", {
       migrations = {
           [1] = function(data)
               data.Coins = data.Coins or 0
               return data
           end,
       },
       retries = 3, -- Number of retries on save failure
       hooks = {
           beforeSave = function(key, data)
               print("Saving data for", key)
           end,
           afterLoad = function(key, data)
               print("Loaded data for", key)
           end,
       },
       expire = 3600, -- Optional expiration time in seconds
       debug  = true, -- Enable debug logging
   })
```
Initialize default data:
```luau
   PlayerData:init("player_123", {
       Coins = 0,
       Level = 1,
   })
```
Update data:
```luau
   PlayerData:update("player_123", function(old)
       old.Coins += 50
       return old
   end)
```
Delete data:
```luau
   PlayerData:delete("player_123", function(success)
       print("Deleted:", success)
   end)
```
Get cached data:
```luau
   local cached = PlayerData:getCached("player_123")
```
Remove from cache:
```luau
   PlayerData:leave("player_123")
```
---

Data Migration Example:
```luau
   local migrations = {
       [1] = function(data)
           data.Level = data.Level or 1
           return data
       end,
       [2] = function(data)
           data.Exp = 0
           return data
       end
   }

   local Store = PPDB.new("UserData", { migrations = migrations })
```
---

Discord Webhooks (Optional):
```luau
   local Store = PPDB.new("PlayerData")
   Store:setWebhook("https://discord.com/api/webhooks/...")
   Store:sendToDiscord(true)
```
---

Notes & Best Practices:

- Cross-server cache clearing is automatic.
- Saves within 1 second are merged to reduce write load.
- Use namespaced keys like "player_" .. UserId for organization.
- For large datasets, use batchUpdate to save multiple keys at once.

---

Contributing:
This project is open source — issues, ideas, and pull requests are welcome.

---

Make your Roblox game smarter — with cool module, PaoPao
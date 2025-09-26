# PPDS Setup Guide

PPDS (PaoPao's DataStore module) is a **ModuleScript** for Roblox that provides a high-performance, caching-friendly, migration-ready wrapper for DataStores.
It **must be used server-side** (e.g., inside `ServerScriptService`).

---

## Step 1: Get PPDS

### Option 1: Roblox Library

* Get the PPDS library model from the [Roblox Asset Library](https://www.roblox.com/library/95562270661505/).

### Option 2: GitHub

* Clone or download from the [PaoPaoDataStore repository](https://github.com/Paopun20/PaoPaoDataStore).

---

## Step 2: Install PPDS

1. Move the `PaoPaoDataStore` ModuleScript to `ServerScriptService` (or your preferred server-side location).
2. Optionally, rename it to `PPDS` for clarity.

---

## Step 3: Using PPDS in Your Scripts

```lua
-- Require PPDS in a server script
local PPDS = require(game.ServerScriptService.PPDS)

-- Create a new database
local myDB = PPDS.new("PlayerData", {
    debug = true,
    migrations = {
        function(data)
            data.coins = data.coins or 0
            return data
        end
    }
})

-- Initialize a player key
myDB:init("Player_12345", { coins = 0 }, function(success, data)
    if success then
        print("Loaded data:", data.coins)
    end
end)

-- Update data
myDB:increment("Player_12345", "coins", 50)
```

---

## Step 4: Optional Configuration

* **Webhooks / Discord Logging**

```lua
myDB:setWebhook("WEBHOOK_URL")
myDB:sendToDiscord(true)
```

* **Periodic Cache Cleaning**

```lua
myDB:cleanCache()
```

* **Flush All Writes on Demand**

```lua
myDB:flushWrites()
```

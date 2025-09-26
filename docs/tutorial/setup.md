# PPDB Setup Guide

PPDB (PaoPao's DataStore Module) is a **ModuleScript** for Roblox that provides a high-performance, caching-friendly, migration-ready wrapper for DataStores with cross-server synchronization.
It **must be used server-side** (e.g., inside `ServerScriptService`).

---

## Step 1: Get PPDB

### Option 1: Roblox Library
* Get the PPDB library model from the [Roblox Asset Library](https://www.roblox.com/library/95562270661505/).

### Option 2: GitHub
* Clone or download from the [PaoPaoDataStore repository](https://github.com/Paopun20/PaoPaoDataStore).

### Option 3: Direct Script
* Copy the PPDB source code into a new ModuleScript in Studio.

---

## Step 2: Install PPDB

1. **Place the Module**: Move the `PaoPaoDataStore` ModuleScript to `ServerScriptService` (or your preferred server-side location).
2. **Rename (Optional)**: Rename it to `PPDB` for clarity.
3. **Verify Location**: Ensure it's accessible from your server scripts.

```
ServerScriptService/
├── PPDB (ModuleScript)
├── PlayerManager (Server Script)
└── GameLogic (Server Script)
```

---

## Step 3: Basic Usage

### Simple Setup

```luau
-- Require PPDB in a server script
local PPDB = require(game.ServerScriptService.PPDB)

-- Create a new database instance
local playerDB = PPDB.new("PlayerData", {
    debug = true -- Enable debug logging during development
})

-- Basic player data structure
local defaultPlayerData = {
    coins = 0,
    level = 1,
    inventory = {},
    stats = {
        gamesPlayed = 0,
        totalPlayTime = 0
    }
}
```

### Player Join/Leave Handling

```luau
local Players = game:GetService("Players")

-- When player joins
Players.PlayerAdded:Connect(function(player)
    local key = "Player_" .. player.UserId
    
    -- Initialize player data
    playerDB:init(key, defaultPlayerData, function(success, data)
        if success then
            print("Player", player.Name, "loaded with", data.coins, "coins")
            
            -- Set player attributes for easy access
            player:SetAttribute("Coins", data.coins)
            player:SetAttribute("Level", data.level)
            player:SetAttribute("DataLoaded", true)
        else
            warn("Failed to load data for", player.Name)
            player:Kick("Failed to load your data. Please rejoin.")
        end
    end)
end)

-- When player leaves
Players.PlayerRemoving:Connect(function(player)
    local key = "Player_" .. player.UserId
    
    -- Save and cleanup player data
    playerDB:leave(key)
    print("Saved data for", player.Name)
end)
```

---

## Step 4: Advanced Features

### Data Migration Setup

Handle data structure changes over time:

```luau
local migrations = {
    -- Version 1: Add inventory system
    function(data)
        if not data.inventory then
            data.inventory = {}
        end
        return data
    end,
    
    -- Version 2: Restructure stats
    function(data)
        if data.kills and not data.stats then
            data.stats = {
                kills = data.kills,
                deaths = data.deaths or 0,
                gamesPlayed = 0
            }
            -- Remove old fields
            data.kills = nil
            data.deaths = nil
        end
        return data
    end,
    
    -- Version 3: Add new currency system
    function(data)
        if not data.premium_currency then
            data.premium_currency = 0
        end
        return data
    end
}

local playerDB = PPDB.new("PlayerData", {
    debug = false, -- Disable in production
    migrations = migrations
})
```

### Event Monitoring

```luau
-- Monitor data operations
playerDB.OnInit:Connect(function(key, data)
    print("📥 Data loaded for", key)
end)

playerDB.OnSave:Connect(function(key, data)
    print("💾 Data saved for", key)
end)

playerDB.OnDelete:Connect(function(key)
    print("🗑️ Cache cleared for", key)
end)
```

---

## Step 5: Common Operations

### Safe Data Updates

```luau
-- Award coins safely
local function awardCoins(player, amount)
    local key = "Player_" .. player.UserId
    
    playerDB:update(key, function(data)
        data.coins = (data.coins or 0) + amount
        data.stats.totalEarned = (data.stats.totalEarned or 0) + amount
        return data
    end)
    
    -- Update player attribute
    local newCoins = playerDB:get(key, defaultPlayerData).coins
    player:SetAttribute("Coins", newCoins)
end

-- Purchase system
local function purchaseItem(player, itemName, cost)
    local key = "Player_" .. player.UserId
    local success = false
    
    playerDB:update(key, function(data)
        if data.coins >= cost then
            data.coins = data.coins - cost
            table.insert(data.inventory, itemName)
            success = true
            return data
        end
        return nil -- Cancel transaction
    end)
    
    return success
end
```

### Leaderboard Data

```luau
-- Create a separate database for global stats
local leaderboardDB = PPDB.new("GlobalStats", { debug = false })

-- Update global leaderboard
local function updateLeaderboard(player, score)
    local key = "Leaderboard_" .. player.UserId
    
    leaderboardDB:update(key, function(data)
        if not data or score > (data.bestScore or 0) then
            return {
                playerName = player.Name,
                bestScore = score,
                timestamp = os.time()
            }
        end
        return data
    end)
end
```

---

## Step 6: Production Configuration

### Discord Webhook Monitoring

```luau
-- Set up Discord logging for production
if game.PlaceId == YOUR_PRODUCTION_PLACE_ID then
    playerDB:setWebhook("https://discord.com/api/webhooks/YOUR_WEBHOOK_URL")
    playerDB:sendToDiscord(true)
end
```

### Automatic Cache Management

```luau
-- Periodic cache cleanup
task.spawn(function()
    while true do
        task.wait(300) -- Every 5 minutes
        playerDB:cleanCache()
        print("🧹 Cache cleaned")
    end
end)
```

### Server Shutdown Handling

```luau
-- Ensure data saves on server shutdown
game:BindToClose(function()
    print("🛑 Server shutting down, saving all data...")
    
    -- Force save all cached data
    playerDB:flushWrites()
    
    -- Wait for saves to complete
    task.wait(3)
    
    print("✅ All data saved successfully")
end)
```

---

## Step 7: Testing and Debugging

### Development Mode Setup

```luau
-- Enable debug mode during development
local IS_DEVELOPMENT = game.PlaceId ~= YOUR_PRODUCTION_PLACE_ID

local playerDB = PPDB.new("PlayerData", {
    debug = IS_DEVELOPMENT,
    migrations = migrations
})

-- Test data export/import
if IS_DEVELOPMENT then
    -- Export current cache for debugging
    local snapshot = playerDB:export()
    print("Cache snapshot:", snapshot)
    
    -- Load test data
    local testData = {
        ["TestPlayer"] = { coins = 1000, level = 10 }
    }
    playerDB:import(testData, false)
end
```

### Error Handling

```luau
-- Robust error handling
local function safePlayerInit(player)
    local key = "Player_" .. player.UserId
    
    playerDB:init(key, defaultPlayerData, function(success, data)
        if success then
            -- Success path
            player:SetAttribute("DataLoaded", true)
            setupPlayerUI(player, data)
        else
            -- Error path
            warn("Failed to load data for", player.Name)
            
            -- Try to load with GET as fallback
            local fallbackData = playerDB:get(key, defaultPlayerData)
            if fallbackData then
                player:SetAttribute("DataLoaded", true)
                setupPlayerUI(player, fallbackData)
            else
                player:Kick("Unable to load your data. Please try again.")
            end
        end
    end)
end
```

---

## Step 8: Performance Tips

### Optimize Data Structure

```luau
-- Good: Flat structure for frequently accessed data
local playerData = {
    coins = 1000,           -- Direct access
    level = 5,              -- Direct access
    lastLogin = os.time(),  -- Direct access
    settings = {            -- Group related data
        music = true,
        notifications = false
    }
}

-- Avoid: Deep nesting for frequently accessed data
local badPlayerData = {
    stats = {
        currency = {
            coins = {
                amount = 1000  -- Too deep!
            }
        }
    }
}
```

### Batch Operations

```luau
-- Batch multiple updates into one operation
playerDB:update(key, function(data)
    -- Multiple changes in single update
    data.coins = data.coins + reward
    data.experience = data.experience + expGain
    data.stats.gamesPlayed = data.stats.gamesPlayed + 1
    data.lastLogin = os.time()
    return data
end)
```

---

## Common Issues and Solutions

### Issue: "DataStore request was throttled"
**Solution**: PPDB handles retries automatically, but avoid calling operations too frequently.

### Issue: Data not saving on server shutdown
**Solution**: Ensure `game:BindToClose()` calls `flushWrites()` with adequate wait time.

### Issue: Memory usage growing over time
**Solution**: Call `cleanCache()` periodically and use `leave()` when players disconnect.

### Issue: Data corruption across servers
**Solution**: PPDB's cross-server locking handles this automatically.

---

## Next Steps

1. **Start Simple**: Begin with basic player data storage
2. **Add Migrations**: Plan for future data structure changes
3. **Monitor Performance**: Use Discord webhooks to track issues
4. **Scale Gradually**: Add more complex features as needed
5. **Test Thoroughly**: Always test with multiple players and servers

For detailed API documentation, see the [PPDB API Reference](`./../../reference/api`).
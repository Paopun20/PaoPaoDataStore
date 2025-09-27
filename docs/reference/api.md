# PPDS API Reference

**PPDS (PaoPao's DataStore Module)** - A high-performance, caching, migration-friendly DataStore wrapper with cross-server synchronization.

---

## Overview

PPDS provides a robust caching layer over Roblox DataStore with advanced features:

- **Global shared cache** across all instances
- **Cross-server lock mechanisms** for data safety
- **Automatic migration system** for data structure updates
- **Event-driven architecture** with signals
- **Exponential backoff retry logic**
- **Discord webhook integration** for monitoring

---

## Getting Started

### Basic Setup

```luau title="Basic Setup"
local PPDS = require(path.to.PPDS)

-- Create a database instance
local db = PPDS.new("PlayerData", {
    debug = true,
    migrations = {} -- Optional migration functions
})
```

### Quick Example

```luau title="Quick Example"
-- Initialize player data
db:init("Player_12345", { coins = 0, level = 1 }, function(success, data)
    if success then
        print("Player loaded:", data.coins, "coins")
    end
end)

-- Update data safely
db:update("Player_12345", function(data)
    data.coins = data.coins + 100
    return data
end)
```

---

## Constructor

### **PPDS.new(name, opts)**

Creates a new database instance with global cache sharing.

**Parameters:**

- `name` _(string)_: DataStore name - multiple instances with same name share cache
- `opts` _(table, optional)_:
  - `debug` _(boolean)_: Enable debug logging
  - `migrations` _(array of functions)_: Migration functions for data versioning

**Returns:** PPDS instance with event signals and automatic cleanup

**Features:**

- Automatic `game:BindToClose()` handler for data flushing
- Global cache shared across all instances with same name
- Built-in event signals for monitoring operations

```luau title="Migrations Example"
local playerDB = PPDS.new("PlayerData", {
    debug = true,
    migrations = {
        -- Version 1: Add inventory system
        function(data)
            if not data.inventory then
                data.inventory = {}
                data._version = 1
            end
            return data
        end,
        -- Version 2: Restructure stats
        function(data)
            if data.kills and not data.stats then
                data.stats = { kills = data.kills }
                data.kills = nil
                data._version = 2
            end
            return data
        end
    }
})
```

---

## Core Data Operations

### Loading and Initialization

#### **PPDS:init(key, defaultData, callback)**

Asynchronously initializes a key with default data if not exists.

**Parameters:**

- `key` _(string)_: The data key to initialize
- `defaultData` _(table)_: Default data structure
- `callback` _(function, optional)_: `(success: boolean, data: table) -> ()`

**Returns:**

- Cached data immediately if available
- `nil` if loading asynchronously

**Behavior:**

- Returns cached data instantly if already loaded
- Spawns async task for DataStore loading
- Applies migrations automatically
- Fires `OnInit` event

```luau title="Init Example"
-- Immediate return if cached
local cachedData = db:init("Player_12345", defaultPlayerData)
if cachedData then
    print("Data was already cached")
end

-- Async callback for new loads
db:init("Player_67890", defaultPlayerData, function(success, data)
    if success then
        print("Player loaded with", data.coins, "coins")
        -- Safe to use data here
    else
        warn("Failed to load player data")
    end
end)
```

#### **PPDS:get(key, default)**

Synchronously fetches data from cache or DataStore with fallback.

**Parameters:**

- `key` _(string)_: Data key to retrieve
- `default` _(any)_: Fallback value if key doesn't exist or load fails

**Returns:** Data from cache/DataStore or default value

**Behavior:**

- Instant return if data is cached
- Synchronous DataStore call if not cached (may yield)
- Applies migrations before returning
- Caches result for future calls

```luau title="Get Example"
-- Get with fallback
local playerData = db:get("Player_12345", { coins = 0, level = 1 })

-- Always returns something
local config = db:get("ServerConfig", {
    maxPlayers = 50,
    difficulty = "normal"
})
```

### Writing Data

#### **PPDS:set(key, value)**

Immediately updates cache and schedules async DataStore write.

**Parameters:**

- `key` _(string)_: Data key to update
- `value` _(table)_: New data to store

**Behavior:**

- Updates cache immediately (instant)
- Schedules DataStore write after 1-second delay
- Uses cross-server locking for safety
- Fires `OnSave` event on successful write

```luau title="Set Example"
-- Immediate cache update, async save
db:set("Player_12345", {
    coins = 500,
    level = 5,
    inventory = {"sword", "potion"},
    lastLogin = os.time()
})
```

#### **PPDS:update(key, fn)**

Safely updates data using a transformation function.

**Parameters:**

- `key` _(string)_: Data key to update
- `fn` _(function)_: `(currentData: table) -> newData: table`

**Behavior:**

- Gets current data (loads if needed)
- Applies transformation function
- Sets result if function returns non-nil

```luau title="Update Example"
-- Safe concurrent updates
db:update("Player_12345", function(data)
    -- This is safe from race conditions
    data.coins = data.coins + 100
    data.stats.gamesPlayed = (data.stats.gamesPlayed or 0) + 1
    data.lastPlayed = os.time()
    return data
end)

-- Conditional updates
db:update("Player_12345", function(data)
    if data.coins >= 100 then
        data.coins = data.coins - 100
        table.insert(data.inventory, "premium_item")
        return data
    end
    -- Return nil to cancel update
    return nil
end)
```

#### **PPDS:increment(key, field, amount)**

Atomically increments a numeric field within a data structure.

**Parameters:**

- `key` _(string)_: Data key containing the field
- `field` _(string)_: Numeric field name to increment
- `amount` _(number)_: Amount to add (negative for subtraction)

```luau title="Increment Example"
-- Add currency
db:increment("Player_12345", "coins", 50)

-- Subtract health
db:increment("Player_12345", "health", -10)

-- Track statistics
db:increment("ServerStats", "totalLogins", 1)
```

---

## Session Management

### **PPDS:leave(key)**

Immediately saves data and removes from cache for cleanup.

**Use Case:** Call when players leave to ensure data persistence and free memory.

**Parameters:**

- `key` _(string)_: Data key to save and remove

**Behavior:**

- Forces immediate save to DataStore
- Removes from cache to free memory
- Fires `OnDelete` event

```luau title="Leave Example"
-- Proper player cleanup
game.Players.PlayerRemoving:Connect(function(player)
    local key = "Player_" .. player.UserId
    db:leave(key)
end)
```

---

## Advanced Features

### Cross-Server Data Safety

PPDS implements cross-server locks using MemoryStoreService to prevent data corruption:

```luau title="Locking Example"
-- Automatic locking (internal)
function PPDS:_acquireLock(key)
    local lockKey = self._name .. ":" .. key
    -- Attempts to acquire distributed lock
    -- Prevents simultaneous writes across servers
end
```

**Benefits:**

- Prevents data loss from concurrent writes
- Ensures data consistency across servers
- Automatic retry with exponential backoff

### Migration System

Handle data structure changes gracefully:

```luau title="Migration Example"
local migrations = {
    [1] = function(data)
        -- Version 1: Add new fields
        data.newField = "defaultValue"
        return data
    end,
    [2] = function(data)
        -- Version 2: Restructure existing data
        if data.oldStructure then
            data.newStructure = transformOldStructure(data.oldStructure)
            data.oldStructure = nil
        end
        return data
    end
}

local db = PPDS.new("PlayerData", { migrations = migrations })
```

**Migration Features:**

- Automatic version tracking (`data._version`)
- Sequential migration application
- Error-safe migration (fails gracefully)
- Applied on every data load

---

## Cache Management

### **PPDS:cleanCache()**

Removes expired entries from memory cache.

**Behavior:**

- Checks each cached entry for expiration timestamp
- Removes entries older than 1 hour (3600 seconds)
- Frees memory for active data

```luau title="Clean Cache Example"
-- Periodic cache cleanup
task.spawn(function()
    while true do
        task.wait(300) -- Every 5 minutes
        db:cleanCache()
    end
end)
```

### **PPDS:flushWrites()**

Forces immediate save of all cached data to DataStore.

**Use Case:** Critical save points, server shutdown, debugging

```luau title="Flush Writes Example"
-- Emergency save all data
game:BindToClose(function()
    db:flushWrites()
    task.wait(3) -- Allow time for saves to complete
end)
```

---

## Event System

PPDS provides event signals for monitoring and integration:

### Available Events

#### **OnInit**

Fired when data is loaded/initialized.

```luau title="OnInit Example"
db.OnInit:Connect(function(key, data)
    print("Data loaded for", key)
    -- Update UI, trigger game logic, etc.
end)
```

#### **OnSave**

Fired when data is successfully saved to DataStore.

```luau title="OnSave Example"
db.OnSave:Connect(function(key, data)
    print("Data saved for", key)
    -- Log successful saves, update metrics
end)
```

#### **OnDelete**

Fired when data is removed from cache.

```luau title="OnDelete Example"
db.OnDelete:Connect(function(key)
    print("Cache cleared for", key)
    -- Cleanup related resources
end)
```

#### **OnInvalidate**

Fired when data should be refreshed (cross-server sync).

```luau title="OnInvalidate Example"
db.OnInvalidate:Connect(function(key)
    print("Data invalidated for", key)
    -- Refresh UI, reload data
end)
```

---

## Development Tools

### Data Export/Import

#### **PPDS:export()**

Creates a deep copy snapshot of current cache.

**Returns:** Complete cache data as Lua table

**Use Cases:**

- Creating development snapshots
- Debugging data states
- Backup creation

```luau title="Export Example"
local snapshot = db:export()
print("Cached entries:", #snapshot)

-- Save snapshot for later use
local backupData = db:export()
```

#### **PPDS:import(tbl, overwrite)**

Loads data from table into cache.

**Parameters:**

- `tbl` _(table)_: Data to import
- `overwrite` _(boolean)_: Replace existing cache entries

```luau title="Import Example"
-- Load test data for development
local testData = {
    ["TestPlayer1"] = { coins = 1000, level = 10 },
    ["TestPlayer2"] = { coins = 500, level = 5 }
}
db:import(testData, false) -- Don't overwrite existing

-- Restore from backup
db:import(backupSnapshot, true) -- Overwrite existing data
```

---

## Discord Integration

### **PPDS:setWebhook(url)**

Configures Discord webhook URL for logging.

```luau title="Set Webhook Example"
db:setWebhook("https://discord.com/api/webhooks/your-webhook-url")
```

### **PPDS:sendToDiscord(enabled)**

Enables/disables Discord logging.

```luau title="Discord Logging Example"
-- Enable for production monitoring
db:sendToDiscord(true)

-- Disable for development
db:sendToDiscord(false)
```

---

## Best Practices

### Error Handling and Resilience

```luau title="Error Handling Example"
-- Always handle init callbacks
db:init("Player_" .. player.UserId, defaultData, function(success, data)
    if not success then
        -- Handle failure gracefully
        warn("Failed to load player data, using defaults")
        player:SetAttribute("DataLoaded", false)
        return
    end

    player:SetAttribute("DataLoaded", true)
    -- Proceed with game logic
end)
```

### Safe Concurrent Operations

```luau title="Safe Update Example"
-- Use update() for race-condition safety
db:update("Player_12345", function(data)
    -- This entire block is atomic
    if data.coins >= cost then
        data.coins = data.coins - cost
        table.insert(data.inventory, item)
        return data -- Apply changes
    end
    return nil -- Cancel if insufficient funds
end)
```

### Memory Management

```luau title="Memory Management Example"
-- Proper cleanup on player leave
game.Players.PlayerRemoving:Connect(function(player)
    db:leave("Player_" .. player.UserId)
end)

-- Periodic cache maintenance
task.spawn(function()
    while true do
        task.wait(600) -- Every 10 minutes
        db:cleanCache()
    end
end)
```

### Production Monitoring

```luau title="Monitoring Example"
-- Set up monitoring
db:setWebhook(DISCORD_WEBHOOK_URL)
db:sendToDiscord(true)

-- Track important events
db.OnSave:Connect(function(key, data)
    -- Log successful saves for monitoring
    analytics:trackEvent("DataSaved", { key = key })
end)

db.OnInit:Connect(function(key, data)
    -- Track data loads
    analytics:trackEvent("DataLoaded", { key = key })
end)
```

---

## Technical Implementation Notes

### Global Cache Architecture

- Cache is shared across all PPDS instances with the same name
- Enables consistent data access patterns
- Reduces memory usage in multi-instance scenarios

### Retry Logic

- Exponential backoff with jitter (0.5s base, up to ~4s)
- Default 3 retries for most operations
- Prevents thundering herd problems

### Cross-Server Synchronization

- Uses MemoryStoreService queues for coordination
- Implements distributed locking for write safety
- Broadcasts invalidation events across servers

### Performance Optimizations

- JSON caching prevents redundant serialization
- Delayed write batching reduces DataStore calls
- Automatic cache expiration manages memory usage

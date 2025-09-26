# PaoPao's DataStore Module (PPDB)

PPDB is a high-performance Roblox DataStore wrapper that simplifies the management of persistent data with advanced caching, cross-server synchronization, and migration capabilities. It is designed to be robust, efficient, and developer-friendly, allowing you to focus on creating engaging gameplay experiences without worrying about the complexities of data storage.

## How It Works

PPDB provides a sophisticated caching layer over Roblox DataStores with cross-server coordination. It loads and caches data from DataStores on each server while maintaining consistency across multiple servers through distributed locking and cache invalidation powered by **MemoryStoreService**.

### Core Architecture

**Global Shared Cache**: PPDB instances with the same name share a global cache, reducing memory usage and improving performance across your codebase.

**Cross-Server Safety**: Uses MemoryStore-based distributed locking to prevent data corruption when multiple servers access the same data simultaneously.

**Smart Write Batching**: Changes are applied to cache immediately for instant access, then written to DataStore asynchronously with automatic retry logic and exponential backoff.

**Event-Driven Design**: Built-in signals (`OnInit`, `OnSave`, `OnDelete`, `OnInvalidate`) allow you to monitor and respond to data operations in real-time.

## Key Features

### **High Performance**

- Instant cache access for loaded data
- Batched writes reduce DataStore API calls
- Exponential backoff retry logic with jitter
- JSON serialization caching for optimization

### **Cross-Server Safety**

- Distributed locking prevents data corruption
- Automatic cache invalidation across servers
- Race condition protection for concurrent updates
- Safe player server-hopping support

### **Developer Experience**

- Familiar API similar to native DataStore
- Comprehensive event system for monitoring
- Built-in debugging and logging capabilities
- Discord webhook integration for production monitoring

### **Scalability**

- Global cache sharing reduces memory overhead
- Automatic cache expiration and cleanup
- Supports both player and global data patterns
- Handles high-frequency operations efficiently

### **Migration System**

- Automatic data structure versioning
- Sequential migration application
- Error-safe migration handling
- Seamless updates without data loss

## Use Cases

PPDB is perfect for:

- **Player Data**: Coins, levels, inventory, settings, statistics
- **Guild/Team Data**: Shared resources, rankings, collective progress
- **Global Systems**: Economy data, server statistics, configuration
- **Session Data**: Temporary data that needs cross-server persistence

### Example: Player Data Management

```luau
local PPDB = require(game.ServerScriptService.PPDB)

-- Create database with migration support
local playerDB = PPDB.new("PlayerData", {
    debug = true,
    migrations = {
        function(data)
            -- Add inventory system
            data.inventory = data.inventory or {}
            return data
        end
    }
})

-- Handle player joining
game.Players.PlayerAdded:Connect(function(player)
    local key = "Player_" .. player.UserId

    playerDB:init(key, {
        coins = 0,
        level = 1,
        inventory = {}
    }, function(success, data)
        if success then
            player:SetAttribute("Coins", data.coins)
            print("Player loaded:", data.coins, "coins")
        end
    end)
end)

-- Safe currency updates
local function awardCoins(player, amount)
    playerDB:update("Player_" .. player.UserId, function(data)
        data.coins = data.coins + amount
        return data
    end)
end

-- Cleanup on leave
game.Players.PlayerRemoving:Connect(function(player)
    playerDB:leave("Player_" .. player.UserId)
end)
```

## Architecture Benefits

### Traditional DataStore Issues

❌ **IDK**: Yes, DataStore can be tricky

### PPDB Solutions

✅ **Automatic retries** with exponential backoff and retry maximums is 3, 2 is not enough, 4 is too much
✅ **Cross-server safety** with distributed locking and cache invalidation
✅ **Instant cache access** for loaded data
✅ **Event-driven** architecture for real-time monitoring
✅ **DataStore limits**: PPDB abstracts away DataStore limits and automatically handles retries.
✅ **Data corruption**: PPDB uses cross-server locking to prevent data corruption.
✅ **Complex migrations**: PPDB provides a robust migration system to handle data structure changes.
✅ **Manual caching**: PPDB handles caching automatically, reducing boilerplate code.
✅ **Server shutdowns**: PPDB ensures all data is saved before server shutdown.

## Performance Characteristics

- **Cache Hits**: Instant access (0ms latency)
- **Cache Misses**: Single DataStore call with retry logic
- **Writes**: Immediate cache update + async DataStore save
- **Cross-Server Sync**: Sub-second invalidation via MemoryStore
- **Memory Usage**: Shared global cache with automatic cleanup

## Production Ready

PPDB includes enterprise-grade features:

- **Discord Webhook Integration**: Real-time monitoring and alerts
- **Comprehensive Logging**: Debug modes and operation tracking
- **Automatic Cleanup**: Memory management and cache expiration
- **Graceful Shutdown**: Ensures all data saves before server close
- **Error Recovery**: Robust handling of network and API failures

## Getting Started

1. **Install**: Place PPDB ModuleScript in ServerScriptService
2. **Create**: Instantiate database with `PPDB.new()`
3. **Initialize**: Load data with `init()` or `get()`
4. **Update**: Safely modify with `update()` or `set()`
5. **Monitor**: Connect to events for real-time insights

```luau
local PPDB = require(game.ServerScriptService.PPDB)
local db = PPDB.new("MyData", { debug = true })

-- Load data
db:init("Player_123", { score = 0 }, function(success, data)
    print("Loaded:", data.score)
end)

-- Update safely
db:update("Player_123", function(data)
    data.score = data.score + 100
    return data
end)
```

## Advanced Features

### Event System

```luau
db.OnSave:Connect(function(key, data)
    print("💾 Saved:", key)
end)

db.OnInit:Connect(function(key, data)
    print("📥 Loaded:", key)
end)
```

### Migration Example

```luau
local migrations = {
    function(data)
        -- V1: Add new field
        data.newField = "default"
        return data
    end,
    function(data)
        -- V2: Restructure data
        if data.oldFormat then
            data.newFormat = transform(data.oldFormat)
            data.oldFormat = nil
        end
        return data
    end
}
```

### Production Monitoring

```luau
db:setWebhook("https://discord.com/api/webhooks/...")
db:sendToDiscord(true)
```

## When NOT to Use PPDB

PPDB is optimized for structured, persistent data storage. Consider alternatives for:

- **Real-time leaderboards**: Use OrderedDataStore directly
- **Highly volatile data**: Frequent changes may overwhelm the system
- **Client-side data**: PPDB is server-only
- **Temporary session data**: Consider regular variables or attributes

## Contributing

PPDB is open for contributions! Whether you have ideas for improvements, bug fixes, or new features, we welcome your input:

- 🐛 **Report Issues**: Found a bug? Open an issue with detailed reproduction steps
- 💡 **Feature Requests**: Have an idea? Share it in the discussions
- 🔧 **Pull Requests**: Ready to contribute code? Submit a PR with tests
- 📚 **Documentation**: Help improve docs and examples

Visit the [GitHub repository](https://github.com/Paopun20/PaoPaoDataStore) to get involved!

## License

PPDB is released under the **Apache License 2.0**. This permissive license allows you to use, modify, and distribute PPDB in both personal and commercial projects.

See the [LICENSE](https://raw.githubusercontent.com/Paopun20/PaoPaoDataStore/main/LICENSE) file for complete details.

---

> **Note**: PPDB represents a production-ready DataStore solution with enterprise features. While the API is stable, we continuously improve performance and add features based on community feedback.

> **Note 2 (A Very Important!):** some api changes may occur in the future, so please check back regularly for updates, not 100% guaranteed that the api will not change, but i will try to keep it stable.

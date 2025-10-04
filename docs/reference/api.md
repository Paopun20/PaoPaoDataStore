# PPDS API Reference

**PPDS (PaoPao's DataStore Module)** – A high-performance, caching, migration-friendly DataStore wrapper with cross-server synchronization.

---

## Overview

PPDS provides a robust caching layer over Roblox DataStore with advanced features:

* **Global shared cache** across all instances
* **Cross-server lock mechanisms** for data safety
* **Automatic migration system** for data structure updates
* **Event-driven architecture** with signals
* **Exponential backoff retry logic**

---

## Getting Started

### Basic Setup

```lua
local PPDS = require(path.to.PPDS)

-- Create DBOptions object
local options = PPDS.DBOptions.new()
options.debug = true

-- Create a database instance
local db = PPDS.new("PlayerData", options)
```

### Quick Example

```lua
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

### **PPDS.new(name, DBOptions)**

Creates a new database instance with global cache sharing.

**Parameters:**

* `name` *(string)* – DataStore name – multiple instances with same name share cache
* `DBOptions` *(PPDS.DBOptions, optional)*:

  * `debug` *(boolean)*: Enable debug logging

**Returns:** PPDS instance with event signals and automatic cleanup

**Example:**

```lua
-- Create a new database instance with DBOptions
local options = PPDS.DBOptions.new()
options.debug = true

local db = PPDS.new("PlayerData", options)
```

---

## Core Data Operations

### **PPDS:init(key, defaultData, callback)**

Asynchronously initializes a key with default data if not exists.

**Parameters:**

* `key` *(string)* – The data key to initialize
* `defaultData` *(table)* – Default data structure
* `callback` *(function, optional)* – `(success: boolean, data: table) -> ()`

**Returns:** Cached data immediately if available; `nil` otherwise

---

### **PPDS:get(key, default, ttl)**

Synchronously fetches data from cache or DataStore with fallback.

---

### **PPDS:set(key, value)**

Updates cache and schedules asynchronous DataStore write.

---

### **PPDS:update(key, fn)**

Safely updates data using a transformation function.

---

### **PPDS:increment(key, field, amount)**

Atomically increments a numeric field.

---

### **PPDS:leave(key)**

Immediately saves data and removes from cache. Fires `OnDelete` event.

---

## Cache Management

* **PPDS:cleanCache(ttl?)** – Remove expired entries
* **PPDS:flushWrites()** – Force immediate save of all cached data

---

## Events

* **OnInit** – Fired when data is loaded or initialized
* **OnSave** – Fired when data is saved to DataStore
* **OnDelete** – Fired when data is removed from cache
* **OnInvalidate** – Fired when data should be refreshed (cross-server sync)

---

## Best Practices

* Use `update()` for atomic operations
* Call `leave()` on player removal
* Periodically run `cleanCache()`
* Monitor important events via `OnSave` and `OnInit`

---

## Development Tools

* **PPDS:export()** – Deep copy snapshot of cache
* **PPDS:import(tbl, overwrite)** – Load table into cache

---

## Performance Notes

* JSON caching prevents redundant serialization
* Delayed write batching reduces DataStore calls
* Automatic cache expiration manages memory usage

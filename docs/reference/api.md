# PPDB API Reference



---

## Getting Started

### Basic Setup

```luau
local PPDB = require(path.to.PPDB)

-- Create DBOptions object
local options = PPDB.DBOptions.new()
options.debug = true

-- Create a database instance
local db = PPDB.new("PlayerData", options)
```

### Quick Example

```luau
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

### **PPDB.new(name, DBOptions)**

Creates a new database instance with global cache sharing.

**Parameters:**

* `name` *(string)* – DataStore name – multiple instances with same name share cache
* `DBOptions` *(PPDB.DBOptions, optional)*:

  * `debug` *(boolean)*: Enable debug logging
  * `migrations` *(table)*: Array of migration functions

**Returns:** PPDB instance with event signals and automatic cleanup

**Example:**

```luau
-- Create a new database instance with DBOptions
local options = PPDB.DBOptions.new()
options.debug = true
options.migrations = {
    function(data) -- Migration 1
        data.level = data.level or 1
        return data
    end
}

local db = PPDB.new("PlayerData", options)
```

---

## Core Data Operations

### **PPDB:init(key, defaultData, callback)**

Asynchronously initializes a key with default data if not exists.

**Parameters:**

* `key` *(string)* – The data key to initialize
* `defaultData` *(table)* – Default data structure
* `callback` *(function, optional)* – `(success: boolean, data: table) -> ()`

**Returns:** Cached data immediately if available; `defaultData` otherwise

### **PPDB:get(key, default, ttl)**

Synchronously fetches data from cache or DataStore with fallback.

**Parameters:**

* `key` *(string)* – Data key to retrieve
* `default` *(any, optional)* – Default value if not found
* `ttl` *(number, optional)* – Time-to-live in seconds for cache expiration

**Returns:** Cached data or loaded data from DataStore

### **PPDB:set(key, value)**

Updates cache and schedules asynchronous DataStore write.

**Parameters:**

* `key` *(string)* – Data key to update
* `value` *(table)* – New data value (must be a table)

### **PPDB:update(key, fn)**

Safely updates data using a transformation function.

**Parameters:**

* `key` *(string)* – Data key to update
* `fn` *(function)* – Transformation function: `(currentData: table) -> newData: table`

### **PPDB:increment(key, field, amount)**

Atomically increments a numeric field.

**Parameters:**

* `key` *(string)* – Data key to update
* `field` *(string)* – Field name to increment
* `amount` *(number, optional)* – Amount to increment (default: 1)

### **PPDB:leave(key)**

Immediately saves data and removes from cache. Fires `OnDelete` event.

**Parameters:**

* `key` *(string)* – Data key to save and remove from cache

---

## Cache Management

* **PPDB:cleanCache(ttl?)** – Remove expired entries based on TTL
* **PPDB:flushWrites()** – Force immediate save of all cached data

---

## Events

* **OnInit** – Fired when data is loaded or initialized: `(key: string, data: table)`
* **OnSave** – Fired when data is saved to DataStore: `(key: string, data: table)`
* **OnDelete** – Fired when data is removed from cache: `(key: string)`
* **OnInvalidate** – Fired when data should be refreshed (cross-server sync): `(key: string)`

---

## Best Practices

* Use `update()` for atomic operations
* Call `leave()` on player removal to ensure data is saved
* Periodically run `cleanCache()` to manage memory
* Monitor important events via `OnSave` and `OnInit`
* Use migrations to handle data structure changes

---

## Development Tools

* **PPDB:export()** – Deep copy snapshot of current cache
* **PPDB:import(tbl, overwrite)** – Load table data into cache

---

## Performance Notes

* Global caching prevents redundant DataStore calls
* Write queuing reduces DataStore operation frequency
* Automatic cache expiration manages memory usage
* Cross-server locking ensures data consistency

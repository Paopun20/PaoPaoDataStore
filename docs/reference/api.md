# PPDS API Reference

This document provides a detailed overview of the PPDS (PaoPao DataStore) API for developers.

---

## **PPDS.new(name, opts)**

Creates a new database instance.

**Parameters:**

* `name` *(string)*: Name of the DataStore.
* `opts` *(table, optional)*:

  * `debug` *(boolean)*: Enable debug logging.
  * `migrations` *(table of functions)*: Functions to migrate data between versions.

**Returns:**

* A new PPDS instance.

```lua
local db = PPDS.new("PlayerData", { debug = true })
```

---

## **PPDS:init(key, defaultData, cb)**

Initializes a key in the database.

**Parameters:**

* `key` *(string)*: The key to initialize.
* `defaultData` *(table)*: Default data for the key.
* `cb` *(function, optional)*: Callback function `(success, data)` after initialization.

**Returns:**

* The cached data if already loaded, otherwise `nil`.

```lua
db:init("Player_12345", { coins = 0 }, function(success, data)
    print(data.coins)
end)
```

---

## **PPDS:get(key, default)**

Fetches a key from cache or DataStore.

**Parameters:**

* `key` *(string)*
* `default` *(any)*: Default value if key does not exist.

**Returns:**

* Data from cache or DataStore.

```lua
local data = db:get("Player_12345", { coins = 0 })
```

---

## **PPDS:set(key, value)**

Sets data for a key and schedules a flush.

**Parameters:**

* `key` *(string)*
* `value` *(table)*

```lua
db:set("Player_12345", { coins = 100 })
```

---

## **PPDS:update(key, fn)**

Updates a key using a callback function.

**Parameters:**

* `key` *(string)*
* `fn` *(function)*: Function `(currentData) -> newData`

```lua
db:update("Player_12345", function(data)
    data.coins = (data.coins or 0) + 50
    return data
end)
```

---

## **PPDS:increment(key, field, amount)**

Increment a numeric field inside a key.

**Parameters:**

* `key` *(string)*
* `field` *(string)*
* `amount` *(number)*

```lua
db:increment("Player_12345", "coins", 10)
```

---

## **PPDS:cleanCache()**

Removes expired entries from the cache.

```lua
db:cleanCache()
```

---

## **PPDS:export()**

Exports the current cache as a Lua table.

**Returns:**

* A deep copy of cached data.

```lua
local snapshot = db:export()
```

---

## **PPDS:import(tbl, overwrite)**

Imports data into the cache.

**Parameters:**

* `tbl` *(table)*: Data to import.
* `overwrite` *(boolean)*: Whether to overwrite existing keys.

```lua
db:import(snapshot, true)
```

---

## **PPDS:flushWrites()**

Flushes all cached writes to the DataStore immediately.

```lua
db:flushWrites()
```

---

## **PPDS:setWebhook(url)**

Sets a Discord webhook URL for logging (optional).

```lua
db:setWebhook("YOUR_WEBHOOK_URL")
```

## **PPDS:sendToDiscord(enabled)**

Enables or disables sending logs to Discord.

```lua
db:sendToDiscord(true)
```

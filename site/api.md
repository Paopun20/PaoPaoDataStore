# API Reference – PPDB

This file documents all public methods, signals, and options of **PPDB**.

---

## Constructor

### `PPDB.new(name: string, options: table?) → PPDB`
Create a new PPDB instance bound to a DataStore.

**Parameters**
- `name` (string) – DataStore name.  
- `options` (table) – Optional configuration:  
  - `scope` (string) – DataStore scope (default: `nil`).  
  - `cacheTtl` (number) – Cache expiration in seconds (default: 300).  
  - `migrations` (array) – Array of migration functions `(data) -> data`.  
  - `hooks` (table) – Lifecycle hooks:  
    - `beforeInit`, `afterInit`, `beforeSave`, `afterSave`  
    - `beforeDelete`, `afterDelete`  

---

## Core Methods

### `init(key: string, defaultData: any, callback: (ok: boolean, data: any) -> ())`
Initialize data for a key, applying migrations and caching.

### `get(key: string) → any?`
Fetch data from cache, or `nil` if not loaded.

### `getWithDefault(key: string, defaultData: any) → any`
Same as `get`, but if nil, returns `defaultData`.

### `update(key: string, transformFn: (data: any) -> any, callback: (ok: boolean, data: any) -> ())`
Update a key’s data using a transform function.  
Writes are queued/debounced.

### `delete(key: string, callback: (ok: boolean) -> ())`
Delete data for a key.

### `flush(key: string, force: boolean?)`
Force a write of a cached key.  
If `force = true`, writes immediately bypassing debounce.

### `close(key: string)`
Flush and remove from cache.

### `stat() → table`
Return runtime statistics: `{ name, cachedKeys, queuedWrites, writeCount }`.

---

## Signals

All signals are instances of `Signal` with `:Connect(fn)`.

- `OnInit(key: string, data: any)`  
- `OnSave(key: string, data: any)`  
- `OnDelete(key: string)`  
- `OnInvalidate(key: string)`  

---

## Hooks

Hooks run before/after lifecycle events.  
They receive `(key, data)` or `(key)` depending on context.

Example:
```lua
local db = PPDB.new("PlayerData", {
    hooks = {
        beforeSave = function(k,d) print("Saving",k) end,
        afterSave  = function(k,d) print("Saved",k) end,
    }
})
```

---

## Migrations

Array of functions that modify data at init:

```lua
local migrations = {
    function(d) d.version = 1; return d end,
    function(d) d.profile = {coins=0}; return d end,
}
```

---

## Logging

### `PPDB:setDiscordWebhook(url: string, minLevel: string)`
Send logs to a Discord webhook.  
`minLevel` can be `"DEBUG" | "INFO" | "WARN" | "ERROR"`.

### Log format
```
[PPDB][INFO][2025-08-21 20:31:00] Initialized key 123
```

---

## BindToClose

PPDB automatically flushes writes on shutdown via `game:BindToClose`.  
It waits for pending writes to finish before closing.

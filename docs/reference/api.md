# PPDB API Reference

## Creating an Instance

### `PPDB.new(name: string, options?: DBOptions): PPDB`

Creates (or attaches to) a DataStore-backed PPDB instance.

* `name` — DataStore name
* `options` — Optional `DBOptions`

**Notes**

* Instances with the same `name` share a global in-memory cache.
* Automatically binds a shutdown handler on first creation.

---

## DBOptions

### `DBOptions.new(): DBOptions`

Creates an options object.

**Fields**

* `debug: boolean` — Enables verbose warnings and logs
* `migrations: { (data: table) -> table }[]` — Ordered migration functions

---

## Lifecycle Signals

### `OnInit: Signal`

Fired when a key finishes loading and is cached.

**Callback**: `(key: string, data: table)`

### `OnSave: Signal`

Fired when a key is set or updated.

**Callback**: `(key: string, data: table)`

### `OnDelete: Signal`

Fired when a key is removed from cache via `leave()`.

**Callback**: `(key: string)`

### `OnInvalidate: Signal`

Reserved for future cross-server invalidation support.

---

## Core Methods

### `init(key: string, defaultData?: table, callback?: (success: boolean, data: any) -> ()) : any`

Initializes and asynchronously loads a key.

**Behavior**

* Returns cached data immediately if present
* If loading is in progress, queues callbacks
* Runs migrations after load

**Returns**

* Cached data if available
* Otherwise `defaultData`

---

### `get(key: string, default?: any, ttl?: number): any`

Fetches data from cache or DataStore.

* `ttl` — Optional cache TTL in seconds

---

### `set(key: string, value: table): boolean`

Sets and caches a value, scheduling an async write.

* Adds/updates internal timestamp `_t`

---

### `update(key: string, fn: (data: table) -> table): boolean`

Atomically updates cached data using a transform function.

* Receives a deep copy of current data
* Result replaces cached value if valid

---

### `increment(key: string, field: string, amount?: number): boolean`

Convenience helper to increment numeric fields.

* Defaults `amount` to `1`
* Warns if field is non-numeric

---

## Write Control

### `flushWrites(): ()`

Schedules async writes for all cached keys.

### `flushWritesSync(): ()`

Synchronously writes all cached data.

**Intended for shutdown use only.**

---

## Session Management

### `leave(key: string, callback?: (success: boolean) -> ()): ()`

Flushes and removes a key from cache.

* Acquires a soft lock
* Fires `OnDelete`

---

## Cache Management

### `cleanCache(ttl?: number): number`

Removes expired cache entries.

* `ttl` defaults to 3600 seconds
* Returns number of cleaned entries

---

### `enableAutoCleanup(interval?: number, ttl?: number): ()`

Starts a background cleanup loop.

* `interval` defaults to 300 seconds
* `ttl` defaults to 3600 seconds

---

## Import / Export

### `export(): table`

Returns a deep copy of the current cache.

### `import(data: table, overwrite?: boolean): number`

Imports key-value pairs into cache.

* `overwrite` replaces existing keys
* Returns number of imported entries

---

## Utilities

### `waitForKey(key: string, timeout?: number): any?`

Blocks until a key is cached or timeout expires.

* `timeout` defaults to 10 seconds

---

### `isLoading(key: string): boolean`

Returns whether a key is currently loading.

---

## Notes on Concurrency

* PPDB uses soft locking via MemoryStore (best-effort)
* Writes are last-write-wins
* Strong cross-server consistency is not guaranteed

---

## Performance Notes

* Global caching prevents redundant DataStore calls
* Write queuing reduces DataStore operation frequency
* Automatic cache expiration manages memory usage
* Cross-server locking ensures data consistency

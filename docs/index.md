# PPDB Documentation

Welcome to the documentation for my *cool* project!  
This site provides an overview of the **PPDS (PaoPao's DataStore modules)** (Or just PPDB for easy call) project, including its architecture, key features, and how to use it.

---

## Key Features

- High-performance caching layer
- Write queue with debounce protection
- Cross-server cache invalidation
- Lifecycle hooks & signals
- Migration support for schema updates
- Safe shutdown with `BindToClose`

---

## 📖 Documentation Structure

- [Getting Started](#getting-started) – Quick overview and installation  
- [API Reference](api.md) – Full API documentation  

---

## 🚀 Getting Started
Get started with PPDB by following these steps:
1. Download the module from [Roblox](https://create.roblox.com/store/asset/95562270661505/) (Not realtime, some upload github, not update roblox)

```lua
local PPDB = require(Path.To.PPDB)

local PlayerDB = PPDB.new("PlayerData")
PlayerDB:init(player.UserId, { coins = 0, level = 1 }, function(ok, data)
    if ok then
        print("Loaded profile:", data)
    end
end)
```

## Note (Important!)
some api changes may occur in the future, so please check back regularly for updates.
not 100% guaranteed that the api will not change, but i will try to keep it stable.
---
# 🧠 PaoPao's DataStore Module (PPDB)

An intelligent data storage system for Roblox designed to be easy to use, modern, and capable of supporting large-scale games.  
Perfect for developers who want to manage player data efficiently, securely, and conveniently.

---

## ✅ Features

- ⚡ **Write Queue System**  
  - Prevents too frequent data saves  
  - Reduces chances of hitting Roblox DataStore limits  

- 🔁 **Cross-Server Sync**  
  - Uses MemoryStore Queue to notify other servers when data changes  

- 🧬 **Data Migration Support**  
  - Automatically updates data structures when system versions change  

- 📡 **Discord Webhook Notifications**  
  - Sends alerts immediately on errors like save failures  

- 🚀 **In-Memory Cache System**  
  - Speeds up access and reduces direct DataStore calls  

- 🧹 **Event Hooks System**  
  - Allows adding custom functions before save or after load  

---

## 📦 Installation

1. Place the `PaoPaoDataStore` ModuleScript inside `ServerStorage` or `ReplicatedStorage`  
2. Require the module with this line:

```lua
local PPDB = require(ServerStorage:WaitForChild("PaoPaoDataStore"))
```

---

## 🛠️ Basic Usage

### 🔹 Create a store to manage data:

```lua
local ProfileStore = PPDB("PlayerData", {
    afterInit = function(key, data)
        print("Data loaded:", key, data)
    end,
    beforeSave = function(key, data)
        print("Saving data for:", key)
    end,
}, 86400 * 7) -- Cache data for 7 days
```

### 🔹 Initialize default data for a player:

```lua
ProfileStore:init("player_123", {
    Coins = 0,
    Level = 1,
})
```

### 🔹 Update player data:

```lua
ProfileStore:update("player_123", function(old)
    old.Coins += 50
    return old
end)
```

### 🔹 Delete data:

```lua
ProfileStore:delete("player_123", function(success)
    print("Deleted:", success)
end)
```

### 🔹 Access data from cache:

```lua
local cached = ProfileStore:getCached("player_123")
```

### 🔹 Remove data from cache (e.g., when player leaves):

```lua
ProfileStore:leave("player_123")
```

---

## 📈 Data Migration Example

Supports upgrading old data safely without losing information:

```lua
local migrations = {
    [1] = function(data)
        data.Level = data.Level or 1
        return data
    end,
    [2] = function(data)
        data.Exp = 0
        return data
    end
}

local Store = PPDB("UserData", nil, nil, nil, migrations)
```

---

## 📮️ Discord Webhook Notifications (Optional)

You can set a webhook URL to get alerts when errors occur:

```lua
_G.PPDBM_WEBHOOK = "https://discord.com/api/webhooks/..."
```

---

## 🚨 Developer Notes

- Cache is automatically cleared across all servers when data changes somewhere else  
- Saves within less than 1 second are delayed and combined to avoid throttling  
- Use structured keys like `"player_" .. UserId` to organize data easily  

---

## 🌍 Contributing and Support

This module is open source. Feel free to contribute, suggest features, or report issues on GitHub:  

👉 https://github.com/Paopun20/PaoPaoDataStore

---

## 🧠 Enjoy making your Roblox game better!  
**With love and care, PaoPaoDev ❤️**

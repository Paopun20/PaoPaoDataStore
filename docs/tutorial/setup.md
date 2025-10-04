# PPDS Setup Guide

PPDS (PaoPao's DataStore Module) is a **ModuleScript** for Roblox that provides a high-performance, caching-friendly, migration-ready wrapper for DataStores with cross-server synchronization.
It **must be used server-side** (e.g., inside `ServerScriptService`).

---

## Step 1: Get PPDS

You have three options to obtain PPDS:

[Roblox Asset Library (Option 1)](https://www.roblox.com/library/95562270661505/){ .md-button .md-button--primary }
[GitHub (Option 2)](https://github.com/Paopun20/PaoPaoDataStore){ .md-button .md-button--primary }
[Wally (Option 3)](https://wally.run/package/paopun20/paopaodatastore){ .md-button .md-button--primary }

---

## Step 2: Install PPDS (for Option 1 and Option 2)

1. Place the `PaoPaoDataStore` folder in `ServerScriptService` or your preferred server-side location.
2. Require the module in your scripts:

```lua
local PPDS = require(game.ServerScriptService.PaoPaoDataStore)
-- Or if you placed it elsewhere:
-- local PPDS = require(game.Workspace.MyModules.PaoPaoDataStore)
```

---

## Step 3: Basic Usage

No, pls go to [API Reference](../reference/api.md) section.

---

!!! tip "Pro Tip 😉"
    When you finish coding, you *might* be tempted to press: ++alt+f4++  

    (Just kidding! Don't actually do it—unless you enjoy closing your editor unexpectedly.)
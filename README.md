# PPDS (PaoPao's DataStore module)

A fast, server-side Roblox DataStore wrapper with caching, cross-server invalidation, migrations, and lifecycle hooks.

## Quick Start

```lua
local PPDS = require(game.ServerScriptService.PPDS)
local db = PPDS.new("PlayerData")
db:init("Player_12345", { coins = 0 })
db:increment("Player_12345", "coins", 50)
```

## Installation

* Get from [Roblox Asset Library](https://www.roblox.com/library/95562270661505/) or [GitHub](https://github.com/Paopun20/PaoPaoDataStore).
* Place `PaoPaoDataStore` in `ServerScriptService` or your preferred server-side location.

## Contributing

PPDS is open for contributions. If you have ideas for improvements, bug fixes, or new features, remake shit part of docs, feel free to submit a pull request or open an issue on the [GitHub repository](https://github.com/Paopun20/PaoPaoDataStore).

## License

PPDS is released under the **Apache License 2.0**. See the [LICENSE](LICENSE) file for details.

PaoPao's DataStore Module (PPDS)

PPDS is a Roblox DataStore wrapper that simplifies the management of persistent data. It is designed to be flexible, efficient, and easy to use, allowing developers to focus on creating engaging gameplay experiences without worrying about the complexities of data storage.

## How does it work?

PPDB loads and caches data from Roblox DataStores on a single game server and keeps it fresh across multiple servers by combining a write queue, cache invalidation, and safe retries. It reduces unnecessary DataStore calls while ensuring that data is always consistent and available when needed.

Data units saved by PPDB are called records, which can be initialized with default values and then accessed like regular Lua tables during gameplay. Changes made to a record are first applied to the local cache and later written back to DataStore in batches through the write queue. This approach minimizes the risk of hitting request limits and ensures stable performance.

Unlike systems that rely only on session locking, PPDB uses a cross-server invalidation mechanism powered by MemoryStore. Whenever a record is updated on one server, other servers are notified to clear their stale cache, guaranteeing that the next read pulls the most up-to-date data. This helps prevent duplication issues or outdated player progress when players hop between servers.

PPDB is designed with both player data and non-player data in mind. For example, it can store player progress, but also shared resources like guild stats, item stocks, or economy balances. The cache and write queue system make it suitable for cases where multiple servers frequently interact with the same data.

The API resembles Roblox’s native DataStore functions for familiarity but extends them with advanced features like lifecycle hooks, signals, health monitoring, and schema migrations. These additions give developers more control over how and when data is saved, while still keeping the workflow simple and predictable.

PPDB is not intended for real-time leaderboards or highly volatile global state, but instead for reliable, scalable, and developer-friendly persistent storage of structured data.

Contributing:
PPDS is open for contributions. If you have ideas for improvements, bug fixes, or new features, feel free to submit a pull request or open an issue on the GitHub repository.

## License

PPDS is released under the **Apache License 2.0**. See the [LICENSE](LICENSE) file for details.
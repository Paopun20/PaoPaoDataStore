# PaoPao's DataStore Module (PPDS)

PPDS is a high-performance Roblox DataStore wrapper that simplifies the management of persistent data with advanced caching, cross-server synchronization, and migration capabilities. It is designed to be robust, efficient, and developer-friendly, allowing you to focus on creating engaging gameplay experiences without worrying about the complexities of data storage.

## Features

- **Global Shared Cache**: Data is cached across all server instances, ensuring consistency and reducing DataStore calls.
- **Cross-Server Locking**: Prevents data corruption from concurrent writes across multiple servers using MemoryStoreService.
- **Automatic Data Migrations**: Seamlessly update your data structure over time without losing player data.
- **Event-Driven Architecture**: Integrate with your game logic using `OnInit`, `OnSave`, `OnDelete`, and `OnInvalidate` events.
- **Robust Error Handling**: Built-in exponential backoff retry logic for DataStore operations.
- **Discord Webhook Integration**: Monitor critical DataStore events and errors directly in Discord.
- **Session Management**: Efficiently handle player data loading, saving, and cleanup.
- **Development Tools**: Export/import cache snapshots for debugging and testing.

## How it work

``` mermaid
graph TD
    A[Player Joins] --> B[Load Data from Cache or DataStore]
    B --> C{Data Exists?}
    C -- Yes --> D[Initialize Player Data]
    C -- No --> E[Create New Data Entry]
    D --> F[Player Plays Game]
    E --> F
    F --> G{Data Changes?}
    G -- Yes --> H[Update Cache and Schedule Save]
    G -- No --> I[Continue Playing]
    H --> J[Save Data to DataStore with Locking]
    J --> K{Save Successful?}
    K -- Yes --> L[Confirm Save and Update Cache]
    K -- No --> M[Retry Save with Exponential Backoff]
    L --> I
    M --> I
    I --> N[Player Leaves]
    N --> O[Save Final Data and Cleanup Cache]
```

### Design Principles

$$
\text{Data Consistency} \propto \frac{\text{Cross-Server Locking} + \text{Global Shared Cache}}{\text{Concurrent Writes}}
$$

$$
\text{Performance} \propto \frac{\text{Caching} + \text{Efficient DataStore Calls}}{\text{Latency}}
$$

$$
\text{Reliability} \propto \frac{\text{Error Handling} + \text{Retry Logic}}{\text{Data Loss}}
$$

$$
\text{Developer Experience} \propto \frac{\text{Automatic Migrations} + \text{Event System}}{\text{Boilerplate Code}}
$$

---

## Quick Start

To get started with PPDS, check out the detailed documentation and tutorials:

[Getting Started Guide](./tutorial/setup.md){ .md-button }
[API Reference](./reference/api.md){ .md-button }

And try this
++alt+f4++

## License

PPDS is released under the **Apache License 2.0**. This permissive license allows you to use, modify, and distribute PPDS in both personal and commercial projects.

[See the LICENSE file for complete details.](https://raw.githubusercontent.com/Paopun20/PaoPaoDataStore/main/LICENSE){ .md-button }

---

!!! note "note 1 (Important)"

    !!! note "sub-note 1"
        PPDS represents a production-ready DataStore solution with enterprise features. While the API is stable, we continuously improve performance and add features based on community feedback.
        
    !!! note "sub-note 2 (A Very Important!)"

        some api changes may occur in the future, so please check back regularly for updates, not 100% guaranteed that the api will not change, but i will try to keep it stable.

    !!! note "sub-note 3"
        If you encounter any issues or have suggestions for improvement, please open an issue on the [GitHub repository](https://github.com/Paopun20/PaoPaoDataStore/issues) but good /w pull request and bug fixes in pull request.

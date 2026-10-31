---
sidebar_position: 1
title: Strata
---

# Strata

**Data, without the overhead.**

Strata isn't the data system with the most features. It's the one that asks the least of you to get a great one.

Typed data, automatic replication, serialization, and session management — without making you build the infrastructure yourself.

```lua
S.Coins.Get()
S.Coins.Set(50)

S.Observe("Coins")(function(Coins)
    print(Coins)
end)
```

## What makes Strata easy?

- **No session setup.** Player sessions are handled automatically.
- **No remotes to manage.** Replication is built in.
- **No separate type definitions.** Your template provides types and autocomplete.
- **No manual serialization.** Supported Roblox and Luau datatypes are handled automatically.
- **No manual saving.** Data saves automatically, and you can still call `Save` when needed.

:::info
For the best autocomplete experience, enable the new Luau type solver by setting `Workspace.UseNewLuauTypeSolver` to `Enabled`. Runtime functionality does not depend on it.
:::

## Getting started

### 1. Install Strata

Place Strata inside `ReplicatedStorage`. Strata automatically creates its required runtime components.

### 2. Create your data module

Create a ModuleScript named `Data` inside `ReplicatedStorage`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Strata = require(ReplicatedStorage.Strata)

local Template = {
    Coins = 0,
    Stats = {
        Level = 1,
        Xp = 0,
    },
    Inventory = {} :: { string },
}

return Strata:Init({
    StoreName = "Players",
    Template = Template,
})
```

The template defines your data structure and provides the types used throughout your project.

New players receive the template, while existing player data is reconciled with newly added fields.

### 3. Load and use data

**Server**

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(ReplicatedStorage.Data)

Players.PlayerAdded:Connect(function(Player)
    local S = Data.Server:LoadVault(Player)
    if not S then
        return
    end

    S.Coins.Update(function(Coins)
        return Coins + 100
    end)

    S.Inventory.Push("Wooden Sword")
end)
```

**Client**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage.Data)

local C = Data.Client:LoadVault()
if C then
    C.Observe("Coins")(function(Coins)
        CoinLabel.Text = tostring(Coins)
    end)
end
```

`Observe` takes a path from the root state and returns a function that accepts your listener. It immediately provides the current value, then runs again whenever that value changes.

## Working with data

Strata provides methods based on the type of value you're working with.

### Any value

- `Get` — Retrieve the current value.
- `Set` — Replace the current value.
- `Update` — Transform the current value.

### Tables

- `Mutate` — Modify a table.
- `Snapshot` — Retrieve a copy of the current data.

### Arrays

- `Push` — Add an item to the end.
- `Pop` — Remove the last item.
- `InsertAt` — Insert an item at a position.
- `RemoveAt` — Remove an item at a position.

### Arrays and maps

- `Has` — Check whether a key or value exists.
- `Keys` — Retrieve keys.
- `Values` — Retrieve values.
- `Size` — Get the number of entries.
- `Insert` — Insert an entry.
- `Remove` — Remove an entry.
- `Clear` — Remove all entries.

### Vault operations

- `Observe` — Subscribe to changes at a path.
- `Save` — Save the current data.
- `End` — End a session.
- `Replicate` — Request replication.
- `GetSessionInfo` — Retrieve session information.
- `IsLoaded` — Check whether a vault is loaded.

All data-node methods use dot syntax:

```lua
S.Coins.Get()
S.Coins.Set(100)
S.Coins.Update(function(Coins)
    return Coins + 1
end)
```

`Observe` is the exception in terms of where it lives: it is exposed once on the root state and takes a path.

```lua
S.Observe("Stats.Level")(function(Level)
    print("Level:", Level)
end)
```

### Batched replication

Strata groups server-side changes together before replicating them. Multiple changes made within the same tick can be sent as a single update rather than separate network updates.

## What Strata is for

Strata is designed for **player data**.

It uses ProfileStore for session-based data saving and provides automatic client replication. It is not intended to replace systems such as `OrderedDataStore` or `MessagingService` for global data, leaderboards, or communication between servers.

The server owns all data changes. The client receives a read-only replica, and server-side changes are replicated automatically.

## What's next?

- [Working with data](working-with-data.md)
- [Configuration](configuration.md)

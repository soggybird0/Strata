---
sidebar_position: 2
title: Working with data
---

# Working with data

This page covers how Strata's data model behaves, including nested values, mutations, replication, observations, and session management.

Every example uses the following template:

```lua
local Template = {
    Coins = 0,
    Stats = { Level = 1, Xp = 0 },
    Inventory = {} :: { string },
    Items = {} :: { [string]: { Damage: number } },
    Equipped = nil :: string?,
}
```

`S` refers to a player's vault. The server and client expose the same read interface, but the client cannot write to data.

## Getting a vault

There are two ways to retrieve a player's vault:

```lua
local S = Data.Server:LoadVault(Player)
local S = Data.Server:GetVault(Player)
```

`LoadVault` waits until the player's data is ready. It returns `nil` if the data cannot be loaded, such as when the player leaves or `LoadTimeout` expires.

Always check its return value before using the vault:

```lua
local S = Data.Server:LoadVault(Player)

if not S then
    return
end
```

`GetVault` never waits. It returns the existing vault if the player's data is already loaded, otherwise `nil`. This is useful in code that runs after loading, such as remote handlers.

### Non-player sessions

You can also pass a string key instead of a Player:

```lua
local Guild = Data.Server:LoadVault("Guild_42")
```

This opens a session that isn't tied to a specific player. It can be useful for data shared across a guild, world, or other keyed entity.

## Reading data

Every value in the template can be accessed through its corresponding node:

```lua
local Coins = S.Coins.Get()
local Level = S.Stats.Level.Get()

local Stats = S.Stats.Get()
```

You can access nested values by chaining keys. The returned value from `Get` corresponds to the node you called it on.

### Client-side reads

On the client, tables returned by `Get` are read-only proxies by default.

You can read and traverse them normally, but attempting to modify them throws an error. This helps prevent accidental local changes from making UI state disagree with the server.

If you need the raw table instead, you can disable this behavior with [`ClientGuard = "Off"`](./configuration#client).

## Writing data

All writes go through node methods rather than direct assignment.

### Set

`Set` replaces a node's current value:

```lua
S.Coins.Set(50)
S.Stats.Level.Set(2)
```

It also supports optional fields:

```lua
S.Equipped.Set("Wooden Sword")
S.Equipped.Set(nil)
```

Both calls are valid because `Equipped` is optional in the template.

### Update

`Update` receives the current value and returns its replacement:

```lua
S.Coins.Update(function(Coins)
    return Coins + 10
end)
```

This is useful when the next value depends on the previous one.

Both `Set` and `Update` return the new value.

:::tip
**No direct assignment**

```lua
S.Coins = 50 -- throws
```

Data nodes aren't ordinary tables. Writes must go through their methods so Strata can track changes and replicate them correctly.
:::

## Mutating tables

For changes involving multiple fields, use `Mutate`.

```lua
S.Stats.Mutate(function(Stats)
    Stats.Level += 1
    Stats.Xp = 0
end)
```

Strata tracks the changes made during the mutation and replicates the resulting changes rather than requiring you to replace the entire table.

### Snapshots

`Snapshot` returns a deep copy of the current value.

```lua
local Before = S.Stats.Snapshot()
```

Unlike a read-only proxy, a snapshot can be modified freely without changing the actual vault.

This is useful when you need to keep a previous version of some data, prepare changes separately, or pass a copy to another system.

## Arrays

Strata provides methods for common array operations.

```lua
S.Inventory.Push("Wooden Sword")
S.Inventory.Push("Shield")
```

`Push` adds an item to the end of the array and returns the new length.

```lua
S.Inventory.InsertAt(1, "Torch")
```

`InsertAt` inserts an item at the specified position, shifting subsequent elements.

```lua
local Removed = S.Inventory.RemoveAt(2)
local Last = S.Inventory.Pop()
```

`RemoveAt` removes and returns the item at a position. `Pop` removes and returns the last item.

You can also use `Size` to retrieve the number of entries:

```lua
print(S.Inventory.Size())
```

## Dictionaries

Dictionaries use the same node API as other tables.

```lua
S.Items.Insert("sword_001", {
    Damage = 12,
})
```

You can access individual entries directly:

```lua
local Damage = S.Items.sword_001.Damage.Get()
```

Use `Has` to check whether an entry exists:

```lua
print(S.Items.Has("sword_001"))
```

`Remove` deletes an entry and returns its previous value:

```lua
local Removed = S.Items.Remove("sword_001")
```

### Shared collection methods

Arrays and dictionaries also support:

- `Keys` — Returns the collection's keys.
- `Values` — Returns its values.
- `Size` — Returns the number of entries.
- `Clear` — Removes all entries.

These methods are available on both collection types.

## Observing changes

Strata provides one `Observe` method on the root state. It accepts a path and returns a function that registers a listener.

```lua
local Connection = S.Observe("Stats.Level")(function(Level)
    print("Level is", Level)
end)
```

The listener runs immediately with the current value, then runs again whenever that value changes.

The returned connection can be disconnected when you no longer need the observation:

```lua
Connection.Disconnect()
```

### Choosing a path

The path determines which part of the vault you're observing.

```lua
S.Observe("Coins")(OnCoins)
S.Observe("Stats")(OnStats)
S.Observe()(OnEntireData)
```

- `"Coins"` observes a single field.
- `"Stats"` observes the entire `Stats` table.
- An empty path observes the entire vault.

Paths can also be provided as tables.

### Parent and child observations

Observations account for changes throughout the selected path.

- Observing a parent fires when one of its descendants changes.
- Observing a child fires when its parent is replaced.
- Unchanged values do not trigger another callback.

The callback value is typed according to the selected path. For example, observing `"Coins"` gives the listener a `number`, while observing `"Stats"` gives it the corresponding table type.

Your editor can autocomplete valid paths from the template.

### Client observations

The client uses the same root-level `Observe` method:

```lua
local C = Data.Client:LoadVault()

if C then
    C.Observe("Coins")(function(Coins)
        CoinLabel.Text = tostring(Coins)
    end)
end
```

There is no separate client observation API. Server-side changes are replicated, and client observations respond to those changes.

## Sessions

Strata manages session loading, saving, and cleanup automatically. You can still interact with a session directly when needed.

```lua
S.Save()
S.End()

print(S.IsLoaded())
```

- `Save` requests an immediate save.
- `End` ends the session.
- `IsLoaded` checks whether the session is still active.

### Session information

Use `GetSessionInfo` to retrieve information about a session:

```lua
local Info = S.GetSessionInfo()

print(Info.UserId)
print(Info.LoadedAt)
print(Info.LastSaveAt)
print(Info.IsActive)
```

### Iterating loaded sessions

`ForEachSession` lets you perform an operation on every currently loaded session:

```lua
Data.Server:ForEachSession(function(Key, S, Info)
    S.Coins.Update(function(Coins)
        return Coins + 5
    end)
end)
```

When the server shuts down, active sessions are saved and ended automatically.

## Metadata

Each session has a metadata table alongside its data.

Metadata is stored with the profile, but it isn't part of the template. This makes it useful for bookkeeping values that don't belong in the main data structure.

```lua
S.SetMeta("LastDevice", "Mobile")

print(S.GetMeta("LastDevice"))
```

## Replication

Server-side changes are replicated to the client automatically.

You don't need to create remotes, manually send updates, or request replication after every write.

Strata batches changes made within the same tick. This means multiple writes can be grouped into a single replication update instead of being sent individually.

The client receives a read-only replica. It can read and observe data, but all modifications must happen on the server.

## Supported values

Strata supports standard Luau values such as:

- Numbers
- Strings
- Booleans
- Optional fields
- Arrays
- Dictionaries
- Buffers

It also automatically serializes supported Roblox datatypes, including `Vector3`, `CFrame`, `Color3`, `UDim2`, `EnumItem`, and `DateTime`.

These values are converted for storage and restored when loaded. You can use supported datatypes directly in your template without manually writing serialization logic.

### Data limitations

Strata follows ProfileStore's underlying data restrictions:

- Arrays cannot contain gaps.
- Tables cannot mix numeric and string keys.
- Instances, functions, and threads cannot be saved.

Keep these restrictions in mind when designing your template.
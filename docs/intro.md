---
sidebar_position: 1
title: Strata
---

# Strata

**Data, without the overhead.**

Strata isn't the data system with the most features. It's the one that asks the least of you to get a great one.

You describe your data once. Strata takes care of loading it, saving it, sending changes to the client, and giving you autocomplete for every field.

```lua
S.Coins.Get()                       -- read
S.Coins.Set(50)                     -- write
S.Observe("Coins", function(Coins)  -- watch
	print(Coins)
end)
```

## What makes Strata easy to use?

With most data systems, you have to set up a lot before you can start using them. Strata takes care of most of that for you.

- **No session setup.** Strata handles player sessions when they join and leave. You don't need to write your own `PlayerAdded` or `PlayerRemoving` code to manage them.
- **No remotes to set up.** Strata handles sending data to the client automatically.
- **No separate type definitions.** Your template defines what your data looks like. Strata uses it to provide types and autocomplete.
- **No manual saving.** Strata saves your data automatically. You can still call `Save` whenever you want.

:::info Type solver required
Autocomplete needs the new Luau type solver. Enable `Workspace.UseNewLuauTypeSolver` in Studio, or the matching setting in Luau LSP. Strata still works without it; you just won't get the extra types.
:::

## Getting started

You only need three steps to get Strata running.

### 1. Put Strata in `ReplicatedStorage`

Strata runs on both the server and client, so both need access to it.

Strata also creates a `StrataRuntime` folder in `ReplicatedStorage` for sending data between them. You don't need to do anything with it.

### 2. Create your data template

Create a shared ModuleScript. You can call it `Data`.

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

`StoreName` and `Template` are the only required options.

New players start with the template. If you add new fields later, Strata adds them to existing players when their data loads.

### 3. Start using your data

On the server, load a player's vault. Strata waits for their data to be ready.

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

On the client, load your own vault. You can read and watch your data, but you can't change it.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage.Data)

local C = Data.Client:LoadVault()
if C then
	C.Observe("Coins", function(Coins)
		CoinLabel.Text = tostring(Coins)
	end)
end
```

That's it. `Observe` runs once with the current value, then runs again whenever that value changes.

## Working with data

A vault is made up of nodes. Each field in your template gets its own node, with methods for working with its value.

| Node | Methods |
| --- | --- |
| Any value | `Get`, `Set`, `Update` |
| Table | `Mutate`, `Snapshot` |
| Array | `Push`, `Pop`, `InsertAt`, `RemoveAt` |
| Array or map | `Has`, `Keys`, `Values`, `Size`, `Insert`, `Remove`, `Clear` |
| Vault | `Observe`, `Save`, `End`, `Replicate`, `GetSessionInfo`, `IsLoaded` |

All methods use dot syntax. For example, `S.Coins.Get()` instead of `S.Coins:Get()`.

Strata also groups server changes together before sending them to the client. If you change a value fifty times in one tick, the client receives one update instead of fifty separate ones.

## What Strata is for

Strata is made for player data. It isn't meant to replace every Roblox data service.

- **Not for global data.** Leaderboards and data shared between servers should use tools like `OrderedDataStore` or `MessagingService`. Strata uses [ProfileStore](https://madstudioroblox.github.io/ProfileStore/), which is made for saving player data.
- **The client can't change data.** Trying to use a write method on the client causes an error. Make changes on the server and Strata sends them to the client.

## Next steps

- [Working with data](PLACEHOLDER) covers the methods, watching changes, and player sessions.
- [Configuration](PLACEHOLDER) covers the options, hooks, and changing your data template.

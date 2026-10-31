---
sidebar_position: 3
title: Configuration
---

# Configuration

Two options are required. Everything else has a default that works, and most games never change any of it.

```lua
return Strata:Init({
	StoreName = "Players",   -- required
	Template = Template,     -- required
})
```

## Storage

| Option       | Default                   | What it does                                                        |
| ------------ | ------------------------- | ------------------------------------------------------------------- |
| `StoreName`  | none                      | The DataStore name. Change it to start a fresh, separate store.     |
| `Template`   | none                      | The shape and default values of a player's data.                    |
| `KeyPrefix`  | `""`                      | Prepended to the player's UserId to build their save key.           |
| `PlayerKey`  | `KeyPrefix .. UserId`     | A function `(Player) -> string` for full control over save keys.    |
| `Mock`       | `false`                   | Uses ProfileStore's in-memory storage. Nothing is saved. Good for tests. |
| `AutoSaveSeconds` | unset                | Adds a save every N seconds on top of ProfileStore's own auto-saving. |

## Sessions

| Option             | Default                                   | What it does                                              |
| ------------------ | ----------------------------------------- | --------------------------------------------------------- |
| `LoadTimeout`      | `30`                                      | Seconds `LoadVault` waits before giving up and returning `nil`. |
| `KickOnFail`       | `true`                                    | Kick a player whose data couldn't load, so they never play on empty data. |
| `KickOnSessionEnd` | `true`                                    | Kick a player if their session ends while they're still in the server. |
| `KickMessage`      | `"Could not load your data. Please rejoin."` | The message shown when a player is kicked.             |

:::caution
Leave `KickOnFail` on unless you have a plan for players with no data. With it off, a player whose data failed to load stays in the game with no vault, and `LoadVault` returns `nil` for them.
:::

## Replication

| Option                 | Default    | What it does                                                         |
| ---------------------- | ---------- | -------------------------------------------------------------------- |
| `ReplicateMode`        | `"Hybrid"` | How changes reach the client. See below.                             |
| `MaxPatchesBeforeFull` | `24`       | Once this many patches queue up in a frame, send a full snapshot instead. |
| `CollapsePatchesAt`    | `12`       | If one `Mutate` changes this many keys in a table, send the table as a single patch. |
| `FlushImmediately`     | `false`    | Send each change right away instead of batching them.               |
| `ReplicateOnSave`      | `false`    | Send a full snapshot to the client after every manual `Save`.        |

`ReplicateMode` takes three values:

- `"Hybrid"` is the default. It sends small patches and switches to a full snapshot when a frame has too many of them.
- `"Diff"` sends patches.
- `"Full"` always sends the whole table. It's simpler to reason about, and it costs more bandwidth on large data.

Each replica carries a sequence number. If a patch is ever missed, the client notices and asks the server for a fresh snapshot by itself.

### Client

| Option        | Default   | What it does                                                           |
| ------------- | --------- | ---------------------------------------------------------------------- |
| `ClientGuard` | `"Proxy"` | `"Proxy"` returns read-only tables from `Get` on the client. `"Off"` returns the raw table. |

## Leaderstats

Name top-level fields that should appear on the Roblox leaderboard. They must be numbers, strings or booleans.

```lua
Strata:Init({
	StoreName = "Players",
	Template = Template,
	Leaderstats = { Coins = true },
})
```

Strata creates the `leaderstats` folder and keeps it in sync with the data. You never touch the values yourself.

## Hooks

Hooks let you react to data events without wrapping every call. Errors inside a hook are caught, so a bad hook never breaks a write.

```lua
Strata:Init({
	StoreName = "Players",
	Template = Template,

	OnSessionStart = function(Key, Player, Data)
		print("Loaded", Key)
	end,

	OnSessionEnd = function(Key, Player)
		print("Ended", Key)
	end,

	BeforeMutate = function(Context)
		-- Context.Key, Context.Player, Context.Data, Context.Path
	end,

	AfterMutate = function(Context)
		print(Context.Key, "changed", table.concat(Context.Path or {}, "."))
	end,
})
```

| Hook             | Receives                    | Runs                                          |
| ---------------- | --------------------------- | --------------------------------------------- |
| `OnSessionStart` | `Key, Player?, Data`        | After a session loads, before the client is sent its data. |
| `OnSessionEnd`   | `Key, Player?`              | Just before a session ends.                   |
| `BeforeMutate`   | `Context`                   | Before every server write.                    |
| `AfterMutate`    | `Context`                   | After every server write.                     |

## Changing your template later

Adding a field to the template is safe. Existing players get the new field and its default the next time they load, and any field whose type changed is reset to the template's value.

For changes that need real logic, like renaming a field or converting a format, set a `SchemaVersion` and write a `Migrate` function. It runs once per profile, when that profile's saved version is older than yours.

```lua
Strata:Init({
	StoreName = "Players",
	Template = Template,
	SchemaVersion = 2,

	Migrate = function(Data, FromVersion, ToVersion)
		if FromVersion < 2 then
			Data.Stats.Xp = Data.Xp or 0
			Data.Xp = nil
		end
	end,
})
```

:::tip
Bump `SchemaVersion` by one each time you ship a migration. `Migrate` always receives the profile's old version, so you can handle players who skipped several updates in a single function.
:::

## Reading settings back

```lua
local Settings = Data.Server:GetSettings()
print(Settings.ReplicateMode, Settings.LoadTimeout)
```

The client has the same method, so shared code can check what it's running under.
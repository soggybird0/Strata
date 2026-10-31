--!optimize 2
--!strict

--[=[
    @class Types
    Shared type contracts for Strata.

    :::danger Type solver required
    **The new Luau type solver is required for `State<T>`, `Node<T>` and `Flags<T>`.**
    Enable `Workspace.UseNewLuauTypeSolver = Enabled` (Studio) or the Luau LSP equivalent.
    :::
]=]

--[=[
    @within Types
    @type JSONAcceptable { JSONAcceptable } | { [string]: JSONAcceptable } | number | string | boolean | buffer
    Values that can be serialized by Strata's underlying data system.
    Supports recursive tables, primitive values, and buffers.
]=]
export type JSONAcceptable = { JSONAcceptable } | { [string]: JSONAcceptable } | number | string | boolean | buffer

--[=[
    @within Types
    @type Path { any }
    Represents a path used to access a nested value in a State.
]=]
export type Path = { any }

--[=[
    @within Types
    @type Connection { Disconnect: (...any) -> () }
    Represents a disconnectable subscription. Provides a `Disconnect` method to stop receiving notifications.
]=]
export type Connection = {
    Disconnect: (...any) -> (),
}

--[=[
    @within Types
    @type MutateContext { Key: string, Player: Player?, Data: T, Path: Path? }
    Context provided to mutation lifecycle callbacks. Contains the session key, associated player, current data, and optional path affected by the mutation.
]=]
export type MutateContext<T> = {
    Key: string,
    Player: Player?,
    Data: T,
    Path: Path?,
}

--[=[
    @within Types
    @type ReplicateMode "Diff" | "Full" | "Hybrid"
    Controls how Strata replicates data to clients.
    - `Diff`: Replicates changes as patches.
    - `Full`: Replicates the complete state.
    - `Hybrid`: Uses patches with full-state replication when appropriate.
]=]
export type ReplicateMode = "Diff" | "Full" | "Hybrid"

--[=[
    @within Types
    @type ClientGuard "Proxy" | "Off"
    Controls how the client handles access to replicated data.
    - `Proxy`: Uses guarded access.
    - `Off`: Disables the client guard.
]=]
export type ClientGuard = "Proxy" | "Off"

--[=[
    @within Types
    @type SessionInfo { Key: string, Player: Player?, UserId: number?, LoadedAt: number, LastSaveAt: number?, Seq: number, IsActive: boolean }
    Describes the current state and metadata of a loaded session.
]=]
export type SessionInfo = {
    Key: string,
    Player: Player?,
    UserId: number?,
    LoadedAt: number,
    LastSaveAt: number?,
    Seq: number,
    IsActive: boolean,
}

--[=[
    @within Types
    @type CachedSettings table
    A snapshot of the effective settings used by a Strata store.
    Contains the resolved configuration, including defaults for omitted options.
]=]
export type CachedSettings = {
    StoreName: string,
    KeyPrefix: string,
    ReplicateMode: ReplicateMode,
    MaxPatchesBeforeFull: number,
    CollapsePatchesAt: number,
    FlushImmediately: boolean,
    ReplicateOnSave: boolean,
    LoadTimeout: number,
    AutoSaveSeconds: number?,
    SchemaVersion: number?,
    ClientGuard: ClientGuard,
    KickOnFail: boolean,
    KickOnSessionEnd: boolean,
    KickMessage: string,
    Mock: boolean,
}

-- Typed fns

type function Flags(T)
	if not T:is("table") then
		return types.any
	end

	local result = types.newtable()
	for key, property in T:properties() do
		local original = property.read or property.write
		if
			original
			and (
				original:issubtypeof(types.number)
					or original:issubtypeof(types.string)
					or original:issubtypeof(types.boolean)
			)
		then
			result:setproperty(key, types.optional(types.boolean))
		end
	end
	return result
end

type function Access(t: type)
	local function fn(head: { type }?, ret: { type }?): type
		local f = types.newfunction()
		if head then
			f:setparameters(head)
		end
		if ret then
			f:setreturns(ret)
		end
		return f
	end

	local function arrayOf(element: type): type
		local arr = types.newtable()
		arr:setindexer(types.number, element)
		return arr
	end

	local function leaf(valueType: type): type
		local node = types.newtable()
		node:setproperty(types.singleton("Get"), fn({}, { valueType }))
		node:setproperty(types.singleton("Set"), fn({ valueType }, { valueType }))
		node:setproperty(
			types.singleton("Update"),
			fn({ fn({ valueType }, { valueType }) }, { valueType })
		)
		return node
	end

	if t:is("number") then
		return leaf(types.number)
	elseif t:is("boolean") then
		return leaf(types.boolean)
	elseif t:is("string") then
		return leaf(types.string)
	elseif t:is("buffer") then
		return leaf(types.buffer)
	end

	if t:is("singleton") then
		local v = (t :: any):value()
		if type(v) == "boolean" then
			return leaf(types.boolean)
		elseif type(v) == "string" then
			return leaf(types.string)
		elseif type(v) == "number" then
			return leaf(types.number)
		end
	end

	if t:is("table") then
		local node = types.newtable()
		local self_t = types.copy(t)

		for key, prop in t:properties() do
			local valueType = prop.read or prop.write
			if valueType then
				node:setproperty(key, Access(valueType))
			end
		end

		node:setproperty(types.singleton("Get"), fn({}, { self_t }))
		node:setproperty(types.singleton("Set"), fn({ self_t }, { self_t }))
		node:setproperty(types.singleton("Update"), fn({ fn({ self_t }, { self_t }) }, { self_t }))
		node:setproperty(types.singleton("Mutate"), fn({ fn({ self_t }, nil) }, nil))
		node:setproperty(types.singleton("Snapshot"), fn({}, { self_t }))

		local indexer = t:indexer()
		if indexer then
			local indexType = indexer.index
			local resultType = indexer.readresult or indexer.writeresult
			if indexType and resultType then
				node:setindexer(indexType, Access(resultType))
				node:setproperty(types.singleton("Has"), fn({ indexType }, { types.boolean }))
				node:setproperty(types.singleton("Keys"), fn({}, { arrayOf(indexType) }))
				node:setproperty(types.singleton("Values"), fn({}, { arrayOf(resultType) }))
				node:setproperty(types.singleton("Size"), fn({}, { types.number }))
				node:setproperty(types.singleton("Clear"), fn({}, nil))
				node:setproperty(types.singleton("Insert"), fn({ indexType, resultType }, nil))
				node:setproperty(
					types.singleton("Remove"),
					fn({ indexType }, { types.optional(resultType) })
				)
				if indexType:is("number") then
					node:setproperty(types.singleton("Push"), fn({ resultType }, { types.number }))
					node:setproperty(types.singleton("Pop"), fn({}, { types.optional(resultType) }))
					node:setproperty(
						types.singleton("InsertAt"),
						fn({ types.number, resultType }, nil)
					)
					node:setproperty(
						types.singleton("RemoveAt"),
						fn({ types.number }, { types.optional(resultType) })
					)
				end
			end
		end

		return node
	end

	if t:is("union") then
		for _, component in (t :: any):components() do
			if not component:is("nil") then
				return Access(component)
			end
		end
	end

	return leaf(t)
end

type function Session(t: type)
	local function fn(head: { type }?, ret: { type }?): type
		local f = types.newfunction()
		if head then
			f:setparameters(head)
		end
		if ret then
			f:setreturns(ret)
		end
		return f
	end

	local MAX_DEPTH = 3
	local MAX_PATHS = 64

	local node = Access(t)

	node:setproperty(types.singleton("IsLoaded"), fn({}, { types.boolean }))
	node:setproperty(types.singleton("Save"), fn({}, nil))
	node:setproperty(types.singleton("End"), fn({}, nil))
	node:setproperty(types.singleton("Replicate"), fn({ types.optional(types.any) }, nil))
	node:setproperty(types.singleton("GetSessionInfo"), fn({}, { types.any }))
	node:setproperty(types.singleton("GetMeta"), fn({ types.optional(types.string) }, { types.any }))
	node:setproperty(types.singleton("SetMeta"), fn({ types.string, types.any }, nil))

	local disconnect = types.newfunction()
	disconnect:setparameters({}, types.any)
	local connection = types.newtable()
	connection:setproperty(types.singleton("Disconnect"), disconnect)

	local function listenerOf(valueType: type): type
		return fn({ fn({ valueType }, nil) }, { connection })
	end

	local overloads: { type } = {}

	table.insert(overloads, fn({}, { listenerOf(t) }))

	local paths: { type } = {}
	local count = 0
	local function walk(tbl: type, prefix: string, depth: number)
		for key, prop in tbl:properties() do
			local valueType = prop.read or prop.write
			if valueType and key:is("singleton") and count < MAX_PATHS then
				local name = (key :: any):value()
				if type(name) == "string" then
					local path = if prefix == "" then name else prefix .. "." .. name
					count += 1
					local literal = types.singleton(path)
					table.insert(paths, literal)
					table.insert(overloads, fn({ literal }, { listenerOf(valueType) }))
					if depth < MAX_DEPTH and valueType:is("table") then
						walk(valueType, path, depth + 1)
					end
				end
			end
		end
	end

	if t:is("table") then
		walk(t, "", 1)
	end

	if #paths > 0 then
		local union = paths[1]
		for i = 2, #paths do
			union = types.unionof(union, paths[i])
		end
		table.insert(overloads, fn({ union }, { listenerOf(types.any) }))
	end

	local observe = overloads[1]
	for i = 2, #overloads do
		observe = types.intersectionof(observe, overloads[i])
	end
	node:setproperty(types.singleton("Observe"), observe)

	return node
end

-- Public aliases

--[=[
	Represents the complete typed state interface for a Strata store.

	Provides root-level access to data, nested nodes, collection operations,
	session methods, and observation.

	Requires the new Luau type solver for accurate type inference.

	@type State<T> Session<T>
	@within Types
]=]
export type State<T> = Session<T>

--[=[
	Represents a typed node within a Strata state.

	Provides type-aware access to values and nested tables, with methods
	appropriate to the underlying value type.

	Requires the new Luau type solver for accurate type inference.

	@type Node<T> Access<T>
	@within Types
]=]
export type Node<T> = Access<T>

--[=[
	Server interface for a Strata store.

	Provides methods for loading and accessing player sessions, checking
	session status, retrieving session information, and iterating over
	active sessions.

	@type StrataServer<T> {
		LoadVault: (self: StrataServer<T>, Target: string | Player) -> State<T>?,
		GetVault: (self: StrataServer<T>, Target: string | Player) -> State<T>?,
		IsLoaded: (self: StrataServer<T>, Target: string | Player) -> boolean,
		GetSessionInfo: (self: StrataServer<T>, Target: string | Player) -> SessionInfo?,
		GetSettings: (self: StrataServer<T>) -> CachedSettings,
		GetPlayerFromKey: (self: StrataServer<T>, Key: string) -> Player?,
		ForEachSession: (self: StrataServer<T>, Callback: (Key: string, State: State<T>, Info: SessionInfo) -> ()) -> (),
	}
	@within Types
]=]
export type StrataServer<T> = {
	LoadVault: (self: StrataServer<T>, Target: string | Player) -> State<T>?,
	GetVault: (self: StrataServer<T>, Target: string | Player) -> State<T>?,
	IsLoaded: (self: StrataServer<T>, Target: string | Player) -> boolean,
	GetSessionInfo: (self: StrataServer<T>, Target: string | Player) -> SessionInfo?,
	GetSettings: (self: StrataServer<T>) -> CachedSettings,
	GetPlayerFromKey: (self: StrataServer<T>, Key: string) -> Player?,
	ForEachSession: (self: StrataServer<T>, Callback: (Key: string, State: State<T>, Info: SessionInfo) -> ()) -> (),
}

--[=[
	Client interface for a Strata store.

	Provides access to the client's replicated state, loading status,
	store settings, and manual synchronization.

	The client replica is read-only.

	@type StrataClient<T> {
		LoadVault: (self: StrataClient<T>) -> State<T>?,
		GetVault: (self: StrataClient<T>) -> State<T>?,
		IsLoaded: (self: StrataClient<T>) -> boolean,
		GetSettings: (self: StrataClient<T>) -> CachedSettings,
		RequestSync: (self: StrataClient<T>) -> (),
	}
	@within Types
]=]
export type StrataClient<T> = {
	LoadVault: (self: StrataClient<T>) -> State<T>?,
	GetVault: (self: StrataClient<T>) -> State<T>?,
	IsLoaded: (self: StrataClient<T>) -> boolean,
	GetSettings: (self: StrataClient<T>) -> CachedSettings,
	RequestSync: (self: StrataClient<T>) -> (),
}

--[=[
	Configuration used to initialize a Strata store.

	`StoreName` and `Template` are required. All other properties are
	optional and use Strata's defaults when omitted.

	Includes session lifecycle hooks, mutation callbacks, replication
	settings, and data migration options.

	@type Config<T> {
		StoreName: string,
		Template: T,
		Leaderstats: Flags<T>?,
		KeyPrefix: string?,
		PlayerKey: ((Player) -> string)?,
		Mock: boolean?,
		KickOnFail: boolean?,
		KickOnSessionEnd: boolean?,
		KickMessage: string?,
		LoadTimeout: number?,
		SchemaVersion: number?,
		Migrate: ((Data: T, FromVersion: number, ToVersion: number) -> ())?,
		AutoSaveSeconds: number?,
		ReplicateMode: ReplicateMode?,
		MaxPatchesBeforeFull: number?,
		CollapsePatchesAt: number?,
		FlushImmediately: boolean?,
		ReplicateOnSave: boolean?,
		ClientGuard: ClientGuard?,
		BeforeMutate: ((Context: MutateContext<T>) -> ())?,
		AfterMutate: ((Context: MutateContext<T>) -> ())?,
		OnSessionStart: ((Key: string, Player: Player?, Data: T) -> ())?,
		OnSessionEnd: ((Key: string, Player: Player?) -> ())?,
	}
	@within Types
]=]
export type Config<T> = {
	-- Mandatory
	StoreName: string,
	Template: T,

	-- Optional
	Leaderstats: Flags<T>?,
	KeyPrefix: string?,
	PlayerKey: ((Player) -> string)?,
	Mock: boolean?,
	KickOnFail: boolean?,
	KickOnSessionEnd: boolean?,
	KickMessage: string?,
	LoadTimeout: number?,
	SchemaVersion: number?,
	Migrate: ((Data: T, FromVersion: number, ToVersion: number) -> ())?,
	AutoSaveSeconds: number?,
	ReplicateMode: ReplicateMode?,
	MaxPatchesBeforeFull: number?,
	CollapsePatchesAt: number?,
	FlushImmediately: boolean?,
	ReplicateOnSave: boolean?,
	ClientGuard: ClientGuard?,
	BeforeMutate: ((Context: MutateContext<T>) -> ())?,
	AfterMutate: ((Context: MutateContext<T>) -> ())?,

	-- Session lifecycle hooks
	OnSessionStart: ((Key: string, Player: Player?, Data: T) -> ())?,
	OnSessionEnd: ((Key: string, Player: Player?) -> ())?,
}

--[=[
	Describes the ProfileStore session interface used internally by Strata.

	Contains the underlying data, metadata, user IDs, and session lifecycle
	and saving methods.

	@type Profile<T> {
		Data: T,
		RobloxMetaData: JSONAcceptable,
		UserIds: { number },
		Key: string,
		OnSessionEnd: any,
		IsActive: (self: Profile<T>) -> boolean,
		Reconcile: (self: Profile<T>) -> (),
		EndSession: (self: Profile<T>) -> (),
		AddUserId: (self: Profile<T>, UserId: number) -> (),
		Save: (self: Profile<T>) -> (),
	}
	@within Types
]=]
export type Profile<T> = {
	Data: T,
	RobloxMetaData: JSONAcceptable,
	UserIds: { number },
	Key: string,
	OnSessionEnd: any,
	IsActive: (self: Profile<T>) -> boolean,
	Reconcile: (self: Profile<T>) -> (),
	EndSession: (self: Profile<T>) -> (),
	AddUserId: (self: Profile<T>, UserId: number) -> (),
	Save: (self: Profile<T>) -> (),
}

--[=[
	Represents an individual data replication patch.

	Contains the path being modified and the value associated with that path.

	@type ReplicaPath { Path: Path, Value: any }
	@within Types
]=]
export type ReplicaPatch = {
	Path: Path,
	Value: any,
}

return {}

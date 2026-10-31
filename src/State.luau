--!optimize 2
--!strict

--[=[
	@class State
	@server
	@client

	The core state interface used by Strata.

	Each state node represents a path within a session. Nodes expose
	pre-bound methods, allowing access through dot syntax without passing
	`self`.

	```lua
	local S = Server:LoadVault(Player)
	if S then
		S.Coins.Update(function(Amount)
			return Amount + 50
		end)

		S.Inventory.Push("Sword")

		S.Observe("Coins")(function(Coins)
			print(`New Amount: {Coins}`)
		end)
	end
	```

	**All nodes:** Get, Set, Update

	**Tables:** Mutate, Snapshot

	**Maps / arrays:** Has, Keys, Values, Size, Clear, Insert, Remove

	**Arrays:** Push, Pop, InsertAt, RemoveAt

	**Root only:** Observe, IsLoaded, Save, End, Replicate,
	GetSessionInfo, GetMeta, SetMeta

	:::danger Type solver required
	Autocomplete needs the new Luau type solver. Runtime works without it.
	:::
]=]

local Util = require(script.Parent.Util)

--[=[
	Defines the communication interface between a State node and its
	underlying session.

	Provides access to session data, mutation operations, observation,
	replication, and session metadata.

	@within State
	@type Bridge {
		GetRoot: (Key: string) -> any?,
		IsLoaded: (Key: string) -> boolean,
		Write: ((Key: string, Path: { any }, Value: any) -> ())?,
		Mutate: ((Key: string, Path: { any }, Mutator: (Target: any) -> (), Full: boolean?) -> ())?,
		Observe: (Key: string, TagPath: { any }?, Listener: (Value: any) -> ()) -> { Disconnect: (...any) -> () },
		Save: ((Key: string) -> ())?,
		End: ((Key: string) -> ())?,
		Replicate: ((Key: string, Target: Player?) -> ())?,
		GetSessionInfo: ((Key: string) -> any?)?,
		GetMeta: ((Key: string, MetaKey: string?) -> any)?,
		SetMeta: ((Key: string, MetaKey: string, Value: any) -> ())?,
		ReadOnly: boolean,
		Guard: boolean,
	}
]=]
export type Bridge = {
	GetRoot: (Key: string) -> any?,
	IsLoaded: (Key: string) -> boolean,
	Write: ((Key: string, Path: { any }, Value: any) -> ())?,
	Mutate: ((Key: string, Path: { any }, Mutator: (Target: any) -> (), Full: boolean?) -> ())?,
	Observe: (Key: string, TagPath: { any }?, Listener: (Value: any) -> ()) -> { Disconnect: (...any) -> () },
	Save: ((Key: string) -> ())?,
	End: ((Key: string) -> ())?,
	Replicate: ((Key: string, Target: Player?) -> ())?,
	GetSessionInfo: ((Key: string) -> any?)?,
	GetMeta: ((Key: string, MetaKey: string?) -> any)?,
	SetMeta: ((Key: string, MetaKey: string, Value: any) -> ())?,
	ReadOnly: boolean,
	Guard: boolean,
}

type Observer = {
	Disconnect: (self: Observer) -> (),
}

type Backend = {
	Observe: (
		Key: string,
		TagPath: { any }?,
		Listener: (Value: any) -> ()
	) -> Observer,
}

type Node = {
	_k: string,
	_b: Backend,
}

local ROOT_ONLY: { [any]: boolean } = {
	IsLoaded = true,
	Observe = true,
	Save = true,
	End = true,
	Replicate = true,
	GetSessionInfo = true,
	GetMeta = true,
	SetMeta = true,
}

local Methods: { [any]: any } = {}
local NodeMT = {}

local function Make(
	Bridge: Backend,
	Key: string,
	Path: { any }
): Node
	return setmetatable({
		_b = Bridge,
		_k = Key,
		_p = Path,
		_c = {},
		_f = {},
	}, NodeMT)
end

local function ChildPath(Node: any, Segment: any): { any }
	local Out = table.clone(Node._p)
	table.insert(Out, Segment)
	return Out
end

local function Resolve(Node: any): any
	local Root = Node._b.GetRoot(Node._k)
	if Root == nil then
		return nil
	end
	local Path = Node._p
	if #Path == 0 then
		return Root
	end
	return Util.GetAt(Root, Path)
end

local function Writable(Node: any)
	local Bridge = Node._b
	if Bridge.ReadOnly then
		error(Util.READ_ONLY_MESSAGE, 3)
	end
	if not Bridge.Write or not Bridge.Mutate then
		error("Strata: writes are not available", 3)
	end
end

-- Core

function Methods.Get(Node: any): any
	local Value = Util.FromStore(Resolve(Node))
	if Node._b.Guard and type(Value) == "table" then
		return Util.ReadOnly(Value, Util.READ_ONLY_MESSAGE)
	end
	return Value
end

function Methods.Snapshot(Node: any): any
	local Value = Util.FromStore(Resolve(Node))
	if Value == nil then
		return nil
	end
	return Util.DeepCopy(Value)
end

function Methods.Set(Node: any, Value: any): any
	Writable(Node)
	local Bridge = Node._b
	if #Node._p == 0 then
		if type(Value) ~= "table" then
			error("Strata: Set on the root expects a table", 2)
		end
		Bridge.Mutate(Node._k, Node._p, function(Data)
			table.clear(Data)
			for K, V in Value do
				Data[K] = Util.ToStore(V)
			end
		end, true)
	else
		Bridge.Write(Node._k, Node._p, Value)
	end
	return Methods.Get(Node)
end

function Methods.Update(Node: any, Updater: (Current: any) -> any): any
	return Methods.Set(Node, Updater(Methods.Get(Node)))
end

function Methods.Mutate(Node: any, Mutator: (Target: any) -> ())
	Writable(Node)
	Node._b.Mutate(Node._k, Node._p, Mutator, false)
end

-- Maps / arrays

function Methods.Has(Node: any, ChildKey: any): boolean
	local Value = Resolve(Node)
	return type(Value) == "table" and Value[ChildKey] ~= nil
end

function Methods.Keys(Node: any): { any }
	local Out = {}
	local Value = Resolve(Node)
	if type(Value) == "table" then
		for K in Value do
			table.insert(Out, K)
		end
	end
	return Out
end

function Methods.Values(Node: any): { any }
	local Out = {}
	local Value = Resolve(Node)
	if type(Value) == "table" then
		for _, V in Value do
			table.insert(Out, V)
		end
	end
	return Out
end

function Methods.Size(Node: any): number
	local N = 0
	local Value = Resolve(Node)
	if type(Value) == "table" then
		for _ in Value do
			N += 1
		end
	end
	return N
end

function Methods.Clear(Node: any)
	Methods.Set(Node, {})
end

function Methods.Insert(Node: any, ChildKey: any, ChildValue: any)
	Writable(Node)
	Node._b.Write(Node._k, ChildPath(Node, ChildKey), ChildValue)
end

function Methods.Remove(Node: any, ChildKey: any): any
	Writable(Node)
	local Value = Resolve(Node)
	local Old = if type(Value) == "table" then Value[ChildKey] else nil
	Node._b.Write(Node._k, ChildPath(Node, ChildKey), nil)
	return Old
end

function Methods.Push(Node: any, Value: any): number
	Writable(Node)
	local Arr = Resolve(Node)
	local Length = if type(Arr) == "table" then #Arr else 0
	Node._b.Write(Node._k, ChildPath(Node, Length + 1), Value)
	return Length + 1
end

function Methods.Pop(Node: any): any
	Writable(Node)
	local Arr = Resolve(Node)
	if type(Arr) ~= "table" or #Arr == 0 then
		return nil
	end
	local Length = #Arr
	local Old = Arr[Length]
	Node._b.Write(Node._k, ChildPath(Node, Length), nil)
	return Old
end

function Methods.InsertAt(Node: any, Index: number, Value: any)
	Writable(Node)
	local Arr = Resolve(Node)
	local Copy = if type(Arr) == "table" then table.clone(Arr) else {}
	table.insert(Copy, Index, Value)
	Methods.Set(Node, Copy)
end

function Methods.RemoveAt(Node: any, Index: number): any
	Writable(Node)
	local Arr = Resolve(Node)
	if type(Arr) ~= "table" then
		return nil
	end
	local Copy = table.clone(Arr)
	local Old = table.remove(Copy, Index)
	Methods.Set(Node, Copy)
	return Old
end

-- Root-only

function Methods.Observe(
	Node: Node,
	Tag: any,
	Listener: ((Value: any) -> ())?
): (Value: any) -> ()
	if type(Tag) == "function" then
		Listener = Tag
		Tag = nil
	end

	local function connect(listener: (Value: any) -> ())
		assert(
			type(listener) == "function",
			"Strata: Observe expects a listener function"
		)
		local TagPath: { any }? = nil
		if Tag ~= nil then
			TagPath = Util.NormalizePath(Tag)
			if #TagPath == 0 then
				TagPath = nil
			end
		end
		return Node._b.Observe(Node._k, TagPath, listener)
	end

	if Listener == nil then
		return connect
	end

	return connect(Listener)
end

function Methods.IsLoaded(Node: any): boolean
	return Node._b.IsLoaded(Node._k)
end

function Methods.Save(Node: any)
	if Node._b.Save then
		Node._b.Save(Node._k)
	end
end

function Methods.End(Node: any)
	if Node._b.End then
		Node._b.End(Node._k)
	end
end

function Methods.Replicate(Node: any, Target: Player?)
	if Node._b.Replicate then
		Node._b.Replicate(Node._k, Target)
	end
end

function Methods.GetSessionInfo(Node: any): any?
	if Node._b.GetSessionInfo then
		return Node._b.GetSessionInfo(Node._k)
	end
	return nil
end

function Methods.GetMeta(Node: any, MetaKey: string?): any
	if Node._b.GetMeta then
		return Node._b.GetMeta(Node._k, MetaKey)
	end
	return nil
end

function Methods.SetMeta(Node: any, MetaKey: string, Value: any)
	if Node._b.SetMeta then
		Node._b.SetMeta(Node._k, MetaKey, Value)
	end
end

-- Metatable

NodeMT.__index = function(Node: any, Key: any): any
	local Impl = Methods[Key]
	if Impl ~= nil and (ROOT_ONLY[Key] == nil or #Node._p == 0) then
		local Bound = Node._f[Key]
		if not Bound then
			Bound = function(...)
				return Impl(Node, ...)
			end
			Node._f[Key] = Bound
		end
		return Bound
	end
	local Child = Node._c[Key]
	if not Child then
		Child = Make(Node._b, Node._k, ChildPath(Node, Key))
		Node._c[Key] = Child
	end
	return Child
end

NodeMT.__newindex = function()
	error("Strata: assign with .Set(value), not S.Key = value", 2)
end

NodeMT.__tostring = function(Node: any)
	local Parts = {}
	for I, Segment in Node._p do
		Parts[I] = tostring(Segment)
	end
	local Suffix = if #Parts == 0 then "" else "." .. table.concat(Parts, ".")
	return ("StrataState<%s>%s"):format(tostring(Node._k), Suffix)
end

local State = {}

--[=[
	Creates a new state node for a session.

	The returned node represents the root of the session's data.
	Child nodes are created automatically when accessing nested properties.

	@param Bridge Bridge -- Backend interface used by the state.
	@param Key string -- Session key associated with the state.
	@return Node
]=]
function State.new(Bridge: Bridge, Key: string): Node
	return Make(Bridge, Key, {})
end

return State

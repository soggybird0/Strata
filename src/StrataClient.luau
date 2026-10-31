--!optimize 2
--!strict

--[=[
	@class StrataClient
	@client

	Client replica of a Strata store. Same State surface as the server, but
	writes error (mutate on the server only).
]=]

local Remote = require(script.Parent.Libraries.Remote)
local Signal = require(script.Parent.Libraries.Signal)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)
local State = require(script.Parent.State)

local ReplicaEvent = Remote.event("Strata_Replicate")
local ReplicaRequest = Remote.event("Strata_Request")

local DEFAULT_TIMEOUT = 30

local Clients = {}
local Listening = false

local function ApplyPatches(Root: any, Patches: { Types.ReplicaPatch }): any
	local Working = Util.Unwrap(Root)
	if type(Working) ~= "table" then
		Working = {}
	end
	for _, Patch in Patches do
		local Value = if type(Patch.Value) == "table" then Util.DeepCopy(Patch.Value) else Patch.Value
		if #Patch.Path == 0 then
			Working = if type(Value) == "table" then Value else {}
		else
			Util.SetAt(Working, Patch.Path, Value)
		end
	end
	return Working
end

local function HandlePayload(Client: any, Payload: any)
	local Decoded = Payload
	if typeof(Payload.Buffer) == "buffer" then
		local Ok, Result = pcall(Util.DecodeReplica, Payload.Buffer)
		if not Ok then
			warn("[Strata] DecodeReplica failed:", Result)
			Client.RequestSync()
			return
		end
		Decoded = Result
	end
	if type(Decoded) ~= "table" then
		return
	end
	if type(Decoded.Seq) ~= "number" or Decoded.Seq <= Client.Seq then
		return
	end

	if Decoded.Kind == "Patch" then
		if Client.Raw == nil or Decoded.Seq ~= Client.Seq + 1 then
			Client.RequestSync()
			return
		end
		if type(Decoded.Patches) ~= "table" then
			return
		end
		Client.Key = Decoded.Key
		Client.Seq = Decoded.Seq
		Client.Raw = ApplyPatches(Client.Raw, Decoded.Patches)
		local Paths = table.create(#Decoded.Patches)
		for I, Patch in Decoded.Patches do
			Paths[I] = Patch.Path
		end
		Client.Changed:Fire(Client.Raw, Paths)
		return
	end

	if Decoded.Kind ~= "Full" or Decoded.Data == nil then
		return
	end
	Client.Key = Decoded.Key
	Client.Seq = Decoded.Seq
	Client.Raw = Util.DeepCopy(Decoded.Data)
	Client.Changed:Fire(Client.Raw, nil)
end

local function EnsureListener()
	if Listening then
		return
	end
	Listening = true
	ReplicaEvent.OnClientEvent:Connect(function(Payload)
		if type(Payload) ~= "table" or type(Payload.StoreName) ~= "string" then
			return
		end
		local Client = Clients[Payload.StoreName]
		if Client then
			HandlePayload(Client, Payload)
		end
	end)
end

local StrataClient = {}

--[=[
    Opens or retrieves a client replica for a Strata store.

    Creates a client replica if one does not already exist. Subsequent
    calls for the same store reuse the existing replica.

    The returned client automatically requests its initial data and
    receives subsequent replication updates.

    @param Options Config<T>
    @return StrataClient<T>
]=]
function StrataClient.Open<T>(Options: Types.Config<T>): Types.StrataClient<T>
	local Existing = Clients[Options.StoreName]
	if Existing then
		return Existing.API
	end

	EnsureListener()

	local Guard = Options.ClientGuard ~= "Off"
	local Timeout = Options.LoadTimeout or DEFAULT_TIMEOUT

	local CachedSettings: Types.CachedSettings = {
		StoreName = Options.StoreName,
		KeyPrefix = Options.KeyPrefix or "",
		ReplicateMode = Options.ReplicateMode or "Hybrid",
		MaxPatchesBeforeFull = Options.MaxPatchesBeforeFull or 24,
		CollapsePatchesAt = Options.CollapsePatchesAt or 12,
		FlushImmediately = Options.FlushImmediately == true,
		ReplicateOnSave = Options.ReplicateOnSave == true,
		LoadTimeout = Timeout,
		AutoSaveSeconds = Options.AutoSaveSeconds,
		SchemaVersion = Options.SchemaVersion,
		ClientGuard = if Guard then "Proxy" else "Off",
		KickOnFail = Options.KickOnFail ~= false,
		KickOnSessionEnd = Options.KickOnSessionEnd ~= false,
		KickMessage = Options.KickMessage or "Could not load your data. Please rejoin.",
		Mock = Options.Mock == true,
	}

	local Client = {
		Raw = nil :: any,
		Key = nil :: string?,
		Seq = 0,
		Changed = Signal.new(),
		API = nil :: any,
	}

	function Client.RequestSync()
		local Ok, Err = pcall(function()
			ReplicaRequest:FireServer({ StoreName = Options.StoreName })
		end)
		if not Ok then
			warn("[Strata] RequestSync failed:", Err)
		end
	end

	local Bridge = {
		GetRoot = function()
			return Client.Raw
		end,
		IsLoaded = function()
			return Client.Raw ~= nil
		end,
		Observe = function(_: string, TagPath: { any }?, Listener: (Value: any) -> ())
			return Util.Subscribe(Client.Changed, TagPath, Listener, function(Data: any)
				local Value = if TagPath then Util.GetAt(Data, TagPath) else Data
				if Guard and type(Value) == "table" then
					return Util.ReadOnly(Value, Util.READ_ONLY_MESSAGE)
				end
				return Value
			end, function()
				return Client.Raw
			end)
		end,
		GetSessionInfo = function()
			if Client.Raw == nil then
				return nil
			end
			return {
				Key = Client.Key or Options.StoreName,
				Player = nil,
				UserId = nil,
				LoadedAt = 0,
				LastSaveAt = nil,
				Seq = Client.Seq,
				IsActive = true,
			}
		end,
		ReadOnly = true,
		Guard = Guard,
	}	

	local Root: any = nil

	local function EnsureRoot(): any
		if not Root then
			Root = State.new(Bridge, Client.Key or Options.StoreName)
		end
		return Root
	end

	--[=[
    	Waits for the initial replica to become available. 
    	Returns the State instance once the replica has loaded. 
    	Returns nil if the configured loading timeout is reached.

    	@within StrataClient
    	@param self StrataClient<T>
    	@return State<T>?
	]=]
	local function LoadVault(self: Types.StrataClient<T>): Types.State<T>?
		if Client.Raw == nil then
			local Ready = Util.WaitSettled(Timeout, function(Settle)
				return {
					Client.Changed:Connect(function()
						Settle(true)
					end),
				}
			end)
			if not Ready then
				return nil
			end
		end
		return EnsureRoot()
	end

	--[=[
		Retrieves the existing client replica without waiting.

		Returns nil if the replica has not loaded yet.

		@within StrataClient
		@param self StrataClient<T>
		@return State<T>?
	]=]
	local function GetVault(self: Types.StrataClient<T>): Types.State<T>?
		if Client.Raw == nil then
			return nil
		end
		return EnsureRoot()
	end

	--[=[
		Checks whether the client replica has loaded.

		@within StrataClient
		@param self StrataClient<T>
		@return boolean
	]=]
	local function IsLoaded(self: Types.StrataClient<T>): boolean
		return Client.Raw ~= nil
	end

	--[=[
		Retrieves the cached configuration for this client store.

		@within StrataClient
		@param self StrataClient<T>
		@return CachedSettings
	]=]
	local function GetSettings(self: Types.StrataClient<T>): Types.CachedSettings
		return CachedSettings
	end

	--[=[
		Requests a full synchronization of the client replica from the server.

		@within StrataClient
		@param self StrataClient<T>
	]=]
	local function RequestSyncAPI(self: Types.StrataClient<T>)
		Client.RequestSync()
	end

	Client.API = {
		LoadVault = LoadVault,
		GetVault = GetVault,
		IsLoaded = IsLoaded,
		GetSettings = GetSettings,
		RequestSync = RequestSyncAPI,
	}
	Clients[Options.StoreName] = Client

	task.defer(function()
		if Client.Raw == nil then
			Client.RequestSync()
		end
	end)

	return Client.API :: Types.StrataClient<T>
end

return StrataClient

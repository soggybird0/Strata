--!optimize 2
--!strict

--[=[
	@class StrataServer
	@server

	Server session manager. Public surface: LoadVault, GetVault, IsLoaded,
	GetSessionInfo, GetSettings, ForEachSession. Sessions load/end automatically
	for every player.
]=]

local Players = game:GetService("Players")

local ProfileStore = require(script.Parent.Libraries.ProfileStore)
local Signal = require(script.Parent.Libraries.Signal)
local Remote = require(script.Parent.Libraries.Remote)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)
local State = require(script.Parent.State)

local ReplicaEvent = Remote.event("Strata_Replicate")
local ReplicaRequest = Remote.event("Strata_Request")

local DEFAULT_KICK_FAIL = "Could not load your data. Please rejoin."
local DEFAULT_KICK_END = "Your data session ended. Please rejoin."
local DEFAULT_MAX_PATCHES = 24
local DEFAULT_COLLAPSE = 12
local DEFAULT_LOAD_TIMEOUT = 30

local VALUE_CLASS: { [string]: string } = {
	number = "NumberValue",
	string = "StringValue",
	boolean = "BoolValue",
}

local StrataServer = {}

--[=[
	Initializes a server store and its session manager.

	Creates the underlying ProfileStore and automatically manages player
	sessions, saving, replication, and cleanup.

	@param Options Config<T>
	@return StrataServer<T>
]=]
function StrataServer.Open<T>(Options: Types.Config<T>): Types.StrataServer<T>
	assert(type(Options) == "table", "Strata: config must be a table")
	assert(type(Options.StoreName) == "string" and Options.StoreName ~= "", "Strata: StoreName required")
	assert(type(Options.Template) == "table", "Strata: Template required")

	local StoreTemplate = Util.ToStore(Options.Template)
	local LiveStore = ProfileStore.New(Options.StoreName, StoreTemplate)
	local Backend = if Options.Mock == true then LiveStore.Mock else LiveStore

	local KeyPrefix = Options.KeyPrefix or ""
	local MakeKey = Options.PlayerKey or function(Player: Player): string
		return KeyPrefix .. tostring(Player.UserId)
	end

	local CachedSettings: Types.CachedSettings = {
		StoreName = Options.StoreName,
		KeyPrefix = KeyPrefix,
		ReplicateMode = Options.ReplicateMode or "Hybrid",
		MaxPatchesBeforeFull = Options.MaxPatchesBeforeFull or DEFAULT_MAX_PATCHES,
		CollapsePatchesAt = Options.CollapsePatchesAt or DEFAULT_COLLAPSE,
		FlushImmediately = Options.FlushImmediately == true,
		ReplicateOnSave = Options.ReplicateOnSave == true,
		LoadTimeout = Options.LoadTimeout or DEFAULT_LOAD_TIMEOUT,
		AutoSaveSeconds = Options.AutoSaveSeconds,
		SchemaVersion = Options.SchemaVersion,
		ClientGuard = Options.ClientGuard or "Proxy",
		KickOnFail = Options.KickOnFail ~= false,
		KickOnSessionEnd = Options.KickOnSessionEnd ~= false,
		KickMessage = Options.KickMessage or DEFAULT_KICK_FAIL,
		Mock = Options.Mock == true,
	}

	local Sessions: { [string]: Types.Profile<T> } = {}
	local Roots: { [string]: Types.State<T> } = {}
	local KeyPlayers: { [string]: Player } = {}
	local SessionMeta: { [string]: { LoadedAt: number, LastSaveAt: number? } } = {}
	local Seq: { [string]: number } = {}
	local PendingPatches: { [string]: { Types.ReplicaPatch } } = {}
	local PendingFull: { [string]: boolean } = {}
	local Changed: { [string]: any } = {}
	local Stats: { [string]: { [string]: any } } = {}
	local Loading: { [string]: boolean } = {}
	local LoadWaiters: { [string]: { thread } } = {}

	local FlushScheduled = false
	local Closing = false

	local ReplicateMode = CachedSettings.ReplicateMode
	local MaxPatchesBeforeFull = CachedSettings.MaxPatchesBeforeFull
	local CollapseAt = CachedSettings.CollapsePatchesAt
	local FlushImmediately = CachedSettings.FlushImmediately
	local ReplicateOnSave = CachedSettings.ReplicateOnSave
	local SchemaVersion = CachedSettings.SchemaVersion
	local LoadTimeout = CachedSettings.LoadTimeout
	local Flags = Options.Leaderstats :: { [string]: boolean }?

	local Loaded = Signal.new()

	-- Helpers

	local function ResolveKey(Target: string | Player): (string, Player?)
		if typeof(Target) == "Instance" then
			local Player = Target :: Player
			return MakeKey(Player), Player
		end
		return Target :: string, nil
	end

	local function GetSession(Key: string): Types.Profile<T>?
		local Profile = Sessions[Key]
		if Profile and Profile:IsActive() then
			return Profile
		end
		return nil
	end

	local function BuildSessionInfo(Key: string): Types.SessionInfo?
		local Profile = GetSession(Key)
		if not Profile then
			return nil
		end
		local Meta = SessionMeta[Key]
		local Player = KeyPlayers[Key]
		return {
			Key = Key,
			Player = Player,
			UserId = if Player then Player.UserId else (Profile.UserIds[1]),
			LoadedAt = if Meta then Meta.LoadedAt else 0,
			LastSaveAt = if Meta then Meta.LastSaveAt else nil,
			Seq = Seq[Key] or 0,
			IsActive = Profile:IsActive(),
		}
	end

	-- Replication

	local function FireEncoded(Key: string, Kind: string, Data: any?, Patches: any?, Target: Player?)
		local Profile = Sessions[Key]
		if not Profile or not Profile:IsActive() then
			return
		end
		local Player = Target or KeyPlayers[Key]
		if not Player or Player.Parent ~= Players then
			return
		end
		local SeqN = (Seq[Key] or 0) + 1
		Seq[Key] = SeqN
		local Ok, Err = pcall(function()
			ReplicaEvent:FireClient(Player, {
				StoreName = Options.StoreName,
				Key = Key,
				Seq = SeqN,
				Kind = Kind,
				Buffer = Util.EncodeReplica(Kind, Options.StoreName, Key, SeqN, Data, Patches),
			})
		end)
		if not Ok then
			warn(("[Strata] FireClient failed for %s: %s"):format(Key, tostring(Err)))
		end
	end

	local function FireFull(Key: string, Target: Player?)
		local Profile = GetSession(Key)
		if Profile then
			FireEncoded(Key, "Full", Util.FromStore(Profile.Data), nil, Target)
		end
	end

	local function QueueFull(Key: string)
		PendingFull[Key] = true
		PendingPatches[Key] = nil
	end

	local function QueuePatches(Key: string, Patches: { Types.ReplicaPatch })
		if PendingFull[Key] then
			return
		end
		if ReplicateMode == "Full" then
			QueueFull(Key)
			return
		end
		local Bucket = PendingPatches[Key]
		if not Bucket then
			Bucket = {}
			PendingPatches[Key] = Bucket
		end
		for _, Patch in Patches do
			table.insert(Bucket, Patch)
		end
		if #Bucket >= MaxPatchesBeforeFull then
			QueueFull(Key)
		end
	end

	local function FlushKey(Key: string)
		if PendingFull[Key] then
			PendingFull[Key] = nil
			PendingPatches[Key] = nil
			FireFull(Key)
			return
		end
		local Bucket = PendingPatches[Key]
		if not Bucket or #Bucket == 0 then
			return
		end
		PendingPatches[Key] = nil
		FireEncoded(Key, "Patch", nil, Bucket, nil)
	end

	local function FlushAll()
		FlushScheduled = false

		local FullKeys = {}
		for Key in PendingFull do
			table.insert(FullKeys, Key)
		end
		local PatchKeys = {}
		for Key in PendingPatches do
			if not PendingFull[Key] then
				table.insert(PatchKeys, Key)
			end
		end
		for _, Key in FullKeys do
			FlushKey(Key)
		end
		for _, Key in PatchKeys do
			FlushKey(Key)
		end
	end

	local function ScheduleFlush()
		if FlushImmediately then
			FlushAll()
			return
		end
		if FlushScheduled then
			return
		end
		FlushScheduled = true
		task.defer(FlushAll)
	end

	-- Leaderstats

	local function BindStats(Key: string, Player: Player, Profile: Types.Profile<T>)
		if not Flags then
			return
		end

		local Existing = Player:FindFirstChild("leaderstats")
		if Existing then
			Existing:Destroy()
		end
		local Folder = Instance.new("Folder")
		Folder.Name = "leaderstats"
		local Values: { [string]: any } = {}
		local Data = Profile.Data :: any
		for Name, Enabled in Flags do
			if Enabled ~= true then
				continue
			end
			local Current = Data[Name]
			local Class = VALUE_CLASS[type(Current)]
			if not Class then
				warn(("Strata: leaderstat %q must be a number, string or boolean in Template"):format(tostring(Name)))
				continue
			end
			local Obj = Instance.new(Class)
			Obj.Name = tostring(Name)
			Obj.Value = Current
			Obj.Parent = Folder
			Values[Name] = Obj
		end
		Stats[Key] = Values
		Folder.Parent = Player
	end

	local function SyncStats(Key: string, Data: any, Paths: { { any } }?)
		local Values = Stats[Key]
		if not Values then
			return
		end
		local function Sync(Name: any)
			local Obj = Values[Name]
			if Obj and Obj.Value ~= Data[Name] then
				Obj.Value = Data[Name]
			end
		end
		if Paths == nil then
			for Name in Values do
				Sync(Name)
			end
			return
		end
		for _, Path in Paths do
			if #Path == 0 then
				for Name in Values do
					Sync(Name)
				end
				return
			end
			Sync(Path[1])
		end
	end

	-- Mutation

	local function RunHook(Hook: ((Context: Types.MutateContext<T>) -> ())?, Name: string, Context: Types.MutateContext<T>)
		if not Hook then
			return
		end
		local Ok, Err = pcall(Hook, Context)
		if not Ok then
			warn("[Strata] " .. Name .. " error:", Err)
		end
	end

	local function BeginMutate(Key: string, Path: { any }): (Types.Profile<T>?, Types.MutateContext<T>?)
		local Profile = GetSession(Key)
		if not Profile then
			return nil, nil
		end
		local Context: Types.MutateContext<T> = {
			Key = Key,
			Player = KeyPlayers[Key],
			Data = Profile.Data,
			Path = Path,
		}
		RunHook(Options.BeforeMutate, "BeforeMutate", Context)
		return Profile, Context
	end

	local function Notify(Key: string, Data: any, Paths: { { any } }?)
		SyncStats(Key, Data, Paths)
		local Sig = Changed[Key]
		if Sig then
			Sig:Fire(Data, Paths)
		end
	end

	local function WritePath(Key: string, Path: { any }, Value: any)
		if #Path == 0 then
			return
		end
		local Profile, Context = BeginMutate(Key, Path)
		if not Profile or not Context then
			return
		end
		local Stored = Util.ToStore(Value)
		Util.SetAt(Profile.Data, Path, Stored)
		RunHook(Options.AfterMutate, "AfterMutate", Context)
		if ReplicateMode == "Full" then
			QueueFull(Key)
		else
			QueuePatches(Key, { { Path = Util.ClonePath(Path), Value = Util.FromStore(Stored) } })
		end
		ScheduleFlush()
		Notify(Key, Profile.Data, { Path })
	end

	local function MutateAt(Key: string, Path: { any }, Mutator: (Target: any) -> (), Full: boolean?)
		local Profile, Context = BeginMutate(Key, Path)
		if not Profile or not Context then
			return
		end
		local Target: any = if #Path == 0 then Profile.Data else Util.GetAt(Profile.Data, Path)
		if type(Target) ~= "table" then
			error("Strata: Mutate on a non-table path", 3)
		end

		if Full or ReplicateMode == "Full" then
			Mutator(Target)
			RunHook(Options.AfterMutate, "AfterMutate", Context)
			QueueFull(Key)
			ScheduleFlush()
			Notify(Key, Profile.Data, nil)
			return
		end

		local Before = Util.DeepCopy(Target)
		Mutator(Target)
		RunHook(Options.AfterMutate, "AfterMutate", Context)
		local Patches = Util.Diff(Before, Target, CollapseAt)
		if #Patches == 0 then
			return
		end
		local Paths = table.create(#Patches)
		for I, Patch in Patches do
			local Joined = table.clone(Path)
			for _, Segment in Patch.Path do
				table.insert(Joined, Segment)
			end
			Patch.Path = Joined
			Paths[I] = Joined
		end
		QueuePatches(Key, Patches)
		ScheduleFlush()
		Notify(Key, Profile.Data, Paths)
	end

	local function ObserveAt(Key: string, TagPath: { any }?, Listener: (Value: any) -> ())
		local Sig = Changed[Key]
		if not Sig then
			Sig = Signal.new()
			Changed[Key] = Sig
		end
		return Util.Subscribe(Sig, TagPath, Listener, function(Data: any)
			return if TagPath then Util.GetAt(Data, TagPath) else Data
		end, function()
			local Profile = GetSession(Key)
			return if Profile then Profile.Data else nil
		end)
	end

	-- Sessions

	local function ForgetKey(Key: string)
		PendingPatches[Key] = nil
		PendingFull[Key] = nil
		Roots[Key] = nil
		KeyPlayers[Key] = nil
		SessionMeta[Key] = nil
		Stats[Key] = nil
		Loading[Key] = nil
		local Sig = Changed[Key]
		if Sig then
			Sig:DisconnectAll()
			Changed[Key] = nil
		end
	end

	local function WakeWaiters(Key: string, Result: Types.Profile<T>?)
		local Waiters = LoadWaiters[Key]
		if not Waiters then
			return
		end
		LoadWaiters[Key] = nil
		for _, Thread in Waiters do
			task.spawn(Thread, Result)
		end
	end

	local function EndSession(Key: string)
		local Profile = Sessions[Key]
		PendingPatches[Key] = nil
		PendingFull[Key] = nil
		Loading[Key] = nil
		if Profile and Profile:IsActive() then
			local Player = KeyPlayers[Key]
			if Options.OnSessionEnd then
				pcall(Options.OnSessionEnd, Key, Player)
			end
			Profile:EndSession()
			return
		end
		if Sessions[Key] ~= nil then
			Sessions[Key] = nil
			ForgetKey(Key)
		end
	end

	local function ApplyMigration(Profile: Types.Profile<T>)
		if SchemaVersion == nil then
			return
		end
		local Meta = Profile.RobloxMetaData :: any
		if type(Meta) ~= "table" then
			Meta = {}
			Profile.RobloxMetaData = Meta
		end
		local FromVersion = Meta.SchemaVersion
		if type(FromVersion) ~= "number" then
			FromVersion = 0
		end
		if FromVersion < SchemaVersion and Options.Migrate then
			local Ok, Err = pcall(Options.Migrate, Profile.Data, FromVersion, SchemaVersion)
			if not Ok then
				warn("[Strata] Migrate error:", Err)
			end
		end
		Meta.SchemaVersion = SchemaVersion
	end

	local function Load(Key: string, Player: Player?): Types.Profile<T>?
		if Closing then
			return nil
		end
		local Existing = GetSession(Key)
		if Existing then
			return Existing
		end

		if Loading[Key] then
			local Thread = coroutine.running()
			local Waiters = LoadWaiters[Key]
			if not Waiters then
				Waiters = {}
				LoadWaiters[Key] = Waiters
			end
			table.insert(Waiters, Thread)
			return coroutine.yield()
		end

		Loading[Key] = true

		local Params
		if Player then
			Params = {
				Cancel = function()
					return Player.Parent ~= Players or Closing
				end,
			}
		end

		local Profile: Types.Profile<T>? = nil
		local Ok, Result = pcall(function()
			return Backend:StartSessionAsync(Key, Params :: any) :: Types.Profile<T>?
		end)
		if Ok then
			Profile = Result
		else
			warn(("[Strata] StartSessionAsync failed for %s: %s"):format(Key, tostring(Result)))
		end

		if not Profile then
			Loading[Key] = nil
			WakeWaiters(Key, nil)
			return nil
		end

		if Player and Player.Parent ~= Players then
			Profile:EndSession()
			Loading[Key] = nil
			WakeWaiters(Key, nil)
			return nil
		end

		Util.Reconcile(Profile.Data, StoreTemplate)
		ApplyMigration(Profile)

		Sessions[Key] = Profile
		Seq[Key] = Seq[Key] or 0
		KeyPlayers[Key] = Player
		SessionMeta[Key] = {
			LoadedAt = os.clock(),
			LastSaveAt = nil,
		}

		Profile.OnSessionEnd:Connect(function()
			if Sessions[Key] == Profile then
				Sessions[Key] = nil
			end
			ForgetKey(Key)
		end)

		if Player then
			Profile:AddUserId(Player.UserId)
			if CachedSettings.KickOnSessionEnd then
				Profile.OnSessionEnd:Connect(function()
					if Player.Parent == Players then
						Player:Kick(Options.KickMessage or DEFAULT_KICK_END)
					end
				end)
			end
			BindStats(Key, Player, Profile)
		end

		if Options.OnSessionStart then
			pcall(Options.OnSessionStart, Key, Player, Profile.Data)
		end

		Loading[Key] = nil
		FireFull(Key)
		Loaded:Fire(Key)
		WakeWaiters(Key, Profile)
		return Profile
	end

	local function WaitFor(Key: string, Player: Player?): Types.Profile<T>?
		local Existing = GetSession(Key)
		if Existing then
			return Existing
		end

		if not Loading[Key] then
			return Load(Key, Player)
		end
		return Util.WaitSettled(LoadTimeout, function(Settle)
			local Connections = {
				Loaded:Connect(function(LoadedKey: string)
					if LoadedKey == Key then
						Settle(GetSession(Key))
					end
				end),
			}
			if Player then
				table.insert(Connections, Players.PlayerRemoving:Connect(function(Leaving: Player)
					if Leaving == Player then
						Settle(nil)
					end
				end))
			end
			return Connections
		end)
	end

	-- Bridge

	local Bridge = {
		GetRoot = function(Key: string)
			local Profile = GetSession(Key)
			return if Profile then Profile.Data else nil
		end,
		IsLoaded = function(Key: string)
			return GetSession(Key) ~= nil
		end,
		Write = WritePath,
		Mutate = MutateAt,
		Observe = ObserveAt,
		Save = function(Key: string)
			local Profile = GetSession(Key)
			if Profile then
				Profile:Save()
				local Meta = SessionMeta[Key]
				if Meta then
					Meta.LastSaveAt = os.clock()
				end
				if ReplicateOnSave then
					QueueFull(Key)
					ScheduleFlush()
				end
			end
		end,
		End = EndSession,
		Replicate = function(Key: string, Target: Player?)
			PendingFull[Key] = nil
			PendingPatches[Key] = nil
			FireFull(Key, Target)
		end,
		GetSessionInfo = function(Key: string)
			return BuildSessionInfo(Key)
		end,
		GetMeta = function(Key: string, MetaKey: string?)
			local Profile = GetSession(Key)
			if not Profile then
				return nil
			end
			local Meta = Profile.RobloxMetaData
			if type(Meta) ~= "table" then
				return nil
			end
			if MetaKey == nil then
				return Util.DeepCopy(Meta)
			end
			return (Meta :: any)[MetaKey]
		end,
		SetMeta = function(Key: string, MetaKey: string, Value: any)
			local Profile = GetSession(Key)
			if not Profile then
				return
			end
			local Meta = Profile.RobloxMetaData
			if type(Meta) ~= "table" then
				Meta = {}
				Profile.RobloxMetaData = Meta
			end
			(Meta :: any)[MetaKey] = Value
		end,
		ReadOnly = false,
		Guard = false,
	}

	-- Public API

	local function EnsureRoot(Key: string): Types.State<T>
		local Root: any = Roots[Key]
		if not Root then
			Root = State.new(Bridge, Key)
			Roots[Key] = Root
		end
		return Root
	end

	--[=[
		Loads or retrieves a player's data vault.

		Waits for the session to become available before returning its State
		interface. Returns nil if the session cannot be loaded or the loading
		timeout is reached.

		Accepts either a Player or a string session key.

		@within StrataServer
		@param self StrataServer<T>
		@param Target Player | string
		@return State<T>?
	]=]
	local function LoadVault(self: Types.StrataServer<T>, Target: string | Player): Types.State<T>?
		local Key, Player = ResolveKey(Target)

		if not GetSession(Key) then
			local Profile = WaitFor(Key, Player)
			if not Profile then
				return nil
			end
		end
		local Root = EnsureRoot(Key)
		return Root
	end

	--[=[
		Retrieves an existing data vault without waiting.

		Returns nil if the session has not loaded or is no longer active.

		Accepts either a Player or a string session key.

		@within StrataServer
		@param self StrataServer<T>
		@param Target Player | string
		@return State<T>?
	]=]
	local function GetVault(self: Types.StrataServer<T>, Target: string | Player): Types.State<T>?
		local Key = ResolveKey(Target)
		if not GetSession(Key) then
			return nil
		end
		local Root = EnsureRoot(Key)
		return Root
	end

	--[=[
		Checks whether a session is currently loaded and active.

		Accepts either a Player or a string session key.

		@within StrataServer
		@param self StrataServer<T>
		@param Target Player | string
		@return boolean
	]=]
	local function IsLoaded(self: Types.StrataServer<T>, Target: string | Player): boolean
		local Key = ResolveKey(Target)
		return GetSession(Key) ~= nil
	end

	--[=[
		Retrieves information about an active session.

		Returns nil if the session is not active.

		Accepts either a Player or a string session key.

		@within StrataServer
		@param self StrataServer<T>
		@param Target Player | string
		@return SessionInfo?
	]=]
	local function GetSessionInfoAPI(self: Types.StrataServer<T>, Target: string | Player): Types.SessionInfo?
		local Key = ResolveKey(Target)
		return BuildSessionInfo(Key)
	end

	--[=[
		Retrieves the cached configuration for this store.

		@within StrataServer
		@param self StrataServer<T>
		@return CachedSettings
	]=]
	local function GetSettings(self: Types.StrataServer<T>): Types.CachedSettings
		return CachedSettings
	end

	--[=[
		Retrieves the Player associated with a session key.

		Returns nil if the session is not associated with a player.

		@within StrataServer
		@param self StrataServer<T>
		@param Key string
		@return Player?
	]=]
	local function GetPlayerFromKey(self: Types.StrataServer<T>, Key: string): Player?
		return KeyPlayers[Key]
	end

	--[=[
		Iterates over all currently active sessions.

		Provides each session's key, State interface, and session information
		to the callback.

		@within StrataServer
		@param self StrataServer<T>
		@param Callback (Key: string, State: State<T>, Info: SessionInfo) -> ()
	]=]
	local function ForEachSession(self: Types.StrataServer<T>, Callback: (Key: string, State: Types.State<T>, Info: Types.SessionInfo) -> ())
		for Key, Profile in Sessions do
			if Profile:IsActive() then
				local Root = EnsureRoot(Key)
				local Info = BuildSessionInfo(Key)
				if Info then
					Callback(Key, Root, Info)
				end
			end
		end
	end

	-- Wiring

	ReplicaRequest.OnServerEvent:Connect(function(Player: Player, Request: any)
		if type(Request) ~= "table" or Request.StoreName ~= Options.StoreName then
			return
		end
		local Key = MakeKey(Player)
		if Sessions[Key] then
			Bridge.Replicate(Key, Player)
		end
	end)

	local KickOnFail = CachedSettings.KickOnFail
	local KickMessage = CachedSettings.KickMessage

	local function OnPlayerAdded(Player: Player)
		local Profile = Load(MakeKey(Player), Player)
		if not Profile and KickOnFail and Player.Parent == Players then
			Player:Kick(KickMessage)
		end
	end

	for _, Player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, Player)
	end
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(function(Player: Player)
		EndSession(MakeKey(Player))
	end)

	local AutoSaveSeconds = CachedSettings.AutoSaveSeconds
	if type(AutoSaveSeconds) == "number" and AutoSaveSeconds > 0 then
		task.spawn(function()
			while not Closing do
				task.wait(AutoSaveSeconds)
				for Key, Profile in Sessions do
					if Profile:IsActive() then
						local Ok, Err = pcall(function()
							Profile:Save()
						end)
						if Ok then
							local Meta = SessionMeta[Key]
							if Meta then
								Meta.LastSaveAt = os.clock()
							end
						else
							warn(("[Strata] AutoSave failed for %s: %s"):format(Key, tostring(Err)))
						end
					end
				end
			end
		end)
	end

	game:BindToClose(function()
		Closing = true
		FlushAll()
		local Profiles = {}
		for _, Profile in Sessions do
			if Profile:IsActive() then
				table.insert(Profiles, Profile)
			end
		end
		for _, Profile in Profiles do
			pcall(function()
				Profile:EndSession()
			end)
		end
	end)

	return {
		LoadVault = LoadVault,
		GetVault = GetVault,
		IsLoaded = IsLoaded,
		GetSessionInfo = GetSessionInfoAPI,
		GetSettings = GetSettings,
		GetPlayerFromKey = GetPlayerFromKey,
		ForEachSession = ForEachSession,
	} :: Types.StrataServer<T>
end

return StrataServer

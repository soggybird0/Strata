--!strict
--!optimize 2

--[=[
	@class Strata
	
	:::danger Type solver required
	Autocomplete needs `Workspace.UseNewLuauTypeSolver = Enabled`. Runtime works
	without it.
	:::

	@server
	@client
]=]

local RunService = game:GetService("RunService")
local Types = require(script.Types)

export type Config<T> = Types.Config<T>
export type Connection = Types.Connection
export type State<T> = Types.State<T>
export type Node<T> = Types.Node<T>
export type SessionInfo = Types.SessionInfo
export type CachedSettings = Types.CachedSettings

local Strata = {}

--[=[
	@prop Version string
	@within Strata
	@readonly
]=]
Strata.Version = "1"

--[=[
	Opens a Strata for the current environment.
	`Server` is only populated on the server, `Client` only on the client.
	The other side is `nil` at runtime, so each side can use its own field
	without nil checks.

	@within Strata
	@param Options Config<T>
	@return { Server: StrataServer<T>, Client: StrataClient<T> }
]=]
function Strata:Init<T>(Options: Types.Config<T>): {
	Server: Types.StrataServer<T>,
	Client: Types.StrataClient<T>,
}
	local Result: any = {
		Server = nil,
		Client = nil,
	}
	if RunService:IsServer() then
		Result.Server = require(script.StrataServer).Open(Options)
	end
	if RunService:IsClient() then
		Result.Client = require(script.StrataClient).Open(Options)
	end
	return Result
end

return Strata

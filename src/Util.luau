--!optimize 2
--!strict

local Util = {}

Util.READ_ONLY_MESSAGE = "Strata: client data is read-only. Change it on the server."

local PROXY_TO_RAW: { [any]: any } = setmetatable({}, { __mode = "k" })

-- Binary wire tags (for replication :p)
local TYPE_NIL = 0
local TYPE_BOOL = 1
local TYPE_NUMBER = 2
local TYPE_STRING = 3
local TYPE_TABLE = 4
local TYPE_ARRAY = 5
local TYPE_BUFFER = 6
local TYPE_VECTOR2 = 7
local TYPE_VECTOR3 = 8
local TYPE_VECTOR2INT16 = 9
local TYPE_VECTOR3INT16 = 10
local TYPE_CFRAME = 11
local TYPE_COLOR3 = 12
local TYPE_BRICKCOLOR = 13
local TYPE_UDIM = 14
local TYPE_UDIM2 = 15
local TYPE_RECT = 16
local TYPE_REGION3 = 17
local TYPE_REGION3INT16 = 18
local TYPE_NUMBERRANGE = 19
local TYPE_NUMBERSEQ = 20
local TYPE_NUMBERSEQKEY = 21
local TYPE_COLORSEQ = 22
local TYPE_COLORSEQKEY = 23
local TYPE_ENUMITEM = 24
local TYPE_PHYSICALPROPERTIES = 25
local TYPE_RAY = 26
local TYPE_FACES = 27
local TYPE_AXES = 28
local TYPE_PATHWAYPOINT = 29
local TYPE_TWEENINFO = 30
local TYPE_DATETIME = 31
local TYPE_FONT = 32
local TYPE_FLOATCURVEKEY = 33
local TYPE_ROTATIONCURVEKEY = 34

local STORE_TAG = "__strata"

function Util.DeepCopy(Value: any): any
	if type(Value) ~= "table" then
		return Value
	end
	local Result = table.clone(Value)
	for K, V in Result do
		if type(V) == "table" then
			Result[K] = Util.DeepCopy(V)
		end
	end
	return Result
end

function Util.ToStore(Value: any): any
	local t = typeof(Value)
	if Value == nil or t == "number" or t == "string" or t == "boolean" then
		return Value
	elseif t == "buffer" then
		local n = buffer.len(Value)
		local bytes = table.create(n)
		for i = 0, n - 1 do
			bytes[i + 1] = buffer.readu8(Value, i)
		end
		return { [STORE_TAG] = "buffer", b = bytes }
	elseif t == "Vector2" then
		return { [STORE_TAG] = "Vector2", x = Value.X, y = Value.Y }
	elseif t == "Vector3" then
		return { [STORE_TAG] = "Vector3", x = Value.X, y = Value.Y, z = Value.Z }
	elseif t == "Vector2int16" then
		return { [STORE_TAG] = "Vector2int16", x = Value.X, y = Value.Y }
	elseif t == "Vector3int16" then
		return { [STORE_TAG] = "Vector3int16", x = Value.X, y = Value.Y, z = Value.Z }
	elseif t == "CFrame" then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = Value:GetComponents()
		return {
			[STORE_TAG] = "CFrame",
			x = x, y = y, z = z,
			r00 = r00, r01 = r01, r02 = r02,
			r10 = r10, r11 = r11, r12 = r12,
			r20 = r20, r21 = r21, r22 = r22,
		}
	elseif t == "Color3" then
		return { [STORE_TAG] = "Color3", r = Value.R, g = Value.G, b = Value.B }
	elseif t == "BrickColor" then
		return { [STORE_TAG] = "BrickColor", n = Value.Number }
	elseif t == "UDim" then
		return { [STORE_TAG] = "UDim", s = Value.Scale, o = Value.Offset }
	elseif t == "UDim2" then
		return {
			[STORE_TAG] = "UDim2",
			xs = Value.X.Scale, xo = Value.X.Offset,
			ys = Value.Y.Scale, yo = Value.Y.Offset,
		}
	elseif t == "Rect" then
		return { [STORE_TAG] = "Rect", minx = Value.Min.X, miny = Value.Min.Y, maxx = Value.Max.X, maxy = Value.Max.Y }
	elseif t == "Region3" then
		local mn, mx = Value.CFrame.Position - Value.Size / 2, Value.CFrame.Position + Value.Size / 2
		return {
			[STORE_TAG] = "Region3",
			minx = mn.X, miny = mn.Y, minz = mn.Z,
			maxx = mx.X, maxy = mx.Y, maxz = mx.Z,
		}
	elseif t == "Region3int16" then
		return {
			[STORE_TAG] = "Region3int16",
			minx = Value.Min.X, miny = Value.Min.Y, minz = Value.Min.Z,
			maxx = Value.Max.X, maxy = Value.Max.Y, maxz = Value.Max.Z,
		}
	elseif t == "NumberRange" then
		return { [STORE_TAG] = "NumberRange", min = Value.Min, max = Value.Max }
	elseif t == "NumberSequenceKeypoint" then
		return { [STORE_TAG] = "NumberSequenceKeypoint", t = Value.Time, v = Value.Value, e = Value.Envelope }
	elseif t == "NumberSequence" then
		local kps = {}
		for i, kp in Value.Keypoints do
			kps[i] = Util.ToStore(kp)
		end
		return { [STORE_TAG] = "NumberSequence", k = kps }
	elseif t == "ColorSequenceKeypoint" then
		return {
			[STORE_TAG] = "ColorSequenceKeypoint",
			t = Value.Time,
			r = Value.Value.R, g = Value.Value.G, b = Value.Value.B,
		}
	elseif t == "ColorSequence" then
		local kps = {}
		for i, kp in Value.Keypoints do
			kps[i] = Util.ToStore(kp)
		end
		return { [STORE_TAG] = "ColorSequence", k = kps }
	elseif t == "EnumItem" then
		return { [STORE_TAG] = "EnumItem", e = tostring(Value.EnumType), n = Value.Name }
	elseif t == "PhysicalProperties" then
		return {
			[STORE_TAG] = "PhysicalProperties",
			d = Value.Density, f = Value.Friction, e = Value.Elasticity,
			fw = Value.FrictionWeight, ew = Value.ElasticityWeight,
		}
	elseif t == "Ray" then
		return {
			[STORE_TAG] = "Ray",
			ox = Value.Origin.X, oy = Value.Origin.Y, oz = Value.Origin.Z,
			dx = Value.Direction.X, dy = Value.Direction.Y, dz = Value.Direction.Z,
		}
	elseif t == "Faces" then
		return {
			[STORE_TAG] = "Faces",
			top = Value.Top, bottom = Value.Bottom, left = Value.Left,
			right = Value.Right, back = Value.Back, front = Value.Front,
		}
	elseif t == "Axes" then
		return { [STORE_TAG] = "Axes", x = Value.X, y = Value.Y, z = Value.Z }
	elseif t == "PathWaypoint" then
		return {
			[STORE_TAG] = "PathWaypoint",
			x = Value.Position.X, y = Value.Position.Y, z = Value.Position.Z,
			a = Value.Action.Name,
			l = Value.Label,
		}
	elseif t == "TweenInfo" then
		return {
			[STORE_TAG] = "TweenInfo",
			t = Value.Time, style = Value.EasingStyle.Name, dir = Value.EasingDirection.Name,
			rp = Value.RepeatCount, rev = Value.Reverses, d = Value.DelayTime,
		}
	elseif t == "DateTime" then
		return { [STORE_TAG] = "DateTime", u = Value.UnixTimestampMillis }
	elseif t == "Font" then
		return {
			[STORE_TAG] = "Font",
			f = Value.Family, w = Value.Weight.Name, s = Value.Style.Name,
		}
	elseif t == "FloatCurveKey" then
		return {
			[STORE_TAG] = "FloatCurveKey",
			t = Value.Time, v = Value.Value, kind = Value.Interpolation.Name,
		}
	elseif t == "RotationCurveKey" then
		local cf = Util.ToStore(Value.Value)
		return { [STORE_TAG] = "RotationCurveKey", t = Value.Time, v = cf, kind = Value.Interpolation.Name }
	elseif t == "table" then
		if Value[STORE_TAG] then
			return Value
		end
		local out = {}
		for k, v in Value do
			out[Util.ToStore(k)] = Util.ToStore(v)
		end
		return out
	end

	return nil
end

function Util.FromStore(Value: any): any
	if type(Value) ~= "table" then
		return Value
	end
	local tag = Value[STORE_TAG]
	if tag == nil then
		local out = {}
		for k, v in Value do
			out[Util.FromStore(k)] = Util.FromStore(v)
		end
		return out
	end
	if tag == "buffer" then
		local bytes = Value.b
		local b = buffer.create(#bytes)
		for i, n in bytes do
			buffer.writeu8(b, i - 1, n)
		end
		return b
	elseif tag == "Vector2" then
		return Vector2.new(Value.x, Value.y)
	elseif tag == "Vector3" then
		return Vector3.new(Value.x, Value.y, Value.z)
	elseif tag == "Vector2int16" then
		return Vector2int16.new(Value.x, Value.y)
	elseif tag == "Vector3int16" then
		return Vector3int16.new(Value.x, Value.y, Value.z)
	elseif tag == "CFrame" then
		return CFrame.new(
			Value.x, Value.y, Value.z,
			Value.r00, Value.r01, Value.r02,
			Value.r10, Value.r11, Value.r12,
			Value.r20, Value.r21, Value.r22
		)
	elseif tag == "Color3" then
		return Color3.new(Value.r, Value.g, Value.b)
	elseif tag == "BrickColor" then
		return BrickColor.new(Value.n)
	elseif tag == "UDim" then
		return UDim.new(Value.s, Value.o)
	elseif tag == "UDim2" then
		return UDim2.new(Value.xs, Value.xo, Value.ys, Value.yo)
	elseif tag == "Rect" then
		return Rect.new(Value.minx, Value.miny, Value.maxx, Value.maxy)
	elseif tag == "Region3" then
		return Region3.new(
			Vector3.new(Value.minx, Value.miny, Value.minz),
			Vector3.new(Value.maxx, Value.maxy, Value.maxz)
		)
	elseif tag == "Region3int16" then
		return Region3int16.new(
			Vector3int16.new(Value.minx, Value.miny, Value.minz),
			Vector3int16.new(Value.maxx, Value.maxy, Value.maxz)
		)
	elseif tag == "NumberRange" then
		return NumberRange.new(Value.min, Value.max)
	elseif tag == "NumberSequenceKeypoint" then
		return NumberSequenceKeypoint.new(Value.t, Value.v, Value.e)
	elseif tag == "NumberSequence" then
		local kps = {}
		for i, kp in Value.k do
			kps[i] = Util.FromStore(kp)
		end
		return NumberSequence.new(kps)
	elseif tag == "ColorSequenceKeypoint" then
		return ColorSequenceKeypoint.new(Value.t, Color3.new(Value.r, Value.g, Value.b))
	elseif tag == "ColorSequence" then
		local kps = {}
		for i, kp in Value.k do
			kps[i] = Util.FromStore(kp)
		end
		return ColorSequence.new(kps)
	elseif tag == "EnumItem" then
		local enum = (Enum :: any)[Value.e]
		if enum then
			return enum[Value.n]
		end
		return nil
	elseif tag == "PhysicalProperties" then
		return PhysicalProperties.new(Value.d, Value.f, Value.e, Value.fw, Value.ew)
	elseif tag == "Ray" then
		return Ray.new(Vector3.new(Value.ox, Value.oy, Value.oz), Vector3.new(Value.dx, Value.dy, Value.dz))
	elseif tag == "Faces" then
		local list = {}
		if Value.top then table.insert(list, Enum.NormalId.Top) end
		if Value.bottom then table.insert(list, Enum.NormalId.Bottom) end
		if Value.left then table.insert(list, Enum.NormalId.Left) end
		if Value.right then table.insert(list, Enum.NormalId.Right) end
		if Value.back then table.insert(list, Enum.NormalId.Back) end
		if Value.front then table.insert(list, Enum.NormalId.Front) end
		return Faces.new(table.unpack(list))
	elseif tag == "Axes" then
		local list = {}
		if Value.x then table.insert(list, Enum.Axis.X) end
		if Value.y then table.insert(list, Enum.Axis.Y) end
		if Value.z then table.insert(list, Enum.Axis.Z) end
		return Axes.new(table.unpack(list))
	elseif tag == "PathWaypoint" then
		local action = (Enum.PathWaypointAction :: any)[Value.a] or Enum.PathWaypointAction.Walk
		return PathWaypoint.new(Vector3.new(Value.x, Value.y, Value.z), action, Value.l or "")
	elseif tag == "TweenInfo" then
		return TweenInfo.new(
			Value.t,
			(Enum.EasingStyle :: any)[Value.style] or Enum.EasingStyle.Linear,
			(Enum.EasingDirection :: any)[Value.dir] or Enum.EasingDirection.InOut,
			Value.rp or 0,
			Value.rev or false,
			Value.d or 0
		)
	elseif tag == "DateTime" then
		return DateTime.fromUnixTimestampMillis(Value.u)
	elseif tag == "Font" then
		return Font.new(
			Value.f,
			(Enum.FontWeight :: any)[Value.w] or Enum.FontWeight.Regular,
			(Enum.FontStyle :: any)[Value.s] or Enum.FontStyle.Normal
		)
	elseif tag == "FloatCurveKey" then
		return FloatCurveKey.new(
			Value.t,
			Value.v,
			(Enum.KeyInterpolationMode :: any)[Value.kind] or Enum.KeyInterpolationMode.Cubic
		)
	elseif tag == "RotationCurveKey" then
		return RotationCurveKey.new(
			Value.t,
			Util.FromStore(Value.v),
			(Enum.KeyInterpolationMode :: any)[Value.kind] or Enum.KeyInterpolationMode.Cubic
		)
	end
	return Value
end

local function isArray(T: any): boolean
	if type(T) ~= "table" then
		return false
	end
	for K in T do
		if type(K) ~= "number" then
			return false
		end
	end
	return true
end

local function valueKind(Value: any): string
	if Value == nil then
		return "nil"
	end

	local T = typeof(Value)
	if T == "table" then
		local tag = (Value :: any)[STORE_TAG]
		if type(tag) == "string" then
			return tag
		end

		if #(Value :: any) > 0 and isArray(Value) then
			return "array"
		end
		return "table"
	end
	return T -- this will return a number, string, boolean, buffer, Vector3, etcetc.
end

function Util.Reconcile(Target: any, Template: any)
	if type(Target) ~= "table" or type(Template) ~= "table" then
		return
	end
	for K, V in Template do
		local Cur = Target[K]
		if Cur == nil then
			Target[K] = Util.DeepCopy(V)
		elseif valueKind(Cur) ~= valueKind(V) then
			Target[K] = Util.DeepCopy(V)
		elseif type(V) == "table" and type(Cur) == "table" then
			local tag = V[STORE_TAG]
			if tag == nil then
				Util.Reconcile(Cur, V)
			end
		end
	end
end

function Util.NormalizePath(Path: any): { any }
	if type(Path) == "table" then
		local Out = table.create(#Path)
		for I, Segment in Path do
			Out[I] = Segment
		end
		return Out
	end
	if type(Path) ~= "string" or Path == "" then
		return {}
	end
	local Out = {}
	for Segment in string.gmatch(Path, "[^%.]+") do
		local AsNumber = tonumber(Segment)
		table.insert(Out, if AsNumber ~= nil and tostring(AsNumber) == Segment then AsNumber else Segment)
	end
	return Out
end

function Util.ClonePath(Path: { any }): { any }
	local Out = table.create(#Path)
	for I, Segment in Path do
		Out[I] = Segment
	end
	return Out
end

function Util.PathStartsWith(Path: { any }, Prefix: { any }): boolean
	if #Prefix > #Path then
		return false
	end
	for I = 1, #Prefix do
		if Path[I] ~= Prefix[I] then
			return false
		end
	end
	return true
end

function Util.Subscribe(
	Sig: any,
	TagPath: { any }?,
	Listener: (Value: any) -> (),
	Read: (Data: any) -> any,
	Current: () -> any
): { Disconnect: (...any) -> () }
	local Last: any = nil
	local Connection = Sig:Connect(function(Data: any, Paths: { { any } }?)
		if TagPath and Paths then
			local Hit = false
			for _, Path in Paths do
				if Util.PathStartsWith(Path, TagPath) or Util.PathStartsWith(TagPath, Path) then
					Hit = true
					break
				end
			end
			if not Hit then
				return
			end
		end
		local Value = Read(Data)
		if Value == Last and type(Value) ~= "table" then
			return
		end
		Last = Value
		Listener(Value)
	end)

	task.defer(function()
		local Data = Current()
		if Data == nil or not Connection.Connected then
			return
		end
		local Value = Read(Data)
		Last = Value
		Listener(Value)
	end)

	return {
		Disconnect = function()
			Connection:Disconnect()
		end,
	}
end

function Util.WaitSettled(Timeout: number, Attach: (Settle: (Result: any) -> ()) -> { any }): any
	local Thread = coroutine.running()
	local Settled = false
	local Connections: { any } = {}
	local function Settle(Result: any)
		if Settled then
			return
		end
		Settled = true
		for _, Connection in Connections do
			Connection:Disconnect()
		end
		task.spawn(Thread, Result)
	end
	Connections = Attach(Settle)
	task.delay(Timeout, Settle, nil)
	return coroutine.yield()
end

function Util.GetAt(Root: any, Path: { any }): any
	local Current = Root
	for _, Segment in Path do
		if type(Current) ~= "table" then
			return nil
		end
		Current = Current[Segment]
	end
	return Current
end

function Util.SetAt(Root: any, Path: { any }, Value: any)
	if #Path == 0 then
		return
	end
	local Current = Root
	for I = 1, #Path - 1 do
		local Segment = Path[I]
		local Next = Current[Segment]
		if type(Next) ~= "table" then
			Next = {}
			Current[Segment] = Next
		end
		Current = Next
	end
	Current[Path[#Path]] = Value
end

function Util.Unwrap(Value: any): any
	return PROXY_TO_RAW[Value] or Value
end

function Util.ReadOnly(Value: any, ErrorMessage: string): any
	if type(Value) ~= "table" then
		return Value
	end
	local Proxy = newproxy(true)
	local MT = getmetatable(Proxy)
	MT.__index = function(_, Key)
		local V = Value[Key]
		if type(V) == "table" then
			return Util.ReadOnly(V, ErrorMessage)
		end
		return V
	end
	MT.__newindex = function()
		error(ErrorMessage, 2)
	end
	MT.__iter = function()
		return next, Value
	end
	MT.__len = function()
		return #Value
	end
	MT.__tostring = function()
		return "ReadOnlyData"
	end
	PROXY_TO_RAW[Proxy] = Value
	return Proxy
end

local function valuesEqual(A: any, B: any): boolean
	if A == B then
		return true
	end
	if type(A) ~= type(B) or type(A) ~= "table" then
		return false
	end
	for K, V in A do
		if not valuesEqual(V, B[K]) then
			return false
		end
	end
	for K in B do
		if A[K] == nil then
			return false
		end
	end
	return true
end

function Util.Diff(Before: any, After: any, CollapseAt: number?): { { Path: { any }, Value: any } }
	local Patches = {}
	local Limit = CollapseAt or 12

	local function walk(A: any, B: any, Path: { any })
		if valuesEqual(A, B) then
			return
		end
		if type(B) ~= "table" or type(A) ~= "table" then
			table.insert(Patches, {
				Path = Util.ClonePath(Path),
				Value = if type(B) == "table" then Util.DeepCopy(B) else B,
			})
			return
		end

		local ChildPaths = {}
		for K, BV in B do
			local AP = table.clone(Path)
			table.insert(AP, K)
			if not valuesEqual(A[K], BV) then
				table.insert(ChildPaths, { Path = AP, AV = A[K], BV = BV })
			end
		end
		for K in A do
			if B[K] == nil then
				local AP = table.clone(Path)
				table.insert(AP, K)
				table.insert(ChildPaths, { Path = AP, AV = A[K], BV = nil })
			end
		end

		if #Path > 0 and #ChildPaths >= Limit then
			table.insert(Patches, { Path = Util.ClonePath(Path), Value = Util.DeepCopy(B) })
			return
		end

		for _, Entry in ChildPaths do
			walk(Entry.AV, Entry.BV, Entry.Path)
		end
	end

	walk(Before, After, {})
	return Patches
end

local function measureValue(Value: any): number
	local T = typeof(Value)
	if Value == nil then
		return 1
	elseif T == "boolean" then
		return 2
	elseif T == "number" then
		return 9
	elseif T == "string" then
		return 5 + #Value
	elseif T == "buffer" then
		return 5 + buffer.len(Value)
	elseif T == "Vector2" or T == "Vector2int16" then
		return 1 + 8
	elseif T == "Vector3" or T == "Vector3int16" then
		return 1 + 12
	elseif T == "CFrame" then
		return 1 + 12 * 4 -- 12 floats btw
	elseif T == "Color3" then
		return 1 + 12
	elseif T == "BrickColor" then
		return 1 + 2
	elseif T == "UDim" then
		return 1 + 8
	elseif T == "UDim2" then
		return 1 + 16
	elseif T == "Rect" then
		return 1 + 16
	elseif T == "Region3" then
		return 1 + 24
	elseif T == "Region3int16" then
		return 1 + 12
	elseif T == "NumberRange" then
		return 1 + 8
	elseif T == "NumberSequenceKeypoint" then
		return 1 + 12
	elseif T == "ColorSequenceKeypoint" then
		return 1 + 4 + 12
	elseif T == "NumberSequence" or T == "ColorSequence" then
		local Size = 5
		for _, kp in Value.Keypoints do
			Size += measureValue(kp)
		end
		return Size
	elseif T == "EnumItem" then
		local e = tostring(Value.EnumType)
		local n = Value.Name
		return 5 + #e + #n
	elseif T == "PhysicalProperties" then
		return 1 + 20
	elseif T == "Ray" then
		return 1 + 24
	elseif T == "Faces" or T == "Axes" then
		return 1 + 1
	elseif T == "PathWaypoint" then
		return 1 + 12 + 1 + 2 + #Value.Label
	elseif T == "TweenInfo" then
		return 1 + 4 + 1 + 1 + 4 + 1 + 4
	elseif T == "DateTime" then
		return 1 + 8
	elseif T == "Font" then
		return 5 + #Value.Family
	elseif T == "FloatCurveKey" then
		return 1 + 8 + 1
	elseif T == "RotationCurveKey" then
		return 1 + 4 + measureValue(Value.Value) + 1
	elseif T == "table" then
		if isArray(Value) then
			local Size = 5
			for I = 1, #Value do
				Size += measureValue(Value[I])
			end
			return Size
		else
			local Size = 5
			for K, V in Value do
				Size += measureValue(K) + measureValue(V)
			end
			return Size
		end
	end
	return 1
end

local function measurePath(Path: { any }): number
	local Size = 1
	for _, Segment in Path do
		Size += measureValue(Segment)
	end
	return Size
end

local function writeValue(Buf: buffer, Offset: number, Value: any): number
	local T = typeof(Value)
	if Value == nil then
		buffer.writeu8(Buf, Offset, TYPE_NIL)
		return Offset + 1
	elseif T == "boolean" then
		buffer.writeu8(Buf, Offset, TYPE_BOOL)
		buffer.writeu8(Buf, Offset + 1, if Value then 1 else 0)
		return Offset + 2
	elseif T == "number" then
		buffer.writeu8(Buf, Offset, TYPE_NUMBER)
		buffer.writef64(Buf, Offset + 1, Value)
		return Offset + 9
	elseif T == "string" then
		buffer.writeu8(Buf, Offset, TYPE_STRING)
		buffer.writeu32(Buf, Offset + 1, #Value)
		buffer.writestring(Buf, Offset + 5, Value)
		return Offset + 5 + #Value
	elseif T == "buffer" then
		local Len = buffer.len(Value)
		buffer.writeu8(Buf, Offset, TYPE_BUFFER)
		buffer.writeu32(Buf, Offset + 1, Len)
		buffer.copy(Buf, Offset + 5, Value, 0, Len)
		return Offset + 5 + Len
	elseif T == "Vector2" then
		buffer.writeu8(Buf, Offset, TYPE_VECTOR2)
		buffer.writef32(Buf, Offset + 1, Value.X)
		buffer.writef32(Buf, Offset + 5, Value.Y)
		return Offset + 9
	elseif T == "Vector3" then
		buffer.writeu8(Buf, Offset, TYPE_VECTOR3)
		buffer.writef32(Buf, Offset + 1, Value.X)
		buffer.writef32(Buf, Offset + 5, Value.Y)
		buffer.writef32(Buf, Offset + 9, Value.Z)
		return Offset + 13
	elseif T == "Vector2int16" then
		buffer.writeu8(Buf, Offset, TYPE_VECTOR2INT16)
		buffer.writei16(Buf, Offset + 1, Value.X)
		buffer.writei16(Buf, Offset + 3, Value.Y)
		return Offset + 5
	elseif T == "Vector3int16" then
		buffer.writeu8(Buf, Offset, TYPE_VECTOR3INT16)
		buffer.writei16(Buf, Offset + 1, Value.X)
		buffer.writei16(Buf, Offset + 3, Value.Y)
		buffer.writei16(Buf, Offset + 5, Value.Z)
		return Offset + 7
	elseif T == "CFrame" then
		buffer.writeu8(Buf, Offset, TYPE_CFRAME)
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = Value:GetComponents()
		local o = Offset + 1
		buffer.writef32(Buf, o, x)
		o += 4
		buffer.writef32(Buf, o, y)
		o += 4
		buffer.writef32(Buf, o, z)
		o += 4
		buffer.writef32(Buf, o, r00)
		o += 4
		buffer.writef32(Buf, o, r01)
		o += 4
		buffer.writef32(Buf, o, r02)
		o += 4
		buffer.writef32(Buf, o, r10)
		o += 4
		buffer.writef32(Buf, o, r11)
		o += 4
		buffer.writef32(Buf, o, r12)
		o += 4
		buffer.writef32(Buf, o, r20)
		o += 4
		buffer.writef32(Buf, o, r21)
		o += 4
		buffer.writef32(Buf, o, r22)
		o += 4
		return o
	elseif T == "Color3" then
		buffer.writeu8(Buf, Offset, TYPE_COLOR3)
		buffer.writef32(Buf, Offset + 1, Value.R)
		buffer.writef32(Buf, Offset + 5, Value.G)
		buffer.writef32(Buf, Offset + 9, Value.B)
		return Offset + 13
	elseif T == "BrickColor" then
		buffer.writeu8(Buf, Offset, TYPE_BRICKCOLOR)
		buffer.writeu16(Buf, Offset + 1, Value.Number)
		return Offset + 3
	elseif T == "UDim" then
		buffer.writeu8(Buf, Offset, TYPE_UDIM)
		buffer.writef32(Buf, Offset + 1, Value.Scale)
		buffer.writei32(Buf, Offset + 5, Value.Offset)
		return Offset + 9
	elseif T == "UDim2" then
		buffer.writeu8(Buf, Offset, TYPE_UDIM2)
		buffer.writef32(Buf, Offset + 1, Value.X.Scale)
		buffer.writei32(Buf, Offset + 5, Value.X.Offset)
		buffer.writef32(Buf, Offset + 9, Value.Y.Scale)
		buffer.writei32(Buf, Offset + 13, Value.Y.Offset)
		return Offset + 17
	elseif T == "Rect" then
		buffer.writeu8(Buf, Offset, TYPE_RECT)
		buffer.writef32(Buf, Offset + 1, Value.Min.X)
		buffer.writef32(Buf, Offset + 5, Value.Min.Y)
		buffer.writef32(Buf, Offset + 9, Value.Max.X)
		buffer.writef32(Buf, Offset + 13, Value.Max.Y)
		return Offset + 17
	elseif T == "Region3" then
		local mn = Value.CFrame.Position - Value.Size / 2
		local mx = Value.CFrame.Position + Value.Size / 2
		buffer.writeu8(Buf, Offset, TYPE_REGION3)
		buffer.writef32(Buf, Offset + 1, mn.X)
		buffer.writef32(Buf, Offset + 5, mn.Y)
		buffer.writef32(Buf, Offset + 9, mn.Z)
		buffer.writef32(Buf, Offset + 13, mx.X)
		buffer.writef32(Buf, Offset + 17, mx.Y)
		buffer.writef32(Buf, Offset + 21, mx.Z)
		return Offset + 25
	elseif T == "Region3int16" then
		buffer.writeu8(Buf, Offset, TYPE_REGION3INT16)
		buffer.writei16(Buf, Offset + 1, Value.Min.X)
		buffer.writei16(Buf, Offset + 3, Value.Min.Y)
		buffer.writei16(Buf, Offset + 5, Value.Min.Z)
		buffer.writei16(Buf, Offset + 7, Value.Max.X)
		buffer.writei16(Buf, Offset + 9, Value.Max.Y)
		buffer.writei16(Buf, Offset + 11, Value.Max.Z)
		return Offset + 13
	elseif T == "NumberRange" then
		buffer.writeu8(Buf, Offset, TYPE_NUMBERRANGE)
		buffer.writef32(Buf, Offset + 1, Value.Min)
		buffer.writef32(Buf, Offset + 5, Value.Max)
		return Offset + 9
	elseif T == "NumberSequenceKeypoint" then
		buffer.writeu8(Buf, Offset, TYPE_NUMBERSEQKEY)
		buffer.writef32(Buf, Offset + 1, Value.Time)
		buffer.writef32(Buf, Offset + 5, Value.Value)
		buffer.writef32(Buf, Offset + 9, Value.Envelope)
		return Offset + 13
	elseif T == "NumberSequence" then
		local kps = Value.Keypoints
		buffer.writeu8(Buf, Offset, TYPE_NUMBERSEQ)
		buffer.writeu32(Buf, Offset + 1, #kps)
		Offset += 5
		for _, kp in kps do
			Offset = writeValue(Buf, Offset, kp)
		end
		return Offset
	elseif T == "ColorSequenceKeypoint" then
		buffer.writeu8(Buf, Offset, TYPE_COLORSEQKEY)
		buffer.writef32(Buf, Offset + 1, Value.Time)
		buffer.writef32(Buf, Offset + 5, Value.Value.R)
		buffer.writef32(Buf, Offset + 9, Value.Value.G)
		buffer.writef32(Buf, Offset + 13, Value.Value.B)
		return Offset + 17
	elseif T == "ColorSequence" then
		local kps = Value.Keypoints
		buffer.writeu8(Buf, Offset, TYPE_COLORSEQ)
		buffer.writeu32(Buf, Offset + 1, #kps)
		Offset += 5
		for _, kp in kps do
			Offset = writeValue(Buf, Offset, kp)
		end
		return Offset
	elseif T == "EnumItem" then
		local e = tostring(Value.EnumType)
		local n = Value.Name
		buffer.writeu8(Buf, Offset, TYPE_ENUMITEM)
		buffer.writeu16(Buf, Offset + 1, #e)
		buffer.writestring(Buf, Offset + 3, e)
		buffer.writeu16(Buf, Offset + 3 + #e, #n)
		buffer.writestring(Buf, Offset + 5 + #e, n)
		return Offset + 5 + #e + #n
	elseif T == "PhysicalProperties" then
		buffer.writeu8(Buf, Offset, TYPE_PHYSICALPROPERTIES)
		buffer.writef32(Buf, Offset + 1, Value.Density)
		buffer.writef32(Buf, Offset + 5, Value.Friction)
		buffer.writef32(Buf, Offset + 9, Value.Elasticity)
		buffer.writef32(Buf, Offset + 13, Value.FrictionWeight)
		buffer.writef32(Buf, Offset + 17, Value.ElasticityWeight)
		return Offset + 21
	elseif T == "Ray" then
		buffer.writeu8(Buf, Offset, TYPE_RAY)
		buffer.writef32(Buf, Offset + 1, Value.Origin.X)
		buffer.writef32(Buf, Offset + 5, Value.Origin.Y)
		buffer.writef32(Buf, Offset + 9, Value.Origin.Z)
		buffer.writef32(Buf, Offset + 13, Value.Direction.X)
		buffer.writef32(Buf, Offset + 17, Value.Direction.Y)
		buffer.writef32(Buf, Offset + 21, Value.Direction.Z)
		return Offset + 25
	elseif T == "Faces" then
		local bits = 0
		if Value.Top then bits = bit32.bor(bits, 1) end
		if Value.Bottom then bits = bit32.bor(bits, 2) end
		if Value.Left then bits = bit32.bor(bits, 4) end
		if Value.Right then bits = bit32.bor(bits, 8) end
		if Value.Back then bits = bit32.bor(bits, 16) end
		if Value.Front then bits = bit32.bor(bits, 32) end
		buffer.writeu8(Buf, Offset, TYPE_FACES)
		buffer.writeu8(Buf, Offset + 1, bits)
		return Offset + 2
	elseif T == "Axes" then
		local bits = 0
		if Value.X then bits = bit32.bor(bits, 1) end
		if Value.Y then bits = bit32.bor(bits, 2) end
		if Value.Z then bits = bit32.bor(bits, 4) end
		buffer.writeu8(Buf, Offset, TYPE_AXES)
		buffer.writeu8(Buf, Offset + 1, bits)
		return Offset + 2
	elseif T == "PathWaypoint" then
		local label = Value.Label or ""
		buffer.writeu8(Buf, Offset, TYPE_PATHWAYPOINT)
		buffer.writef32(Buf, Offset + 1, Value.Position.X)
		buffer.writef32(Buf, Offset + 5, Value.Position.Y)
		buffer.writef32(Buf, Offset + 9, Value.Position.Z)
		buffer.writeu8(Buf, Offset + 13, Value.Action.Value)
		buffer.writeu16(Buf, Offset + 14, #label)
		buffer.writestring(Buf, Offset + 16, label)
		return Offset + 16 + #label
	elseif T == "TweenInfo" then
		buffer.writeu8(Buf, Offset, TYPE_TWEENINFO)
		buffer.writef32(Buf, Offset + 1, Value.Time)
		buffer.writeu8(Buf, Offset + 5, Value.EasingStyle.Value)
		buffer.writeu8(Buf, Offset + 6, Value.EasingDirection.Value)
		buffer.writei32(Buf, Offset + 7, Value.RepeatCount)
		buffer.writeu8(Buf, Offset + 11, if Value.Reverses then 1 else 0)
		buffer.writef32(Buf, Offset + 12, Value.DelayTime)
		return Offset + 16
	elseif T == "DateTime" then
		buffer.writeu8(Buf, Offset, TYPE_DATETIME)
		buffer.writef64(Buf, Offset + 1, Value.UnixTimestampMillis)
		return Offset + 9
	elseif T == "Font" then
		local fam = Value.Family
		buffer.writeu8(Buf, Offset, TYPE_FONT)
		buffer.writeu16(Buf, Offset + 1, #fam)
		buffer.writestring(Buf, Offset + 3, fam)
		buffer.writeu8(Buf, Offset + 3 + #fam, Value.Weight.Value)
		buffer.writeu8(Buf, Offset + 4 + #fam, Value.Style.Value)
		return Offset + 5 + #fam
	elseif T == "FloatCurveKey" then
		buffer.writeu8(Buf, Offset, TYPE_FLOATCURVEKEY)
		buffer.writef32(Buf, Offset + 1, Value.Time)
		buffer.writef32(Buf, Offset + 5, Value.Value)
		buffer.writeu8(Buf, Offset + 9, Value.Interpolation.Value)
		return Offset + 10
	elseif T == "RotationCurveKey" then
		buffer.writeu8(Buf, Offset, TYPE_ROTATIONCURVEKEY)
		buffer.writef32(Buf, Offset + 1, Value.Time)
		Offset = writeValue(Buf, Offset + 5, Value.Value)
		buffer.writeu8(Buf, Offset, Value.Interpolation.Value)
		return Offset + 1
	elseif T == "table" then
		if isArray(Value) then
			buffer.writeu8(Buf, Offset, TYPE_ARRAY)
			buffer.writeu32(Buf, Offset + 1, #Value)
			Offset += 5
			for I = 1, #Value do
				Offset = writeValue(Buf, Offset, Value[I])
			end
			return Offset
		else
			local Count = 0
			for _ in Value do
				Count += 1
			end
			buffer.writeu8(Buf, Offset, TYPE_TABLE)
			buffer.writeu32(Buf, Offset + 1, Count)
			Offset += 5
			for K, V in Value do
				Offset = writeValue(Buf, Offset, K)
				Offset = writeValue(Buf, Offset, V)
			end
			return Offset
		end
	end
	buffer.writeu8(Buf, Offset, TYPE_NIL)
	return Offset + 1
end

local function readValue(Buf: buffer, Offset: number): (any, number)
	local Tag = buffer.readu8(Buf, Offset)
	Offset += 1
	if Tag == TYPE_NIL then
		return nil, Offset
	elseif Tag == TYPE_BOOL then
		return buffer.readu8(Buf, Offset) == 1, Offset + 1
	elseif Tag == TYPE_NUMBER then
		return buffer.readf64(Buf, Offset), Offset + 8
	elseif Tag == TYPE_STRING then
		local Len = buffer.readu32(Buf, Offset)
		return buffer.readstring(Buf, Offset + 4, Len), Offset + 4 + Len
	elseif Tag == TYPE_BUFFER then
		local Len = buffer.readu32(Buf, Offset)
		local B = buffer.create(Len)
		buffer.copy(B, 0, Buf, Offset + 4, Len)
		return B, Offset + 4 + Len
	elseif Tag == TYPE_VECTOR2 then
		return Vector2.new(buffer.readf32(Buf, Offset), buffer.readf32(Buf, Offset + 4)), Offset + 8
	elseif Tag == TYPE_VECTOR3 then
		return Vector3.new(
			buffer.readf32(Buf, Offset),
			buffer.readf32(Buf, Offset + 4),
			buffer.readf32(Buf, Offset + 8)
		), Offset + 12
	elseif Tag == TYPE_VECTOR2INT16 then
		return Vector2int16.new(buffer.readi16(Buf, Offset), buffer.readi16(Buf, Offset + 2)), Offset + 4
	elseif Tag == TYPE_VECTOR3INT16 then
		return Vector3int16.new(
			buffer.readi16(Buf, Offset),
			buffer.readi16(Buf, Offset + 2),
			buffer.readi16(Buf, Offset + 4)
		), Offset + 6
	elseif Tag == TYPE_CFRAME then
		local o = Offset
		local x = buffer.readf32(Buf, o)
		o += 4
		local y = buffer.readf32(Buf, o)
		o += 4
		local z = buffer.readf32(Buf, o)
		o += 4
		local r00 = buffer.readf32(Buf, o)
		o += 4
		local r01 = buffer.readf32(Buf, o)
		o += 4
		local r02 = buffer.readf32(Buf, o)
		o += 4
		local r10 = buffer.readf32(Buf, o)
		o += 4
		local r11 = buffer.readf32(Buf, o)
		o += 4
		local r12 = buffer.readf32(Buf, o)
		o += 4
		local r20 = buffer.readf32(Buf, o)
		o += 4
		local r21 = buffer.readf32(Buf, o)
		o += 4
		local r22 = buffer.readf32(Buf, o)
		o += 4
		return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22), o
	elseif Tag == TYPE_COLOR3 then
		return Color3.new(
			buffer.readf32(Buf, Offset),
			buffer.readf32(Buf, Offset + 4),
			buffer.readf32(Buf, Offset + 8)
		), Offset + 12
	elseif Tag == TYPE_BRICKCOLOR then
		return BrickColor.new(buffer.readu16(Buf, Offset)), Offset + 2
	elseif Tag == TYPE_UDIM then
		return UDim.new(buffer.readf32(Buf, Offset), buffer.readi32(Buf, Offset + 4)), Offset + 8
	elseif Tag == TYPE_UDIM2 then
		return UDim2.new(
			buffer.readf32(Buf, Offset),
			buffer.readi32(Buf, Offset + 4),
			buffer.readf32(Buf, Offset + 8),
			buffer.readi32(Buf, Offset + 12)
		), Offset + 16
	elseif Tag == TYPE_RECT then
		return Rect.new(
			buffer.readf32(Buf, Offset),
			buffer.readf32(Buf, Offset + 4),
			buffer.readf32(Buf, Offset + 8),
			buffer.readf32(Buf, Offset + 12)
		), Offset + 16
	elseif Tag == TYPE_REGION3 then
		return Region3.new(
			Vector3.new(buffer.readf32(Buf, Offset), buffer.readf32(Buf, Offset + 4), buffer.readf32(Buf, Offset + 8)),
			Vector3.new(buffer.readf32(Buf, Offset + 12), buffer.readf32(Buf, Offset + 16), buffer.readf32(Buf, Offset + 20))
		), Offset + 24
	elseif Tag == TYPE_REGION3INT16 then
		return Region3int16.new(
			Vector3int16.new(buffer.readi16(Buf, Offset), buffer.readi16(Buf, Offset + 2), buffer.readi16(Buf, Offset + 4)),
			Vector3int16.new(buffer.readi16(Buf, Offset + 6), buffer.readi16(Buf, Offset + 8), buffer.readi16(Buf, Offset + 10))
		), Offset + 12
	elseif Tag == TYPE_NUMBERRANGE then
		return NumberRange.new(buffer.readf32(Buf, Offset), buffer.readf32(Buf, Offset + 4)), Offset + 8
	elseif Tag == TYPE_NUMBERSEQKEY then
		return NumberSequenceKeypoint.new(
			buffer.readf32(Buf, Offset),
			buffer.readf32(Buf, Offset + 4),
			buffer.readf32(Buf, Offset + 8)
		), Offset + 12
	elseif Tag == TYPE_NUMBERSEQ then
		local Count = buffer.readu32(Buf, Offset)
		Offset += 4
		local Kps = table.create(Count)
		for I = 1, Count do
			Kps[I], Offset = readValue(Buf, Offset)
		end
		return NumberSequence.new(Kps), Offset
	elseif Tag == TYPE_COLORSEQKEY then
		return ColorSequenceKeypoint.new(
			buffer.readf32(Buf, Offset),
			Color3.new(buffer.readf32(Buf, Offset + 4), buffer.readf32(Buf, Offset + 8), buffer.readf32(Buf, Offset + 12))
		), Offset + 16
	elseif Tag == TYPE_COLORSEQ then
		local Count = buffer.readu32(Buf, Offset)
		Offset += 4
		local Kps = table.create(Count)
		for I = 1, Count do
			Kps[I], Offset = readValue(Buf, Offset)
		end
		return ColorSequence.new(Kps), Offset
	elseif Tag == TYPE_ENUMITEM then
		local ELen = buffer.readu16(Buf, Offset)
		local EName = buffer.readstring(Buf, Offset + 2, ELen)
		local NLen = buffer.readu16(Buf, Offset + 2 + ELen)
		local NName = buffer.readstring(Buf, Offset + 4 + ELen, NLen)
		local EnumType = (Enum :: any)[EName]
		local Item = if EnumType then EnumType[NName] else nil
		return Item, Offset + 4 + ELen + NLen
	elseif Tag == TYPE_PHYSICALPROPERTIES then
		return PhysicalProperties.new(
			buffer.readf32(Buf, Offset),
			buffer.readf32(Buf, Offset + 4),
			buffer.readf32(Buf, Offset + 8),
			buffer.readf32(Buf, Offset + 12),
			buffer.readf32(Buf, Offset + 16)
		), Offset + 20
	elseif Tag == TYPE_RAY then
		return Ray.new(
			Vector3.new(buffer.readf32(Buf, Offset), buffer.readf32(Buf, Offset + 4), buffer.readf32(Buf, Offset + 8)),
			Vector3.new(buffer.readf32(Buf, Offset + 12), buffer.readf32(Buf, Offset + 16), buffer.readf32(Buf, Offset + 20))
		), Offset + 24
	elseif Tag == TYPE_FACES then
		local bits = buffer.readu8(Buf, Offset)
		local list = {}
		if bit32.band(bits, 1) ~= 0 then table.insert(list, Enum.NormalId.Top) end
		if bit32.band(bits, 2) ~= 0 then table.insert(list, Enum.NormalId.Bottom) end
		if bit32.band(bits, 4) ~= 0 then table.insert(list, Enum.NormalId.Left) end
		if bit32.band(bits, 8) ~= 0 then table.insert(list, Enum.NormalId.Right) end
		if bit32.band(bits, 16) ~= 0 then table.insert(list, Enum.NormalId.Back) end
		if bit32.band(bits, 32) ~= 0 then table.insert(list, Enum.NormalId.Front) end
		return Faces.new(table.unpack(list)), Offset + 1
	elseif Tag == TYPE_AXES then
		local bits = buffer.readu8(Buf, Offset)
		local list = {}
		if bit32.band(bits, 1) ~= 0 then table.insert(list, Enum.Axis.X) end
		if bit32.band(bits, 2) ~= 0 then table.insert(list, Enum.Axis.Y) end
		if bit32.band(bits, 4) ~= 0 then table.insert(list, Enum.Axis.Z) end
		return Axes.new(table.unpack(list)), Offset + 1
	elseif Tag == TYPE_PATHWAYPOINT then
		local x = buffer.readf32(Buf, Offset)
		local y = buffer.readf32(Buf, Offset + 4)
		local z = buffer.readf32(Buf, Offset + 8)
		local actionVal = buffer.readu8(Buf, Offset + 12)
		local labelLen = buffer.readu16(Buf, Offset + 13)
		local label = buffer.readstring(Buf, Offset + 15, labelLen)
		local action = Enum.PathWaypointAction:FromValue(actionVal) or Enum.PathWaypointAction.Walk
		return PathWaypoint.new(Vector3.new(x, y, z), action, label), Offset + 15 + labelLen
	elseif Tag == TYPE_TWEENINFO then
		return TweenInfo.new(
			buffer.readf32(Buf, Offset),
			Enum.EasingStyle:FromValue(buffer.readu8(Buf, Offset + 4)) or Enum.EasingStyle.Linear,
			Enum.EasingDirection:FromValue(buffer.readu8(Buf, Offset + 5)) or Enum.EasingDirection.InOut,
			buffer.readi32(Buf, Offset + 6),
			buffer.readu8(Buf, Offset + 10) == 1,
			buffer.readf32(Buf, Offset + 11)
		), Offset + 15
	elseif Tag == TYPE_DATETIME then
		return DateTime.fromUnixTimestampMillis(buffer.readf64(Buf, Offset)), Offset + 8
	elseif Tag == TYPE_FONT then
		local famLen = buffer.readu16(Buf, Offset)
		local fam = buffer.readstring(Buf, Offset + 2, famLen)
		local weight = Enum.FontWeight:FromValue(buffer.readu8(Buf, Offset + 2 + famLen)) or Enum.FontWeight.Regular
		local style = Enum.FontStyle:FromValue(buffer.readu8(Buf, Offset + 3 + famLen)) or Enum.FontStyle.Normal
		return Font.new(fam, weight, style), Offset + 4 + famLen
	elseif Tag == TYPE_FLOATCURVEKEY then
		return FloatCurveKey.new(
			buffer.readf32(Buf, Offset),
			buffer.readf32(Buf, Offset + 4),
			Enum.KeyInterpolationMode:FromValue(buffer.readu8(Buf, Offset + 8)) or Enum.KeyInterpolationMode.Cubic
		), Offset + 9
	elseif Tag == TYPE_ROTATIONCURVEKEY then
		local t = buffer.readf32(Buf, Offset)
		local cf
		cf, Offset = readValue(Buf, Offset + 4)
		local mode = Enum.KeyInterpolationMode:FromValue(buffer.readu8(Buf, Offset)) or Enum.KeyInterpolationMode.Cubic
		return RotationCurveKey.new(t, cf, mode), Offset + 1
	elseif Tag == TYPE_ARRAY then
		local Count = buffer.readu32(Buf, Offset)
		Offset += 4
		local Arr = table.create(Count)
		for I = 1, Count do
			Arr[I], Offset = readValue(Buf, Offset)
		end
		return Arr, Offset
	elseif Tag == TYPE_TABLE then
		local Count = buffer.readu32(Buf, Offset)
		Offset += 4
		local Tbl = {}
		for _ = 1, Count do
			local K, V
			K, Offset = readValue(Buf, Offset)
			V, Offset = readValue(Buf, Offset)
			Tbl[K] = V
		end
		return Tbl, Offset
	end
	return nil, Offset
end

local function writePath(Buf: buffer, Offset: number, Path: { any }): number
	buffer.writeu8(Buf, Offset, math.min(#Path, 255))
	Offset += 1
	for I = 1, math.min(#Path, 255) do
		Offset = writeValue(Buf, Offset, Path[I])
	end
	return Offset
end

local function readPath(Buf: buffer, Offset: number): ({ any }, number)
	local Len = buffer.readu8(Buf, Offset)
	Offset += 1
	local Path = table.create(Len)
	for I = 1, Len do
		Path[I], Offset = readValue(Buf, Offset)
	end
	return Path, Offset
end

function Util.MeasureReplica(Kind: string, StoreName: string, Key: string, Seq: number, Data: any?, Patches: { any }?): number
	local Size = 1 + 4 + 2 + #StoreName + 2 + #Key
	if Kind == "Full" then
		Size += measureValue(Data)
	else
		Size += 2
		if Patches then
			for _, Patch in Patches do
				Size += measurePath(Patch.Path) + measureValue(Patch.Value)
			end
		end
	end
	return Size
end

function Util.EncodeReplica(Kind: string, StoreName: string, Key: string, Seq: number, Data: any?, Patches: { any }?): buffer
	local Size = Util.MeasureReplica(Kind, StoreName, Key, Seq, Data, Patches)
	local Buf = buffer.create(Size)
	local Offset = 0
	buffer.writeu8(Buf, Offset, if Kind == "Full" then 1 else 2)
	Offset += 1
	buffer.writeu32(Buf, Offset, Seq)
	Offset += 4
	buffer.writeu16(Buf, Offset, #StoreName)
	Offset += 2
	buffer.writestring(Buf, Offset, StoreName)
	Offset += #StoreName
	buffer.writeu16(Buf, Offset, #Key)
	Offset += 2
	buffer.writestring(Buf, Offset, Key)
	Offset += #Key
	if Kind == "Full" then
		writeValue(Buf, Offset, Data)
	else
		local Count = if Patches then #Patches else 0
		buffer.writeu16(Buf, Offset, Count)
		Offset += 2
		if Patches then
			for _, Patch in Patches do
				Offset = writePath(Buf, Offset, Patch.Path)
				Offset = writeValue(Buf, Offset, Patch.Value)
			end
		end
	end
	return Buf
end

function Util.DecodeReplica(Buf: buffer): any
	local Offset = 0
	local KindByte = buffer.readu8(Buf, Offset)
	Offset += 1
	local Seq = buffer.readu32(Buf, Offset)
	Offset += 4
	local StoreLen = buffer.readu16(Buf, Offset)
	Offset += 2
	local StoreName = buffer.readstring(Buf, Offset, StoreLen)
	Offset += StoreLen
	local KeyLen = buffer.readu16(Buf, Offset)
	Offset += 2
	local Key = buffer.readstring(Buf, Offset, KeyLen)
	Offset += KeyLen
	if KindByte == 1 then
		local Data
		Data, Offset = readValue(Buf, Offset)
		return { StoreName = StoreName, Key = Key, Seq = Seq, Kind = "Full", Data = Data }
	end
	local Count = buffer.readu16(Buf, Offset)
	Offset += 2
	local Patches = table.create(Count)
	for I = 1, Count do
		local Path, Value
		Path, Offset = readPath(Buf, Offset)
		Value, Offset = readValue(Buf, Offset)
		Patches[I] = { Path = Path, Value = Value }
	end
	return { StoreName = StoreName, Key = Key, Seq = Seq, Kind = "Patch", Patches = Patches }
end

return Util

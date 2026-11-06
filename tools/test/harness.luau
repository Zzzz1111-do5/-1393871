--!nocheck
-- 测试台：用 Lune 的 roblox 库（实例、属性、枚举按 Roblox 反射数据库校验）模拟一个 Roblox 服务器 + 若干客户端，
-- 把 rbxlx 里的脚本原样跑起来：虚拟时钟的任务调度、信号、远程事件（下一帧送达、按 Roblox 规则拷贝参数）、
-- 角色、背包、射线、DataStore（未发布 / 内存两种）、补间、Debris。服务器和客户端共用一棵实例树（不模拟复制）。
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local Inst = roblox.Instance
local V3, CF, V2 = roblox.Vector3, roblox.CFrame, roblox.Vector2
local Enum = roblox.Enum

local H = {
	errors = {}, warns = {}, netWarns = {}, prints = {}, now = 0, ctx = nil, frame = 0, verbose = false,
	input = {}, Gs = {}, epoch = 1762387200, dsMode = "unpublished", ds = {}, terrainFills = 0, kicked = {},
	closeFns = {}, maxErrors = 60, printFilter = nil,
}

---------------------------------------------------------------- 调度
local heap, seq = {}, 0
local function less(a, b) return a.at < b.at or (a.at == b.at and a.seq < b.seq) end
local function hpush(e)
	seq += 1
	e.seq = seq
	table.insert(heap, e)
	local i = #heap
	while i > 1 do
		local p = i // 2
		if less(heap[p], heap[i]) then break end
		heap[p], heap[i] = heap[i], heap[p]
		i = p
	end
end
local function hpop()
	local n = #heap
	if n == 0 then return nil end
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r, s = i * 2, i * 2 + 1, i
		if l <= n and less(heap[l], heap[s]) then s = l end
		if r <= n and less(heap[r], heap[s]) then s = r end
		if s == i then break end
		heap[i], heap[s] = heap[s], heap[i]
		i = s
	end
	return top
end

local threadCtx = setmetatable({}, { __mode = "k" })
local cancelled = setmetatable({}, { __mode = "k" })
local function sideName(c) return c and c.Name or "server" end
H.sideName = sideName
local PlayersSvc -- 后面赋值
local function setCtx(c)
	H.ctx = c
	-- Lune 的引用属性不能设成 nil：只在进客户端时设（服务器代码不读 LocalPlayer）
	if PlayersSvc and c and H.lastLocal ~= c then
		PlayersSvc.LocalPlayer = c
		H.lastLocal = c
	end
end

local function report(where, err, co)
	local msg = tostring(err)
	local tb = co and debug.traceback(co, msg) or msg
	table.insert(H.errors, { where = where, msg = msg, tb = tb, t = H.now, side = sideName(H.ctx) })
	H.errSeen = H.errSeen or {}
	local key = msg:sub(1, 160)
	local first = not H.errSeen[key]
	H.errSeen[key] = (H.errSeen[key] or 0) + 1
	if first and #H.errors <= H.maxErrors then
		print(string.format("[错误 %.2f 秒 %s] %s：%s", H.now, sideName(H.ctx), where, tb))
	end
end
H.report = report

local function resume(co, ...)
	if cancelled[co] then return end
	if coroutine.status(co) ~= "suspended" then return end
	local prev = H.ctx
	local c = threadCtx[co]
	setCtx(c or nil)
	local ok, err = coroutine.resume(co, ...)
	setCtx(prev)
	if not ok then report("线程", err, co) end
end
H.resume = resume
local function newThread(f)
	local co = coroutine.create(f)
	threadCtx[co] = H.ctx or false
	return co
end

local task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or newThread(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or newThread(f)
	hpush({ at = H.now, co = co, args = table.pack(...) })
	return co
end
function task.delay(t, f, ...)
	local co = type(f) == "thread" and f or newThread(f)
	hpush({ at = H.now + (tonumber(t) or 0), co = co, args = table.pack(...) })
	return co
end
function task.wait(t)
	if not coroutine.isyieldable() then error("task.wait 不能在主线程里调用", 2) end
	local co = coroutine.running()
	local t0 = H.now
	hpush({ at = H.now + math.max(tonumber(t) or 0, 1 / 60 - 1e-6), co = co, args = { n = 0 } })
	coroutine.yield()
	return H.now - t0, H.now
end
function task.cancel(co) cancelled[co] = true end
function task.synchronize() end
function task.desynchronize() end
H.task = task

---------------------------------------------------------------- 信号
local Signal = {}
Signal.__index = Signal
local function newSignal(name) return setmetatable({ name = name, conns = {} }, Signal) end
H.newSignal = newSignal
function Signal:Connect(fn)
	if type(fn) ~= "function" then error(tostring(self.name) .. ":Connect 要传函数", 2) end
	local c = { fn = fn, ctx = H.ctx or false, on = true }
	table.insert(self.conns, c)
	local conn = { Connected = true }
	conn.Disconnect = function()
		c.on = false
		conn.Connected = false
	end
	return conn
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Wait()
	local co = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		resume(co, ...)
	end)
	return coroutine.yield()
end
local function runConn(c, ...)
	local co = coroutine.create(c.fn)
	threadCtx[co] = c.ctx
	resume(co, ...)
end
function Signal:Fire(...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.on then runConn(c, ...) end
	end
end
-- 只发给某一边的连接（false = 服务器，玩家 = 那个客户端）
function Signal:FireSide(side, ...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.on and c.ctx == side then runConn(c, ...) end
	end
end
function Signal:Count(side)
	local n = 0
	for _, c in ipairs(self.conns) do
		if c.on and (side == nil or c.ctx == side) then n += 1 end
	end
	return n
end

-- 每个实例的事件
local evStore = {}
local softDestroy -- 后面定义
local childWatch = {}
local function snapshot(inst)
	local s = {}
	local ok, kids = pcall(function() return inst:GetChildren() end)
	if ok then for _, k in kids do s[k] = true end end
	return s
end
local function ev(inst, name)
	local s = evStore[inst]
	if not s then
		s = {}
		evStore[inst] = s
	end
	local g = s[name]
	if not g then
		local nm = "?"
		pcall(function() nm = inst.Name end)
		g = newSignal(nm .. "." .. name)
		s[name] = g
		if (name == "ChildAdded" or name == "ChildRemoved") and not childWatch[inst] then childWatch[inst] = snapshot(inst) end
	end
	return g
end
H.ev = ev
local function evProp(class, name)
	roblox.implementProperty(class, name, function(self) return ev(self, name) end)
end
local function evPropSide(class, name)
	roblox.implementProperty(class, name, function(self) return ev(self, name .. "@" .. sideName(H.ctx)) end)
end
for _, n in { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "AttributeChanged", "Changed" } do
	evProp("Instance", n)
end
for _, n in { "Touched", "TouchEnded" } do evProp("BasePart", n) end
for _, n in { "PlayerAdded", "PlayerRemoving" } do evProp("Players", n) end
for _, n in { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled" } do evProp("Player", n) end
for _, n in { "Died", "HealthChanged", "Running", "StateChanged", "MoveToFinished", "Jumping", "FreeFalling" } do evProp("Humanoid", n) end
for _, n in { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" } do evProp("ProximityPrompt", n) end
evProp("RemoteEvent", "OnServerEvent")
evPropSide("RemoteEvent", "OnClientEvent")
evProp("BindableEvent", "Event")
evProp("RunService", "Heartbeat")
evProp("RunService", "Stepped")
evPropSide("RunService", "RenderStepped")
for _, n in { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" } do
	evProp("GuiButton", n)
end
for _, n in { "FocusLost", "Focused" } do evProp("TextBox", n) end
for _, n in { "Activated", "Deactivated", "Equipped", "Unequipped" } do evProp("Tool", n) end
for _, n in { "InputBegan", "InputEnded", "InputChanged", "TouchTap", "TouchPan", "TouchPinch", "TouchStarted", "TouchEnded", "TouchMoved", "TouchLongPress", "TouchSwipe", "TouchRotate", "JumpRequest", "LastInputTypeChanged", "WindowFocused", "WindowFocusReleased" } do
	evPropSide("UserInputService", n)
end
evProp("TeleportService", "TeleportInitFailed")
evProp("TeleportService", "LocalPlayerArrivedFromTeleport")
for _, n in { "PromptTriggered", "PromptShown", "PromptHidden", "PromptTriggerEnded" } do evPropSide("ProximityPromptService", n) end
evProp("ScriptContext", "Error")
evProp("Sound", "Ended")
evProp("Sound", "Loaded")

roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, prop) return ev(self, "Changed:" .. tostring(prop)) end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, a) return ev(self, "AttrChanged:" .. tostring(a)) end)

---------------------------------------------------------------- 实例方法
roblox.implementMethod("Instance", "WaitForChild", function(self, name, timeout)
	if type(name) ~= "string" then error("WaitForChild 要传字符串名字", 2) end
	local c = self:FindFirstChild(name)
	if c then return c end
	if not coroutine.isyieldable() then error("WaitForChild 在主线程里等不了：" .. self:GetFullName() .. "." .. name) end
	local t0, warned = H.now, false
	while true do
		task.wait()
		local ok, r = pcall(function() return self:FindFirstChild(name) end)
		if ok and r then return r end
		if timeout and H.now - t0 >= timeout then return nil end
		if not timeout and not warned and H.now - t0 > 5 then
			warned = true
			H.warn("Infinite yield possible on '" .. self:GetFullName() .. ":WaitForChild(\"" .. name .. "\")'")
		end
	end
end)

-- 世界坐标：顺着 Weld / Motor6D 找到锚定的根（Motor6D 的 Transform 不算）
local function worldCF(p, depth)
	depth = depth or 0
	if depth > 24 or p.Anchored then return p.CFrame end
	for _, j in p:GetChildren() do
		if (j.ClassName == "Weld" or j.ClassName == "Motor6D" or j.ClassName == "WeldConstraint") and j.ClassName ~= "WeldConstraint" then
			if j.Part1 == p and j.Part0 then return worldCF(j.Part0, depth + 1) * j.C0 * j.C1:Inverse() end
		end
	end
	return p.CFrame
end
H.worldCF = worldCF

local posTracked = {}
H.posTracked = posTracked
local function movePart(p, cf)
	p.CFrame = cf
	if posTracked[p] then p.Position = cf.Position end
end
local function pivotOf(m)
	if m.PrimaryPart then return m.PrimaryPart.CFrame end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then return d.CFrame end
	end
	return CF.new()
end
roblox.implementMethod("Model", "GetPivot", function(self) return pivotOf(self) end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	if typeof(cf) ~= "CFrame" then error("PivotTo 要传 CFrame", 2) end
	local delta = cf * pivotOf(self):Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then movePart(d, delta * d.CFrame) end
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(self)
	local mn, mx = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			local c = worldCF(d).Position
			mn = V3.new(math.min(mn.X, c.X), math.min(mn.Y, c.Y), math.min(mn.Z, c.Z))
			mx = V3.new(math.max(mx.X, c.X), math.max(mx.Y, c.Y), math.max(mx.Z, c.Z))
		end
	end
	return CF.new((mn + mx) / 2), mx - mn
end)
roblox.implementMethod("Model", "ScaleTo", function(self, s) end)
roblox.implementMethod("Model", "GetScale", function(self) return 1 end)

roblox.implementMethod("Humanoid", "TakeDamage", function(self, n)
	if type(n) ~= "number" then error("TakeDamage 要传数字", 2) end
	if self.Health <= 0 then return end
	self.Health = math.max(0, self.Health - n)
	if self.Health <= 0 then ev(self, "Died"):Fire() end
end)
roblox.implementMethod("Humanoid", "MoveTo", function(self) end)
roblox.implementMethod("Humanoid", "Move", function(self) end)
roblox.implementMethod("Humanoid", "ChangeState", function(self) end)
roblox.implementMethod("Humanoid", "UnequipTools", function(self)
	local ch = self.Parent
	local pl = ch and PlayersSvc:GetPlayerFromCharacter(ch)
	if not pl then return end
	for _, t in ch:GetChildren() do
		if t:IsA("Tool") then t.Parent = pl:FindFirstChildOfClass("Backpack") end
	end
end)
roblox.implementMethod("Humanoid", "EquipTool", function(self, tool) tool.Parent = self.Parent end)
roblox.implementMethod("Humanoid", "GetState", function(self) return Enum.HumanoidStateType.Running end)

roblox.implementMethod("Sound", "Play", function(self) end)
roblox.implementMethod("Sound", "Stop", function(self) end)
roblox.implementMethod("Sound", "Pause", function(self) end)
roblox.implementMethod("Sound", "Resume", function(self) end)
roblox.implementMethod("ParticleEmitter", "Emit", function(self, n) end)
roblox.implementMethod("ParticleEmitter", "Clear", function(self) end)
roblox.implementMethod("BindableEvent", "Fire", function(self, ...) ev(self, "Event"):Fire(...) end)

---------------------------------------------------------------- 服务
local Services = {}
roblox.implementMethod("Terrain", "FillBlock", function(self, cf, size, mat)
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" or typeof(mat) ~= "EnumItem" then error("FillBlock 参数不对", 2) end
	H.terrainFills += 1
end)
roblox.implementMethod("Terrain", "FillBall", function(self) H.terrainFills += 1 end)
roblox.implementMethod("Terrain", "FillCylinder", function(self) H.terrainFills += 1 end)
roblox.implementMethod("Terrain", "FillWedge", function(self) H.terrainFills += 1 end)
roblox.implementMethod("Terrain", "Clear", function(self) end)

-- 射线：零件按长方体（球按外接盒）算，地面是 y = 0 的地形
local function rayBox(o, d, cf, size)
	local lo = cf:PointToObjectSpace(o)
	local ld = cf:VectorToObjectSpace(d)
	local h = size / 2
	local tmin, tmax = 0, 1
	for _, ax in { "X", "Y", "Z" } do
		local oo, dd, hh = lo[ax], ld[ax], h[ax]
		if math.abs(dd) < 1e-9 then
			if oo < -hh or oo > hh then return nil end
		else
			local t1, t2 = (-hh - oo) / dd, (hh - oo) / dd
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	return tmin
end
local function inList(inst, list)
	for _, x in list do
		if x ~= nil and (inst == x or inst:IsDescendantOf(x)) then return true end
	end
	return false
end
function H.raycast(o, d, params)
	if typeof(o) ~= "Vector3" or typeof(d) ~= "Vector3" then error("Raycast 参数要是 Vector3", 3) end
	local include = params and params.FilterType == Enum.RaycastFilterType.Include
	local list = params and params.FilterDescendantsInstances or {}
	local ws = H.workspace
	local best, bt = nil, math.huge
	for _, p in ws:GetDescendants() do
		if p:IsA("BasePart") and p.CanQuery then
			local ok = true
			if #list > 0 or include then
				local hit = inList(p, list)
				if include then ok = hit else ok = not hit end
			end
			if ok then
				local t = rayBox(o, d, worldCF(p), p.Size)
				if t and t < bt then bt, best = t, p end
			end
		end
	end
	local terrain = ws:FindFirstChildOfClass("Terrain")
	local terrainOK = true
	if include then terrainOK = terrain ~= nil and inList(terrain, list) elseif terrain and inList(terrain, list) then terrainOK = false end
	if terrainOK and d.Y < 0 then
		local t = -o.Y / d.Y
		if t >= 0 and t <= 1 and t < bt then bt, best = t, terrain end
	end
	if not best then return nil end
	local pos = o + d * bt
	return { Instance = best, Position = pos, Normal = V3.new(0, 1, 0), Distance = d.Magnitude * bt, Material = Enum.Material.Plastic }
end

local function camRay(cam, x, y)
	local vs = cam.ViewportSize
	local cf = cam.CFrame
	local tanY = math.tan(math.rad(35))
	local nx = (x / vs.X) * 2 - 1
	local ny = 1 - (y / vs.Y) * 2
	local dir = (cf.LookVector + cf.RightVector * nx * tanY * (vs.X / vs.Y) + cf.UpVector * ny * tanY).Unit
	return roblox.Ray.new(cf.Position, dir)
end
roblox.implementMethod("Camera", "ScreenPointToRay", function(self, x, y) return camRay(self, x, y + 36) end)
roblox.implementMethod("Camera", "ViewportPointToRay", function(self, x, y) return camRay(self, x, y) end)
roblox.implementMethod("Camera", "WorldToViewportPoint", function(self, p)
	local lp = self.CFrame:PointToObjectSpace(p)
	return V3.new(640, 360, -lp.Z), lp.Z < 0
end)
roblox.implementMethod("Camera", "WorldToScreenPoint", function(self, p)
	local lp = self.CFrame:PointToObjectSpace(p)
	return V3.new(640, 324, -lp.Z), lp.Z < 0
end)

-- 远程事件：下一帧送达，参数按 Roblox 规则拷贝（函数丢掉、混合表只留数组部分），没人听的先排队
local netQ = {}
local function netWarn(msg)
	if not H.netWarns[msg] then
		H.netWarns[msg] = true
		print("[远程事件警告] " .. msg)
	end
end
local function wire(v, path, mode, seen)
	local t = type(v)
	if t == "function" or t == "thread" then
		if mode == "ds" then error("DataStore 存不了函数：" .. path) end
		netWarn("函数不能经远程事件传：" .. path)
		return nil
	end
	if t == "userdata" then
		if mode == "ds" then error("DataStore 存不了 " .. typeof(v) .. "：" .. path) end
		return v
	end
	if t ~= "table" then
		if mode == "ds" and t == "number" and (v ~= v or v == math.huge or v == -math.huge) then error("DataStore 存不了 NaN / inf：" .. path) end
		return v
	end
	seen = seen or {}
	if seen[v] then
		if mode == "ds" then error("DataStore 表里有环：" .. path) end
		netWarn("表里有环：" .. path)
		return nil
	end
	seen[v] = true
	local hasNum, hasStr, n = false, false, #v
	for k in pairs(v) do
		if type(k) == "number" then
			hasNum = true
			if k < 1 or k > n or k % 1 ~= 0 then
				if mode == "ds" then error("DataStore 数组有空洞 / 非整数键：" .. path) end
				netWarn("数组有空洞或非整数键（会被截断 / 转成字符串）：" .. path .. "[" .. tostring(k) .. "]")
			end
		elseif type(k) == "string" then
			hasStr = true
		else
			if mode == "ds" then error("DataStore 键只能是字符串：" .. path) end
			netWarn("非字符串键：" .. path)
		end
	end
	if hasNum and hasStr then
		if mode == "ds" then error("DataStore 混合表：" .. path) end
		netWarn("混合表（数字键 + 字符串键，Roblox 只传数组部分）：" .. path)
	end
	local out = {}
	for k, x in pairs(v) do out[k] = wire(x, path .. "." .. tostring(k), mode, seen) end
	if hasNum and hasStr then
		local arr = {}
		for i = 1, n do arr[i] = out[i] end
		out = arr
	end
	seen[v] = nil
	return out
end
H.wire = wire
local function packWire(...)
	local a = table.pack(...)
	for i = 1, a.n do a[i] = wire(a[i], "参数" .. i, "net") end
	return a
end
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	if not H.ctx then error("FireServer 只能在客户端调用", 2) end
	table.insert(netQ, { kind = "s", remote = self, from = H.ctx, args = packWire(...), t = H.now })
	if H.showNet then
		local a = table.pack(...)
		local parts = {}
		for i = 1, a.n do parts[i] = tostring(a[i]) end
		print(string.format("  [上行 %.2f %s → %s] %s", H.now, H.ctx.Name, self.Name, table.concat(parts, ", ")))
	end
end)
roblox.implementMethod("RemoteEvent", "FireClient", function(self, pl, ...)
	if H.ctx then error("FireClient 只能在服务器调用", 2) end
	if typeof(pl) ~= "Instance" or not pl:IsA("Player") then error("FireClient 第一个参数要是 Player", 2) end
	table.insert(netQ, { kind = "c", remote = self, to = pl, args = packWire(...), t = H.now })
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
	if H.ctx then error("FireAllClients 只能在服务器调用", 2) end
	local args = packWire(...)
	for _, pl in PlayersSvc:GetChildren() do
		if pl:IsA("Player") then table.insert(netQ, { kind = "c", remote = self, to = pl, args = args, t = H.now }) end
	end
end)
H.netStats = { s = 0, c = 0, bytes = 0 }
local function deliver(m)
	if m.kind == "s" then
		if m.from.Parent == nil then return true end
		local sig = ev(m.remote, "OnServerEvent")
		if sig:Count(false) == 0 then return false end
		H.netStats.s += 1
		sig:FireSide(false, m.from, table.unpack(m.args, 1, m.args.n))
	else
		if m.to.Parent == nil then return true end
		local sig = ev(m.remote, "OnClientEvent@" .. m.to.Name)
		if sig:Count() == 0 then return false end
		if m.remote.Name == "Toast" then
			H.toasts = H.toasts or {}
			table.insert(H.toasts, { t = H.now, to = m.to.Name, msg = tostring(m.args[1]), kind = m.args[2] })
			if H.showToasts then print(string.format("  [提示 %.1f %s %s] %s", H.now, m.to.Name, tostring(m.args[2]), tostring(m.args[1]))) end
		end
		H.netStats.c += 1
		sig:Fire(table.unpack(m.args, 1, m.args.n))
	end
	return true
end

-- DataStore（未发布：一调用就报错；mock：内存里存，按 JSON 规则检查）
local function mockStore(name, ordered)
	H.ds[name] = H.ds[name] or {}
	local data = H.ds[name]
	local S = {}
	local function chk(v, key)
		return wire(v, name .. "/" .. key, "ds")
	end
	function S:GetAsync(key)
		task.wait(0.05)
		local v = data[key]
		if type(v) == "table" then return wire(v, "", "net") end
		return v
	end
	function S:SetAsync(key, v)
		task.wait(0.05)
		if ordered and (type(v) ~= "number" or v % 1 ~= 0) then error("OrderedDataStore 只能存整数：" .. tostring(v)) end
		data[key] = chk(v, key)
	end
	function S:UpdateAsync(key, f)
		task.wait(0.05)
		local old = data[key]
		if type(old) == "table" then old = wire(old, "", "net") end
		local nv = f(old)
		if nv ~= nil then data[key] = chk(nv, key) end
		return nv
	end
	function S:RemoveAsync(key)
		local v = data[key]
		data[key] = nil
		return v
	end
	function S:IncrementAsync(key, d)
		data[key] = (data[key] or 0) + (d or 1)
		return data[key]
	end
	function S:GetSortedAsync(asc, pageSize, mn, mx)
		task.wait(0.05)
		local items = {}
		for k, v in pairs(data) do
			if (not mn or v >= mn) and (not mx or v <= mx) then table.insert(items, { key = k, value = v }) end
		end
		table.sort(items, function(a, b)
			if asc then return a.value < b.value end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize or 50, #items) do page[i] = items[i] end
		return { GetCurrentPage = function() return page end, IsFinished = true, AdvanceToNextPageAsync = function() end }
	end
	return S
end
roblox.implementMethod("DataStoreService", "GetDataStore", function(self, name)
	if H.dsMode == "unpublished" then error("You must publish this place to the web to access DataStore.", 2) end
	return mockStore(name, false)
end)
roblox.implementMethod("DataStoreService", "GetOrderedDataStore", function(self, name)
	if H.dsMode == "unpublished" then error("You must publish this place to the web to access DataStore.", 2) end
	return mockStore("ordered:" .. name, true)
end)
roblox.implementMethod("DataStoreService", "GetRequestBudgetForRequestType", function() return 100 end)
roblox.implementMethod("MemoryStoreService", "GetSortedMap", function(self, name) error("MemoryStoreService 在 Studio 里不可用（模拟）", 2) end)
roblox.implementMethod("MemoryStoreService", "GetQueue", function(self, name) error("MemoryStoreService 在 Studio 里不可用（模拟）", 2) end)
roblox.implementMethod("MessagingService", "SubscribeAsync", function(self) task.wait(0.5); error("MessagingService 在 Studio 里不可用（模拟）") end)
roblox.implementMethod("MessagingService", "PublishAsync", function(self) error("MessagingService 在 Studio 里不可用（模拟）") end)
roblox.implementMethod("TeleportService", "ReserveServer", function(self) error("Studio 里不能传送（模拟）") end)
roblox.implementMethod("TeleportService", "TeleportAsync", function(self) error("Studio 里不能传送（模拟）") end)
roblox.implementMethod("TeleportService", "Teleport", function(self) error("Studio 里不能传送（模拟）") end)
roblox.implementMethod("TeleportService", "GetLocalPlayerTeleportData", function(self) return nil end)

roblox.implementMethod("Debris", "AddItem", function(self, inst, t)
	if typeof(inst) ~= "Instance" then error("Debris:AddItem 要传实例", 2) end
	task.delay(t or 10, function() softDestroy(inst) end)
end)
roblox.implementMethod("CollectionService", "AddTag", function(self, inst, tag) inst:AddTag(tag) end)
roblox.implementMethod("CollectionService", "RemoveTag", function(self, inst, tag) inst:RemoveTag(tag) end)
roblox.implementMethod("CollectionService", "HasTag", function(self, inst, tag) return inst:HasTag(tag) end)
roblox.implementMethod("CollectionService", "GetTagged", function(self, tag)
	local out = {}
	for _, d in H.game:GetDescendants() do
		if d:HasTag(tag) then table.insert(out, d) end
	end
	return out
end)
roblox.implementMethod("CollectionService", "GetInstanceAddedSignal", function(self, tag) return ev(self, "Added:" .. tag) end)

roblox.implementMethod("TweenService", "Create", function(self, inst, info, props)
	if typeof(inst) ~= "Instance" then error("TweenService:Create 第一个参数要是实例", 2) end
	if type(info) ~= "table" or info.__type ~= "TweenInfo" then error("TweenService:Create 第二个参数要是 TweenInfo", 2) end
	if type(props) ~= "table" then error("TweenService:Create 第三个参数要是表", 2) end
	for k, v in pairs(props) do
		local okR, cur = pcall(function() return inst[k] end)
		if okR and cur ~= nil and typeof(cur) ~= typeof(v) and not (type(cur) == "number" and type(v) == "number") then
			error("TweenService:Create 属性 " .. k .. " 类型不对（" .. typeof(cur) .. " ← " .. typeof(v) .. "）", 2)
		end
		if not okR and not tostring(cur):find("missing default") then error("TweenService:Create：" .. tostring(cur), 2) end
	end
	local tw = { Completed = newSignal("Tween.Completed"), PlaybackState = Enum.PlaybackState.Begin, Instance = inst }
	function tw.Play()
		task.delay(info.Time or 1, function()
			local ok = pcall(function() return inst.Parent end)
			if not ok then return end
			for k, v in pairs(props) do
				local okS, err = pcall(function() inst[k] = v end)
				if not okS and not tostring(err):find("destroyed") then report("补间设属性 " .. k, err) end
			end
			tw.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tw.Cancel() end
	function tw.Pause() end
	function tw.Destroy() end
	return tw
end)

roblox.implementMethod("Players", "GetPlayers", function(self)
	local t = {}
	for _, c in self:GetChildren() do
		if c:IsA("Player") then table.insert(t, c) end
	end
	return t
end)
roblox.implementMethod("Players", "GetPlayerFromCharacter", function(self, ch)
	if ch == nil then return nil end
	for _, p in self:GetChildren() do
		if p:IsA("Player") and p.Character == ch then return p end
	end
	return nil
end)
roblox.implementMethod("Players", "GetPlayerByUserId", function(self, id)
	for _, p in self:GetChildren() do
		if p:IsA("Player") and p.UserId == id then return p end
	end
	return nil
end)
roblox.implementMethod("Players", "GetNameFromUserIdAsync", function(self, id) return "User" .. tostring(id) end)
roblox.implementMethod("Players", "GetUserIdFromNameAsync", function(self, n) return 1 end)

roblox.implementMethod("Player", "Kick", function(self, msg)
	H.kicked[self.Name] = msg or ""
	print("[踢出] " .. self.Name .. "：" .. tostring(msg))
	task.defer(function() H.removePlayer(self) end)
end)
roblox.implementMethod("Player", "GetJoinData", function(self) return { TeleportData = nil, SourcePlaceId = 0 } end)
roblox.implementMethod("Player", "GetMouse", function(self)
	return { Hit = CF.new(0, 0, -100), Target = nil, X = 640, Y = 360, Icon = "", UnitRay = roblox.Ray.new(V3.new(), V3.new(0, 0, -1)) }
end)
roblox.implementMethod("Player", "IsInGroup", function(self) return false end)
roblox.implementMethod("Player", "GetRankInGroup", function(self) return 0 end)
roblox.implementMethod("Player", "LoadCharacter", function(self) H.loadChar(self) end)

roblox.implementMethod("RunService", "IsServer", function(self) return H.ctx == nil end)
roblox.implementMethod("RunService", "IsClient", function(self) return H.ctx ~= nil end)
roblox.implementMethod("RunService", "IsStudio", function(self) return true end)
roblox.implementMethod("RunService", "IsRunning", function(self) return true end)
roblox.implementMethod("RunService", "BindToRenderStep", function(self, name, prio, fn)
	ev(self, "RenderStepped@" .. sideName(H.ctx)):Connect(fn)
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(self) end)

roblox.implementMethod("UserInputService", "GetMouseLocation", function(self)
	local s = H.input[H.ctx]
	return s and s.mouse or V2.new(640, 360)
end)
roblox.implementMethod("UserInputService", "IsKeyDown", function(self, key)
	local s = H.input[H.ctx]
	return s ~= nil and s.keys[key] == true
end)
roblox.implementMethod("UserInputService", "IsMouseButtonPressed", function(self, b)
	local s = H.input[H.ctx]
	return s ~= nil and s.keys[b] == true
end)
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function(self) return nil end)
roblox.implementMethod("UserInputService", "GetKeysPressed", function(self) return {} end)
roblox.implementMethod("UserInputService", "GetLastInputType", function(self) return Enum.UserInputType.Keyboard end)
roblox.implementMethod("ContextActionService", "BindAction", function(self) end)
roblox.implementMethod("ContextActionService", "UnbindAction", function(self) end)
roblox.implementMethod("StarterGui", "SetCoreGuiEnabled", function(self) end)
roblox.implementMethod("StarterGui", "SetCore", function(self) end)
roblox.implementMethod("GuiService", "GetGuiInset", function(self) return V2.new(0, 36), V2.new() end)

roblox.implementMethod("DataModel", "BindToClose", function(self, f) table.insert(H.closeFns, f) end)
roblox.implementMethod("Workspace", "Raycast", function(self, o, d, params) return H.raycast(o, d, params) end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function(self) return H.epoch + H.now end)
roblox.implementMethod("Workspace", "GetPartBoundsInRadius", function(self) return {} end)
roblox.implementMethod("Workspace", "GetPartBoundsInBox", function(self) return {} end)

---------------------------------------------------------------- Roblox 全局里 Lune 没有的
local Random = {}
local RandomMT = {}
RandomMT.__index = RandomMT
function Random.new(seed)
	local s = math.floor(tonumber(seed) or (H.now * 1000 + 12345)) % 2147483647
	if s <= 0 then s += 2147483646 end
	return setmetatable({ __type = "Random", s = s }, RandomMT)
end
function RandomMT:_n()
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function RandomMT:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * self:_n()
end
function RandomMT:NextInteger(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then error("NextInteger 要两个数字", 2) end
	if b < a then error("invalid argument #2 to 'NextInteger' (max must be greater than or equal to min)", 2) end
	return a + math.floor(self:_n() * (b - a + 1))
end
function RandomMT:NextUnitVector()
	return V3.new(self:_n() - 0.5, self:_n() - 0.5, self:_n() - 0.5).Unit
end
function RandomMT:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomMT:Clone() return setmetatable({ __type = "Random", s = self.s }, RandomMT) end

local TweenInfo = {
	new = function(time, style, dir, rep, rev, delay)
		return { __type = "TweenInfo", Time = time or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rep or 0, Reverses = rev or false, DelayTime = delay or 0 }
	end,
}
local function paramsClass(name, fields)
	return {
		new = function()
			local data = {}
			for k, v in pairs(fields) do data[k] = v end
			return setmetatable({}, {
				__index = function(_, k)
					if k == "__type" then return name end
					if fields[k] == nil and k ~= "FilterDescendantsInstances" then error(tostring(k) .. " is not a valid member of " .. name, 2) end
					return data[k]
				end,
				__newindex = function(_, k, v)
					if fields[k] == nil and k ~= "FilterDescendantsInstances" then error(tostring(k) .. " is not a valid member of " .. name, 2) end
					if k == "FilterType" and (typeof(v) ~= "EnumItem" or v.EnumType ~= Enum.RaycastFilterType) then error("FilterType 要是 Enum.RaycastFilterType", 2) end
					data[k] = v
				end,
			})
		end,
	}
end
local RaycastParams = paramsClass("RaycastParams", { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = false, IgnoreWater = false, RespectCanCollide = false, CollisionGroup = "Default", BruteForceAllSlow = false })
local OverlapParams = paramsClass("OverlapParams", { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = false, MaxParts = 0, RespectCanCollide = false, CollisionGroup = "Default", BruteForceAllSlow = false })
local DateTime = {
	now = function()
		local t = H.epoch + H.now
		return { UnixTimestamp = math.floor(t), UnixTimestampMillis = math.floor(t * 1000) }
	end,
}
local function typeofx(v)
	if type(v) == "table" then
		local ok, t = pcall(function() return rawget(v, "__type") end)
		if ok and t then return t end
		local mt = getmetatable(v)
		if type(mt) == "table" and type(mt.__index) == "function" then
			local ok2, t2 = pcall(function() return v.__type end)
			if ok2 and t2 then return t2 end
		end
	end
	return typeof(v)
end

local function hwarn(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local s = table.concat(parts, " ")
	table.insert(H.warns, { t = H.now, side = sideName(H.ctx), msg = s })
	if H.verbose or not H.quietWarn then print(string.format("[warn %.2f %s] %s", H.now, sideName(H.ctx), s)) end
end
H.warn = hwarn
local function hprint(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local s = table.concat(parts, " ")
	table.insert(H.prints, { t = H.now, side = sideName(H.ctx), msg = s })
	if H.verbose then print(string.format("[print %.2f %s] %s", H.now, sideName(H.ctx), s)) end
end

local OS = {
	clock = function() return H.now end,
	time = function(t)
		if t then return os.time(t) end
		return math.floor(H.epoch + H.now)
	end,
	date = os.date,
	difftime = os.difftime,
}

---------------------------------------------------------------- 脚本加载
local genv = {
	math = math, string = string, table = table, coroutine = coroutine, utf8 = utf8, bit32 = bit32, buffer = buffer, debug = debug,
	pairs = pairs, ipairs = ipairs, next = next, select = select, type = type, tostring = tostring, tonumber = tonumber,
	rawequal = rawequal, rawget = rawget, rawset = rawset, rawlen = rawlen, setmetatable = setmetatable, getmetatable = getmetatable,
	pcall = pcall, xpcall = xpcall, error = error, assert = assert, unpack = table.unpack, newproxy = newproxy, gcinfo = gcinfo,
	typeof = typeofx, print = hprint, warn = hwarn, os = OS, task = task,
	tick = function() return H.epoch + H.now end, time = function() return H.now end, elapsedTime = function() return H.now end,
	wait = function(t) return task.wait(t) end, delay = function(t, f) return task.delay(t, f) end, spawn = function(f) return task.defer(f) end,
	Vector3 = V3, Vector2 = V2, CFrame = CF, Color3 = roblox.Color3, UDim = roblox.UDim, UDim2 = roblox.UDim2, Enum = Enum,
	BrickColor = roblox.BrickColor, Ray = roblox.Ray, Rect = roblox.Rect, Region3 = roblox.Region3, NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange, PhysicalProperties = roblox.PhysicalProperties, Faces = roblox.Faces, Axes = roblox.Axes, Font = roblox.Font,
	Vector3int16 = roblox.Vector3int16, Vector2int16 = roblox.Vector2int16,
	Random = Random, TweenInfo = TweenInfo, RaycastParams = RaycastParams, OverlapParams = OverlapParams, DateTime = DateTime,
	Instance = { new = function(class, parent)
		local i = Inst.new(class)
		if class == "Humanoid" then
			i.MaxHealth = 100
			i.Health = 100
		end
		if parent then i.Parent = parent end
		return i
	end },
	shared = {}, _VERSION = "Luau",
}
genv._G = genv

local modCache = {}
local loadScript
local function hrequire(m)
	if typeof(m) ~= "Instance" or not m:IsA("ModuleScript") then error("require 只能传 ModuleScript：" .. tostring(m), 2) end
	local side = sideName(H.ctx)
	modCache[m] = modCache[m] or {}
	local c = modCache[m][side]
	if c then
		if c.loading then error("循环 require：" .. m:GetFullName(), 2) end
		return c.value
	end
	c = { loading = true }
	modCache[m][side] = c
	local fn = loadScript(m)
	local res = table.pack(fn())
	if res.n ~= 1 then error("模块必须正好返回一个值：" .. m:GetFullName(), 2) end
	local value = res[1]
	if type(value) == "table" and type(rawget(value, "init")) == "function" then
		local init = value.init
		value.init = function(G, ...)
			H.Gs[side] = G
			return init(G, ...)
		end
	end
	c.loading = false
	c.value = value
	return value
end
genv.require = hrequire

local destroyed = {}
H.destroyed = destroyed
function softDestroy(x)
	if destroyed[x] then return end
	local ok = pcall(function()
		local s = evStore[x]
		if s and s.Destroying then s.Destroying:Fire() end
		for _, d in x:GetDescendants() do destroyed[d] = true end
		destroyed[x] = true
		x.Parent = nil
	end)
end
H.softDestroy = softDestroy
roblox.implementMethod("Instance", "HDestroy", function(self) softDestroy(self) end)
roblox.implementMethod("Instance", "HClearAllChildren", function(self)
	for _, c in self:GetChildren() do softDestroy(c) end
end)
function loadScript(inst)
	local src = inst.Source
	if type(src) ~= "string" then src = tostring(src) end
	src = src:gsub(":Destroy%(%)", ":HDestroy()"):gsub(":ClearAllChildren%(%)", ":HClearAllChildren()")
	local env = setmetatable({ script = inst }, { __index = genv })
	H.envs = H.envs or {}
	H.envs[inst] = env
	local ok, fn = pcall(luau.load, src, { debugName = inst:GetFullName(), environment = env, injectGlobals = false })
	if not ok then error("编译失败 " .. inst:GetFullName() .. "：" .. tostring(fn), 0) end
	return fn
end
H.loadScript = loadScript

---------------------------------------------------------------- 角色、玩家
function H.makeChar(pl)
	local m = Inst.new("Model")
	m.Name = pl.Name
	local hum = Inst.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	local function part(name, size, y)
		local p = Inst.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CF.new(0, y, 0)
		p.Position = V3.new(0, y, 0)
		posTracked[p] = true
		p.Parent = m
		return p
	end
	local hrp = part("HumanoidRootPart", V3.new(2, 2, 1), 3)
	hrp.Transparency = 1
	part("Head", V3.new(2, 1, 1), 4.5)
	part("Torso", V3.new(2, 2, 1), 3)
	part("Left Leg", V3.new(1, 2, 1), 1)
	part("Right Leg", V3.new(1, 2, 1), 1)
	local face = Inst.new("Decal")
	face.Name = "face"
	face.Parent = m.Head
	hum.Parent = m
	m.PrimaryPart = hrp
	return m
end

function H.loadChar(pl)
	local old = pl.Character
	if old then
		ev(pl, "CharacterRemoving"):Fire(old)
		softDestroy(old)
	end
	local bp = pl:FindFirstChildOfClass("Backpack")
	if bp then softDestroy(bp) end
	bp = Inst.new("Backpack")
	bp.Parent = pl
	local ch = H.makeChar(pl)
	ch:PivotTo(CF.new(0, 50, 0))
	ch.Parent = H.workspace
	pl.Character = ch
	ev(pl, "CharacterAdded"):Fire(ch)
	H.charLoads = (H.charLoads or 0) + 1
	return ch
end

function H.addPlayer(name, userId)
	local pl = Inst.new("Player")
	pl.Name = name
	pl.UserId = userId
	pl.DisplayName = name
	local pg = Inst.new("PlayerGui")
	pg.Parent = pl
	local bp = Inst.new("Backpack")
	bp.Parent = pl
	local ps = Inst.new("PlayerScripts")
	ps.Parent = pl
	H.input[pl] = { keys = {}, mouse = V2.new(640, 360) }
	pl.Parent = PlayersSvc
	ev(PlayersSvc, "PlayerAdded"):Fire(pl)
	local sps = H.game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if sps then
		for _, c in sps:GetChildren() do c:Clone().Parent = ps end
	end
	local prev = H.ctx
	setCtx(pl)
	for _, s in ps:GetDescendants() do
		if s.ClassName == "LocalScript" then
			local ok, fn = pcall(loadScript, s)
			if ok then task.spawn(fn) else report("加载客户端脚本", fn) end
		end
	end
	setCtx(prev)
	if PlayersSvc.CharacterAutoLoads then task.defer(function() H.loadChar(pl) end) end
	return pl
end

function H.removePlayer(pl)
	if pl.Parent == nil then return end
	ev(PlayersSvc, "PlayerRemoving"):Fire(pl)
	if pl.Character then softDestroy(pl.Character) end
	pl.Parent = nil
end

---------------------------------------------------------------- 输入模拟
local KC_NONE = (pcall(function() return Enum.KeyCode.Unknown end)) and Enum.KeyCode.Unknown or Enum.KeyCode.Pause
local function inputObj(kind, key, pos, state, delta)
	return {
		UserInputType = kind, KeyCode = key or KC_NONE, Position = pos or V3.new(640, 360, 0),
		UserInputState = state or Enum.UserInputState.Begin, Delta = delta or V3.new(), __type = "InputObject",
	}
end
function H.key(pl, keyCode, down)
	local s = H.input[pl]
	s.keys[keyCode] = down
	local o = inputObj(Enum.UserInputType.Keyboard, keyCode, nil, down and Enum.UserInputState.Begin or Enum.UserInputState.End)
	ev(H.UIS, (down and "InputBegan@" or "InputEnded@") .. pl.Name):Fire(o, false)
end
function H.mouseDown(pl, x, y, button)
	local s = H.input[pl]
	button = button or Enum.UserInputType.MouseButton1
	s.mouse = V2.new(x, y)
	s.keys[button] = true
	ev(H.UIS, "InputBegan@" .. pl.Name):Fire(inputObj(button, nil, V3.new(x, y, 0)), false)
end
function H.mouseUp(pl, x, y, button)
	local s = H.input[pl]
	button = button or Enum.UserInputType.MouseButton1
	s.keys[button] = false
	ev(H.UIS, "InputEnded@" .. pl.Name):Fire(inputObj(button, nil, V3.new(x or 640, y or 360, 0), Enum.UserInputState.End), false)
end
function H.mouseMove(pl, x, y)
	local s = H.input[pl]
	local old = s.mouse
	s.mouse = V2.new(x, y)
	ev(H.UIS, "InputChanged@" .. pl.Name):Fire(inputObj(Enum.UserInputType.MouseMovement, nil, V3.new(x, y, 0), Enum.UserInputState.Change, V3.new(x - old.X, y - old.Y, 0)), false)
end
function H.wheel(pl, z)
	ev(H.UIS, "InputChanged@" .. pl.Name):Fire(inputObj(Enum.UserInputType.MouseWheel, nil, V3.new(640, 360, z), Enum.UserInputState.Change), false)
end

-- 界面：按文字找按钮（要看得见才算能点）
local function visible(g)
	local x = g
	while x and not x:IsA("PlayerGui") do
		if x:IsA("GuiObject") and not x.Visible then return false end
		if x:IsA("LayerCollector") and not x.Enabled then return false end
		x = x.Parent
	end
	return x ~= nil
end
H.visible = visible
function H.findButton(pl, pattern, all)
	local pg = pl:FindFirstChildOfClass("PlayerGui")
	local out = {}
	for _, d in pg:GetDescendants() do
		if d:IsA("GuiButton") and d:IsA("TextButton") and string.find(d.Text, pattern) then
			if all or visible(d) then table.insert(out, d) end
		end
	end
	return out[1], out
end
function H.press(pl, btn)
	if not btn then error("要按的按钮不存在", 2) end
	if not visible(btn) then error("按钮看不见、点不到：" .. btn.Text, 2) end
	ev(btn, "MouseButton1Down"):Fire(640, 360)
	ev(btn, "Activated"):Fire(inputObj(Enum.UserInputType.MouseButton1), 1)
	ev(btn, "MouseButton1Click"):Fire()
	ev(btn, "MouseButton1Up"):Fire(640, 360)
end
function H.click(pl, pattern)
	local b = H.findButton(pl, pattern)
	if not b then error("找不到看得见的按钮：" .. pattern, 2) end
	H.press(pl, b)
	return b
end
function H.texts(pl, pattern)
	local pg = pl:FindFirstChildOfClass("PlayerGui")
	local out = {}
	for _, d in pg:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and visible(d) and (not pattern or string.find(d.Text, pattern)) then table.insert(out, d.Text) end
	end
	return out
end

---------------------------------------------------------------- 主循环
local function scanChildren()
	for inst, snap in pairs(childWatch) do
		local ok, kids = pcall(function() return inst:GetChildren() end)
		if not ok then
			childWatch[inst] = nil
		else
			local now = {}
			for _, k in kids do
				now[k] = true
				if not snap[k] then
					local s = evStore[inst]
					if s and s.ChildAdded then s.ChildAdded:Fire(k) end
				end
			end
			for k in pairs(snap) do
				if not now[k] then
					local s = evStore[inst]
					if s and s.ChildRemoved then s.ChildRemoved:Fire(k) end
				end
			end
			childWatch[inst] = now
		end
	end
end

function H.step(dt)
	dt = dt or 1 / 60
	H.now += dt
	H.frame += 1
	local rs = H.RunService
	for _, pl in PlayersSvc:GetChildren() do
		if pl:IsA("Player") then
			local sig = evStore[rs] and evStore[rs]["RenderStepped@" .. pl.Name]
			if sig then sig:Fire(dt) end
		end
	end
	local guard = 0
	while heap[1] and heap[1].at <= H.now + 1e-9 do
		local e = hpop()
		resume(e.co, table.unpack(e.args, 1, e.args.n))
		guard += 1
		if guard > 200000 then error("任务风暴：一帧里恢复了二十万个线程") end
	end
	local hb = evStore[rs] and evStore[rs].Heartbeat
	if hb then hb:Fire(dt) end
	local q = netQ
	netQ = {}
	for _, m in ipairs(q) do
		if not deliver(m) then
			if H.now - m.t < 10 then
				table.insert(netQ, m)
			else
				netWarn("远程事件没人听，丢掉了：" .. m.remote:GetFullName())
			end
		end
	end
	scanChildren()
	-- 想要的话模拟默认镜头：跟在角色身后（Roblox 自带的镜头脚本测试台里没有）
	if H.followCam and H.lastLocal and H.workspace.CurrentCamera.CameraType == Enum.CameraType.Custom then
		local ch = H.lastLocal.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p = hrp.CFrame.Position
			H.workspace.CurrentCamera.CFrame = CF.lookAt(p + V3.new(0, 14, -26), p)
		end
	end
	for _, pl in PlayersSvc:GetChildren() do
		local ch = pl:IsA("Player") and pl.Character
		if ch and ch.Parent and ch.PrimaryPart then
			local root = ch.PrimaryPart.CFrame
			for _, t in ch:GetChildren() do
				if t:IsA("Tool") then
					local hd = t:FindFirstChild("Handle")
					if hd then hd.CFrame = root * CF.new(1.5, 0, -1) end
				end
			end
			for _, a in ch:GetDescendants() do
				if a:IsA("Attachment") and a.Parent and a.Parent:IsA("BasePart") then
					a.WorldPosition = worldCF(a.Parent) * a.Position
				end
			end
		end
	end
end
function H.run(sec, dt)
	dt = dt or 1 / 30
	local n = math.max(1, math.floor(sec / dt + 0.5))
	for _ = 1, n do H.step(dt) end
end
function H.runUntil(pred, maxSec, dt)
	dt = dt or 1 / 30
	local t0 = H.now
	while H.now - t0 < maxSec do
		H.step(dt)
		if pred() then return true end
	end
	return false
end
function H.shutdown()
	for _, f in H.closeFns do
		local co = newThread(f)
		resume(co)
	end
	H.run(2)
end

---------------------------------------------------------------- 开服
function H.boot(placePath, opts)
	opts = opts or {}
	H.dsMode = opts.ds or H.dsMode
	local game = roblox.deserializePlace(fs.readFile(placePath))
	H.game = game
	local CS = {
		AddTag = function(_, inst, tag) inst:AddTag(tag) end,
		RemoveTag = function(_, inst, tag) inst:RemoveTag(tag) end,
		HasTag = function(_, inst, tag) return inst:HasTag(tag) end,
		GetTags = function(_, inst) return inst:GetTags() end,
		GetTagged = function(_, tag)
			local out = {}
			for _, d in game:GetDescendants() do
				if d:HasTag(tag) then table.insert(out, d) end
			end
			return out
		end,
		GetInstanceAddedSignal = function(_, tag) return newSignal("Added:" .. tag) end,
		GetInstanceRemovedSignal = function(_, tag) return newSignal("Removed:" .. tag) end,
	}
	H.CS = CS
	genv.game = setmetatable({}, {
		__index = function(_, k)
			if k == "GetService" or k == "FindService" then
				return function(_, n)
					if n == "CollectionService" then return CS end
					return game:GetService(n)
				end
			end
			local v = game[k]
			if type(v) == "function" then return function(_, ...) return v(game, ...) end end
			return v
		end,
		__newindex = function(_, k, v) game[k] = v end,
		__tostring = function() return "Game" end,
	})
	local ws = game:GetService("Workspace")
	H.workspace = ws
	genv.workspace = ws
	if not ws:FindFirstChildOfClass("Terrain") then
		local t = Inst.new("Terrain")
		t.Parent = ws
	end
	pcall(function() ws.Terrain = ws:FindFirstChildOfClass("Terrain") end)
	if opts.before then opts.before(game) end   -- 开服前往场景里加东西（比如模拟 Studio 里导入的模型）
	local cam = ws.CurrentCamera
	if not cam then
		cam = Inst.new("Camera")
		cam.Parent = ws
		ws.CurrentCamera = cam
	end
	cam.ViewportSize = V2.new(1280, 720)
	cam.CFrame = CF.new(0, 50, 0)
	cam.CameraType = Enum.CameraType.Custom   -- Roblox 里默认就是 Custom
	game.PlaceId = 0
	game.GameId = 0
	game.JobId = "studio-job-1"
	game.PrivateServerId = ""
	game.PrivateServerOwnerId = 0
	game.CreatorId = 0
	PlayersSvc = game:GetService("Players")
	H.Players = PlayersSvc
	H.RunService = game:GetService("RunService")
	H.UIS = game:GetService("UserInputService")
	H.UIS.TouchEnabled = false
	H.UIS.KeyboardEnabled = true
	H.UIS.MouseEnabled = true
	H.UIS.GamepadEnabled = false
	H.UIS.MouseBehavior = Enum.MouseBehavior.Default
	for _, s in { "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "Lighting", "Debris", "TweenService", "CollectionService", "DataStoreService", "MemoryStoreService", "MessagingService", "TeleportService", "ProximityPromptService", "SoundService", "StarterGui", "Teams", "Chat", "TextChatService", "GuiService", "ContextActionService" } do
		pcall(function() game:GetService(s) end)
	end
	local ok = pcall(function() return game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts") end)
	-- 跑服务器脚本（ServerScriptService、Workspace 里的 Script）
	for _, root in { game:GetService("ServerScriptService"), ws } do
		for _, s in root:GetDescendants() do
			if s.ClassName == "Script" then
				local okL, fn = pcall(loadScript, s)
				if okL then task.spawn(fn) else report("加载服务器脚本", fn) end
			end
		end
	end
	return game
end

function H.summary()
	print(string.format("—— 模拟 %.1f 秒（%d 帧）：错误 %d 个，警告 %d 条，远程事件 上行 %d / 下行 %d ——", H.now, H.frame, #H.errors, #H.warns, H.netStats.s, H.netStats.c))
end

return H

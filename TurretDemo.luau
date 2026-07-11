-- Made By: <trus.dev> | Roblox: <localdih>
-- Demo Turret Build

--SERVICES----------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

--CONSTANTS AND CONFIG---------------------------------------------------------
local TARGET_TAG = "TurretTarget"
local TRACER_LIFETIME = 0.07
local DRONE_HEALTH = 45
local DRONE_RESPAWN_TIME = 3

local DEFAULT_CONFIG = {
	Range = 120,
	FireRate = 4,
	ProjectileSpeed = 300,
	Damage = 12,
	TurnSpeed = 6,
	MinPitch = -15,
	MaxPitch = 60,
	MagazineSize = 24,
	ReloadTime = 2.5,
	AimTolerance = 3,
	SpreadDegrees = 1.25,
	RetargetInterval = 0.35,
}

local STATE = {
	Idle = "Idle",
	Acquiring = "Acquiring",
	Tracking = "Tracking",
	Firing = "Firing",
	Reloading = "Reloading",
}

--CLASSES-----------------------------------------------------------------
local Turret = {}
Turret.__index = Turret

local activeTurrets: { [Model]: any } = {}
local activeDrones: { [BasePart]: any } = {}
local turretCount = 0
local heartbeat: RBXScriptConnection? = nil
local tracerFolder: Folder? = nil


--HELPERS-----------------------------------------------------------------------

local function mergeConfig(overrides: { [string]: any }?): { [string]: any }
	local config = {}
	for key, value in pairs(DEFAULT_CONFIG) do
		config[key] = value
	end
	if overrides then
		for key, value in pairs(overrides) do
			config[key] = value
		end
	end
	return config
end

--Creates a part with the specified turret properties and applies a property table
local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

-- Equation using yaw that finds the shortest angle instead of going the long way around 
local function shortestAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

--keeps tracers and the workspace organized
local function getTracerFolder(): Folder
	if not tracerFolder or not tracerFolder.Parent then
		tracerFolder = Instance.new("Folder")
		tracerFolder.Name = "TurretTracers"
		tracerFolder.Parent = Workspace
	end
	return tracerFolder :: Folder
end

--Finds every humanoidrootpart in the game and every part tagged with TurretTarget only if they have positive
--help attributes
local function collectCandidateRoots(): { BasePart }
	local roots = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and rootPart then
			table.insert(roots, rootPart)
		end
	end

	for _, tagged in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if tagged:IsA("BasePart") and tagged.Parent and (tagged:GetAttribute("Health") or 0) > 0 then
			table.insert(roots, tagged)
		end
	end

	return roots
end

--updates the drowns position and velocity to produce a hover effect
local function updateDrone(drone: BasePart, data)
	local along = (drone.Position - data.Origin):Dot(data.Direction)
	if along >= data.Span and data.Sign > 0 then
		data.Sign = -1
		data.Mover.VectorVelocity = data.Direction * data.Speed * data.Sign
	elseif along <= -data.Span and data.Sign < 0 then
		data.Sign = 1
		data.Mover.VectorVelocity = data.Direction * data.Speed * data.Sign
	end
end

--Destroys the drown part, creates an explosion, and respawns the drone 
local function destroyDrone(drone: BasePart)
	local data = activeDrones[drone]
	activeDrones[drone] = nil

	local burst = Instance.new("Explosion")
	burst.Position = drone.Position
	burst.BlastPressure = 0
	burst.BlastRadius = 0
	burst.Parent = Workspace
	drone:Destroy()

	if data then
		task.delay(DRONE_RESPAWN_TIME, function()
			Turret.spawnDrone(data.Origin, data.Direction, data.Span, data.Speed)
		end)
	end
end

--keeps everything updated and cleans up drones from the regisrty after deletion
local function step(dt: number)
	for _, turret in pairs(activeTurrets) do
		turret:Update(dt)
	end
	for drone, data in pairs(activeDrones) do
		if drone.Parent then
			updateDrone(drone, data)
		else
			activeDrones[drone] = nil
		end
	end
end

--Ensures that the heartbeat connection starts the first time anything is registered 
local function ensureLoop()
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(step)
	end
end

--stops the heartbeat connection if there is nothing registered anymore
local function stopLoopIfIdle()
	if heartbeat and turretCount == 0 and next(activeDrones) == nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end


--MODEL CONSTRUCTION-------------------------------
--builds the turret part by part
function Turret.build(position: Vector3, name: string?): Model
	local model = Instance.new("Model")
	model.Name = name or "Turret"

	local pedestal = makePart({
		Name = "Pedestal",
		Size = Vector3.new(4, 3, 4),
		Color = Color3.fromRGB(58, 60, 68),
		Material = Enum.Material.DiamondPlate,
		CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0)),
		CanCollide = true,
	})
	pedestal.Parent = model

	local head = makePart({
		Name = "Head",
		Size = Vector3.new(2.6, 1.4, 2.6),
		Color = Color3.fromRGB(92, 98, 112),
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(position + Vector3.new(0, 3.7, 0)),
	})
	head.Parent = model

	local barrel = makePart({
		Name = "Barrel",
		Size = Vector3.new(0.5, 0.5, 3.6),
		Color = Color3.fromRGB(40, 42, 48),
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(position + Vector3.new(0, 4.2, -2.1)),
	})
	barrel.Parent = model

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -barrel.Size.Z / 2)
	muzzle.Parent = barrel

	model.PrimaryPart = pedestal
	model.Parent = Workspace
	return model
end

--Creates the drone part, assignes a health attribute, applies the TurretTarget tag, and registers it in active
--drones
function Turret.spawnDrone(position: Vector3, direction: Vector3, span: number, speed: number): BasePart
	local drone = Instance.new("Part")
	drone.Name = "TargetDrone"
	drone.Shape = Enum.PartType.Ball
	drone.Size = Vector3.new(2.4, 2.4, 2.4)
	drone.Material = Enum.Material.Metal
	drone.Color = Color3.fromRGB(196, 70, 70)
	drone.CFrame = CFrame.new(position)
	drone.CanCollide = false
	drone:SetAttribute("Health", DRONE_HEALTH)

	local attachment = Instance.new("Attachment")
	attachment.Parent = drone

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = math.huge
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VectorVelocity = direction.Unit * speed
	mover.Parent = drone

	CollectionService:AddTag(drone, TARGET_TAG)
	drone.Parent = Workspace

	activeDrones[drone] = {
		Origin = position,
		Direction = direction.Unit,
		Span = span,
		Speed = speed,
		Sign = 1,
		Mover = mover,
	}
	ensureLoop()
	return drone
end


--CONSTRUCTOR--------------------------------------------------------
--Puts the turret in the correct state and actually creates the instance, it also builds the raycast
--with the exclude filter and registers it in activeTurrets
function Turret.new(model: Model, config: { [string]: any }?)
	local self = setmetatable({}, Turret)

	self.Model = model
	self.Config = mergeConfig(config)
	self.Head = assert(model:FindFirstChild("Head"), "Turret model needs a Head part") :: Part
	self.Barrel = assert(model:FindFirstChild("Barrel"), "Turret model needs a Barrel part") :: Part
	self.Muzzle = assert(self.Barrel:FindFirstChild("Muzzle"), "Barrel needs a Muzzle attachment") :: Attachment
	self.BarrelLength = self.Barrel.Size.Z
	self.BarrelLift = 0.5

	local _, initialYaw = self.Head.CFrame:ToOrientation()
	self.Yaw = initialYaw
	self.Pitch = 0

	self.State = STATE.Idle
	self.TargetRoot = nil
	self.Ammo = self.Config.MagazineSize
	self.Cooldown = 0
	self.ReloadClock = 0
	self.RetargetClock = 0
	self.Random = Random.new()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, getTracerFolder() }
	self.RayParams = params

	activeTurrets[model] = self
	turretCount += 1
	ensureLoop()
	return self
end


--STATE MACHINE-------------------------------------------------
--Handles when the turret should fire, handles the cooldowns ticks(reloading, cooldown, retargeting), it handles
--the turrets state and makes the turret look alive
function Turret:Update(dt: number)
	self.Cooldown = math.max(0, self.Cooldown - dt)

	if self.State == STATE.Reloading then
		self.ReloadClock -= dt
		if self.ReloadClock <= 0 then
			self.Ammo = self.Config.MagazineSize
			self.State = STATE.Idle
		end
		self:IdleSweep(dt)
		return
	end

	self.RetargetClock -= dt
	if self.RetargetClock <= 0 or not self:IsTargetValid() then
		self:AcquireTarget()
		self.RetargetClock = self.Config.RetargetInterval
	end

	if not self.TargetRoot then
		self.State = STATE.Idle
		self:IdleSweep(dt)
		return
	end

	local aimed = self:Aim(dt)
	if aimed and self.Cooldown <= 0 then
		self.State = STATE.Firing
		self:Fire()
	else
		self.State = aimed and STATE.Tracking or STATE.Acquiring
	end
end

--Does a "idle sweep" that makes the turret look alive and scanning while idle
function Turret:IdleSweep(dt: number)
	self.Yaw = shortestAngle(self.Yaw + dt * 0.45)
	self.Pitch += (0 - self.Pitch) * math.min(1, dt * 2)
	self:ApplyOrientation()
end


--TARGETING---------------------------------------------------------
--Picks the best and nearest target
function Turret:AcquireTarget()
	local origin = self.Head.Position
	local bestRoot: BasePart? = nil
	local bestDistance = self.Config.Range

	for _, root in ipairs(collectCandidateRoots()) do
		local distance = (root.Position - origin).Magnitude
		if distance <= bestDistance and self:HasLineOfSight(root) then
			bestRoot = root
			bestDistance = distance
		end
	end

	self.TargetRoot = bestRoot
end

--function that constantly checks whether the target is still valid so it can drop it immediately
function Turret:IsTargetValid(): boolean
	local root = self.TargetRoot
	if not root or not root.Parent then
		return false
	end
	if (root.Position - self.Head.Position).Magnitude > self.Config.Range * 1.15 then
		return false
	end
	local humanoid = root.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health > 0
	end
	return (root:GetAttribute("Health") or 0) > 0
end

--checks if the turret can see the target so it doesnt shoot at targets behind walls
function Turret:HasLineOfSight(root: BasePart): boolean
	local origin = self.Head.Position
	local result = Workspace:Raycast(origin, root.Position - origin, self.RayParams)
	if not result then
		return true
	end
	if result.Instance == root then
		return true
	end
	local container = root.Parent
	return container ~= nil and container:IsA("Model") and result.Instance:IsDescendantOf(container)
end

--AIMING-----------------------------------------------------------------
--predicts where the target is going so the turret gets a more accurate shot
function Turret:ComputeLeadPoint(root: BasePart): Vector3
	local origin = self.Head.Position
	local targetPosition = root.Position
	local velocity = root.AssemblyLinearVelocity
	local speed = self.Config.ProjectileSpeed

	local travelTime = (targetPosition - origin).Magnitude / speed
	local predicted = targetPosition + velocity * travelTime

	travelTime = (predicted - origin).Magnitude / speed
	predicted = targetPosition + velocity * travelTime

	return predicted
end

--aims the turret at the target and keeps it smooth while tracking
function Turret:Aim(dt: number): boolean
	local aimPoint = self:ComputeLeadPoint(self.TargetRoot)
	local origin = self.Head.Position
	local offset = aimPoint - origin
	local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude

	local desiredYaw = math.atan2(-offset.X, -offset.Z)
	local desiredPitch = math.clamp(
		math.atan2(offset.Y, flatDistance),
		math.rad(self.Config.MinPitch),
		math.rad(self.Config.MaxPitch)
	)

	local alpha = 1 - math.exp(-self.Config.TurnSpeed * dt)
	self.Yaw = shortestAngle(self.Yaw + shortestAngle(desiredYaw - self.Yaw) * alpha)
	self.Pitch += (desiredPitch - self.Pitch) * alpha
	self:ApplyOrientation()

	local look = self.Barrel.CFrame.LookVector
	local errorAngle = math.acos(math.clamp(look:Dot(offset.Unit), -1, 1))
	return math.deg(errorAngle) <= self.Config.AimTolerance
end

--turns the angles into part CFrames and applies them
function Turret:ApplyOrientation()
	local headCFrame = CFrame.new(self.Head.Position) * CFrame.Angles(0, self.Yaw, 0)
	self.Head.CFrame = headCFrame

	local pivot = headCFrame * CFrame.new(0, self.BarrelLift, 0)
	self.Barrel.CFrame = pivot
		* CFrame.Angles(self.Pitch, 0, 0)
		* CFrame.new(0, 0, -(self.BarrelLength / 2 + 0.3))
end

--FIRING------------------------------------------------------------
--handles the actual firing and tracks the ammo and state of reloading
function Turret:Fire()
	local spreadRadians = math.rad(self.Config.SpreadDegrees)
	local spread = CFrame.Angles(
		self.Random:NextNumber(-spreadRadians, spreadRadians),
		self.Random:NextNumber(-spreadRadians, spreadRadians),
		0
	)
	local origin = self.Muzzle.WorldPosition
	local direction = (self.Barrel.CFrame * spread).LookVector * self.Config.Range

	local result = Workspace:Raycast(origin, direction, self.RayParams)
	local hitPosition = if result then result.Position else origin + direction

	self:DrawTracer(origin, hitPosition)
	if result then
		self:ApplyDamage(result.Instance)
	end

	self.Ammo -= 1
	self.Cooldown = 1 / self.Config.FireRate
	if self.Ammo <= 0 then
		self.State = STATE.Reloading
		self.ReloadClock = self.Config.ReloadTime
	end
end

--draws the tracer with a thin neon part
function Turret:DrawTracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 196, 90)
	tracer.Size = Vector3.new(0.12, 0.12, length)
	tracer.CFrame = CFrame.lookAt((from + to) / 2, to)
	tracer.Parent = getTracerFolder()
	Debris:AddItem(tracer, TRACER_LIFETIME)
end

--finds what was hit and applies the damage
function Turret:ApplyDamage(hitPart: BasePart)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(self.Config.Damage)
		return
	end

	if CollectionService:HasTag(hitPart, TARGET_TAG) then
		local health = (hitPart:GetAttribute("Health") or 0) - self.Config.Damage
		hitPart:SetAttribute("Health", health)
		if health <= 0 then
			destroyDrone(hitPart)
		end
	end
end


--TEARDOWN-------------------------------------------------------------
--handles the destruction of the turret model and removes it from the activeTurrets table
function Turret:Destroy(destroyModel: boolean?)
	if activeTurrets[self.Model] then
		activeTurrets[self.Model] = nil
		turretCount -= 1
	end
	if destroyModel then
		self.Model:Destroy()
	end
	stopLoopIfIdle()
end

return Turret

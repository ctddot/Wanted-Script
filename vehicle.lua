-- Vehicle Kavo Live Tuner
-- Use only in your own Roblox experience/test environment.
-- Does not mutate read-only vehicle definition modules.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Workspace  = game:GetService("Workspace")

local player  = Players.LocalPlayer
local Library -- Kavo handle

local enabled   = false
local autoApply = true
local currentSeat
local currentVehicle
local chassis
local heartbeat

local cfg = {
	SpeedCap   = 230,
	Accel      = 8,
	Brake      = 12,
	SteerPower = 1.5,
	Grip       = 1.25,
	Downforce  = 1.7,
	SpringDamp = 1.15,
	SpinDamp   = 0.9,
}

local defaults = {}

-- ─── Vehicle helpers ──────────────────────────────────────────────────────────

local function getSeat()
	local char     = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local seat     = humanoid and humanoid.SeatPart
	return seat and seat:IsA("VehicleSeat") and seat or nil
end

local function getVehicleFromSeat(seat)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	local node = seat
	while node and node ~= Workspace do
		if vehicles and node.Parent == vehicles then return node end
		node = node.Parent
	end
	return seat and seat:FindFirstAncestorOfClass("Model") or nil
end

local function getChassis(vehicle)
	local part = vehicle and vehicle:FindFirstChild("Chassis")
	if part and part:IsA("BasePart") then return part end
	local best
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") and (not best or item.AssemblyMass > best.AssemblyMass) then
			best = item
		end
	end
	return best
end

local function saveDefault(item, key, value)
	defaults[item] = defaults[item] or {}
	if defaults[item][key] == nil then defaults[item][key] = value end
end

local function setProp(item, key, value)
	pcall(function()
		saveDefault(item, key, item[key])
		item[key] = value
	end)
end

local function refreshVehicle()
	currentSeat    = getSeat()
	currentVehicle = currentSeat and getVehicleFromSeat(currentSeat) or nil
	chassis        = currentVehicle and getChassis(currentVehicle) or nil
	return currentVehicle ~= nil and chassis ~= nil
end

local function flatUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return flat.Magnitude > 0.001 and flat.Unit or Vector3.zero
end

local function applyLiveTune()
	if not currentVehicle and not refreshVehicle() then return end
	for _, item in ipairs(currentVehicle:GetDescendants()) do
		if item:IsA("HingeConstraint") and item.Parent and tostring(item.Parent.Name):find("Steer") then
			setProp(item, "ServoMaxTorque",       1000   * cfg.SteerPower * cfg.Grip)
			setProp(item, "MotorMaxAcceleration", 500000 * cfg.SteerPower)
			setProp(item, "AngularSpeed",         math.clamp(4 * cfg.SteerPower, 1, 30))
		elseif item:IsA("SpringConstraint") then
			setProp(item, "Damping", 1000 * cfg.SpringDamp)
		elseif item:IsA("VectorForce") and item.Name == "Down" then
			item.Force = Vector3.new(0, -404 * cfg.Downforce, 0)
		end
	end
end

local function resetLiveTune()
	for item, data in pairs(defaults) do
		if item and item.Parent then
			for key, value in pairs(data) do
				pcall(function() item[key] = value end)
			end
		end
	end
	table.clear(defaults)
end

local function startController()
	if enabled then return end
	if not refreshVehicle() then
		warn("[VehicleTuner] Sit in a VehicleSeat first.")
		return
	end
	enabled = true
	applyLiveTune()
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		if not enabled
			or not currentSeat or not currentSeat:IsDescendantOf(Workspace)
			or not chassis     or not chassis:IsDescendantOf(Workspace)
		then
			enabled = false
			if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
			return
		end
		if autoApply then applyLiveTune() end

		local cf           = chassis.CFrame
		local forward      = flatUnit(cf.LookVector)
		local right        = flatUnit(cf.RightVector)
		local velocity     = chassis.AssemblyLinearVelocity
		local flatVel      = Vector3.new(velocity.X, 0, velocity.Z)
		local forwardSpeed = flatVel:Dot(forward)
		local sideSpeed    = flatVel:Dot(right)
		local throttle     = currentSeat.ThrottleFloat

		local wantedSpeed = forwardSpeed * 0.992
		if throttle > 0.05 then
			wantedSpeed = cfg.SpeedCap
		elseif throttle < -0.05 then
			wantedSpeed = math.max(0, forwardSpeed - cfg.Brake * dt * 20)
			if forwardSpeed < 5 then
				wantedSpeed = -math.min(cfg.SpeedCap * 0.28, 90)
			end
		end

		local alpha      = math.clamp(dt * cfg.Accel, 0, 1)
		local newForward = forwardSpeed + (wantedSpeed - forwardSpeed) * alpha
		local newSide    = sideSpeed / cfg.Grip
		local newY       = math.clamp(velocity.Y, -55, 22)

		chassis.AssemblyLinearVelocity  = (forward * newForward) + (right * newSide) + Vector3.new(0, newY, 0)
		chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity * cfg.SpinDamp
	end)
end

local function stopController()
	enabled = false
	if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
end

local function hardStop()
	if chassis or refreshVehicle() then
		chassis.AssemblyLinearVelocity  = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end
end

local function eject()
	stopController()
	resetLiveTune()
	if Library then Library:Destroy() end
	script:Destroy()
end

-- ─── UI (Kavo — zero filesystem usage) ───────────────────────────────────────

Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()

local Window = Library.CreateLib("Vehicle Live Tuner", "DarkTheme")

-- Drive tab
local DriveTab     = Window:NewTab("Drive")
local CtrlSection  = DriveTab:NewSection("Controller")

CtrlSection:NewToggle("Enabled", "Start/stop the tuner controller", function(state)
	if state then startController() else stopController() end
end)

CtrlSection:NewToggle("Auto Reapply Tune", "Reapply tune every frame", function(state)
	autoApply = state
end)

local SpeedSection = DriveTab:NewSection("Speed")

SpeedSection:NewSlider("Speed Cap", "Max speed in studs/s", 1000, 20, function(value)
	cfg.SpeedCap = value
end)

SpeedSection:NewSlider("Acceleration", "How quickly speed builds up (1-30)", 30, 1, function(value)
	cfg.Accel = value
end)

SpeedSection:NewSlider("Brake Strength", "Braking force multiplier (1-60)", 60, 1, function(value)
	cfg.Brake = value
end)

-- Handling tab
local HandlingTab  = Window:NewTab("Handling")
local GripSection  = HandlingTab:NewSection("Grip & Stability")

GripSection:NewSlider("Steer Power x10", "Steering torque (5-50 = 0.5x-5.0x)", 50, 5, function(value)
	cfg.SteerPower = value / 10
	applyLiveTune()
end)

GripSection:NewSlider("Grip x10", "Lateral grip (10-50 = 1.0x-5.0x)", 50, 10, function(value)
	cfg.Grip = value / 10
	applyLiveTune()
end)

GripSection:NewSlider("Downforce x10", "Downforce multiplier (10-80 = 1.0x-8.0x)", 80, 10, function(value)
	cfg.Downforce = value / 10
	applyLiveTune()
end)

GripSection:NewSlider("Spring Damp x10", "Suspension damping (5-40 = 0.5x-4.0x)", 40, 5, function(value)
	cfg.SpringDamp = value / 10
	applyLiveTune()
end)

GripSection:NewSlider("Spin Damp x100", "Angular velocity decay (65-99 = 0.65x-0.99x)", 99, 65, function(value)
	cfg.SpinDamp = value / 100
end)

-- Actions tab
local ActionsTab    = Window:NewTab("Actions")
local ActSection    = ActionsTab:NewSection("Vehicle Controls")

ActSection:NewButton("Refresh Vehicle", "Re-detect seat and chassis", function()
	refreshVehicle()
end)

ActSection:NewButton("Apply Live Tune", "Push current cfg values now", function()
	applyLiveTune()
end)

ActSection:NewButton("Reset Live Tune", "Restore original vehicle values", function()
	resetLiveTune()
end)

ActSection:NewButton("Hard Stop", "Zero out all vehicle velocity", function()
	hardStop()
end)

ActSection:NewButton("Eject (F12)", "Destroy UI and clean up", function()
	eject()
end)

-- Keyboard shortcuts
UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.B then
		if enabled then stopController() else startController() end
	elseif input.KeyCode == Enum.KeyCode.F12 then
		eject()
	end
end)

print("[VehicleTuner] Kavo loaded. B = toggle controller, F12 = eject.")

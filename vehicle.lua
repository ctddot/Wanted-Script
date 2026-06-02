-- Vehicle Orion Live Tuner
-- Use only in your own Roblox experience/test environment.
-- Does not mutate read-only vehicle definition modules.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local OrionLib
local enabled = false
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

local function getSeat()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
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
			setProp(item, "ServoMaxTorque",       1000 * cfg.SteerPower * cfg.Grip)
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
			or not currentSeat
			or not currentSeat:IsDescendantOf(Workspace)
			or not chassis
			or not chassis:IsDescendantOf(Workspace)
		then
			enabled = false
			if heartbeat then heartbeat:Disconnect() heartbeat = nil end
			return
		end
		if autoApply then applyLiveTune() end
		local cf           = chassis.CFrame
		local forward      = flatUnit(cf.LookVector)
		local right        = flatUnit(cf.RightVector)
		local velocity     = chassis.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local forwardSpeed = flatVelocity:Dot(forward)
		local sideSpeed    = flatVelocity:Dot(right)
		local throttle     = currentSeat.ThrottleFloat
		local wantedSpeed  = forwardSpeed * 0.992
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
	if heartbeat then heartbeat:Disconnect() heartbeat = nil end
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
	if OrionLib then OrionLib:Destroy() end
	script:Destroy()
end

-- ─── UI ───────────────────────────────────────────────────────────────────────

OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/shlexware/Orion/main/source"))()

local Window = OrionLib:MakeWindow({
	Name         = "Vehicle Live Tuner",
	HidePremium  = true,
	SaveConfig   = false,       -- no filesystem calls at all
	IntroEnabled = false,
})

-- Drive tab
local DriveTab = Window:MakeTab({ Name = "Drive", Icon = "rbxassetid://0", PremiumOnly = false })

DriveTab:AddSection({ Name = "Controller" })

DriveTab:AddToggle({
	Name     = "Enabled",
	Default  = false,
	Callback = function(value)
		if value then startController() else stopController() end
	end,
})

DriveTab:AddToggle({
	Name     = "Auto Reapply Live Tune",
	Default  = true,
	Callback = function(value) autoApply = value end,
})

DriveTab:AddSection({ Name = "Speed" })

DriveTab:AddSlider({
	Name    = "Speed Cap",
	Min     = 20,
	Max     = 1000,
	Default = cfg.SpeedCap,
	Color   = Color3.fromRGB(255, 255, 255),
	Increment = 5,
	Callback = function(value) cfg.SpeedCap = value end,
})

DriveTab:AddSlider({
	Name      = "Acceleration Response",
	Min       = 1,
	Max       = 30,
	Default   = cfg.Accel,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.Accel = value end,
})

DriveTab:AddSlider({
	Name      = "Brake Strength",
	Min       = 1,
	Max       = 60,
	Default   = cfg.Brake,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.Brake = value end,
})

-- Handling tab
local HandlingTab = Window:MakeTab({ Name = "Handling", Icon = "rbxassetid://0", PremiumOnly = false })

HandlingTab:AddSection({ Name = "Grip And Stability" })

HandlingTab:AddSlider({
	Name      = "Steer Power",
	Min       = 5,
	Max       = 50,
	Default   = cfg.SteerPower * 10,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.SteerPower = value / 10 applyLiveTune() end,
})

HandlingTab:AddSlider({
	Name      = "Grip",
	Min       = 10,
	Max       = 50,
	Default   = cfg.Grip * 10,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.Grip = value / 10 applyLiveTune() end,
})

HandlingTab:AddSlider({
	Name      = "Downforce",
	Min       = 10,
	Max       = 80,
	Default   = cfg.Downforce * 10,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.Downforce = value / 10 applyLiveTune() end,
})

HandlingTab:AddSlider({
	Name      = "Spring Damping",
	Min       = 5,
	Max       = 40,
	Default   = cfg.SpringDamp * 10,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.SpringDamp = value / 10 applyLiveTune() end,
})

HandlingTab:AddSlider({
	Name      = "Spin Damping",
	Min       = 65,
	Max       = 99,
	Default   = cfg.SpinDamp * 100,
	Color     = Color3.fromRGB(255, 255, 255),
	Increment = 1,
	Callback  = function(value) cfg.SpinDamp = value / 100 end,
})

-- Actions tab
local ActionsTab = Window:MakeTab({ Name = "Actions", Icon = "rbxassetid://0", PremiumOnly = false })

ActionsTab:AddSection({ Name = "Vehicle" })

ActionsTab:AddButton({ Name = "Refresh Current Vehicle", Callback = refreshVehicle })
ActionsTab:AddButton({ Name = "Apply Live Tune",         Callback = applyLiveTune })
ActionsTab:AddButton({ Name = "Reset Live Tune",         Callback = resetLiveTune })
ActionsTab:AddButton({ Name = "Hard Stop Vehicle",       Callback = hardStop })

ActionsTab:AddSection({ Name = "Keybinds  (toggle = B,  eject = F12)" })

ActionsTab:AddButton({
	Name = "Toggle Controller  [B]",
	Callback = function()
		if enabled then stopController() else startController() end
	end,
})

ActionsTab:AddButton({
	Name     = "Eject  [F12]",
	Callback = eject,
})

-- Keyboard shortcuts (B and F12) – no keybind element needed, no filesystem risk
UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.B then
		if enabled then stopController() else startController() end
	elseif input.KeyCode == Enum.KeyCode.F12 then
		eject()
	end
end)

OrionLib:Init()
print("[VehicleTuner] OrionLib loaded. B toggles controller, F12 ejects.")

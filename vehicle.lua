-- Vehicle Rayfield Live Tuner
-- Use only in your own Roblox experience/test environment.
-- Does not mutate read-only vehicle definition modules.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Rayfield
local enabled = false
local autoApply = true
local currentSeat
local currentVehicle
local chassis
local heartbeat

local cfg = {
	SpeedCap = 230,
	Accel = 8,
	Brake = 12,
	SteerPower = 1.5,
	Grip = 1.25,
	Downforce = 1.7,
	SpringDamp = 1.15,
	SpinDamp = 0.9,
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
		if vehicles and node.Parent == vehicles then
			return node
		end
		node = node.Parent
	end
	return seat and seat:FindFirstAncestorOfClass("Model") or nil
end

local function getChassis(vehicle)
	local part = vehicle and vehicle:FindFirstChild("Chassis")
	if part and part:IsA("BasePart") then
		return part
	end

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
	if defaults[item][key] == nil then
		defaults[item][key] = value
	end
end

local function setProp(item, key, value)
	pcall(function()
		saveDefault(item, key, item[key])
		item[key] = value
	end)
end

local function refreshVehicle()
	currentSeat = getSeat()
	currentVehicle = currentSeat and getVehicleFromSeat(currentSeat) or nil
	chassis = currentVehicle and getChassis(currentVehicle) or nil
	return currentVehicle ~= nil and chassis ~= nil
end

local function flatUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return flat.Magnitude > 0.001 and flat.Unit or Vector3.zero
end

local function applyLiveTune()
	if not currentVehicle and not refreshVehicle() then
		return
	end

	for _, item in ipairs(currentVehicle:GetDescendants()) do
		if item:IsA("HingeConstraint") and item.Parent and tostring(item.Parent.Name):find("Steer") then
			setProp(item, "ServoMaxTorque", 1000 * cfg.SteerPower * cfg.Grip)
			setProp(item, "MotorMaxAcceleration", 500000 * cfg.SteerPower)
			setProp(item, "AngularSpeed", math.clamp(4 * cfg.SteerPower, 1, 30))
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
				pcall(function()
					item[key] = value
				end)
			end
		end
	end
	table.clear(defaults)
end

local function startController()
	if enabled then
		return
	end

	if not refreshVehicle() then
		warn("[VehicleTuner] Sit in a VehicleSeat first.")
		return
	end

	enabled = true
	applyLiveTune()

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		if not enabled or not currentSeat or not currentSeat:IsDescendantOf(Workspace) or not chassis or not chassis:IsDescendantOf(Workspace) then
			enabled = false
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
			return
		end

		if autoApply then
			applyLiveTune()
		end

		local cf = chassis.CFrame
		local forward = flatUnit(cf.LookVector)
		local right = flatUnit(cf.RightVector)
		local velocity = chassis.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local forwardSpeed = flatVelocity:Dot(forward)
		local sideSpeed = flatVelocity:Dot(right)
		local throttle = currentSeat.ThrottleFloat

		local wantedSpeed = forwardSpeed * 0.992
		if throttle > 0.05 then
			wantedSpeed = cfg.SpeedCap
		elseif throttle < -0.05 then
			wantedSpeed = math.max(0, forwardSpeed - cfg.Brake * dt * 20)
			if forwardSpeed < 5 then
				wantedSpeed = -math.min(cfg.SpeedCap * 0.28, 90)
			end
		end

		local alpha = math.clamp(dt * cfg.Accel, 0, 1)
		local newForward = forwardSpeed + (wantedSpeed - forwardSpeed) * alpha
		local newSide = sideSpeed / cfg.Grip
		local newY = math.clamp(velocity.Y, -55, 22)

		chassis.AssemblyLinearVelocity = (forward * newForward) + (right * newSide) + Vector3.new(0, newY, 0)
		chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity * cfg.SpinDamp
	end)
end

local function stopController()
	enabled = false
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function hardStop()
	if chassis or refreshVehicle() then
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end
end

local function eject()
	stopController()
	resetLiveTune()
	if Rayfield then
		Rayfield:Destroy()
	end
	script:Destroy()
end

local function makeSlider(tab, name, range, increment, suffix, current, callback)
	tab:CreateSlider({
		Name = name,
		Range = range,
		Increment = increment,
		Suffix = suffix,
		CurrentValue = current,
		Callback = callback,
	})
end

local function createUI()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

	local Window = Rayfield:CreateWindow({
		Name = "Vehicle Live Tuner",
		Icon = 0,
		LoadingTitle = "Vehicle Live Tuner",
		LoadingSubtitle = "Live chassis controls",
		ShowText = "Vehicle",
		Theme = "Default",
		ToggleUIKeybind = "K",
		DisableRayfieldPrompts = true,
		DisableBuildWarnings = true,
		ConfigurationSaving = {
			Enabled = false,
			FolderName = nil,
			FileName = "VehicleLiveTuner",
		},
		Discord = {
			Enabled = false,
			Invite = "noinvitelink",
			RememberJoins = false,
		},
		KeySystem = false,
	})

	local driveTab = Window:CreateTab("Drive", "gauge")
	driveTab:CreateSection("Controller")
	driveTab:CreateToggle({
		Name = "Enabled",
		CurrentValue = false,
		Callback = function(value)
			if value then
				startController()
			else
				stopController()
			end
		end,
	})
	driveTab:CreateToggle({
		Name = "Auto Reapply Live Tune",
		CurrentValue = autoApply,
		Callback = function(value)
			autoApply = value
		end,
	})
	makeSlider(driveTab, "Speed Cap", {20, 1000}, 5, " studs/s", cfg.SpeedCap, function(value)
		cfg.SpeedCap = value
	end)
	makeSlider(driveTab, "Acceleration Response", {1, 30}, 1, "x", cfg.Accel, function(value)
		cfg.Accel = value
	end)
	makeSlider(driveTab, "Brake Strength", {1, 60}, 1, "x", cfg.Brake, function(value)
		cfg.Brake = value
	end)

	local handlingTab = Window:CreateTab("Handling", "settings")
	handlingTab:CreateSection("Grip And Stability")
	makeSlider(handlingTab, "Steer Power", {0.5, 5}, 0.1, "x", cfg.SteerPower, function(value)
		cfg.SteerPower = value
		applyLiveTune()
	end)
	makeSlider(handlingTab, "Grip", {1, 5}, 0.1, "x", cfg.Grip, function(value)
		cfg.Grip = value
		applyLiveTune()
	end)
	makeSlider(handlingTab, "Downforce", {1, 8}, 0.1, "x", cfg.Downforce, function(value)
		cfg.Downforce = value
		applyLiveTune()
	end)
	makeSlider(handlingTab, "Spring Damping", {0.5, 4}, 0.1, "x", cfg.SpringDamp, function(value)
		cfg.SpringDamp = value
		applyLiveTune()
	end)
	makeSlider(handlingTab, "Spin Damping", {0.65, 0.99}, 0.01, "x", cfg.SpinDamp, function(value)
		cfg.SpinDamp = value
	end)

	local actionsTab = Window:CreateTab("Actions", "wrench")
	actionsTab:CreateButton({ Name = "Refresh Current Vehicle", Callback = refreshVehicle })
	actionsTab:CreateButton({ Name = "Apply Live Tune", Callback = applyLiveTune })
	actionsTab:CreateButton({ Name = "Reset Live Tune", Callback = resetLiveTune })
	actionsTab:CreateButton({ Name = "Hard Stop Vehicle", Callback = hardStop })
	actionsTab:CreateKeybind({
		Name = "Toggle Controller",
		CurrentKeybind = "B",
		HoldToInteract = false,
		Callback = function()
			if enabled then
				stopController()
			else
				startController()
			end
		end,
	})
	actionsTab:CreateKeybind({
		Name = "Eject",
		CurrentKeybind = "F12",
		HoldToInteract = false,
		Callback = eject,
	})
end

createUI()
print("[VehicleTuner] Rayfield loaded. K toggles UI, B toggles controller, F12 ejects.")

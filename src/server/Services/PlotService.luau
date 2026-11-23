-- PlotService: แจกล็อตร้าน 6 ล็อตให้ผู้เล่นตอนเข้าเกม และคืนล็อตตอนออก
--
-- โครงสร้างที่ต้องมีใน Workspace (สร้างเองใน Studio หรือปล่อยให้ระบบสร้างล็อตชั่วคราวให้):
--   Workspace
--     Plots (Folder)
--       Plot1 (Model)  ... Plot6
--         Base        (Part)  พื้นร้าน = PrimaryPart
--         SpawnPoint  (Part)  จุดที่ผู้เล่นเกิด หน้าตรงของ part (-Z) คือทิศที่ผู้เล่นหันหน้า
--         Sign        (Part, ไม่บังคับ)
--           SignGui (SurfaceGui)
--             OwnerLabel (TextLabel)
--
-- ข้อมูลที่ระบบอื่นใช้ได้:
--   plot:GetAttribute("PlotId")        -> 1..6
--   plot:GetAttribute("OwnerUserId")   -> 0 = ว่าง
--   player:GetAttribute("PlotId")      -> ล็อตของผู้เล่น (client ก็อ่านได้)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ShopBuilder = require(script.Parent.Parent.Modules.ShopBuilder)
local Ground = require(script.Parent.Parent.Modules.Ground)

local PlotService = {}

local plotsFolder: Folder
local plotByPlayer: { [Player]: Model } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local plotAssignedEvent = Instance.new("BindableEvent")
local plotReleasedEvent = Instance.new("BindableEvent")
-- PlotService.PlotAssigned:Connect(function(player, plot) ... end)
PlotService.PlotAssigned = plotAssignedEvent.Event
-- PlotService.PlotReleased:Connect(function(player, plot) ... end)  -> ใช้ล้างของในร้าน
PlotService.PlotReleased = plotReleasedEvent.Event

---------------------------------------------------------------------
-- ร้านเริ่มต้นสร้างด้วยโค้ด (ShopBuilder) ถ้ายังไม่มี Workspace.Plots ที่ทำเองใน Studio
---------------------------------------------------------------------

local function buildPlaceholderPlots(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Plots"

	local count = GameConfig.Plots.Count
	local radius = GameConfig.Plots.PlaceholderRadius
	local size = GameConfig.Plots.PlaceholderSize

	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		local groundY = Ground.GetY(Vector3.new(x, 0, z))
		-- วางบนพื้นจริง และหันหน้าร้าน (-Z) เข้าหาโรงงานที่จุดกลางแมพ
		local origin = CFrame.lookAt(Vector3.new(x, groundY, z), Vector3.new(0, groundY, 0))
		ShopBuilder.Build(i, origin, size).Parent = folder
	end

	folder.Parent = workspace
	print("[PlotService] ไม่พบ Workspace.Plots -> สร้างร้านเริ่มต้น " .. count .. " ล็อตด้วย ShopBuilder")
	return folder
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function getPlots(): { Model }
	local plots = {}
	for _, child in plotsFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(plots, child)
		end
	end
	table.sort(plots, function(a, b)
		return (a:GetAttribute("PlotId") or 0) < (b:GetAttribute("PlotId") or 0)
	end)
	return plots
end

local function validatePlots()
	local plots = getPlots()
	if #plots < GameConfig.Plots.Count then
		warn(("[PlotService] มีล็อตแค่ %d แต่ตั้งไว้ %d ผู้เล่น"):format(#plots, GameConfig.Plots.Count))
	end
	for index, plot in plots do
		assert(plot:FindFirstChild("Base"), "[PlotService] " .. plot:GetFullName() .. " ไม่มี Part ชื่อ Base")
		assert(plot:FindFirstChild("SpawnPoint"), "[PlotService] " .. plot:GetFullName() .. " ไม่มี Part ชื่อ SpawnPoint")
		if plot:GetAttribute("PlotId") == nil then
			-- ล็อตที่สร้างเองใน Studio อาจลืมใส่ attribute -> เติมจากเลขท้ายชื่อหรือลำดับ
			plot:SetAttribute("PlotId", tonumber(plot.Name:match("%d+$")) or index)
		end
		plot:SetAttribute("OwnerUserId", 0)
	end
end

local function updateSign(plot: Model, owner: Player?)
	local sign = plot:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChild("OwnerLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = if owner then owner.DisplayName .. "'s Shop" else "Available"
	end
end

local function findFreePlot(): Model?
	for _, plot in getPlots() do
		if plot:GetAttribute("OwnerUserId") == 0 then
			return plot
		end
	end
	return nil
end

local function teleportToPlot(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	if not character.Parent then
		character.AncestryChanged:Wait()
	end
	task.wait() -- รอให้ engine วางตัวละครที่ spawn ปกติเสร็จก่อน แล้วค่อยย้าย

	local plot = plotByPlayer[player]
	local spawnPoint = plot and plot:FindFirstChild("SpawnPoint")
	if spawnPoint and spawnPoint:IsA("BasePart") and character.Parent then
		character:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))
	end
end

---------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local plot = findFreePlot()
	if not plot then
		player:Kick("เซิร์ฟเวอร์เต็ม ไม่มีล็อตร้านว่าง (Server full)")
		return
	end

	plot:SetAttribute("OwnerUserId", player.UserId)
	plotByPlayer[player] = plot
	player:SetAttribute("PlotId", plot:GetAttribute("PlotId"))
	updateSign(plot, player)

	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		teleportToPlot(player, character)
	end)
	if player.Character then
		task.spawn(teleportToPlot, player, player.Character)
	end

	plotAssignedEvent:Fire(player, plot)
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end

	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	plotByPlayer[player] = nil
	plotReleasedEvent:Fire(player, plot)
	plot:SetAttribute("OwnerUserId", 0)
	updateSign(plot, nil)
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

function PlotService:GetPlot(player: Player): Model?
	return plotByPlayer[player]
end

function PlotService:GetOwner(plot: Model): Player?
	local userId = plot:GetAttribute("OwnerUserId")
	if not userId or userId == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

function PlotService:GetAllPlots(): { Model }
	return getPlots()
end

---------------------------------------------------------------------
-- Init / Start
---------------------------------------------------------------------

function PlotService:Init()
	local existing = workspace:FindFirstChild("Plots")
	plotsFolder = if existing and existing:IsA("Folder") then existing else buildPlaceholderPlots()
	validatePlots()
	for _, plot in getPlots() do
		updateSign(plot, nil)
	end
end

function PlotService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlotService

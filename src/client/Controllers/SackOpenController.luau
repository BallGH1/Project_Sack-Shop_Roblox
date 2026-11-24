-- SackOpenController: แอนิเมชันเปิดกระสอบ เสื้อเด้งออกมาทีละตัว ตัวแรร์มีลุ้น + แฟลชสี
-- รับผลจาก Remotes.SackOpened (server สุ่มเสร็จแล้ว client แค่แสดงผล)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local SackTypes = require(Config:WaitForChild("SackTypes"))
local ShirtCard = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ShirtCard"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local RunService = game:GetService("RunService")

local SackOpenController = {}

local CARD_SIZE = Vector2.new(150, 200)
local PADDING = 12
local COLUMNS = 5

local gui: ScreenGui
local overlay: Frame
local title: TextLabel
local grid: Frame
local gridScale: UIScale
local summary: TextLabel
local closeButton: TextButton
local rays: Frame
local raysConnection: RBXScriptConnection? = nil

local queue = {}
local busy = false

local function createGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "SackOpenGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.25
	Theme.Gradient(overlay, Color3.fromRGB(60, 45, 30), Color3.fromRGB(10, 8, 6))

	-- แสงรัศมีหมุนช้า ๆ ด้านหลังการ์ด
	rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(1400, 1400)
	rays.BackgroundTransparency = 1
	rays.Parent = gui
	for i = 0, 11 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, 90, 1, 0)
		ray.Rotation = i * 15
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Theme.Colors.Accent
		ray.BackgroundTransparency = 0.9
		ray.Parent = rays
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	overlay.Parent = gui

	title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.12)
	title.Size = UDim2.new(0.8, 0, 0, 54)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Theme.Colors.Accent
	title.TextStrokeTransparency = 0.4
	title.Parent = gui

	grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.AnchorPoint = Vector2.new(0.5, 0.5)
	grid.Position = UDim2.fromScale(0.5, 0.5)
	grid.Size = UDim2.fromOffset(COLUMNS * CARD_SIZE.X + (COLUMNS - 1) * PADDING, 2 * CARD_SIZE.Y + PADDING)
	grid.BackgroundTransparency = 1
	grid.Parent = gui

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	layout.CellPadding = UDim2.fromOffset(PADDING, PADDING)
	layout.FillDirectionMaxCells = COLUMNS
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	gridScale = Instance.new("UIScale")
	gridScale.Parent = grid

	summary = Instance.new("TextLabel")
	summary.Name = "Summary"
	summary.AnchorPoint = Vector2.new(0.5, 0.5)
	summary.Position = UDim2.fromScale(0.5, 0.82)
	summary.Size = UDim2.new(0.8, 0, 0, 30)
	summary.BackgroundTransparency = 1
	summary.TextScaled = true
	summary.Font = Enum.Font.GothamBold
	summary.TextColor3 = Color3.fromRGB(255, 225, 110)
	summary.Parent = gui

	closeButton = Theme.Button(gui, "เก็บเข้าคลัง", "primary", UDim2.fromOffset(280, 54))
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	closeButton.Position = UDim2.fromScale(0.5, 0.9)
	closeButton.TextSize = 22
	closeButton.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function fitGridToScreen()
	local viewport = workspace.CurrentCamera.ViewportSize
	local size = grid.Size
	gridScale.Scale = math.min(1, viewport.X * 0.95 / size.X.Offset, viewport.Y * 0.6 / size.Y.Offset)
end

local function flash(color: Color3)
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 0.1
	TweenService:Create(overlay, TweenInfo.new(0.6), {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
	}):Play()
end

local function popIn(card: Frame, big: boolean)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = card
	local tween = TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = if big then 1.15 else 1,
	})
	tween:Play()
	if big then
		tween.Completed:Wait()
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 1 }):Play()
	end
end

local function show(sackTypeId: string, shirts)
	busy = true
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local sackType = SackTypes.Get(sackTypeId)
	title.Text = "เปิด" .. (if sackType then sackType.DisplayName else "กระสอบ") .. "!"
	summary.Text = ""
	closeButton.Visible = false
	fitGridToScreen()
	gui.Enabled = true
	raysConnection = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation = (rays.Rotation + dt * 8) % 360
	end)

	local totalMin, totalMax = 0, 0
	for index, shirt in shirts do
		local rarity = Rarities.ByName[shirt.Rarity]
		local order = if rarity then rarity.Order else 1
		if order >= 4 then
			task.wait(0.6) -- ลุ้นก่อนของแรงออก
		end

		local card = ShirtCard.Create(shirt)
		card.LayoutOrder = index
		card.Parent = grid
		popIn(card, order >= 4)
		if order >= 4 and rarity then
			flash(rarity.Color)
		end

		totalMin += shirt.PriceMin
		totalMax += shirt.PriceMax
		task.wait(if order >= 3 then 0.55 else 0.3)
	end

	summary.Text = ("มูลค่าประมาณรวม %s - %s"):format(ShirtCard.FormatMoney(totalMin), ShirtCard.FormatMoney(totalMax))
	closeButton.Visible = true
	closeButton.Activated:Wait()

	gui.Enabled = false
	if raysConnection then
		raysConnection:Disconnect()
		raysConnection = nil
	end
	busy = false
end

local function processQueue()
	if busy then
		return
	end
	while #queue > 0 do
		local item = table.remove(queue, 1)
		show(item.SackTypeId, item.Shirts)
	end
end

function SackOpenController:Start()
	createGui()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SackOpened") :: RemoteEvent
	remote.OnClientEvent:Connect(function(sackTypeId, shirts)
		table.insert(queue, { SackTypeId = sackTypeId, Shirts = shirts })
		processQueue()
	end)
end

return SackOpenController

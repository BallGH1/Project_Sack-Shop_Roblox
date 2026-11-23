-- SackOpenController: แอนิเมชันเปิดกระสอบ เสื้อเด้งออกมาทีละตัว ตัวแรร์มีลุ้น + แฟลชสี
-- รับผลจาก Remotes.SackOpened (server สุ่มเสร็จแล้ว client แค่แสดงผล)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local SackTypes = require(Config:WaitForChild("SackTypes"))
local ShirtCard = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ShirtCard"))

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
	overlay.BackgroundTransparency = 0.35
	overlay.Parent = gui

	title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.12)
	title.Size = UDim2.new(0.8, 0, 0, 54)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 230, 150)
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

	closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	closeButton.Position = UDim2.fromScale(0.5, 0.9)
	closeButton.Size = UDim2.fromOffset(260, 52)
	closeButton.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextScaled = true
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Text = "เก็บเข้าคลัง ✔"
	closeButton.Visible = false
	closeButton.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = closeButton

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

-- InventoryController: หน้าต่าง "คลังเสื้อ" + "อัตราสุ่ม" (ปุ่มอยู่แถบซ้ายของ HudController)
--   คลังเสื้อ : ขอรายการจาก server (Remotes.GetInventory) แล้วแสดงเป็นการ์ด กรองตาม rarity ได้
--   อัตราสุ่ม : อ่านจาก SackTypes (เปิดเผยอัตราตามกฎ Roblox)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local SackTypes = require(Config:WaitForChild("SackTypes"))
local UI = script.Parent.Parent:WaitForChild("UI")
local ShirtCard = require(UI:WaitForChild("ShirtCard"))
local Theme = require(UI:WaitForChild("Theme"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local InventoryController = {}

local gui: ScreenGui
local inventoryWindow
local dropRateWindow
local grid: ScrollingFrame
local filterBar: Frame
local capacityFill: Frame
local emptyLabel: TextLabel
local loading = false
local lastResult = nil
local currentFilter = "All"

---------------------------------------------------------------------
-- คลังเสื้อ
---------------------------------------------------------------------

local function renderGrid()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not lastResult then
		return
	end

	local shirts = {}
	for _, shirt in lastResult.Shirts do
		if currentFilter == "All" or shirt.Rarity == currentFilter then
			table.insert(shirts, shirt)
		end
	end
	ShirtCard.Sort(shirts)

	emptyLabel.Visible = #shirts == 0
	emptyLabel.Text = if #lastResult.Shirts == 0
		then "📦\nยังไม่มีเสื้อ ไปซื้อกระสอบที่โรงงานกลางเมืองสิ!"
		else "ไม่มีเสื้อระดับนี้"
	for index, shirt in shirts do
		local card = ShirtCard.Create(shirt)
		card.LayoutOrder = index
		card.Parent = grid
	end
end

local function refreshInventory()
	if loading then
		return
	end
	loading = true
	inventoryWindow.SubtitleLabel.Text = "กำลังโหลด..."

	local remote = Remotes:WaitForChild("GetInventory") :: RemoteFunction
	local result
	for _ = 1, 3 do
		local ok, response = pcall(remote.InvokeServer, remote)
		if ok and response then
			result = response
			break
		end
		task.wait(0.4)
	end
	loading = false

	if not result then
		inventoryWindow.SubtitleLabel.Text = "โหลดไม่สำเร็จ ลองเปิดใหม่อีกครั้ง"
		return
	end
	lastResult = result
	local count, capacity = #result.Shirts, result.Capacity
	inventoryWindow.SubtitleLabel.Text = ("เสื้อ %d / %d ตัว"):format(count, capacity)
	capacityFill.Size = UDim2.fromScale(math.clamp(count / math.max(capacity, 1), 0, 1), 1)
	capacityFill.BackgroundColor3 = if count >= capacity then Theme.Colors.Danger else Theme.Colors.Accent
	renderGrid()
end

local function buildInventoryWindow()
	inventoryWindow = Theme.Window(gui, {
		Name = "InventoryWindow",
		Title = "คลังเสื้อ",
		Icon = "👕",
		Subtitle = "",
	})
	local body = inventoryWindow.Body

	-- แถบความจุ
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = Theme.Colors.PanelLighter
	bar.Parent = body
	Theme.Corner(bar, 4)
	capacityFill = Instance.new("Frame")
	capacityFill.Size = UDim2.fromScale(0, 1)
	capacityFill.BackgroundColor3 = Theme.Colors.Accent
	capacityFill.Parent = bar
	Theme.Corner(capacityFill, 4)

	-- ปุ่มกรองตาม rarity
	filterBar = Instance.new("Frame")
	filterBar.Position = UDim2.fromOffset(0, 18)
	filterBar.Size = UDim2.new(1, 0, 0, 30)
	filterBar.BackgroundTransparency = 1
	filterBar.Parent = body
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0, 6)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = filterBar

	local filterButtons = {}
	local function addFilter(order: number, key: string, label: string, color: Color3)
		local button = Instance.new("TextButton")
		button.LayoutOrder = order
		button.AutoButtonColor = false
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.fromOffset(0, 30)
		button.BackgroundColor3 = Theme.Colors.PanelLighter
		button.Font = Theme.Fonts.Bold
		button.TextSize = 14
		button.TextColor3 = color
		button.Text = label
		button.Parent = filterBar
		Theme.Corner(button, 15)
		Theme.Padding(button, 0, 12)
		local stroke = Theme.Stroke(button, color, 1.5, 0.6)
		Theme.AttachHover(button)
		filterButtons[key] = { Button = button, Stroke = stroke }
		button.Activated:Connect(function()
			currentFilter = key
			for k, item in filterButtons do
				item.Stroke.Transparency = if k == key then 0 else 0.6
				item.Button.BackgroundColor3 = if k == key then Theme.Colors.Stroke else Theme.Colors.PanelLighter
			end
			renderGrid()
		end)
	end
	addFilter(0, "All", "ทั้งหมด", Theme.Colors.Text)
	for i, rarity in Rarities.List do
		addFilter(i, rarity.Name, rarity.Name, rarity.Color)
	end
	filterButtons.All.Stroke.Transparency = 0
	filterButtons.All.Button.BackgroundColor3 = Theme.Colors.Stroke

	local holder = Instance.new("Frame")
	holder.Position = UDim2.fromOffset(0, 58)
	holder.Size = UDim2.new(1, 0, 1, -58)
	holder.BackgroundTransparency = 1
	holder.Parent = body
	grid = Theme.Scroll(holder)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(136, 182)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	Theme.Padding(grid, 4)
	emptyLabel = Theme.Text(holder, {
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.fromOffset(0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.Muted,
		TextSize = 20,
		TextWrapped = true,
		Visible = false,
		Text = "",
	})

	inventoryWindow.Opened:Connect(refreshInventory)
end

---------------------------------------------------------------------
-- อัตราสุ่ม
---------------------------------------------------------------------

local function buildDropRateWindow()
	dropRateWindow = Theme.Window(gui, {
		Name = "DropRateWindow",
		Title = "อัตราสุ่มของกระสอบ",
		Icon = "🎲",
		Subtitle = "โอกาสได้เสื้อแต่ละระดับต่อ 1 ตัว",
	})
	local scroll = Theme.Scroll(dropRateWindow.Body)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	Theme.Padding(scroll, 2, 4)

	for index, sackType in SackTypes.GetEnabled() do
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.Size = UDim2.new(1, -8, 0, 96)
		card.BackgroundColor3 = Theme.Colors.PanelLight
		card.Parent = scroll
		Theme.Corner(card, 12)
		Theme.Stroke(card, sackType.Color, 2, 0.4)

		Theme.Text(card, {
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(0.6, 0, 0, 26),
			Font = Theme.Fonts.Title,
			TextSize = 20,
			TextColor3 = sackType.Color,
			Text = "🛍️ " .. sackType.DisplayName,
		})
		Theme.Text(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 10),
			Size = UDim2.new(0.4, 0, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Colors.Money,
			TextSize = 18,
			Text = Theme.FormatMoney(sackType.Price) .. "  ·  " .. sackType.ShirtCount .. " ตัว",
		})

		-- แถบสัดส่วน rarity
		local bar = Instance.new("Frame")
		bar.Position = UDim2.fromOffset(16, 44)
		bar.Size = UDim2.new(1, -32, 0, 12)
		bar.BackgroundColor3 = Theme.Colors.PanelLighter
		bar.ClipsDescendants = true
		bar.Parent = card
		Theme.Corner(bar, 6)
		local barRow = Instance.new("UIListLayout")
		barRow.FillDirection = Enum.FillDirection.Horizontal
		barRow.SortOrder = Enum.SortOrder.LayoutOrder
		barRow.Parent = bar

		local legend = Instance.new("Frame")
		legend.Position = UDim2.fromOffset(16, 64)
		legend.Size = UDim2.new(1, -32, 0, 22)
		legend.BackgroundTransparency = 1
		legend.Parent = card
		local legendRow = Instance.new("UIListLayout")
		legendRow.FillDirection = Enum.FillDirection.Horizontal
		legendRow.Padding = UDim.new(0, 14)
		legendRow.SortOrder = Enum.SortOrder.LayoutOrder
		legendRow.Parent = legend

		for order, rarity in Rarities.List do
			local weight = sackType.RarityWeights[rarity.Name] or 0
			if weight > 0 then
				local segment = Instance.new("Frame")
				segment.LayoutOrder = order
				segment.BorderSizePixel = 0
				segment.Size = UDim2.fromScale(weight / 100, 1)
				segment.BackgroundColor3 = rarity.Color
				segment.Parent = bar
				Theme.Text(legend, {
					LayoutOrder = order,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 22),
					TextSize = 14,
					TextColor3 = rarity.Color,
					Text = rarity.Name .. " " .. ("%g"):format(weight) .. "%",
				})
			end
		end
	end
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------

function InventoryController:Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	buildInventoryWindow()
	buildDropRateWindow()

	local _, setInventoryActive = HudController:AddButton(1, "👕", "คลังเสื้อ", Enum.KeyCode.G, function()
		inventoryWindow:Toggle()
	end)
	local _, setDropActive = HudController:AddButton(3, "🎲", "อัตราสุ่ม", nil, function()
		dropRateWindow:Toggle()
	end)
	inventoryWindow.Opened:Connect(function()
		setInventoryActive(true)
	end)
	inventoryWindow.Closed:Connect(function()
		setInventoryActive(false)
	end)
	dropRateWindow.Opened:Connect(function()
		setDropActive(true)
	end)
	dropRateWindow.Closed:Connect(function()
		setDropActive(false)
	end)

	-- เปิดกระสอบได้เสื้อใหม่ ถ้าคลังเปิดอยู่ให้รีเฟรช
	local sackOpened = Remotes:WaitForChild("SackOpened") :: RemoteEvent
	sackOpened.OnClientEvent:Connect(function()
		if inventoryWindow:IsOpen() then
			task.delay(0.5, refreshInventory)
		end
	end)
end

return InventoryController

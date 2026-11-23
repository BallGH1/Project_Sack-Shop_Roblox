-- InventoryController: ปุ่มด้านซ้ายจอ "คลังเสื้อ" + "อัตราสุ่ม"
--   คลังเสื้อ : ขอรายการจาก server (Remotes.GetInventory) แล้วแสดงเป็นการ์ด
--   อัตราสุ่ม : อ่านจาก SackTypes (เปิดเผยอัตราตามกฎ Roblox)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local SackTypes = require(Config:WaitForChild("SackTypes"))
local ShirtCard = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ShirtCard"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local InventoryController = {}

local gui: ScreenGui
local inventoryWindow: Frame
local inventoryBody: ScrollingFrame
local inventoryTitle: TextLabel
local dropRateWindow: Frame
local loading = false

local DARK = Color3.fromRGB(30, 27, 25)
local PANEL = Color3.fromRGB(45, 40, 36)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeSideButton(text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(150, 44)
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.1
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	corner(button, 10)
	return button
end

-- หน้าต่างกลางจอ: คืน (window, titleLabel, body)
local function makeWindow(name: string): (Frame, TextLabel, ScrollingFrame)
	local window = Instance.new("Frame")
	window.Name = name
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.7, 0.72)
	window.BackgroundColor3 = DARK
	window.Visible = false
	window.Parent = gui
	corner(window, 14)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(900, 620)
	constraint.Parent = window

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(20, 10)
	titleLabel.Size = UDim2.new(1, -90, 0, 40)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 26
	titleLabel.TextColor3 = Color3.fromRGB(255, 230, 150)
	titleLabel.Parent = window

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = window
	corner(close, 8)
	close.Activated:Connect(function()
		window.Visible = false
	end)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(16, 60)
	body.Size = UDim2.new(1, -32, 1, -76)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 8
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = window

	return window, titleLabel, body
end

local function clearBody(body: ScrollingFrame)
	for _, child in body:GetChildren() do
		child:Destroy()
	end
end

---------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------

local function refreshInventory()
	if loading then
		return
	end
	loading = true
	inventoryTitle.Text = "คลังเสื้อ (กำลังโหลด...)"

	local remote = Remotes:WaitForChild("GetInventory") :: RemoteFunction
	local result
	for _ = 1, 3 do
		local ok, response = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and response then
			result = response
			break
		end
		task.wait(0.4)
	end
	loading = false

	clearBody(inventoryBody)
	if not result then
		inventoryTitle.Text = "คลังเสื้อ (โหลดไม่สำเร็จ ลองใหม่)"
		return
	end

	local shirts = ShirtCard.Sort(result.Shirts)
	inventoryTitle.Text = ("คลังเสื้อ (%d/%d)"):format(#shirts, result.Capacity)

	if #shirts == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.GothamBold
		empty.TextSize = 20
		empty.TextColor3 = Color3.fromRGB(190, 185, 175)
		empty.Text = "ยังไม่มีเสื้อ ไปซื้อกระสอบที่โรงงานกลางแมพสิ!"
		empty.Parent = inventoryBody
		return
	end

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(130, 175)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = inventoryBody

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.Parent = inventoryBody

	for index, shirt in shirts do
		local card = ShirtCard.Create(shirt)
		card.LayoutOrder = index
		card.Parent = inventoryBody
	end
end

---------------------------------------------------------------------
-- Drop rates
---------------------------------------------------------------------

local function buildDropRates(body: ScrollingFrame)
	clearBody(body)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	for index, sackType in SackTypes.GetEnabled() do
		local parts = {}
		for _, rarity in Rarities.List do
			local weight = sackType.RarityWeights[rarity.Name] or 0
			if weight > 0 then
				local hex = rarity.Color:ToHex()
				table.insert(parts, '<font color="#' .. hex .. '">' .. rarity.Name .. " " .. ("%g"):format(weight) .. "%</font>")
			end
		end

		local row = Instance.new("TextLabel")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -12, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundColor3 = PANEL
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextWrapped = true
		row.RichText = true
		row.Font = Enum.Font.Gotham
		row.TextSize = 18
		row.TextColor3 = Color3.new(1, 1, 1)
		row.Text = "<b>"
			.. sackType.DisplayName
			.. "</b>   "
			.. ShirtCard.FormatMoney(sackType.Price)
			.. " · เสื้อ "
			.. sackType.ShirtCount
			.. " ตัว/กระสอบ\n"
			.. table.concat(parts, "   ")
		row.Parent = body
		corner(row, 8)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = row
	end
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------

function InventoryController:Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local side = Instance.new("Frame")
	side.Name = "SideButtons"
	side.AnchorPoint = Vector2.new(0, 0.5)
	side.Position = UDim2.new(0, 12, 0.5, 0)
	side.Size = UDim2.fromOffset(150, 100)
	side.BackgroundTransparency = 1
	side.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = side

	local inventoryButton = makeSideButton("👕 คลังเสื้อ", 1)
	inventoryButton.Parent = side
	local dropRateButton = makeSideButton("🎲 อัตราสุ่ม", 2)
	dropRateButton.Parent = side

	local dropRateTitle, dropRateBody
	inventoryWindow, inventoryTitle, inventoryBody = makeWindow("InventoryWindow")
	dropRateWindow, dropRateTitle, dropRateBody = makeWindow("DropRateWindow")
	dropRateTitle.Text = "อัตราสุ่มของกระสอบ"
	buildDropRates(dropRateBody)

	inventoryButton.Activated:Connect(function()
		dropRateWindow.Visible = false
		inventoryWindow.Visible = not inventoryWindow.Visible
		if inventoryWindow.Visible then
			refreshInventory()
		end
	end)
	dropRateButton.Activated:Connect(function()
		inventoryWindow.Visible = false
		dropRateWindow.Visible = not dropRateWindow.Visible
	end)

	-- เปิดกระสอบได้เสื้อใหม่ ถ้าคลังเปิดอยู่ให้รีเฟรช
	local sackOpened = Remotes:WaitForChild("SackOpened") :: RemoteEvent
	sackOpened.OnClientEvent:Connect(function()
		if inventoryWindow.Visible then
			task.delay(0.5, refreshInventory)
		end
	end)
end

return InventoryController

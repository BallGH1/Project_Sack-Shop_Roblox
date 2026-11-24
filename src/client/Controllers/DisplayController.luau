-- DisplayController: หน้าต่างวางเสื้อ (ราวเหล็ก / ราวตากผ้า / ตู้โชว์ / กรอบรูป)
--   ช่องว่าง     → เลือกเสื้อจากคลัง → วางขาย (ตั้งราคา) หรือ วางโชว์ (ไม่ขาย) / ปุ่ม "กลับ" ไปเลือกตัวใหม่
--   ช่องมีเสื้อ  → แก้ราคา / สลับวางขาย-วางโชว์ / เก็บกลับคลัง
-- server เป็นคนเปิดหน้าต่าง (Remotes.OpenDisplayMenu) และตัดสินทุกคำสั่ง (Remotes.DisplayAction)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent:WaitForChild("UI")
local ShirtCard = require(UI:WaitForChild("ShirtCard"))
local Theme = require(UI:WaitForChild("Theme"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DisplayController = {}

local gui: ScreenGui
local window
local currentSlot: string? = nil
local currentLabel = ""
local busy = false
local viewToken = 0

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function clearBody()
	for _, child in window.Body:GetChildren() do
		child:Destroy()
	end
end

local function parsePrice(text: string): number?
	local digits = (text:gsub("%D", ""))
	return tonumber(digits)
end

local function suggestedPrice(shirt): number
	if shirt.IsGraded and shirt.TrueValue then
		return shirt.TrueValue
	end
	return math.floor((shirt.PriceMin + shirt.PriceMax) / 2)
end

-- ส่งคำสั่งไป server แล้วแจ้งผล คืน true ถ้าสำเร็จ
local function send(action: string, ...): boolean
	if busy then
		return false
	end
	busy = true
	local remote = Remotes:WaitForChild("DisplayAction") :: RemoteFunction
	local okCall, ok, message = pcall(remote.InvokeServer, remote, action, currentSlot, ...)
	busy = false
	if not okCall then
		NotificationController:Show("เชื่อมต่อ server ไม่สำเร็จ ลองใหม่", "error")
		return false
	end
	NotificationController:Show(tostring(message), if ok then "success" else "error")
	return ok == true
end

---------------------------------------------------------------------
-- Views
---------------------------------------------------------------------

local showPickView: () -> ()

-- หน้าเสื้อที่เลือก: ด้านซ้ายการ์ด + ปุ่ม "กลับ" สีแดงใต้การ์ด / ด้านขวาราคา + ปุ่ม วางขาย / วางโชว์
-- occupied = ช่องนี้มีเสื้ออยู่แล้ว (มาจากการกด E ที่เสื้อที่วางไว้)
local function showPriceView(shirt, price: number?, occupied: boolean, showOnly: boolean?)
	viewToken += 1
	clearBody()
	if occupied then
		window.TitleLabel.Text = if showOnly then "เสื้อที่วางโชว์" else "เสื้อที่วางขาย"
	else
		window.TitleLabel.Text = "วางเสื้อ"
	end
	window.SubtitleLabel.Text = currentLabel

	-- ซ้าย: การ์ดเสื้อ + ปุ่มกลับ
	local left = Instance.new("Frame")
	left.Size = UDim2.new(0, 180, 1, 0)
	left.BackgroundTransparency = 1
	left.Parent = window.Body
	local card = ShirtCard.Create(shirt)
	card.Size = UDim2.fromOffset(180, 240)
	card.Parent = left
	if not occupied then
		local back = Theme.Button(left, "กลับ", "danger", UDim2.fromOffset(180, 40))
		back.Position = UDim2.fromOffset(0, 250)
		back.Activated:Connect(function()
			showPickView()
		end)
	end

	-- ขวา: ราคา + ปุ่ม
	local right = Instance.new("Frame")
	right.Position = UDim2.fromOffset(200, 0)
	right.Size = UDim2.new(1, -200, 1, 0)
	right.BackgroundTransparency = 1
	right.Parent = window.Body
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = right

	local info = Instance.new("Frame")
	info.LayoutOrder = 1
	info.Size = UDim2.new(1, 0, 0, 64)
	info.BackgroundColor3 = Theme.Colors.PanelLight
	info.Parent = right
	Theme.Corner(info, 10)
	Theme.Padding(info, 8, 12)
	local graded = shirt.IsGraded and shirt.TrueValue
	Theme.Text(info, {
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 14,
		TextColor3 = Theme.Colors.Muted,
		Text = if graded then "ราคาจริง (ส่งเกรดแล้ว)" else "ช่วงราคาที่ประเมินได้",
	})
	Theme.Text(info, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Theme.Colors.Money,
		Text = if graded
			then Theme.FormatMoney(shirt.TrueValue)
			else Theme.FormatMoney(shirt.PriceMin) .. "  –  " .. Theme.FormatMoney(shirt.PriceMax),
	})

	Theme.Text(right, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 36),
		TextWrapped = true,
		TextSize = 14,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Muted,
		Text = if occupied and showOnly
			then "💡 เสื้อตัวนี้วางโชว์อยู่ ลูกค้าจะไม่หยิบไปซื้อ ใส่ราคาแล้วกดวางขายเพื่อเริ่มขาย"
			else "💡 วางขาย = ลูกค้าซื้อได้ · วางโชว์ = แต่งร้านเฉย ๆ ไม่ขาย",
	})

	local box = Instance.new("TextBox")
	box.LayoutOrder = 3
	box.Size = UDim2.new(1, 0, 0, 48)
	box.BackgroundColor3 = Theme.Colors.Backdrop
	box.ClearTextOnFocus = false
	box.Font = Theme.Fonts.Title
	box.TextSize = 24
	box.TextColor3 = Theme.Colors.Money
	box.PlaceholderText = "ราคาขาย เช่น 120"
	box.PlaceholderColor3 = Theme.Colors.Muted
	box.Text = tostring(price or suggestedPrice(shirt))
	box.Parent = right
	Theme.Corner(box, 10)
	Theme.Stroke(box, Theme.Colors.AccentDark, 2)

	local function readPrice(): number?
		local value = parsePrice(box.Text)
		if not value or value < 1 then
			NotificationController:Show("ใส่ราคาเป็นตัวเลขก่อนนะ", "error")
			return nil
		end
		return value
	end

	-- แถวปุ่มคู่
	local row = Instance.new("Frame")
	row.LayoutOrder = 4
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundTransparency = 1
	row.Parent = right
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
	local half = UDim2.new(0.5, -5, 1, 0)

	if not occupied then
		local sell = Theme.Button(row, "🏷️ วางขาย", "primary", half)
		sell.LayoutOrder = 1
		sell.Activated:Connect(function()
			local value = readPrice()
			if value and send("Display", shirt.Id, value, false) then
				window:Close()
			end
		end)
		local show = Theme.Button(row, "👀 วางโชว์", "secondary", half)
		show.LayoutOrder = 2
		show.Activated:Connect(function()
			if send("Display", shirt.Id, parsePrice(box.Text), true) then
				window:Close()
			end
		end)
		return
	end

	if showOnly then
		local sell = Theme.Button(row, "🏷️ วางขายราคานี้", "primary", UDim2.fromScale(1, 1))
		sell.Activated:Connect(function()
			local value = readPrice()
			if value and send("SetPrice", value) then
				window:Close()
			end
		end)
	else
		local update = Theme.Button(row, "อัปเดตราคา", "primary", half)
		update.LayoutOrder = 1
		update.Activated:Connect(function()
			local value = readPrice()
			if value and send("SetPrice", value) then
				window:Close()
			end
		end)
		local toShow = Theme.Button(row, "👀 เปลี่ยนเป็นวางโชว์", "secondary", half)
		toShow.LayoutOrder = 2
		toShow.TextSize = 16
		toShow.Activated:Connect(function()
			if send("ShowOnly") then
				window:Close()
			end
		end)
	end

	local unlist = Theme.Button(right, "เก็บกลับคลัง", "danger", UDim2.new(1, 0, 0, 40))
	unlist.LayoutOrder = 5
	unlist.Activated:Connect(function()
		if send("Unlist") then
			window:Close()
		end
	end)
end

function showPickView()
	viewToken += 1
	local token = viewToken
	clearBody()
	window.TitleLabel.Text = "เลือกเสื้อที่จะวาง"
	window.SubtitleLabel.Text = currentLabel

	local loadingLabel = Theme.Text(window.Body, { Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.Muted, Text = "กำลังโหลดคลัง..." })
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
	if token ~= viewToken or not window:IsOpen() then
		return -- ผู้เล่นเปลี่ยนหน้า/ปิดไปแล้วระหว่างโหลด
	end
	loadingLabel:Destroy()
	if not result then
		Theme.Text(window.Body, { Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.Danger, Text = "โหลดคลังไม่สำเร็จ ลองปิดแล้วเปิดใหม่" })
		return
	end

	local shirts = {}
	for _, shirt in result.Shirts do
		if not shirt.OnDisplay then
			table.insert(shirts, shirt)
		end
	end
	ShirtCard.Sort(shirts)

	if #shirts == 0 then
		Theme.Text(window.Body, {
			Size = UDim2.new(1, 0, 0, 80),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.Colors.Muted,
			TextSize = 18,
			Text = "📦\nไม่มีเสื้อในคลังที่วางขายได้ ไปเปิดกระสอบก่อนนะ",
		})
		return
	end

	local scroll = Theme.Scroll(window.Body)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(136, 182)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	Theme.Padding(scroll, 4)

	for index, shirt in shirts do
		local card = ShirtCard.Create(shirt)
		card.LayoutOrder = index
		card.Parent = scroll
		Theme.AttachHover((function()
			local click = Instance.new("TextButton")
			click.Size = UDim2.fromScale(1, 1)
			click.BackgroundTransparency = 1
			click.Text = ""
			click.ZIndex = 5
			click.Parent = card
			click.Activated:Connect(function()
				showPriceView(shirt, suggestedPrice(shirt), false)
			end)
			return click
		end)())
	end
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------

function DisplayController:Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "DisplayGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	window = Theme.Window(gui, {
		Name = "DisplayWindow",
		Title = "วางเสื้อ",
		Icon = "🏷️",
		Size = UDim2.fromScale(0.6, 0.66),
		MinSize = Vector2.new(600, 420),
		MaxSize = Vector2.new(840, 540),
	})
	window.Closed:Connect(function()
		currentSlot = nil
		viewToken += 1
		clearBody()
	end)

	local openRemote = Remotes:WaitForChild("OpenDisplayMenu") :: RemoteEvent
	openRemote.OnClientEvent:Connect(function(slotKey, current, label)
		currentSlot = slotKey
		currentLabel = if type(label) == "string" then label else ""
		window:Open()
		if current then
			showPriceView(current.Shirt, current.Price, true, current.ShowOnly == true)
		else
			showPickView()
		end
	end)
end

return DisplayController

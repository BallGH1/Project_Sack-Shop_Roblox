-- HudController: แถบด้านซ้ายจอ = ป้ายเงิน + ปุ่มเมนู (คลังเสื้อ / ตกแต่ง / อัตราสุ่ม)
-- controller อื่นเพิ่มปุ่มผ่าน HudController:AddButton(...) ตอน Start (HudController ต้องโหลดก่อน)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local HudController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local column: Frame
local moneyLabel: TextLabel
local displayedMoney = 0
local hotkeys: { [Enum.KeyCode]: () -> () } = {}

---------------------------------------------------------------------
-- เงิน
---------------------------------------------------------------------

local function popDelta(delta: number)
	local label = Theme.Text(gui, {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(160, 26),
		Position = UDim2.new(0, 196, 0, 0),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = if delta > 0 then Theme.Colors.Success else Theme.Colors.Danger,
		TextStrokeTransparency = 0.4,
		Text = (if delta > 0 then "+" else "-") .. Theme.FormatMoney(math.abs(delta)),
	})
	-- วางให้อยู่ระดับเดียวกับป้ายเงิน
	local pill = column:FindFirstChild("Money") :: Frame
	label.Position = UDim2.fromOffset(pill.AbsolutePosition.X + pill.AbsoluteSize.X + 10, pill.AbsolutePosition.Y + pill.AbsoluteSize.Y / 2)
	local tween = TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = label.Position - UDim2.fromOffset(0, 34),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

local function animateMoney(target: number)
	local start = displayedMoney
	local delta = target - start
	if delta == 0 then
		moneyLabel.Text = Theme.FormatMoney(target)
		return
	end
	popDelta(delta)
	displayedMoney = target
	local counter = Instance.new("NumberValue")
	counter.Value = start
	counter.Changed:Connect(function(value)
		moneyLabel.Text = Theme.FormatMoney(value)
	end)
	local tween = TweenService:Create(counter, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	tween:Play()
	tween.Completed:Connect(function()
		moneyLabel.Text = Theme.FormatMoney(target)
		counter:Destroy()
	end)
end

local function createMoneyPill()
	local pill = Instance.new("Frame")
	pill.Name = "Money"
	pill.LayoutOrder = 0
	pill.Size = UDim2.fromOffset(180, 46)
	pill.BackgroundColor3 = Theme.Colors.Panel
	pill.Parent = column
	Theme.Corner(pill, 23)
	Theme.Stroke(pill, Theme.Colors.AccentDark, 2)
	Theme.Gradient(pill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 195, 190))

	local coin = Theme.Text(pill, {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Money,
		TextColor3 = Color3.fromRGB(110, 70, 10),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		Text = "฿",
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Theme.Corner(coin, 17)
	Theme.Stroke(coin, Color3.fromRGB(200, 140, 30), 2)

	moneyLabel = Theme.Text(pill, {
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Theme.Colors.Money,
		Text = "฿0",
	})

	local function sync()
		local money = player:GetAttribute("Money")
		if typeof(money) == "number" then
			animateMoney(money)
		end
	end
	displayedMoney = player:GetAttribute("Money") or 0
	moneyLabel.Text = Theme.FormatMoney(displayedMoney)
	player:GetAttributeChangedSignal("Money"):Connect(sync)
end

---------------------------------------------------------------------
-- ปุ่มเมนู
---------------------------------------------------------------------

-- เพิ่มปุ่มด้านซ้าย คืนปุ่มกับฟังก์ชันตั้งสถานะ "กำลังเปิดอยู่"
function HudController:AddButton(order: number, icon: string, text: string, hotkey: Enum.KeyCode?, callback: () -> ()): (TextButton, (boolean) -> ())
	local button = Theme.Button(column, "", "secondary", UDim2.fromOffset(180, 52))
	button.Name = text
	button.LayoutOrder = order

	Theme.Text(button, {
		Size = UDim2.fromOffset(40, 52),
		Position = UDim2.fromOffset(8, 0),
		Text = icon,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Theme.Text(button, {
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(52, 0),
		Text = text,
		TextSize = 18,
	})
	if hotkey then
		local key = Theme.Text(button, {
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.new(1, -8, 0.5, 0),
			BackgroundTransparency = 0.3,
			BackgroundColor3 = Theme.Colors.Backdrop,
			TextColor3 = Theme.Colors.Muted,
			TextSize = 12,
			Text = hotkey.Name,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Theme.Corner(key, 5)
		hotkeys[hotkey] = callback
	end

	button.Activated:Connect(callback)

	local function setActive(active: boolean)
		Theme.SetButtonVariant(button, if active then "primary" else "secondary")
		for _, child in button:GetChildren() do
			if child:IsA("TextLabel") and child.Text ~= icon and child.BackgroundTransparency == 1 then
				child.TextColor3 = if active then Color3.fromRGB(46, 28, 8) else Theme.Colors.Text
			end
		end
	end
	return button, setActive
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------

function HudController:Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "HudGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	column = Instance.new("Frame")
	column.Name = "LeftColumn"
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0, 14, 0.5, 0)
	column.Size = UDim2.fromOffset(180, 300)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = column

	createMoneyPill()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local callback = hotkeys[input.KeyCode]
		if callback then
			callback()
		end
	end)
end

return HudController

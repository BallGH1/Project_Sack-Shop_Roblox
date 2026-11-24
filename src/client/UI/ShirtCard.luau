-- ShirtCard: การ์ดแสดงเสื้อ 1 ตัว (ใช้ทั้งตอนเปิดกระสอบและในคลัง)
-- ขนาดการ์ดกำหนดจากภายนอก (เช่น CellSize ของ UIGridLayout) ข้างในใช้ scale ทั้งหมด

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local ShirtRules = require(Config:WaitForChild("ShirtRules"))
local ShirtTemplates = require(Config:WaitForChild("ShirtTemplates"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ShirtCard = {}

function ShirtCard.FormatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "฿" .. (formatted:gsub("^,", ""))
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2, text: string, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = position
	l.Size = size
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.TextWrapped = true
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextColor3 = color
	l.Text = text
	l.Parent = parent
	return l
end

local function addRainbow(stroke: UIStroke, card: Frame)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 120)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
	})
	gradient.Parent = stroke
	local connection = RunService.RenderStepped:Connect(function(dt)
		gradient.Rotation = (gradient.Rotation + dt * 120) % 360
	end)
	card.Destroying:Connect(function()
		connection:Disconnect()
	end)
end

-- shirt = ข้อมูลแบบ public จาก server
function ShirtCard.Create(shirt): Frame
	local rarity = Rarities.ByName[shirt.Rarity] or Rarities.List[1]
	local tier = ShirtRules.GetTier(shirt.Condition)

	local card = Instance.new("Frame")
	card.Name = "ShirtCard"
	card.Size = UDim2.fromOffset(150, 200)
	card.BackgroundColor3 = Theme.Colors.PanelLight
	Theme.Gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 178, 170))

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	-- แถบสี rarity ด้านบน
	local strip = Instance.new("Frame")
	strip.Name = "RarityStrip"
	strip.Size = UDim2.new(1, 0, 0, 5)
	strip.BorderSizePixel = 0
	strip.BackgroundColor3 = rarity.Color
	strip.Parent = card
	Theme.Corner(strip, 3)

	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Thickness = if rarity.Order >= 4 then 4 else 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	if rarity.Name == "Mythic" then
		stroke.Color = Color3.new(1, 1, 1)
		addRainbow(stroke, card)
	end

	label(card, "Rarity", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.1), rarity.Name, rarity.Color, true)

	local iconBg = Instance.new("Frame")
	iconBg.Name = "IconBg"
	iconBg.Position = UDim2.fromScale(0.1, 0.14)
	iconBg.Size = UDim2.fromScale(0.8, 0.33)
	iconBg.BackgroundColor3 = rarity.Color
	iconBg.BackgroundTransparency = 0.75
	iconBg.Parent = card
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 8)
	iconCorner.Parent = iconBg
	-- รูปเสื้อ: เสื้อทั้งตัว (ShirtImageId) > ลายหน้าอก (GraphicId) > อิโมจิ
	local template = ShirtTemplates.Get(shirt.TemplateId)
	local imageId = if template and (template.ShirtImageId or 0) > 0
		then template.ShirtImageId
		elseif template and (template.GraphicId or 0) > 0 then template.GraphicId
		else 0
	if imageId > 0 then
		if template.ShirtImageId and template.ShirtImageId > 0 then
			-- เสื้อทั้งตัว: ขยายกรอบรูปให้ใหญ่ขึ้นนิด
			iconBg.Position = UDim2.fromScale(0.06, 0.12)
			iconBg.Size = UDim2.fromScale(0.88, 0.37)
		end
		local image = Instance.new("ImageLabel")
		image.Name = "Graphic"
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. imageId
		image.Parent = iconBg
	else
		label(iconBg, "Icon", UDim2.fromScale(0, 0.05), UDim2.fromScale(1, 0.9), "👕", Color3.new(1, 1, 1))
	end

	label(card, "Name", UDim2.fromScale(0.05, 0.5), UDim2.fromScale(0.9, 0.13), shirt.DisplayName, Color3.new(1, 1, 1), true)
	label(card, "Condition", UDim2.fromScale(0.05, 0.64), UDim2.fromScale(0.9, 0.09), ("สภาพ %d%%"):format(shirt.Condition), tier.Color, true)

	local defectNames = {}
	for _, defectId in shirt.Defects do
		local defect = ShirtRules.Defects[defectId]
		table.insert(defectNames, if defect then defect.Name else defectId)
	end
	local defectText = if #defectNames > 0 then table.concat(defectNames, ", ") else "ไม่มีตำหนิ"
	label(card, "Defects", UDim2.fromScale(0.05, 0.74), UDim2.fromScale(0.9, 0.08), defectText, Color3.fromRGB(170, 165, 155))

	local priceText
	if shirt.IsGraded and shirt.TrueValue then
		priceText = ("%s (เกรด %d)"):format(ShirtCard.FormatMoney(shirt.TrueValue), shirt.Grade)
	else
		priceText = ShirtCard.FormatMoney(shirt.PriceMin) .. " - " .. ShirtCard.FormatMoney(shirt.PriceMax)
	end
	label(card, "Price", UDim2.fromScale(0.05, 0.85), UDim2.fromScale(0.9, 0.11), priceText, Color3.fromRGB(255, 225, 110), true)

	-- ป้าย "วางขายอยู่" (เสื้อที่แขวนบนราว)
	if shirt.OnDisplay then
		local tag = label(card, "OnDisplay", UDim2.fromScale(0.1, 0.14), UDim2.fromScale(0.8, 0.1), "วางขายอยู่", Color3.new(1, 1, 1), true)
		tag.BackgroundTransparency = 0.1
		tag.BackgroundColor3 = Color3.fromRGB(210, 120, 40)
		tag.ZIndex = 2
		local tagCorner = Instance.new("UICorner")
		tagCorner.CornerRadius = UDim.new(0, 6)
		tagCorner.Parent = tag
	end

	return card
end

-- เรียงเสื้อ: rarity สูงก่อน แล้วสภาพดีก่อน
function ShirtCard.Sort(shirts)
	table.sort(shirts, function(a, b)
		local ra = Rarities.ByName[a.Rarity]
		local rb = Rarities.ByName[b.Rarity]
		local oa = if ra then ra.Order else 0
		local ob = if rb then rb.Order else 0
		if oa ~= ob then
			return oa > ob
		end
		return a.Condition > b.Condition
	end)
	return shirts
end

return ShirtCard

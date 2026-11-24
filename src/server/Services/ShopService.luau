-- ShopService: ช่องโชว์เสื้อขายในร้าน + ตั้งราคา + ขายให้ NPC
--
-- "ช่อง" (slot) มี 2 แบบ อ้างอิงด้วย key แบบ string:
--   "1".."4"            ราวเหล็กเดิมของร้าน (Fixtures.RackSlots.Slot1..4)
--   "<furnitureId>:<n>"  ช่องที่ n ของของตกแต่งที่ผู้เล่นวางเอง (ราวตากผ้า / ตู้โชว์ / กรอบรูป)
--
-- ข้อมูล: Data.Displayed[key] = { ShirtId, Price, ShowOnly? }  (เสื้อยังอยู่ใน Data.Shirts จนกว่าจะขายออก)
--   ShowOnly = true → วางโชว์เฉย ๆ ไม่ขาย (ลูกค้าไม่หยิบ)
-- ผู้เล่นกด E ที่ช่อง → server ส่ง Remotes.OpenDisplayMenu(key, current, label) ให้ client เปิดหน้าต่าง
-- client ส่งคำสั่งกลับผ่าน Remotes.DisplayAction (RemoteFunction):
--   ("Display", key, shirtId, price, showOnly) | ("SetPrice", key, price) | ("ShowOnly", key) | ("Unlist", key)
-- server ตรวจทุกอย่างก่อนทำ: เป็นเจ้าของร้านไหม, ยืนใกล้ไหม, เสื้อเป็นของเขาไหม, ราคาถูกต้องไหม

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local ShirtTemplates = require(ReplicatedStorage.Shared.Config.ShirtTemplates)
local Furniture = require(ReplicatedStorage.Shared.Config.Furniture)
local PlacementRules = require(ReplicatedStorage.Shared.Building.PlacementRules)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ShirtGenerator = require(script.Parent.Parent.Modules.ShirtGenerator)
local Notify = require(script.Parent.Parent.Modules.Notify)

local CONFIG = GameConfig.Shop
local TEE_SIZE = Vector3.new(2.4, 2.86, 0.12) -- ขนาดโมเดลเสื้อ (ตรงกับ art/shirts/mesh/tee.obj)

export type Listing = {
	Key: string,
	ShirtId: string,
	Price: number,
	Shirt: ShirtGenerator.Shirt, -- ตัวเต็ม (มี TrueValue) ใช้บน server เท่านั้น
	Reserved: boolean, -- ลูกค้าหยิบไปถือรอจ่ายเงินอยู่
	Bonus: number, -- ลูกค้ายอมจ่ายเพิ่มกี่ % (ตู้โชว์/กรอบรูป)
}

export type BrowseInfo = {
	StopId: string, -- จุดยืนดูเดียวกัน = ดูเสื้อหลายตัวได้ในครั้งเดียว
	Point: Vector3, -- จุดที่ลูกค้ายืน
	LookAt: Vector3, -- ตำแหน่งเสื้อ (ให้ลูกค้าหันไปมอง)
}

local ShopService = {}

local openMenuRemote: RemoteEvent
local visuals: { [Player]: { [string]: Model } } = {}
local lastAction: { [Player]: number } = {}
-- ช่องที่ลูกค้าหยิบเสื้อไปถือรอคิดเงิน (เก็บในหน่วยความจำ ไม่เซฟ: ถ้าเซิร์ฟดับ เสื้อก็ยังอยู่บนราวตามเดิม)
local reserved: { [Player]: { [string]: boolean } } = {}

local function isReserved(player: Player, key: string): boolean
	return reserved[player] ~= nil and reserved[player][key] == true
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "฿" .. (formatted:gsub("^,", ""))
end

local function isValidPrice(price: any): boolean
	return type(price) == "number" and price == price and price % 1 == 0 and price >= 1 and price <= CONFIG.MaxPrice
end

-- แยก key: คืน ("base", nil, n) หรือ ("furniture", id, n) หรือ nil
local function parseKey(key: any): (string?, string?, number?)
	if type(key) ~= "string" or #key > 80 then
		return nil
	end
	local n = tonumber(key)
	if n then
		if n % 1 == 0 and n >= 1 and n <= CONFIG.RackSlots then
			return "base", nil, n
		end
		return nil
	end
	local id, index = key:match("^([%w%-]+):(%d+)$")
	if id then
		return "furniture", id, tonumber(index)
	end
	return nil
end

local function getFurnitureModel(plot: Model, id: string): Model?
	local folder = plot:FindFirstChild("Furniture")
	local model = folder and folder:FindFirstChild(id)
	return if model and model:IsA("Model") then model else nil
end

local function getSlotPart(plot: Model, key: string): BasePart?
	local kind, id, n = parseKey(key)
	local slot
	if kind == "base" then
		local folder = plot:FindFirstChild("RackSlots", true)
		slot = folder and folder:FindFirstChild("Slot" .. n)
	elseif kind == "furniture" then
		local model = getFurnitureModel(plot, id :: string)
		slot = model and model:FindFirstChild("Slot" .. n)
	end
	return if slot and slot:IsA("BasePart") then slot else nil
end

-- key นี้ใช้ได้สำหรับผู้เล่นคนนี้ไหม (ของตกแต่งยังอยู่ และมีช่องที่ n จริง)
local function isValidKey(player: Player, key: any): boolean
	local kind, id, n = parseKey(key)
	if kind == "base" then
		return true
	elseif kind == "furniture" then
		local data = DataService:GetData(player)
		local entry = data and data.Furniture[id]
		local def = entry and Furniture.Get(entry.Type)
		return def ~= nil and (n :: number) >= 1 and (n :: number) <= def.Slots
	end
	return false
end

local function slotLabel(player: Player, key: string): string
	local kind, id, n = parseKey(key)
	if kind == "furniture" then
		local data = DataService:GetData(player)
		local entry = data and data.Furniture[id]
		local def = entry and Furniture.Get(entry.Type)
		if def then
			return if def.Slots > 1 then def.DisplayName .. " ช่อง " .. n else def.DisplayName
		end
	end
	return "ราวเหล็ก ช่อง " .. tostring(n)
end

local function slotBonus(plot: Model, key: string): number
	local kind, id = parseKey(key)
	if kind == "furniture" then
		local model = getFurnitureModel(plot, id :: string)
		return model and model:GetAttribute("PriceBonus") or 0
	end
	return 0
end

local function displayName(shirt): string
	local template = ShirtTemplates.Get(shirt.TemplateId)
	return if template then template.DisplayName else shirt.TemplateId
end

local function isShirtDisplayed(data, shirtId: string): boolean
	for _, entry in data.Displayed do
		if entry.ShirtId == shirtId then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Visuals (เสื้อบนช่อง + ป้ายราคา)
---------------------------------------------------------------------

local function updatePrompt(plot: Model, key: string, occupied: boolean, isHeld: boolean?)
	local slot = getSlotPart(plot, key)
	local prompt = slot and slot:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = if occupied then "จัดการเสื้อ" else "วางเสื้อ"
		prompt.Enabled = not isHeld
	end
end

local function removeVisual(player: Player, key: string)
	local playerVisuals = visuals[player]
	local model = playerVisuals and playerVisuals[key]
	if model then
		model:Destroy()
		playerVisuals[key] = nil
	end
end

local function makeShirtModel(slot: BasePart, shirt, price: number, showOnly: boolean?): Model
	local rarity = Rarities.ByName[shirt.Rarity] or Rarities.List[1]
	local cloth = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.25)

	local model = Instance.new("Model")
	model.Name = "DisplayShirt"

	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = slot.CFrame * offset
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		return p
	end

	-- เลือกวิธีแสดงเสื้อตามของที่อัปโหลดไว้ (ดีสุด → สำรอง)
	--   1) โมเดลเสื้อ 3D (TeeMeshId) + รูปเสื้อทั้งตัว (ShirtImageId)
	--   2) รูปเสื้อทั้งตัวแปะบนแผ่นล่องหน (cut-out)
	--   3) บล็อกสีตาม rarity + ลายหน้าอก (GraphicId)
	local template = ShirtTemplates.Get(shirt.TemplateId)
	local imageId = if template and template.ShirtImageId then template.ShirtImageId else 0
	local graphicId = if template and template.GraphicId then template.GraphicId else 0
	local meshId = CONFIG.TeeMeshId
	-- ด้านลายของเสื้อหันไปทาง -Z ของช่อง (ด้านลายของโมเดลหลังนำเข้า Roblox คือ +Z ของ part → หมุน 180°)
	-- ถ้าเห็นลายอยู่ผิดด้าน สลับ GameConfig.Shop.TeeFacingFlip
	local facing = CFrame.Angles(0, if CONFIG.TeeFacingFlip then 0 else math.pi, 0)
	local body: Part

	if imageId > 0 and meshId > 0 then
		body = piece("Body", TEE_SIZE, facing, Color3.new(1, 1, 1))
		body.Material = Enum.Material.SmoothPlastic
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = "rbxassetid://" .. meshId
		mesh.TextureId = "rbxassetid://" .. imageId
		mesh.Scale = Vector3.one * CONFIG.TeeMeshScale
		mesh.Parent = body
	elseif imageId > 0 then
		body = piece("Body", Vector3.new(TEE_SIZE.X, TEE_SIZE.Y, 0.05), facing, cloth)
		body.Transparency = 1
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local decal = Instance.new("Decal")
			decal.Name = "Tee"
			decal.Face = face
			decal.Texture = "rbxassetid://" .. imageId
			decal.Parent = body
		end
	else
		body = piece("Body", Vector3.new(2.2, 2.4, 0.3), CFrame.new(), cloth)
		piece("SleeveL", Vector3.new(0.7, 0.9, 0.3), CFrame.new(-1.4, 0.7, 0), cloth)
		piece("SleeveR", Vector3.new(0.7, 0.9, 0.3), CFrame.new(1.4, 0.7, 0), cloth)
		if graphicId > 0 then
			local decal = Instance.new("Decal")
			decal.Name = "Graphic"
			decal.Face = Enum.NormalId.Front
			decal.Texture = "rbxassetid://" .. graphicId
			decal.Parent = body
		end
	end
	piece("Hanger", Vector3.new(0.15, 0.35, 0.15), CFrame.new(0, TEE_SIZE.Y / 2 + 0.12, 0), Color3.fromRGB(60, 60, 60))
	model.PrimaryPart = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PriceTag"
	billboard.Size = UDim2.fromOffset(140, 44)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.MaxDistance = 40
	billboard.LightInfluence = 0
	billboard.Parent = body

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.fromScale(1, 0.4)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.TextScaled = true
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextColor3 = rarity.Color
	rarityLabel.TextStrokeTransparency = 0.3
	rarityLabel.Text = rarity.Name
	rarityLabel.Parent = billboard

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Position = UDim2.fromScale(0, 0.4)
	priceLabel.Size = UDim2.fromScale(1, 0.6)
	priceLabel.BackgroundTransparency = 1
	priceLabel.TextScaled = true
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextColor3 = if showOnly then Color3.fromRGB(200, 210, 230) else Color3.fromRGB(255, 230, 110)
	priceLabel.TextStrokeTransparency = 0.2
	priceLabel.Text = if showOnly then "โชว์ · ไม่ขาย" else formatMoney(price)
	priceLabel.Parent = billboard

	return model
end

local function renderSlot(player: Player, key: string)
	removeVisual(player, key)
	local plot = PlotService:GetPlot(player)
	local data = DataService:GetData(player)
	if not plot or not data then
		return
	end
	local slot = getSlotPart(plot, key)
	local entry = data.Displayed[key]
	local shirt = entry and data.Shirts[entry.ShirtId]
	local held = isReserved(player, key)
	updatePrompt(plot, key, shirt ~= nil, held)
	if not slot or not shirt or held then
		return -- ช่องว่าง หรือ ลูกค้าถือเสื้อไปแล้ว (ไม่ต้องวาด)
	end
	local model = makeShirtModel(slot, shirt, entry.Price or 0, entry.ShowOnly == true)
	model.Parent = plot
	visuals[player] = visuals[player] or {}
	visuals[player][key] = model
end

---------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------

local function onSlotPrompt(plot: Model, key: string, player: Player)
	if PlotService:GetOwner(plot) ~= player then
		Notify(player, "ของชิ้นนี้เป็นของร้านอื่น", "error")
		return
	end
	local data = DataService:GetData(player)
	if not data or not isValidKey(player, key) then
		return
	end
	if isReserved(player, key) then
		Notify(player, "ลูกค้ากำลังถือเสื้อตัวนี้ไปจ่ายเงิน ไปคิดเงินที่เคาน์เตอร์สิ", "info")
		return
	end
	local entry = data.Displayed[key]
	local shirt = entry and data.Shirts[entry.ShirtId]
	local current = if shirt then { Shirt = ShirtGenerator.ToPublic(shirt), Price = entry.Price, ShowOnly = entry.ShowOnly == true } else nil
	openMenuRemote:FireClient(player, key, current, slotLabel(player, key))
end

local function createSlotPrompt(plot: Model, key: string, slot: BasePart, objectText: string)
	local old = slot:FindFirstChildOfClass("ProximityPrompt")
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = objectText
	prompt.ActionText = "วางเสื้อ"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = slot
	prompt.Triggered:Connect(function(player)
		onSlotPrompt(plot, key, player)
	end)
end

local function handleAction(player: Player, action: any, key: any, a: any, b: any, c: any): (boolean, string)
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.25 then
		return false, "กดเร็วเกินไป"
	end
	lastAction[player] = now

	if type(action) ~= "string" or not isValidKey(player, key) then
		return false, "คำสั่งไม่ถูกต้อง"
	end
	local data = DataService:GetData(player)
	local plot = PlotService:GetPlot(player)
	if not data or not plot then
		return false, "ยังโหลดข้อมูลไม่เสร็จ"
	end
	local slot = getSlotPart(plot, key)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not slot or not root or ((root :: BasePart).Position - slot.Position).Magnitude > CONFIG.InteractDistance then
		return false, "ต้องยืนใกล้ ๆ ก่อน"
	end

	local entry = data.Displayed[key]
	if isReserved(player, key) then
		return false, "ลูกค้ากำลังถือเสื้อตัวนี้ไปจ่ายเงิน"
	end

	if action == "Display" then
		local shirtId, price, showOnly = a, b, c == true
		if entry then
			return false, "ช่องนี้มีเสื้ออยู่แล้ว"
		end
		if type(shirtId) ~= "string" or not data.Shirts[shirtId] then
			return false, "ไม่พบเสื้อตัวนี้ในคลัง"
		end
		if isShirtDisplayed(data, shirtId) then
			return false, "เสื้อตัวนี้วางอยู่ที่อื่นแล้ว"
		end
		if showOnly then
			-- วางโชว์: ไม่ต้องมีราคา (ถ้าใส่ราคามาด้วยก็จำไว้ใช้ตอนเปลี่ยนเป็นวางขาย)
			data.Displayed[key] = { ShirtId = shirtId, Price = if isValidPrice(price) then price else nil, ShowOnly = true }
			renderSlot(player, key)
			return true, "วางโชว์ " .. displayName(data.Shirts[shirtId]) .. " แล้ว (ไม่ขาย)"
		end
		if not isValidPrice(price) then
			return false, "ราคาไม่ถูกต้อง (1 - " .. formatMoney(CONFIG.MaxPrice) .. ")"
		end
		data.Displayed[key] = { ShirtId = shirtId, Price = price }
		renderSlot(player, key)
		return true, "วางขาย " .. displayName(data.Shirts[shirtId]) .. " ราคา " .. formatMoney(price)
	elseif action == "ShowOnly" then
		if not entry then
			return false, "ช่องนี้ว่าง"
		end
		entry.ShowOnly = true
		renderSlot(player, key)
		return true, "เปลี่ยนเป็นวางโชว์แล้ว (ไม่ขาย)"
	elseif action == "SetPrice" then
		local price = a
		if not entry then
			return false, "ช่องนี้ว่าง"
		end
		if not isValidPrice(price) then
			return false, "ราคาไม่ถูกต้อง (1 - " .. formatMoney(CONFIG.MaxPrice) .. ")"
		end
		local wasShowOnly = entry.ShowOnly == true
		entry.Price = price
		entry.ShowOnly = nil
		renderSlot(player, key)
		return true, if wasShowOnly then "วางขายราคา " .. formatMoney(price) else "เปลี่ยนราคาเป็น " .. formatMoney(price)
	elseif action == "Unlist" then
		if not entry then
			return false, "ช่องนี้ว่าง"
		end
		data.Displayed[key] = nil
		renderSlot(player, key)
		return true, "เก็บเสื้อกลับเข้าคลังแล้ว"
	end

	return false, "คำสั่งไม่ถูกต้อง"
end

---------------------------------------------------------------------
-- API สำหรับ NPCService
---------------------------------------------------------------------

function ShopService:GetListing(player: Player, key: string): Listing?
	local data = DataService:GetData(player)
	local plot = PlotService:GetPlot(player)
	local entry = data and data.Displayed[key]
	local shirt = entry and data.Shirts[entry.ShirtId]
	if not shirt or not plot or not getSlotPart(plot, key) or entry.ShowOnly or not entry.Price then
		return nil -- ว่าง / วางโชว์อย่างเดียว (ไม่ขาย)
	end
	return {
		Key = key,
		ShirtId = entry.ShirtId,
		Price = entry.Price,
		Shirt = shirt,
		Reserved = isReserved(player, key),
		Bonus = slotBonus(plot, key),
	}
end

-- เสื้อที่ยังโชว์อยู่ (ไม่นับตัวที่ลูกค้าถือไปแล้ว)
function ShopService:GetListings(player: Player): { Listing }
	local list = {}
	local data = DataService:GetData(player)
	if not data then
		return list
	end
	for key in data.Displayed do
		local listing = self:GetListing(player, key)
		if listing and not listing.Reserved then
			table.insert(list, listing)
		end
	end
	return list
end

-- จุดที่ลูกค้าควรยืนดูช่องนี้
function ShopService:GetBrowseInfo(player: Player, key: string): BrowseInfo?
	local plot = PlotService:GetPlot(player)
	local slot = plot and getSlotPart(plot, key)
	if not plot or not slot then
		return nil
	end
	local kind, id = parseKey(key)
	if kind == "base" then
		local browse = plot:FindFirstChild("NpcBrowse", true)
		if browse and browse:IsA("BasePart") then
			return { StopId = "base", Point = browse.Position, LookAt = slot.Position }
		end
		return nil
	end
	local model = getFurnitureModel(plot, id :: string)
	local point = model and model:FindFirstChild("BrowsePoint")
	local area = PlacementRules.GetBuildArea(plot)
	if not point or not point:IsA("BasePart") then
		return nil
	end
	local position = point.Position
	if area then
		-- ยืนบนพื้นในร้าน (กรอบรูปติดผนังอยู่สูง จุดยืนต้องลงมาที่พื้น)
		position = Vector3.new(position.X, PlacementRules.FloorY(area) + 0.5, position.Z)
	end
	return { StopId = id :: string, Point = position, LookAt = slot.Position }
end

-- ลูกค้าตัดสินใจซื้อ: หยิบเสื้อออกจากช่อง (จองไว้ ระหว่างนี้เจ้าของแก้ราคา/เก็บ/ย้ายของไม่ได้)
function ShopService:ReserveForNPC(player: Player, key: string, shirtId: string): boolean
	local listing = self:GetListing(player, key)
	if not listing or listing.ShirtId ~= shirtId or listing.Reserved then
		return false
	end
	reserved[player] = reserved[player] or {}
	reserved[player][key] = true
	renderSlot(player, key)
	return true
end

-- ลูกค้ายกเลิก (รอนานเกิน): เอาเสื้อกลับขึ้นช่อง
function ShopService:ReleaseReservation(player: Player, key: string)
	if reserved[player] then
		reserved[player][key] = nil
	end
	if player.Parent then
		renderSlot(player, key)
	end
end

-- คิดเงินเสร็จ: ตรวจว่ายังเป็นตัวเดิมอยู่ แล้วลบเสื้อ + ให้เงิน (ไม่มี yield = ขายซ้ำไม่ได้)
function ShopService:SellToNPC(player: Player, key: string, shirtId: string): boolean
	local data = DataService:GetData(player)
	local entry = data and data.Displayed[key]
	if not entry or entry.ShirtId ~= shirtId or not data.Shirts[shirtId] then
		return false
	end
	local shirt = data.Shirts[shirtId]
	local price = entry.Price

	if reserved[player] then
		reserved[player][key] = nil
	end
	data.Displayed[key] = nil
	data.Shirts[shirtId] = nil
	data.Stats.ShirtsSold += 1
	DataService:AddMoney(player, price, "SellToNPC")
	renderSlot(player, key)

	Notify(player, "ขาย " .. displayName(shirt) .. " ได้ " .. formatMoney(price) .. "!", "success")
	return true
end

---------------------------------------------------------------------
-- API สำหรับ DecorService
---------------------------------------------------------------------

local function furnitureKeys(id: string, slotCount: number): { string }
	local keys = {}
	for n = 1, slotCount do
		table.insert(keys, id .. ":" .. n)
	end
	return keys
end

-- ของตกแต่งชิ้นนี้มีลูกค้าถือเสื้อจากมันอยู่ไหม (ถ้ามี ห้ามย้าย/ขาย)
function ShopService:IsFurnitureBusy(player: Player, id: string, slotCount: number): boolean
	for _, key in furnitureKeys(id, slotCount) do
		if isReserved(player, key) then
			return true
		end
	end
	return false
end

-- ใส่ปุ่ม E ให้ทุกช่องของของตกแต่ง แล้ววาดเสื้อที่โชว์อยู่ (เรียกหลังวาง/ย้าย/โหลด)
function ShopService:SetupFurnitureSlots(player: Player, plot: Model, id: string, model: Model, def)
	for n = 1, def.Slots do
		local key = id .. ":" .. n
		local slot = model:FindFirstChild("Slot" .. n)
		if slot and slot:IsA("BasePart") then
			createSlotPrompt(plot, key, slot, if def.Slots > 1 then def.DisplayName .. " ช่อง " .. n else def.DisplayName)
		end
		renderSlot(player, key)
	end
end

-- ขายของตกแต่งคืน: เสื้อที่โชว์อยู่กลับเข้าคลัง คืนจำนวนตัวที่เก็บกลับ
function ShopService:ClearFurnitureSlots(player: Player, id: string, slotCount: number): number
	local data = DataService:GetData(player)
	local returned = 0
	for _, key in furnitureKeys(id, slotCount) do
		if data and data.Displayed[key] then
			data.Displayed[key] = nil
			returned += 1
		end
		removeVisual(player, key)
	end
	return returned
end

-- วาดช่องทั้งหมดใหม่หลังโหลดข้อมูล (เรียกโดย DecorService หลังวางของตกแต่งครบแล้ว)
function ShopService:RestoreDisplay(player: Player)
	local data = DataService:GetData(player)
	local plot = PlotService:GetPlot(player)
	if not data or not plot then
		return
	end
	-- ล้างรายการที่ใช้ไม่ได้ (ช่องหาย / เสื้อหายไปแล้ว) เสื้อจะกลับเข้าคลังเอง
	for key, entry in data.Displayed do
		if not isValidKey(player, key) or not getSlotPart(plot, key) or not data.Shirts[entry.ShirtId] then
			data.Displayed[key] = nil
		end
	end
	for index = 1, CONFIG.RackSlots do
		renderSlot(player, tostring(index))
	end
	for key in data.Displayed do
		if not tonumber(key) then
			renderSlot(player, key)
		end
	end
end

---------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------

local function onPlotReleased(player: Player, plot: Model)
	if visuals[player] then
		for key in visuals[player] do
			removeVisual(player, key)
		end
	end
	for index = 1, CONFIG.RackSlots do
		updatePrompt(plot, tostring(index), false)
	end
	visuals[player] = nil
	lastAction[player] = nil
	reserved[player] = nil
end

---------------------------------------------------------------------
-- Init / Start
---------------------------------------------------------------------

function ShopService:Init()
	openMenuRemote = ReplicatedStorage.Remotes.OpenDisplayMenu
end

function ShopService:Start()
	-- ใส่ ProximityPrompt ให้ราวเหล็กเดิมของทุกล็อต
	for _, plot in PlotService:GetAllPlots() do
		local found = 0
		for index = 1, CONFIG.RackSlots do
			local key = tostring(index)
			local slot = getSlotPart(plot, key)
			if slot then
				found += 1
				createSlotPrompt(plot, key, slot, "ราวเหล็ก ช่อง " .. index)
			end
		end
		if found < CONFIG.RackSlots then
			warn(("[ShopService] %s มีช่องแขวน (RackSlots/Slot1..) แค่ %d จาก %d"):format(plot.Name, found, CONFIG.RackSlots))
		end
	end

	local actionRemote = ReplicatedStorage.Remotes.DisplayAction :: RemoteFunction
	actionRemote.OnServerInvoke = handleAction

	PlotService.PlotReleased:Connect(onPlotReleased)
	-- การโหลดเสื้อที่โชว์อยู่ตอนเข้าเกม: DecorService เรียก RestoreDisplay หลังวางของตกแต่งเสร็จ
end

return ShopService

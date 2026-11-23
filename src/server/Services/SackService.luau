-- SackService: กระสอบตั้งแต่เกิดที่โรงงาน → ซื้อ → แบก → วางรอเปิดในร้าน
--
-- สถานะของกระสอบ (State)
--   "ForSale" : วางอยู่บนพาเลทในโรงงาน ใครก็ซื้อได้ (ProximityPrompt)
--   "Carried" : มีเจ้าของแล้ว ติดอยู่บนหลังเจ้าของ คนอื่นแตะไม่ได้
--   "Placed"  : วางในโซนเทปเหลืองที่ร้านแล้ว บันทึกลง Data.PendingSacks รอเปิด (Phase 1 ข้อ 5)
--
-- กติกา
--   * ใครกดซื้อก่อนและเงินพอได้ไป (ตัดสินบน server ไม่มี yield ระหว่างเช็คกับหักเงิน)
--   * แบกได้ทีละ 1 ใบ เดินช้าลง เดินเข้ากรอบเทปเหลืองที่ร้านตัวเอง = วางอัตโนมัติ
--   * ออกจากเกมระหว่างแบก: เงินไม่คืน กระสอบกลับไปที่จุดเดิมในโรงงาน
--     (ถ้าจุดเดิมมีกระสอบใหม่มาแทนแล้ว ใช้จุดว่างอื่น ถ้าโรงงานเต็มทุกจุด กระสอบหายไป)
--   * ตาย/รีเซ็ตระหว่างแบก: กระสอบกลับมาติดหลังตอนเกิดใหม่
--   * กระสอบที่วางในร้านแล้วไม่หาย ออกเกมแล้วเข้าใหม่ก็ยังอยู่

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local StarterPlayer = game:GetService("StarterPlayer")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SackTypes = require(ReplicatedStorage.Shared.Config.SackTypes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local FactoryBuilder = require(script.Parent.Parent.Modules.FactoryBuilder)
local Notify = require(script.Parent.Parent.Modules.Notify)

local CONFIG = GameConfig.Sacks
local SACK_SIZE = Vector3.new(2.6, 3.2, 2.2)
-- ตำแหน่งวางกระสอบในกรอบเทปเหลือง (เทียบกับจุดกลางโซน)
local PLACE_OFFSETS = {
	Vector3.new(-2, 0, -2),
	Vector3.new(2, 0, -2),
	Vector3.new(-2, 0, 2),
	Vector3.new(2, 0, 2),
}
local MAX_PENDING = math.min(CONFIG.MaxPendingSacks, #PLACE_OFFSETS)

type SackState = "ForSale" | "Carried" | "Placed"

type Sack = {
	Id: string,
	TypeId: string,
	Model: Model,
	Body: Part,
	Prompt: ProximityPrompt,
	Billboard: BillboardGui,
	PriceLabel: TextLabel,
	State: SackState,
	Owner: Player?,
	SlotIndex: number?, -- จุดในโรงงาน (ตอนแบกยังจำไว้ เพื่อคืนกลับที่เดิม)
	PlaceIndex: number?, -- ตำแหน่งในกรอบเทปที่ร้าน
	SpawnTime: number,
	CarryWeld: WeldConstraint?,
}

local SackService = {}

local rng = Random.new()
local sacksFolder: Folder
local slots: { BasePart } = {}
local slotOccupant: { [number]: string } = {} -- slotIndex -> sackId
local sacks: { [string]: Sack } = {}
local carriedBy: { [Player]: Sack } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local lastFullNotice: { [Player]: number } = {}
local openHandler: ((Player, Sack) -> ())? = nil -- ตั้งโดย SackOpenService

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function getTorso(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

local function setCarrySpeed(character: Model?, carrying: boolean)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local multiplier = if carrying then CONFIG.CarryWalkSpeedMultiplier else 1
		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed * multiplier
	end
end

local function getSackZone(plot: Model): BasePart?
	local zone = plot:FindFirstChild("SackOpenZone", true)
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function pickSackType(): SackTypes.SackType?
	local enabled = SackTypes.GetEnabled()
	local total = 0
	for _, sackType in enabled do
		total += sackType.SpawnWeight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	for _, sackType in enabled do
		roll -= sackType.SpawnWeight
		if roll <= 0 then
			return sackType
		end
	end
	return enabled[#enabled]
end

---------------------------------------------------------------------
-- Sack model
---------------------------------------------------------------------

local function updateVisual(sack: Sack)
	local sackType = SackTypes.Get(sack.TypeId)
	local forSale = sack.State == "ForSale"

	sack.Billboard.Enabled = sack.State ~= "Carried"
	if forSale and sackType then
		sack.Prompt.Enabled = true
		sack.Prompt.ActionText = "ซื้อ ฿" .. formatMoney(sackType.Price)
		sack.Prompt.HoldDuration = CONFIG.BuyHoldDuration
	elseif sack.State == "Placed" then
		sack.Prompt.Enabled = true
		sack.Prompt.ActionText = "เปิดกระสอบ"
		sack.Prompt.HoldDuration = CONFIG.OpenHoldDuration
	else
		sack.Prompt.Enabled = false
	end
	if forSale and sackType then
		sack.PriceLabel.Text = "฿" .. formatMoney(sackType.Price)
	elseif sack.State == "Placed" then
		sack.PriceLabel.Text = "รอเปิด"
	else
		sack.PriceLabel.Text = ""
	end

	sack.Model:SetAttribute("State", sack.State)
	sack.Model:SetAttribute("OwnerUserId", if sack.Owner then sack.Owner.UserId else 0)
end

local onPromptTriggered: (Sack, Player) -> () -- ประกาศไว้ก่อน (นิยามด้านล่าง)

local function createSack(typeId: string, id: string?): Sack?
	local sackType = SackTypes.Get(typeId)
	if not sackType then
		warn("[SackService] ไม่รู้จักกระสอบประเภท " .. tostring(typeId))
		return nil
	end
	local sackId = id or HttpService:GenerateGUID(false)

	local model = Instance.new("Model")
	model.Name = "Sack_" .. sackType.Id

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = SACK_SIZE
	body.Color = sackType.Color
	body.Material = Enum.Material.Fabric
	body.Anchored = true
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	-- ปากกระสอบที่มัดไว้
	local neck = Instance.new("Part")
	neck.Name = "Neck"
	neck.Size = Vector3.new(1, 0.7, 1)
	neck.Color = sackType.Color:Lerp(Color3.new(0, 0, 0), 0.3)
	neck.Material = Enum.Material.Fabric
	neck.Anchored = true
	neck.CanCollide = false
	neck.CFrame = body.CFrame * CFrame.new(0, SACK_SIZE.Y / 2 + 0.35, 0)
	neck.Parent = model
	local neckWeld = Instance.new("WeldConstraint")
	neckWeld.Part0 = body
	neckWeld.Part1 = neck
	neckWeld.Parent = body

	-- ป้ายชื่อ + ราคาลอยเหนือกระสอบ
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(170, 52)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	billboard.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.fromScale(1, 0.5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = sackType.Color
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Text = sackType.DisplayName
	nameLabel.Parent = billboard

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Size = UDim2.fromScale(1, 0.5)
	priceLabel.Position = UDim2.fromScale(0, 0.5)
	priceLabel.BackgroundTransparency = 1
	priceLabel.TextScaled = true
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextColor3 = Color3.fromRGB(255, 235, 120)
	priceLabel.TextStrokeTransparency = 0.2
	priceLabel.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "ซื้อ ฿" .. formatMoney(sackType.Price)
	prompt.ObjectText = sackType.DisplayName
	prompt.HoldDuration = CONFIG.BuyHoldDuration
	prompt.MaxActivationDistance = CONFIG.BuyDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	model.PrimaryPart = body
	model:SetAttribute("SackId", sackId)
	model:SetAttribute("SackType", sackType.Id)
	model.Parent = sacksFolder

	local sack: Sack = {
		Id = sackId,
		TypeId = sackType.Id,
		Model = model,
		Body = body,
		Prompt = prompt,
		Billboard = billboard,
		PriceLabel = priceLabel,
		State = "ForSale",
		Owner = nil,
		SlotIndex = nil,
		PlaceIndex = nil,
		SpawnTime = os.clock(),
		CarryWeld = nil,
	}
	sacks[sackId] = sack

	prompt.Triggered:Connect(function(player)
		onPromptTriggered(sack, player)
	end)

	return sack
end

local function destroySack(sack: Sack)
	if sack.SlotIndex and slotOccupant[sack.SlotIndex] == sack.Id then
		slotOccupant[sack.SlotIndex] = nil
	end
	if sack.Owner and carriedBy[sack.Owner] == sack then
		carriedBy[sack.Owner] = nil
	end
	sacks[sack.Id] = nil
	sack.Model:Destroy()
end

---------------------------------------------------------------------
-- Factory slots
---------------------------------------------------------------------

local function findFreeSlot(preferred: number?): number?
	if preferred and slots[preferred] and slotOccupant[preferred] == nil then
		return preferred
	end
	local free = {}
	for index in slots do
		if slotOccupant[index] == nil then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng:NextInteger(1, #free)]
end

local function putInSlot(sack: Sack, index: number)
	slotOccupant[index] = sack.Id
	sack.SlotIndex = index
	sack.PlaceIndex = nil
	sack.State = "ForSale"
	sack.Owner = nil
	sack.SpawnTime = os.clock()
	sack.Model:PivotTo(slots[index].CFrame * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0))
	updateVisual(sack)
end

local function spawnRandomSack()
	local index = findFreeSlot()
	local sackType = pickSackType()
	if not index or not sackType then
		return
	end
	local sack = createSack(sackType.Id)
	if sack then
		putInSlot(sack, index)
	end
end

---------------------------------------------------------------------
-- Carry
---------------------------------------------------------------------

local function setPhysicsForCarry(sack: Sack, carrying: boolean)
	for _, descendant in sack.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = not carrying
			descendant.Massless = carrying
			descendant.CanCollide = (not carrying) and descendant == sack.Body
		end
	end
end

local function attach(sack: Sack, character: Model): boolean
	local torso = getTorso(character)
	if not torso then
		return false
	end
	if sack.CarryWeld then
		sack.CarryWeld:Destroy()
	end
	-- วางไว้ด้านหลังลำตัว (+Z ของ torso คือด้านหลัง)
	sack.Model:PivotTo(torso.CFrame * CFrame.new(0, 0.2, 1.7))
	setPhysicsForCarry(sack, true)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = torso
	weld.Part1 = sack.Body
	weld.Parent = sack.Body
	sack.CarryWeld = weld
	setCarrySpeed(character, true)
	return true
end

local function detach(sack: Sack)
	if sack.CarryWeld then
		sack.CarryWeld:Destroy()
		sack.CarryWeld = nil
	end
	setPhysicsForCarry(sack, false)
	if sack.Owner then
		setCarrySpeed(sack.Owner.Character, false)
	end
end

local function returnToFactory(sack: Sack)
	detach(sack)
	if sack.Owner and carriedBy[sack.Owner] == sack then
		carriedBy[sack.Owner] = nil
	end
	sack.Owner = nil
	local index = findFreeSlot(sack.SlotIndex)
	if index then
		putInSlot(sack, index)
	else
		destroySack(sack)
	end
end

---------------------------------------------------------------------
-- Placing in shop
---------------------------------------------------------------------

local function positionInZone(sack: Sack, zone: BasePart, placeIndex: number)
	local offset = PLACE_OFFSETS[placeIndex]
	-- ก้นกระสอบวางบนพื้น (ขอบล่างของโซน)
	local y = -zone.Size.Y / 2 + SACK_SIZE.Y / 2
	sack.Model:PivotTo(zone.CFrame * CFrame.new(offset.X, y, offset.Z) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0))
end

local function freePlaceIndex(player: Player): number?
	local used = {}
	for _, sack in sacks do
		if sack.State == "Placed" and sack.Owner == player and sack.PlaceIndex then
			used[sack.PlaceIndex] = true
		end
	end
	for index = 1, MAX_PENDING do
		if not used[index] then
			return index
		end
	end
	return nil
end

local function notifyZoneFull(player: Player)
	local now = os.clock()
	if now - (lastFullNotice[player] or 0) > 4 then
		lastFullNotice[player] = now
		Notify(player, ("กรอบวางกระสอบเต็มแล้ว (สูงสุด %d ใบ) เปิดกระสอบที่มีอยู่ก่อนนะ"):format(MAX_PENDING), "error")
	end
end

local function placeInShop(sack: Sack, player: Player, zone: BasePart)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local placeIndex = freePlaceIndex(player)
	if #data.PendingSacks >= MAX_PENDING or not placeIndex then
		notifyZoneFull(player)
		return
	end

	detach(sack)
	carriedBy[player] = nil
	sack.State = "Placed"
	sack.SlotIndex = nil
	sack.PlaceIndex = placeIndex
	table.insert(data.PendingSacks, { Id = sack.Id, TypeId = sack.TypeId })

	positionInZone(sack, zone, placeIndex)
	updateVisual(sack)
	Notify(player, "วางกระสอบในร้านแล้ว!", "success")
end

-- ตรวจทุก 0.2 วินาทีว่าคนที่แบกอยู่เดินเข้ากรอบเทปที่ร้านตัวเองหรือยัง
local function checkCarriers()
	for player, sack in carriedBy do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local plot = PlotService:GetPlot(player)
		local zone = plot and getSackZone(plot)
		if root and zone and sack.CarryWeld then
			local rel = zone.CFrame:PointToObjectSpace((root :: BasePart).Position)
			if math.abs(rel.X) <= zone.Size.X / 2 + 1 and math.abs(rel.Z) <= zone.Size.Z / 2 + 1 and math.abs(rel.Y) < 6 then
				placeInShop(sack, player, zone)
			end
		end
	end
end

---------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------

function onPromptTriggered(sack: Sack, player: Player)
	if sacks[sack.Id] ~= sack then
		return
	end
	if sack.State == "Placed" then
		if openHandler then
			openHandler(player, sack)
		end
		return
	end
	if sack.State ~= "ForSale" then
		return -- มีคนซื้อตัดหน้าไปแล้ว
	end
	if carriedBy[player] then
		Notify(player, "แบกกระสอบอยู่แล้ว เอาไปวางที่ร้านก่อน", "error")
		return
	end
	if not PlotService:GetPlot(player) then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return
	end
	if ((root :: BasePart).Position - sack.Body.Position).Magnitude > CONFIG.BuyDistance + 4 then
		return
	end

	local sackType = SackTypes.Get(sack.TypeId)
	if not sackType then
		return
	end
	if not DataService:TrySpend(player, sackType.Price, "BuySack") then
		Notify(player, "เงินไม่พอ! ต้องใช้ ฿" .. formatMoney(sackType.Price), "error")
		return
	end

	-- ปล่อยจุดในโรงงานให้กระสอบใหม่เกิดได้ แต่ยังจำ SlotIndex ไว้เผื่อต้องคืนที่เดิม
	if sack.SlotIndex and slotOccupant[sack.SlotIndex] == sack.Id then
		slotOccupant[sack.SlotIndex] = nil
	end
	sack.State = "Carried"
	sack.Owner = player
	carriedBy[player] = sack
	updateVisual(sack)
	attach(sack, character :: Model)

	Notify(player, "ซื้อ " .. sackType.DisplayName .. " แล้ว! แบกไปวางในกรอบเทปเหลืองที่ร้าน", "success")
end

---------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------

local function restorePendingSacks(player: Player)
	local data = DataService:WaitForData(player)
	if not data then
		return
	end
	local plot
	for _ = 1, 100 do
		plot = PlotService:GetPlot(player)
		if plot or player.Parent == nil then
			break
		end
		task.wait(0.1)
	end
	local zone = plot and getSackZone(plot)
	if not zone or player.Parent == nil then
		return
	end

	for index, entry in data.PendingSacks do
		if index > MAX_PENDING then
			break
		end
		local sack = createSack(entry.TypeId, entry.Id)
		if sack then
			sack.State = "Placed"
			sack.Owner = player
			sack.PlaceIndex = index
			positionInZone(sack, zone, index)
			updateVisual(sack)
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local sack = carriedBy[player]
	if not sack then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait() -- รอให้ลำตัวโหลดครบ
	if carriedBy[player] == sack and getTorso(character) then
		attach(sack, character)
	end
end

local function onCharacterRemoving(player: Player)
	-- ตัวละครกำลังจะหาย: แขวนกระสอบไว้กลางอากาศก่อน ไม่ให้ร่วงหาย แล้วติดใหม่ตอนเกิด
	local sack = carriedBy[player]
	if sack and sack.CarryWeld then
		sack.CarryWeld:Destroy()
		sack.CarryWeld = nil
		setPhysicsForCarry(sack, false)
	end
end

local function onPlayerAdded(player: Player)
	playerConnections[player] = {
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end),
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end),
	}
	task.spawn(restorePendingSacks, player)
end

local function onPlayerRemoving(player: Player)
	for _, connection in playerConnections[player] or {} do
		connection:Disconnect()
	end
	playerConnections[player] = nil
	lastFullNotice[player] = nil

	-- ออกระหว่างแบก: เงินไม่คืน กระสอบกลับโรงงาน
	local carried = carriedBy[player]
	if carried then
		returnToFactory(carried)
	end

	-- กระสอบที่วางในร้านแล้ว: เอาโมเดลออก (ข้อมูลยังอยู่ใน Data.PendingSacks)
	for _, sack in sacks do
		if sack.Owner == player then
			destroySack(sack)
		end
	end
end

---------------------------------------------------------------------
-- Public API (ใช้ใน SackOpenService)
---------------------------------------------------------------------

function SackService:SetOpenHandler(handler: (Player, Sack) -> ())
	openHandler = handler
end

-- ใช้กระสอบที่วางในร้าน (ตอนเปิด): ลบออกจาก Data.PendingSacks และลบโมเดล
-- คืน true ถ้าสำเร็จ (ไม่มี yield จึงเรียกซ้อนกันแล้วใช้กระสอบเดียวซ้ำไม่ได้)
function SackService:ConsumePlacedSack(player: Player, sack: Sack): boolean
	if sacks[sack.Id] ~= sack or sack.State ~= "Placed" or sack.Owner ~= player then
		return false
	end
	local data = DataService:GetData(player)
	if not data then
		return false
	end
	local removed = false
	for index, entry in data.PendingSacks do
		if entry.Id == sack.Id then
			table.remove(data.PendingSacks, index)
			removed = true
			break
		end
	end
	if not removed then
		return false
	end
	destroySack(sack)
	return true
end

function SackService:GetPlacedSacks(player: Player): { Sack }
	local result = {}
	for _, sack in sacks do
		if sack.State == "Placed" and sack.Owner == player then
			table.insert(result, sack)
		end
	end
	return result
end

---------------------------------------------------------------------
-- Init / Start
---------------------------------------------------------------------

function SackService:Init()
	sacksFolder = Instance.new("Folder")
	sacksFolder.Name = "Sacks"
	sacksFolder.Parent = workspace

	local factory = workspace:FindFirstChild("Factory") or FactoryBuilder.Build(CONFIG.SlotCount)
	local slotsFolder = factory:FindFirstChild("SackSlots")
	assert(slotsFolder, "[SackService] Workspace.Factory ต้องมีโฟลเดอร์ SackSlots")

	for _, child in slotsFolder:GetChildren() do
		local index = tonumber(child.Name:match("^Slot(%d+)$"))
		if index and child:IsA("BasePart") then
			slots[index] = child
		end
	end
	assert(next(slots) ~= nil, "[SackService] ไม่พบ Part ชื่อ Slot1, Slot2, ... ใน Factory.SackSlots")
end

function SackService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- เกิดกระสอบ
	task.spawn(function()
		for _ = 1, CONFIG.InitialSpawnCount do
			spawnRandomSack()
		end
		while true do
			task.wait(rng:NextNumber(CONFIG.SpawnIntervalMin, CONFIG.SpawnIntervalMax))
			spawnRandomSack()
		end
	end)

	-- กระสอบที่ไม่มีใครซื้อนานเกินไปจะหายไป
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for _, sack in sacks do
				if sack.State == "ForSale" and now - sack.SpawnTime > CONFIG.DespawnTime then
					destroySack(sack)
				end
			end
		end
	end)

	-- ตรวจการวางกระสอบในร้าน
	task.spawn(function()
		while true do
			task.wait(0.2)
			checkCarriers()
		end
	end)
end

return SackService

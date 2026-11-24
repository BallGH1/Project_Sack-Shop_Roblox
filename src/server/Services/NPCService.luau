-- NPCService: NPC ลูกค้าเดินเข้าร้าน ดูเสื้อบนราว แล้วตัดสินใจซื้อ (ตัดสินบน server ทั้งหมด)
--
-- สูตรตาม GDD ข้อ 7.2
--   perceivedValue = trueValue            (เสื้อส่งเกรดแล้ว)
--                  = trueValue × 0.8–1.0  (ยังไม่ส่งเกรด NPC ไม่ค่อยไว้ใจ)
--   ratio = ราคาที่ตั้ง / perceivedValue
--     ≤ 0.8     ซื้อแน่นอน
--     0.8–1.0   95% → 70%
--     1.0–1.2   70% → 30%
--     1.2–1.5   30% → 5%
--     > 1.5     ไม่ซื้อ ("แพงไป!")
--
-- ขั้นตอนลูกค้า: เดินเข้าร้าน → ดูราว → ถูกใจหยิบเสื้อ → ถือไปต่อคิวที่เคาน์เตอร์
--   → เจ้าของร้านกด "คิดเงิน" (อนาคต: พนักงานแคชเชียร์กดให้) → ได้เงิน
--   → ถ้ารอนานเกิน CheckoutPatience ลูกค้าวางเสื้อคืนราวแล้วเดินออก
-- NPC มาเฉพาะร้านที่มีเจ้าของ + มีเสื้อแขวนอยู่
-- แต่ละร้านต้องมีจุด Fixtures: NpcSpawn, NpcEntrance, NpcBrowse, NpcAisle, CheckoutSpot1/2, Register

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)

local CONFIG = GameConfig.Shop.Customer

local NPCService = {}

local rng = Random.new()
local npcFolder: Folder
local customers: { [Player]: { [Model]: boolean } } = {}
local nextSpawn: { [Player]: number } = {}

local SKIN_COLORS = {
	Color3.fromRGB(255, 220, 190),
	Color3.fromRGB(234, 190, 150),
	Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(150, 105, 75),
	Color3.fromRGB(105, 70, 50),
}
local SHIRT_COLORS = {
	Color3.fromRGB(200, 60, 60),
	Color3.fromRGB(60, 110, 200),
	Color3.fromRGB(240, 240, 235),
	Color3.fromRGB(40, 40, 45),
	Color3.fromRGB(90, 160, 90),
	Color3.fromRGB(240, 190, 60),
	Color3.fromRGB(150, 90, 180),
}
local PANTS_COLORS = {
	Color3.fromRGB(50, 60, 90),
	Color3.fromRGB(35, 35, 40),
	Color3.fromRGB(110, 95, 75),
	Color3.fromRGB(80, 80, 85),
}

---------------------------------------------------------------------
-- Buy decision
---------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function buyChance(ratio: number): number
	if ratio <= 0.8 then
		return 1
	elseif ratio <= 1.0 then
		return lerp(0.95, 0.70, (ratio - 0.8) / 0.2)
	elseif ratio <= 1.2 then
		return lerp(0.70, 0.30, (ratio - 1.0) / 0.2)
	elseif ratio <= 1.5 then
		return lerp(0.30, 0.05, (ratio - 1.2) / 0.3)
	end
	return 0
end

local function reactionText(ratio: number): string
	if ratio <= 0.8 then
		return "ถูกจัง!"
	elseif ratio <= 1.0 then
		return "ราคาดีนะ..."
	elseif ratio <= 1.2 then
		return "ก็พอได้ ขอคิดดูก่อน"
	elseif ratio <= 1.5 then
		return "แพงไปหน่อย"
	end
	return "แพงไป!"
end

local function evaluate(listing): number
	local shirt = listing.Shirt
	local perceived = if shirt.IsGraded then shirt.TrueValue else shirt.TrueValue * rng:NextNumber(0.8, 1.0)
	-- ตู้โชว์ / กรอบรูป ทำให้เสื้อดูมีค่ากว่า ลูกค้ายอมจ่ายเพิ่ม
	perceived *= 1 + (listing.Bonus or 0)
	return listing.Price / math.max(perceived, 1)
end

---------------------------------------------------------------------
-- NPC model
---------------------------------------------------------------------

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function createCustomer(): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = pick(SKIN_COLORS)
	local shirt = pick(SHIRT_COLORS)
	local pants = pick(PANTS_COLORS)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = shirt
	description.LeftLegColor = pants
	description.RightLegColor = pants

	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("[NPCService] สร้าง NPC ไม่สำเร็จ: " .. tostring(npc))
		return nil
	end

	npc.Name = "Customer"
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = CONFIG.WalkSpeed
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- ฟองคำพูดเหนือหัว
	local head = npc:FindFirstChild("Head")
	if head then
		local bubble = Instance.new("BillboardGui")
		bubble.Name = "Bubble"
		bubble.Size = UDim2.fromOffset(180, 40)
		bubble.StudsOffset = Vector3.new(0, 2.6, 0)
		bubble.MaxDistance = 60
		bubble.Enabled = false
		bubble.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.new(1, 1, 1)
		label.TextColor3 = Color3.fromRGB(30, 30, 30)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = bubble
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = label
	end

	return npc
end

local function say(npc: Model, text: string)
	local head = npc:FindFirstChild("Head")
	local bubble = head and head:FindFirstChild("Bubble")
	if not bubble then
		return
	end
	local label = bubble:FindFirstChild("Text") :: TextLabel
	label.Text = text
	bubble.Enabled = true
	task.delay(2.5, function()
		if label.Parent and label.Text == text then
			bubble.Enabled = false
		end
	end)
end

-- เดินไปที่จุดหมาย ถ้าติดนานเกินไปวาร์ปไปเลย (กันลูกค้าค้างกลางทาง)
local function walkTo(npc: Model, target: Vector3)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid or not npc.Parent then
		return
	end
	local done, reached = false, false
	local connection = humanoid.MoveToFinished:Connect(function(success)
		done, reached = true, success
	end)
	humanoid:MoveTo(target)
	local elapsed = 0
	while not done and elapsed < 12 and npc.Parent do
		elapsed += task.wait(0.2)
	end
	connection:Disconnect()
	if not reached and npc.Parent then
		npc:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
	end
end

-- เดินแบบหาทางอ้อมของที่ขวาง (ของตกแต่งที่ผู้เล่นวางเอง) ถ้าหาทางไม่ได้เดินตรง ๆ
local function walkPath(npc: Model, target: Vector3)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not npc.Parent then
		return
	end
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local ok = pcall(function()
		path:ComputeAsync(root.Position, target)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		for _, waypoint in path:GetWaypoints() do
			if not npc.Parent then
				return
			end
			walkTo(npc, waypoint.Position)
		end
	else
		walkTo(npc, target)
	end
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

---------------------------------------------------------------------
-- Customer visit
---------------------------------------------------------------------

type QueueEntry = {
	Npc: Model,
	Key: string, -- ช่องที่หยิบเสื้อมา
	ShirtId: string,
	Price: number,
	Arrived: boolean, -- ยืนถึงหน้าเคาน์เตอร์แล้ว
	Paid: boolean,
}

local queues: { [Player]: { QueueEntry } } = {}
local registerPrompts: { [Model]: ProximityPrompt } = {}

local function countCustomers(player: Player): number
	local count = 0
	for _ in customers[player] or {} do
		count += 1
	end
	return count
end

local function formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "฿" .. (formatted:gsub("^,", ""))
end

-- ปุ่ม "คิดเงิน" ที่เคาน์เตอร์: เปิดเฉพาะตอนมีลูกค้ายืนรอคนแรกในคิว
local function updateRegister(player: Player)
	local plot = PlotService:GetPlot(player)
	local prompt = plot and registerPrompts[plot]
	if not prompt then
		return
	end
	local first = queues[player] and queues[player][1]
	if first and first.Arrived then
		prompt.Enabled = true
		prompt.ActionText = "คิดเงิน " .. formatMoney(first.Price)
	else
		prompt.Enabled = false
	end
end

local function removeFromQueue(player: Player, entry: QueueEntry)
	local queue = queues[player]
	if not queue then
		return
	end
	local position = table.find(queue, entry)
	if position then
		table.remove(queue, position)
	end
	updateRegister(player)
end

-- เสื้อพับในมือลูกค้า (สีตาม rarity)
local function holdShirt(npc: Model, rarityName: string)
	local hand = npc:FindFirstChild("RightHand") or npc:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local rarity = Rarities.ByName[rarityName] or Rarities.List[1]
	local held = Instance.new("Part")
	held.Name = "HeldShirt"
	held.Size = Vector3.new(1.3, 0.35, 1)
	held.Color = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.25)
	held.Material = Enum.Material.Fabric
	held.CanCollide = false
	held.CanQuery = false
	held.CanTouch = false
	held.Massless = true
	held.CFrame = hand.CFrame * CFrame.new(0, -0.5, -0.4)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = held
	weld.Parent = held
	held.Parent = npc
end

local function dropHeldShirt(npc: Model)
	local held = npc:FindFirstChild("HeldShirt")
	if held then
		held:Destroy()
	end
end

local function faceTowards(npc: Model, target: Vector3)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.X, root.Position.Y, target.Z))
	end
end

-- คิดเงินลูกค้าคนแรกในคิว
-- ตอนนี้เรียกจากปุ่มของเจ้าของร้าน / อนาคต: พนักงานแคชเชียร์ที่จ้างไว้เรียกฟังก์ชันนี้เองอัตโนมัติ
function NPCService:CheckoutNext(player: Player): boolean
	local queue = queues[player]
	local first = queue and queue[1]
	if not first or not first.Arrived or first.Paid then
		return false
	end
	local sold = ShopService:SellToNPC(player, first.Key, first.ShirtId)
	-- ขายไม่สำเร็จ (เสื้อหายไประหว่างทาง ไม่ควรเกิด) ก็ปล่อยลูกค้าออกไปเฉย ๆ
	first.Paid = true
	removeFromQueue(player, first)
	return sold
end

-- ต่อคิวที่เคาน์เตอร์ แล้วรอจนกว่าจะได้คิดเงิน หรือหมดความอดทน คืน true ถ้าจ่ายแล้ว
local function waitForCheckout(player: Player, plot: Model, npc: Model, entry: QueueEntry, stillValid: () -> boolean): boolean
	local spot1 = plot:FindFirstChild("CheckoutSpot1", true) :: BasePart?
	local spot2 = plot:FindFirstChild("CheckoutSpot2", true) :: BasePart?
	local register = plot:FindFirstChild("Register", true) :: BasePart?
	if not spot1 then
		return false
	end

	queues[player] = queues[player] or {}
	table.insert(queues[player], entry)

	local deadline = os.clock() + CONFIG.CheckoutPatience
	local warned = false
	local currentSpot: BasePart? = nil

	while stillValid() and not entry.Paid do
		local queue = queues[player]
		local position = if queue then table.find(queue, entry) else nil
		if not position then
			break
		end

		-- เดินไปตำแหน่งคิวของตัวเอง (คนแรก = หน้าเคาน์เตอร์, ที่เหลือต่อคิวช่อง 2)
		local targetSpot = if position == 1 then spot1 else (spot2 or spot1)
		if targetSpot ~= currentSpot then
			currentSpot = targetSpot
			entry.Arrived = false
			updateRegister(player)
			walkPath(npc, targetSpot.Position)
			if register then
				faceTowards(npc, register.Position)
			end
			entry.Arrived = position == 1
			updateRegister(player)
			if position == 1 then
				say(npc, "คิดเงินด้วยครับ")
			end
		end

		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		elseif remaining <= 12 and not warned then
			warned = true
			say(npc, "เร็ว ๆ หน่อยได้ไหม...")
		end
		task.wait(0.25)
	end

	if not entry.Paid then
		removeFromQueue(player, entry)
	end
	return entry.Paid
end

local function runCustomer(player: Player, plot: Model)
	local spawnPoint = plot:FindFirstChild("NpcSpawn", true) :: BasePart?
	local entrance = plot:FindFirstChild("NpcEntrance", true) :: BasePart?
	local browse = plot:FindFirstChild("NpcBrowse", true) :: BasePart?
	local aisle = plot:FindFirstChild("NpcAisle", true) :: BasePart?
	if not (spawnPoint and entrance and browse) then
		return
	end

	local npc = createCustomer()
	if not npc then
		return
	end
	customers[player] = customers[player] or {}
	customers[player][npc] = true

	local function stillValid(): boolean
		return npc.Parent ~= nil and player.Parent ~= nil and PlotService:GetPlot(player) == plot
	end

	npc:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))
	npc.Parent = npcFolder
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil) -- ให้ server คุมการเดิน
		end)
	end

	walkTo(npc, entrance.Position)

	-- 1) เดินดูของในร้านทีละจุด (ราวเดิม / ราวตากผ้า / ตู้โชว์ / กรอบรูป) ถ้าถูกใจหยิบไป 1 ตัว
	local picked = nil
	if stillValid() then
		-- จัดกลุ่มเสื้อตามจุดที่ยืนดู (ราวเดียวกัน = ยืนดูที่เดียว)
		local stops = {}
		local stopList = {}
		for _, listing in ShopService:GetListings(player) do
			local info = ShopService:GetBrowseInfo(player, listing.Key)
			if info then
				local stop = stops[info.StopId]
				if not stop then
					stop = { Point = info.Point, Items = {} }
					stops[info.StopId] = stop
					table.insert(stopList, stop)
				end
				table.insert(stop.Items, { Key = listing.Key, ShirtId = listing.ShirtId, LookAt = info.LookAt })
			end
		end
		shuffle(stopList)

		for stopIndex, stop in stopList do
			if stopIndex > CONFIG.MaxStops or picked or not stillValid() then
				break
			end
			walkPath(npc, stop.Point)
			shuffle(stop.Items)
			for _, item in stop.Items do
				if not stillValid() then
					break
				end
				faceTowards(npc, item.LookAt)
				task.wait(CONFIG.LookTime)
				if not stillValid() then
					break
				end
				-- อ่านข้อมูลล่าสุด แล้วตัดสินใจ + หยิบในจังหวะเดียว (ไม่มี yield คั่น)
				local listing = ShopService:GetListing(player, item.Key)
				if listing and listing.ShirtId == item.ShirtId and not listing.Reserved then
					local ratio = evaluate(listing)
					if rng:NextNumber() < buyChance(ratio) then
						if ShopService:ReserveForNPC(player, listing.Key, listing.ShirtId) then
							picked = { Key = listing.Key, ShirtId = listing.ShirtId, Price = listing.Price }
							holdShirt(npc, listing.Shirt.Rarity)
							say(npc, "เอาตัวนี้!")
							break
						end
					else
						say(npc, reactionText(ratio))
					end
				end
			end
		end
		task.wait(1.2)
	end

	-- 2) ถือเสื้อไปจ่ายเงินที่เคาน์เตอร์
	if picked and stillValid() then
		if aisle then
			walkPath(npc, aisle.Position)
		end
		local entry: QueueEntry = {
			Npc = npc,
			Key = picked.Key,
			ShirtId = picked.ShirtId,
			Price = picked.Price,
			Arrived = false,
			Paid = false,
		}
		local paid = waitForCheckout(player, plot, npc, entry, stillValid)
		if paid then
			say(npc, "ขอบคุณครับ!")
		else
			-- ไม่ได้จ่าย: วางเสื้อคืนราว
			ShopService:ReleaseReservation(player, picked.Key)
			dropHeldShirt(npc)
			if stillValid() then
				say(npc, "รอนานจัง ไม่เอาแล้ว!")
			end
		end
		task.wait(1)
		if aisle and npc.Parent then
			walkPath(npc, aisle.Position)
		end
	elseif picked then
		-- เจ้าของออกเกมระหว่างทาง: คืนการจอง (ข้อมูลเสื้อยังอยู่บนราวตามเดิม)
		ShopService:ReleaseReservation(player, picked.Key)
	end

	-- 3) เดินออกจากร้าน
	if npc.Parent then
		walkPath(npc, entrance.Position)
		walkTo(npc, spawnPoint.Position)
	end

	if customers[player] then
		customers[player][npc] = nil
	end
	npc:Destroy()
end

---------------------------------------------------------------------
-- Scheduler
---------------------------------------------------------------------

local function scheduleNext(player: Player, listingCount: number)
	local base = rng:NextNumber(CONFIG.IntervalMin, CONFIG.IntervalMax)
	local speedup = 1 + CONFIG.PerShirtSpeedup * math.max(listingCount - 1, 0)
	nextSpawn[player] = os.clock() + base / speedup
end

local function update()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local plot = PlotService:GetPlot(player)
		local listingCount = if plot then #ShopService:GetListings(player) else 0
		if listingCount == 0 then
			nextSpawn[player] = nil
		elseif not nextSpawn[player] then
			-- เพิ่งเริ่มวางขาย: ลูกค้าคนแรกมาเร็วหน่อย
			nextSpawn[player] = now + rng:NextNumber(3, 6)
		elseif now >= nextSpawn[player] then
			if countCustomers(player) < CONFIG.MaxPerShop then
				task.spawn(runCustomer, player, plot :: Model)
			end
			scheduleNext(player, listingCount)
		end
	end
end

local function onPlayerRemoving(player: Player)
	nextSpawn[player] = nil
	queues[player] = nil
	local list = customers[player]
	customers[player] = nil
	if list then
		for npc in list do
			npc:Destroy()
		end
	end
end

---------------------------------------------------------------------
-- Init / Start
---------------------------------------------------------------------

function NPCService:Init()
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "NPCs"
	npcFolder.Parent = workspace
end

function NPCService:Start()
	-- ปุ่ม "คิดเงิน" ที่เครื่องคิดเงินของทุกร้าน (เฉพาะเจ้าของร้านกดได้)
	for _, plot in PlotService:GetAllPlots() do
		local register = plot:FindFirstChild("Register", true)
		if register and register:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = "เครื่องคิดเงิน"
			prompt.ActionText = "คิดเงิน"
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false
			prompt.Parent = register
			registerPrompts[plot] = prompt
			prompt.Triggered:Connect(function(player)
				if PlotService:GetOwner(plot) == player then
					self:CheckoutNext(player)
				end
			end)
		else
			warn("[NPCService] " .. plot.Name .. " ไม่มี Fixtures.Register (เครื่องคิดเงิน)")
		end
	end
	PlotService.PlotReleased:Connect(function(_player, plot)
		local prompt = registerPrompts[plot]
		if prompt then
			prompt.Enabled = false
		end
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	task.spawn(function()
		while true do
			task.wait(1)
			update()
		end
	end)
end

return NPCService

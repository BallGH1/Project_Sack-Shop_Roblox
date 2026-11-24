-- DecorService: ซื้อ / วาง / ย้าย / ขายคืนของตกแต่งร้าน (ตัดสินบน server ทั้งหมด)
--
-- Remotes.DecorAction (RemoteFunction):
--   ("Place", typeId, payload)  ซื้อ + วางของชิ้นใหม่
--   ("Move", furnitureId, payload)
--   ("Remove", furnitureId)     ขายคืน ได้เงินกลับ RefundRate และเสื้อที่โชว์อยู่กลับเข้าคลัง
-- payload = ตำแหน่งบนพื้นผิว (ดู PlacementRules) ไม่ใช่ CFrame → server คำนวณตำแหน่งจริงเอง
--
-- Data.Furniture[furnitureId] = { Type, X, Z, Rot } (พื้น) หรือ { Type, Wall, U, V } (ผนัง)
-- เก็บตำแหน่งเทียบกับร้าน ไม่ใช่พิกัดในแมพ → เข้าเซิร์ฟใหม่ได้ล็อตไหนก็วางกลับได้เหมือนเดิม

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Furniture = require(ReplicatedStorage.Shared.Config.Furniture)
local FurnitureBuilder = require(ReplicatedStorage.Shared.Building.FurnitureBuilder)
local PlacementRules = require(ReplicatedStorage.Shared.Building.PlacementRules)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)

local CONFIG = GameConfig.Decor

local DecorService = {}

local lastAction: { [Player]: number } = {}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "฿" .. (formatted:gsub("^,", ""))
end

local function getFolder(plot: Model): Folder
	local folder = plot:FindFirstChild("Furniture")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Furniture"
		folder.Parent = plot
	end
	return folder :: Folder
end

local function countFurniture(data): number
	local count = 0
	for _ in data.Furniture do
		count += 1
	end
	return count
end

local function spawnFurniture(player: Player, plot: Model, id: string, entry): Model?
	local def = Furniture.Get(entry.Type)
	if not def then
		return nil
	end
	local cframe = PlacementRules.ResolveEntry(plot, def, entry)
	if not cframe then
		return nil
	end
	local model = FurnitureBuilder.Build(def)
	model.Name = id
	model:SetAttribute("FurnitureId", id)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:PivotTo(cframe)
	model.Parent = getFolder(plot)
	ShopService:SetupFurnitureSlots(player, plot, id, model, def)
	return model
end

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

local function place(player: Player, data, plot: Model, typeId: any, payload: any): (boolean, string)
	local def = type(typeId) == "string" and Furniture.Get(typeId)
	if not def then
		return false, "ไม่รู้จักของชิ้นนี้"
	end
	if countFurniture(data) >= CONFIG.MaxFurniture then
		return false, ("วางของได้สูงสุด %d ชิ้น"):format(CONFIG.MaxFurniture)
	end
	local entry = PlacementRules.Sanitize(def, payload)
	if not entry then
		return false, "ตำแหน่งไม่ถูกต้อง"
	end
	local cframe, wall = PlacementRules.ResolveEntry(plot, def, entry)
	if not cframe then
		return false, "ตำแหน่งไม่ถูกต้อง"
	end
	local ok, reason = PlacementRules.Validate(plot, def, cframe, nil, wall)
	if not ok then
		return false, reason or "วางตรงนี้ไม่ได้"
	end
	-- ตรวจครบแล้วค่อยหักเงิน (ไม่มี yield ระหว่างนี้)
	if not DataService:TrySpend(player, def.Price, "BuyFurniture") then
		return false, "เงินไม่พอ! ต้องใช้ " .. formatMoney(def.Price)
	end
	local id = HttpService:GenerateGUID(false)
	data.Furniture[id] = entry
	spawnFurniture(player, plot, id, entry)
	return true, "วาง" .. def.DisplayName .. "แล้ว!"
end

local function move(player: Player, data, plot: Model, id: any, payload: any): (boolean, string)
	local entry = type(id) == "string" and data.Furniture[id]
	local def = entry and Furniture.Get(entry.Type)
	local model = def and getFolder(plot):FindFirstChild(id)
	if not entry or not def or not model then
		return false, "ไม่พบของชิ้นนี้"
	end
	if ShopService:IsFurnitureBusy(player, id, def.Slots) then
		return false, "ลูกค้ากำลังถือเสื้อจากชิ้นนี้ไปจ่ายเงิน รอก่อนนะ"
	end
	local newEntry = PlacementRules.Sanitize(def, payload)
	if not newEntry then
		return false, "ตำแหน่งไม่ถูกต้อง"
	end
	local cframe, wall = PlacementRules.ResolveEntry(plot, def, newEntry)
	if not cframe then
		return false, "ตำแหน่งไม่ถูกต้อง"
	end
	local ok, reason = PlacementRules.Validate(plot, def, cframe, model, wall)
	if not ok then
		return false, reason or "วางตรงนี้ไม่ได้"
	end
	data.Furniture[id] = newEntry
	model:PivotTo(cframe)
	ShopService:SetupFurnitureSlots(player, plot, id, model, def) -- วาดเสื้อตามตำแหน่งใหม่
	return true, "ย้าย" .. def.DisplayName .. "แล้ว"
end

local function remove(player: Player, data, plot: Model, id: any): (boolean, string)
	local entry = type(id) == "string" and data.Furniture[id]
	local def = entry and Furniture.Get(entry.Type)
	if not entry or not def then
		return false, "ไม่พบของชิ้นนี้"
	end
	if ShopService:IsFurnitureBusy(player, id, def.Slots) then
		return false, "ลูกค้ากำลังถือเสื้อจากชิ้นนี้ไปจ่ายเงิน รอก่อนนะ"
	end
	local returned = ShopService:ClearFurnitureSlots(player, id, def.Slots)
	data.Furniture[id] = nil
	local model = getFolder(plot):FindFirstChild(id)
	if model then
		model:Destroy()
	end
	local refund = math.floor(def.Price * CONFIG.RefundRate)
	if refund > 0 then
		DataService:AddMoney(player, refund, "SellFurniture")
	end
	local message = "ขาย" .. def.DisplayName .. "คืน ได้ " .. formatMoney(refund)
	if returned > 0 then
		message ..= (" (เสื้อ %d ตัวกลับเข้าคลัง)"):format(returned)
	end
	return true, message
end

local function handleAction(player: Player, action: any, a: any, b: any): (boolean, string)
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.3 then
		return false, "กดเร็วเกินไป"
	end
	lastAction[player] = now

	local data = DataService:GetData(player)
	local plot = PlotService:GetPlot(player)
	if not data or not plot then
		return false, "ยังโหลดข้อมูลไม่เสร็จ"
	end
	if action == "Place" then
		return place(player, data, plot, a, b)
	elseif action == "Move" then
		return move(player, data, plot, a, b)
	elseif action == "Remove" then
		return remove(player, data, plot, a)
	end
	return false, "คำสั่งไม่ถูกต้อง"
end

---------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------

-- เข้าเกม: วางของตกแต่งกลับตามที่บันทึกไว้ แล้วให้ ShopService วาดเสื้อที่โชว์อยู่
local function restore(player: Player)
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
	if not plot or player.Parent == nil then
		return
	end
	for id, entry in data.Furniture do
		if not spawnFurniture(player, plot, id, entry) then
			warn(("[DecorService] วางของตกแต่ง %s (%s) ของ %s ไม่ได้"):format(id, tostring(entry.Type), player.Name))
		end
	end
	ShopService:RestoreDisplay(player)
end

local function onPlotReleased(player: Player, plot: Model)
	lastAction[player] = nil
	local folder = plot:FindFirstChild("Furniture")
	if folder then
		folder:ClearAllChildren()
	end
end

---------------------------------------------------------------------
-- Init / Start
---------------------------------------------------------------------

function DecorService:Start()
	local remote = ReplicatedStorage.Remotes.DecorAction :: RemoteFunction
	remote.OnServerInvoke = handleAction

	PlotService.PlotReleased:Connect(onPlotReleased)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(restore, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(restore, player)
	end
end

return DecorService

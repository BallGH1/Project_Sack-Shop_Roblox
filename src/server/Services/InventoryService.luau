-- InventoryService: คลังเสื้อของผู้เล่น (Data.Shirts) + ส่งรายการเสื้อให้ client
-- client ขอดูคลังผ่าน Remotes.GetInventory (RemoteFunction) และจะได้แค่ข้อมูลสาธารณะ (ไม่มี trueValue)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataService = require(script.Parent.DataService)
local ShirtGenerator = require(script.Parent.Parent.Modules.ShirtGenerator)

local InventoryService = {}

local REQUEST_COOLDOWN = 0.3
local lastRequest: { [Player]: number } = {}

function InventoryService:GetCapacity(_player: Player): number
	return GameConfig.Shirts.InventoryCapacity
end

function InventoryService:GetShirtCount(player: Player): number
	local data = DataService:GetData(player)
	if not data then
		return 0
	end
	local count = 0
	for _ in data.Shirts do
		count += 1
	end
	return count
end

function InventoryService:HasSpaceFor(player: Player, amount: number): boolean
	return self:GetShirtCount(player) + amount <= self:GetCapacity(player)
end

-- เพิ่มเสื้อเข้าคลัง + บันทึก Collection คืนรายการแบบ public
function InventoryService:AddShirts(player: Player, shirts: { ShirtGenerator.Shirt }): { ShirtGenerator.PublicShirt }
	local data = DataService:GetData(player)
	assert(data, "InventoryService:AddShirts called before data loaded")
	local public = {}
	for _, shirt in shirts do
		data.Shirts[shirt.Id] = shirt
		data.Collection[shirt.TemplateId] = true
		table.insert(public, ShirtGenerator.ToPublic(shirt))
	end
	return public
end

function InventoryService:GetPublicInventory(player: Player): { ShirtGenerator.PublicShirt }
	local data = DataService:GetData(player)
	local list = {}
	if data then
		local displayed = {}
		for _, entry in data.Displayed do
			displayed[entry.ShirtId] = true
		end
		for _, shirt in data.Shirts do
			local public = ShirtGenerator.ToPublic(shirt) :: any
			public.OnDisplay = displayed[shirt.Id] == true
			table.insert(list, public)
		end
	end
	return list
end

function InventoryService:Start()
	local remote = ReplicatedStorage.Remotes.GetInventory :: RemoteFunction
	remote.OnServerInvoke = function(player: Player)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
			return nil -- ขอถี่เกินไป
		end
		lastRequest[player] = now
		return {
			Shirts = self:GetPublicInventory(player),
			Capacity = self:GetCapacity(player),
		}
	end

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return InventoryService

-- SackOpenService: เปิดกระสอบที่วางในร้าน → สุ่มเสื้อ → เข้าคลัง → ส่งผลให้ client เล่นแอนิเมชัน
--
-- ผู้เล่นกด E ค้างที่กระสอบ "รอเปิด" ในร้านตัวเอง (ProximityPrompt ของ SackService)
-- ทุกอย่างตัดสินบน server: เป็นเจ้าของไหม, คลังเต็มไหม, สุ่มผล
-- ระหว่างเช็คจนถึงบันทึกไม่มี yield จึงกดรัว ๆ ก็เปิดซ้ำ/ได้เสื้อเบิ้ลไม่ได้

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SackTypes = require(ReplicatedStorage.Shared.Config.SackTypes)
local DataService = require(script.Parent.DataService)
local SackService = require(script.Parent.SackService)
local InventoryService = require(script.Parent.InventoryService)
local ShirtGenerator = require(script.Parent.Parent.Modules.ShirtGenerator)
local Notify = require(script.Parent.Parent.Modules.Notify)

local SackOpenService = {}

local sackOpenedRemote: RemoteEvent

local function onOpenRequested(player: Player, sack)
	if sack.Owner ~= player then
		Notify(player, "กระสอบนี้ไม่ใช่ของคุณ", "error")
		return
	end
	local data = DataService:GetData(player)
	local sackType = SackTypes.Get(sack.TypeId)
	if not data or not sackType then
		return
	end

	if not InventoryService:HasSpaceFor(player, sackType.ShirtCount) then
		Notify(
			player,
			("คลังเสื้อเต็ม! (%d/%d) ต้องว่างอย่างน้อย %d ช่อง"):format(
				InventoryService:GetShirtCount(player),
				InventoryService:GetCapacity(player),
				sackType.ShirtCount
			),
			"error"
		)
		return
	end

	if not SackService:ConsumePlacedSack(player, sack) then
		return
	end

	local shirts = ShirtGenerator.RollSack(sackType)
	local public = InventoryService:AddShirts(player, shirts)
	data.Stats.SacksOpened += 1

	sackOpenedRemote:FireClient(player, sackType.Id, public)
end

function SackOpenService:Init()
	sackOpenedRemote = ReplicatedStorage.Remotes.SackOpened
end

function SackOpenService:Start()
	SackService:SetOpenHandler(onOpenRequested)
end

return SackOpenService

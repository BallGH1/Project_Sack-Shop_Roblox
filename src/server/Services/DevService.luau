-- DevService: สิทธิ์พิเศษของบัญชีทดสอบ (ตั้งค่าใน GameConfig.Dev)
--   * วิ่งเร็ว: เก็บความเร็วพื้นฐานไว้ใน attribute "BaseWalkSpeed" ของผู้เล่น
--     ระบบอื่นที่ปรับความเร็ว (เช่น แบกกระสอบ) จะคูณจากค่านี้ ไม่ทับบูสต์
--   * เงินเยอะ: เข้าเกมทุกครั้งเติมเงินให้ไม่ต่ำกว่า Dev.Money

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataService = require(script.Parent.DataService)

local CONFIG = GameConfig.Dev

local DevService = {}

local function isDev(player: Player): boolean
	if CONFIG.OnlyInStudio and not RunService:IsStudio() then
		return false
	end
	if table.find(CONFIG.UserIds, player.UserId) then
		return true
	end
	for _, name in CONFIG.Usernames do
		if string.lower(name) == string.lower(player.Name) then
			return true
		end
	end
	return false
end

local function applySpeed(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local speed = player:GetAttribute("BaseWalkSpeed")
	if humanoid and speed then
		humanoid.WalkSpeed = speed
	end
end

local function topUpMoney(player: Player)
	if CONFIG.Money <= 0 then
		return
	end
	local current = DataService:GetMoney(player)
	if current and current < CONFIG.Money then
		DataService:SetMoney(player, CONFIG.Money)
		print(("[DevService] เติมเงินให้ %s เป็น %d"):format(player.Name, CONFIG.Money))
	end
end

local function onPlayerAdded(player: Player)
	if not isDev(player) then
		return
	end
	print(("[DevService] %s (UserId %d) เป็นบัญชีทดสอบ"):format(player.Name, player.UserId))

	if CONFIG.WalkSpeed > 0 then
		player:SetAttribute("BaseWalkSpeed", CONFIG.WalkSpeed)
		player.CharacterAdded:Connect(function(character)
			applySpeed(player, character)
		end)
		if player.Character then
			task.spawn(applySpeed, player, player.Character)
		end
	end

	if DataService:IsLoaded(player) then
		topUpMoney(player)
	end
end

function DevService:Start()
	DataService.ProfileLoaded:Connect(function(player)
		if isDev(player) then
			topUpMoney(player)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DevService

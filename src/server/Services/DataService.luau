-- DataService: โหลด/บันทึกข้อมูลผู้เล่น + ระบบเงิน (server เท่านั้น)
--
-- ทำอะไรให้บ้าง
--   * โหลดข้อมูลตอนเข้าเกม, autosave ทุก N วินาที, เซฟตอนออก และตอนเซิร์ฟปิด (BindToClose)
--   * Session lock: ถ้าผู้เล่นย้ายเซิร์ฟเร็ว ๆ เซิร์ฟใหม่จะรอให้เซิร์ฟเก่าเซฟเสร็จก่อน
--     กันปัญหาข้อมูลเก่าเขียนทับข้อมูลใหม่ / ของเบิ้ล (สำคัญมากเมื่อมีระบบเทรดใน Phase 3)
--   * ถ้าเทสใน Studio แล้วยังไม่ได้เปิด API Services จะใช้ที่เก็บในหน่วยความจำแทน (ข้อมูลไม่ถูกเซฟ)
--
-- ระบบอื่นต้องแก้เงินผ่าน AddMoney / TrySpend เท่านั้น ห้ามแก้ leaderstats ตรง ๆ

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DATA_CONFIG = GameConfig.Data
local CURRENT_VERSION = 1

local DataService = {}

type Profile = {
	Data: { [string]: any },
	MoneyValue: IntValue?,
}

local store -- GlobalDataStore จริง หรือ mock
local usingMock = false
local profiles: { [Player]: Profile } = {}
local leftDuringLoad: { [Player]: boolean } = {}
local activeSaves = 0

local profileLoadedEvent = Instance.new("BindableEvent")
-- ระบบอื่น connect ได้: DataService.ProfileLoaded:Connect(function(player) ... end)
DataService.ProfileLoaded = profileLoadedEvent.Event

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

-- ข้อมูลเริ่มต้นของผู้เล่นใหม่ เพิ่ม field ใหม่ตรงนี้แล้ว reconcile จะเติมให้ผู้เล่นเก่าอัตโนมัติ
local function newTemplate()
	return {
		Version = CURRENT_VERSION,
		Money = GameConfig.StartingMoney,
		PendingSacks = {}, -- กระสอบที่วางในร้านแล้วแต่ยังไม่เปิด: { {Id, TypeId}, ... }
		Shirts = {}, -- [shirtId] = ShirtData (Phase 1 ข้อ 5) เก็บ trueValue ได้เพราะ DataStore อยู่ฝั่ง server
		Upgrades = {}, -- [upgradeId] = level
		Vehicles = {}, -- [vehicleId] = true
		Collection = {}, -- [templateId] = true
		Stats = {
			TotalEarned = 0,
			SacksOpened = 0,
			ShirtsSold = 0,
		},
	}
end

-- เติม key ที่ขาดจาก template (ไม่ลบ/ไม่ทับของเดิม)
local function reconcile(data: { [any]: any }, template: { [any]: any })
	for key, defaultValue in template do
		if data[key] == nil then
			data[key] = deepCopy(defaultValue)
		elseif type(defaultValue) == "table" and type(data[key]) == "table" then
			reconcile(data[key], defaultValue)
		end
	end
end

local function isValidAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount -- ไม่ใช่ NaN
		and amount > 0
		and amount < math.huge
		and amount % 1 == 0 -- จำนวนเต็มเท่านั้น
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function createMockStore()
	local memory = {}
	return {
		UpdateAsync = function(_self, key: string, transform: (any) -> any)
			local result = transform(deepCopy(memory[key]))
			if result ~= nil then
				memory[key] = deepCopy(result)
			end
			return result
		end,
	}
end

local function setupStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATA_CONFIG.StoreName)
	end)

	if ok and RunService:IsStudio() then
		-- ใน Studio ทดลองอ่านดูก่อนว่าเปิด API access ไว้หรือยัง
		local probeOk, probeErr = pcall(function()
			result:GetAsync("__studio_probe")
		end)
		if not probeOk then
			ok = false
			result = probeErr
		end
	end

	if ok then
		store = result
	else
		store = createMockStore()
		usingMock = true
		warn(
			"[DataService] ใช้ DataStore ไม่ได้ -> ใช้ที่เก็บชั่วคราว (ข้อมูลจะไม่ถูกเซฟ). "
				.. "ถ้าอยากเซฟจริงใน Studio: Publish เกม แล้วเปิด Game Settings > Security > Enable Studio Access to API Services. Error: "
				.. tostring(result)
		)
	end
end

---------------------------------------------------------------------
-- Load / Save
---------------------------------------------------------------------

local function loadData(player: Player): { [string]: any }?
	local key = keyFor(player)

	for attempt = 1, DATA_CONFIG.LoadRetries do
		local lockedByOther = false

		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				lockedByOther = false -- transform อาจถูกเรียกซ้ำ ต้อง reset ทุกครั้ง
				local data = old or newTemplate()
				local lock = data.SessionLock
				if lock and lock.JobId ~= game.JobId and os.time() - lock.Time < DATA_CONFIG.SessionLockTimeout then
					lockedByOther = true
					return nil -- ยกเลิกการเขียน
				end
				data.SessionLock = { JobId = game.JobId, Time = os.time() }
				return data
			end)
		end)

		if ok and result and not lockedByOther then
			reconcile(result, newTemplate())
			result.Version = CURRENT_VERSION
			return result
		end

		if not ok then
			warn(("[DataService] โหลดข้อมูล %s ล้มเหลว (ครั้งที่ %d): %s"):format(player.Name, attempt, tostring(result)))
		elseif lockedByOther then
			warn(("[DataService] ข้อมูล %s ยังถูกเซิร์ฟเวอร์อื่นใช้อยู่ รอสักครู่... (ครั้งที่ %d)"):format(player.Name, attempt))
		end

		if player.Parent == nil then
			return nil
		end
		task.wait(DATA_CONFIG.RetryDelay)
	end

	return nil
end

-- คืน true ถ้าเซฟสำเร็จ
local function saveData(player: Player, profile: Profile, release: boolean): boolean
	local key = keyFor(player)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			if old and old.SessionLock and old.SessionLock.JobId ~= game.JobId then
				-- เซิร์ฟเวอร์อื่นยึดข้อมูลไปแล้ว (เช่น lock เราหมดอายุ) ห้ามเขียนทับของเขา
				return nil
			end
			profile.Data.SessionLock = if release then nil else { JobId = game.JobId, Time = os.time() }
			return profile.Data
		end)
	end)
	if not ok then
		warn(("[DataService] เซฟข้อมูล %s ล้มเหลว: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

local function saveWithRetry(player: Player, profile: Profile, release: boolean)
	activeSaves += 1
	for _ = 1, 3 do
		if saveData(player, profile, release) then
			break
		end
		task.wait(2)
	end
	activeSaves -= 1
end

---------------------------------------------------------------------
-- Money sync (leaderstats + attribute ให้ client อ่าน)
---------------------------------------------------------------------

local function syncMoney(player: Player, profile: Profile)
	local money = profile.Data.Money
	if profile.MoneyValue then
		profile.MoneyValue.Value = money
	end
	player:SetAttribute("Money", money)
end

---------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data = loadData(player)

	-- ผู้เล่นออกไปแล้วระหว่างรอโหลด -> ปล่อย lock ทันที
	if leftDuringLoad[player] or player.Parent == nil then
		leftDuringLoad[player] = nil
		if data then
			saveWithRetry(player, { Data = data }, true)
		end
		return
	end

	if not data then
		player:Kick("โหลดข้อมูลไม่สำเร็จ กรุณาเข้าเกมใหม่อีกครั้ง (Data failed to load, please rejoin)")
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local moneyValue = Instance.new("IntValue")
	moneyValue.Name = "Money"
	moneyValue.Parent = leaderstats
	leaderstats.Parent = player

	local profile: Profile = { Data = data, MoneyValue = moneyValue }
	profiles[player] = profile
	syncMoney(player, profile)
	player:SetAttribute("DataLoaded", true)

	profileLoadedEvent:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		leftDuringLoad[player] = true
		return
	end
	profiles[player] = nil -- ตัดออกก่อน ระบบอื่นจะได้แก้ข้อมูลไม่ได้ระหว่างเซฟ
	saveWithRetry(player, profile, true)
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

-- คืนตารางข้อมูลจริง (แก้ได้ แต่ระวัง) หรือ nil ถ้ายังโหลดไม่เสร็จ
function DataService:GetData(player: Player): { [string]: any }?
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- รอจนโหลดเสร็จ คืน data หรือ nil ถ้าหมดเวลา/ผู้เล่นออก
function DataService:WaitForData(player: Player, timeout: number?): { [string]: any }?
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player.Parent ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return self:GetData(player)
end

function DataService:GetMoney(player: Player): number?
	local profile = profiles[player]
	return profile and profile.Data.Money
end

-- เพิ่มเงิน (เช่น ขายเสื้อได้) คืน true ถ้าสำเร็จ
function DataService:AddMoney(player: Player, amount: number, reason: string?): boolean
	local profile = profiles[player]
	if not profile or not isValidAmount(amount) then
		return false
	end
	profile.Data.Money += amount
	profile.Data.Stats.TotalEarned += amount
	syncMoney(player, profile)
	return true
end

-- หักเงินถ้าพอ (เช่น ซื้อกระสอบ) คืน true ถ้าหักสำเร็จ
-- ทำงานแบบ atomic บน server: ไม่มี yield ระหว่างเช็คกับหัก จึงกดซื้อรัว ๆ ก็ติดลบไม่ได้
function DataService:TrySpend(player: Player, amount: number, reason: string?): boolean
	local profile = profiles[player]
	if not profile or not isValidAmount(amount) then
		return false
	end
	if profile.Data.Money < amount then
		return false
	end
	profile.Data.Money -= amount
	syncMoney(player, profile)
	return true
end

---------------------------------------------------------------------
-- Init / Start
---------------------------------------------------------------------

function DataService:Init()
	setupStore()
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(DATA_CONFIG.AutosaveInterval)
			for player, profile in profiles do
				task.spawn(saveWithRetry, player, profile, false)
			end
		end
	end)

	-- เซิร์ฟเวอร์ปิด: เซฟทุกคนแล้วรอให้เสร็จ (Roblox ให้เวลาสูงสุด ~30 วินาที)
	game:BindToClose(function()
		if usingMock then
			return
		end
		for player, profile in profiles do
			profiles[player] = nil
			task.spawn(saveWithRetry, player, profile, true)
		end
		local deadline = os.clock() + 25
		while activeSaves > 0 and os.clock() < deadline do
			task.wait(0.5)
		end
	end)
end

return DataService

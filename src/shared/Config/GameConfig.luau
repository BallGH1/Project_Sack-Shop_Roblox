--!strict
-- GameConfig: ค่าตั้งค่ารวมของเกม (ปรับตัวเลขที่นี่ที่เดียว)
-- อยู่ใน ReplicatedStorage เพราะไม่มีข้อมูลลับ client อ่านได้

local GameConfig = {
	MaxPlayers = 6, -- ต้องไปตั้ง Server Size = 6 ใน Creator Hub ด้วย (ดู README)
	StartingMoney = 500, -- เงินเริ่มต้นของผู้เล่นใหม่ (ซื้อกระสอบ Basic ได้ 2 ใบ)

	Data = {
		StoreName = "PlayerData_v1", -- เปลี่ยนชื่อ = ล้างข้อมูลทุกคน (ใช้ตอนเทส)
		AutosaveInterval = 90, -- วินาที
		SessionLockTimeout = 300, -- วินาที: lock เก่ากว่านี้ถือว่าเซิร์ฟเวอร์เดิมตายแล้ว ยึดได้
		LoadRetries = 6,
		RetryDelay = 3,
	},

	Plots = {
		Count = 6,
		-- ใช้ตอนที่ไม่มีโฟลเดอร์ Workspace.Plots (ระบบจะสร้างล็อตชั่วคราวให้อัตโนมัติ)
		PlaceholderRadius = 150, -- ระยะจากโรงงาน (จุด 0,0,0) ถึงกลางล็อต
		PlaceholderSize = 70, -- ขนาดล็อต (studs)
	},

	Sacks = {
		SlotCount = 10, -- จุดวางกระสอบในโรงงาน
		InitialSpawnCount = 4, -- เปิดเซิร์ฟมาแล้วมีกระสอบรอเลย
		SpawnIntervalMin = 30, -- วินาที: สุ่มเกิดกระสอบใหม่ทุก Min..Max
		SpawnIntervalMax = 60,
		DespawnTime = 180, -- วินาที: กระสอบที่ไม่มีใครซื้อจะหายไป
		BuyHoldDuration = 0.4, -- กด E ค้างกี่วินาทีถึงจะซื้อ
		BuyDistance = 8, -- studs
		CarryWalkSpeedMultiplier = 0.7, -- แบกแล้วเดินช้าลงเหลือ 70%
		MaxPendingSacks = 4, -- วางกระสอบรอเปิดในร้านได้สูงสุด (โซนเทปเหลือง)
		OpenHoldDuration = 0.8, -- กด E ค้างเพื่อเปิดกระสอบ
	},

	Shirts = {
		InventoryCapacity = 60, -- จำนวนเสื้อสูงสุดในคลัง (ขยายได้ใน Phase 4)
	},
}

return GameConfig

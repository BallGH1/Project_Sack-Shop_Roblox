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
		PlaceholderRadius = 260, -- ระยะจากโรงงาน (จุด 0,0,0) ถึงกลางล็อต (ถนนในเมืองคำนวณจากค่านี้)
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

	Shop = {
		RackSlots = 4, -- ช่องแขวนขายบนราวเริ่มต้น (เพิ่มได้ตอนตกแต่งร้าน Phase 3)
		MaxPrice = 9999999, -- ราคาตั้งขายสูงสุด
		InteractDistance = 16, -- ต้องยืนใกล้ราวแค่ไหนถึงจะวาง/แก้ราคาได้
		TeeMeshId = 97741502367343, -- โมเดลเสื้อ 3D (อัปโหลด art/shirts/mesh/tee.obj แล้วใส่เลข id) 0 = ยังไม่มี
		TeeMeshScale = 1, -- ถ้าเสื้อบนราวใหญ่/เล็กเกินไปให้ปรับตรงนี้
		TeeFacingFlip = false, -- ถ้าลายเสื้อบนราวไปอยู่ด้านหลัง (หันเข้าผนัง/หลังร้าน) ให้เปลี่ยนเป็น true

		Customer = {
			IntervalMin = 15, -- วินาที: NPC เดินเข้าร้านทุก Min..Max
			IntervalMax = 30,
			PerShirtSpeedup = 0.15, -- เสื้อแขวนเพิ่มทีละตัว NPC มาถี่ขึ้น 15%
			MaxPerShop = 2, -- NPC ในร้านพร้อมกันสูงสุด
			WalkSpeed = 10,
			LookTime = 1.4, -- วินาทีที่ใช้ดูเสื้อแต่ละตัว
			MaxStops = 3, -- ลูกค้าเดินดูได้กี่จุด (ราว/ตู้/กรอบ) ต่อการมาหนึ่งครั้ง
			CheckoutPatience = 45, -- วินาทีที่ยอมรอให้คิดเงิน เกินนี้วางเสื้อคืนแล้วเดินออก
		},
	},

	-- ตกแต่งร้าน (ของที่ขายดูใน Config/Furniture)
	Decor = {
		MaxFurniture = 12, -- วางของได้สูงสุดต่อร้าน
		RefundRate = 0.5, -- ขายคืนได้เงินกลับกี่ %
	},

	-- บัญชีทดสอบ (ของคุณ) ได้สิทธิ์พิเศษไว้เทสเกม — ก่อนเปิดเกมจริงควรตั้ง OnlyInStudio = true
	Dev = {
		OnlyInStudio = false, -- true = ใช้ได้เฉพาะตอนเทสใน Studio
		UserIds = {}, -- ใส่ UserId (ตัวเลข) ปลอดภัยกว่าชื่อ เพราะชื่อเปลี่ยนได้
		Usernames = { "Ballmuangrod" }, -- ชื่อผู้ใช้ Roblox (ไม่ใช่ชื่อที่แสดง)
		WalkSpeed = 32, -- วิ่งเร็ว (ปกติ 16) ใส่ 0 = ปิด
		Money = 1000000, -- เข้าเกมทุกครั้งเติมเงินให้ไม่ต่ำกว่านี้ ใส่ 0 = ปิด
	},
}

return GameConfig

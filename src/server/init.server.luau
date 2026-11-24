-- Server bootstrap: โหลดทุก Service ตามลำดับ แล้วเรียก Init() ทั้งหมดก่อน ค่อยเรียก Start()
--   Init  = เตรียมของ (ห้ามพึ่ง service อื่นที่ยังไม่ Init)
--   Start = เริ่มฟัง event / loop (ตอนนี้ทุก service Init เสร็จแล้ว เรียกหากันได้)
-- เพิ่ม service ใหม่: สร้างไฟล์ใน src/server/Services แล้วใส่ชื่อในลิสต์ข้างล่าง

local ServicesFolder = script:WaitForChild("Services")

local LOAD_ORDER = {
	"DataService",
	"PlotService",
	"DevService", -- บัญชีทดสอบ: วิ่งเร็ว + เงินเยอะ
	"SackService",
	"WorldService", -- ต้องอยู่หลัง Plot/Sack (สร้างเมืองรอบร้านและโรงงาน)
	"InventoryService",
	"SackOpenService",
	"ShopService",
	"DecorService", -- ต้องอยู่หลัง ShopService (วางของตกแต่ง แล้วให้ ShopService วาดเสื้อ)
	"NPCService",
}

local services = {}
for _, name in LOAD_ORDER do
	services[name] = require(ServicesFolder:WaitForChild(name))
end

for _, name in LOAD_ORDER do
	local service = services[name]
	if service.Init then
		service:Init()
	end
end

for _, name in LOAD_ORDER do
	local service = services[name]
	if service.Start then
		service:Start()
	end
end

print("[Server] Services started:", table.concat(LOAD_ORDER, ", "))

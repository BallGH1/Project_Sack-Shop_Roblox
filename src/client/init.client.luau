-- Client bootstrap: โหลด Controllers (UI / เอฟเฟกต์ฝั่ง client) แล้วเรียก Start()
-- client ห้ามตัดสินอะไรเอง ทุกอย่างส่ง request ไป server ผ่าน ReplicatedStorage.Remotes

local ControllersFolder = script:WaitForChild("Controllers")

local LOAD_ORDER = {
	"NotificationController",
	"SackOpenController",
	"InventoryController",
}

for _, name in LOAD_ORDER do
	local controller = require(ControllersFolder:WaitForChild(name))
	if controller.Start then
		controller:Start()
	end
end

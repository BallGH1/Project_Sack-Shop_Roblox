-- Notify: ส่งข้อความแจ้งเตือนสั้น ๆ ไปขึ้นจอผู้เล่น (client แสดงผลใน NotificationController)
--   Notify(player, "ซื้อสำเร็จ!", "success")   kind = "info" | "success" | "error"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent

return function(player: Player, message: string, kind: string?)
	remote:FireClient(player, message, kind or "info")
end

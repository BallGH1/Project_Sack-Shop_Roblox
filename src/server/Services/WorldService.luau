-- WorldService: สร้างฉากเมือง (ถนน สวน ตึก ไฟถนน) ถ้ายังไม่มี Workspace.City
-- ต้องอยู่หลัง PlotService และ SackService ใน LOAD_ORDER เพราะต้องรู้ตำแหน่งร้าน/โรงงานก่อน

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CityBuilder = require(script.Parent.Parent.Modules.CityBuilder)
local Ground = require(script.Parent.Parent.Modules.Ground)

local WorldService = {}

function WorldService:Init()
	if workspace:FindFirstChild("City") then
		return -- มีเมืองที่ทำไว้เองใน Studio แล้ว
	end

	-- วัดความสูงพื้นจริง โดยไม่นับร้าน/โรงงานที่สร้างไปแล้ว
	local ignore = {}
	for _, name in { "Plots", "Factory", "Sacks", "NPCs" } do
		local instance = workspace:FindFirstChild(name)
		if instance then
			table.insert(ignore, instance)
		end
	end
	local groundY = Ground.GetY(Vector3.zero, ignore)

	local startTime = os.clock()
	local city = CityBuilder.Build({
		GroundY = groundY,
		PlotRadius = GameConfig.Plots.PlaceholderRadius,
		PlotSize = GameConfig.Plots.PlaceholderSize,
		PlotCount = GameConfig.Plots.Count,
	})
	print(("[WorldService] สร้างเมืองเสร็จ: %d ชิ้น ใช้เวลา %.2f วินาที"):format(#city:GetDescendants(), os.clock() - startTime))
end

return WorldService

-- FactoryBuilder: สร้าง "โรงงาน" กลางแมพ (จุด 0,0,0) เป็นโกดังโล่งหลังคาสังกะสี เข้าได้ทุกด้าน
--
-- โครงสร้างที่ได้ (SackService ใช้):
--   Workspace.Factory (Model)
--     SackSlots (Folder)
--       Slot1..SlotN (Part ล่องหน)  ตำแหน่ง = จุดกึ่งกลางของกระสอบที่วางบนพาเลท
--
-- อยากแก้มือ: Play → copy Workspace.Factory → Stop → paste ลง Workspace → Ctrl+S
-- (ต้องมีโฟลเดอร์ SackSlots ที่มี Part ชื่อ Slot1, Slot2, ... อยู่ข้างใน)

local Ground = require(script.Parent.Ground)

local FactoryBuilder = {}

local SACK_HEIGHT = 3.2 -- ต้องตรงกับ SACK_SIZE ใน SackService

local function material(name: string): Enum.Material
	local ok, result = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and result then result else Enum.Material.SmoothPlastic
end

local M = {
	Concrete = material("Concrete"),
	Sheet = material("Metal"),
	Rust = material("CorrodedMetal"),
	Planks = material("WoodPlanks"),
	Fabric = material("Fabric"),
	Neon = material("Neon"),
	Plastic = Enum.Material.SmoothPlastic,
}

local C = {
	Floor = Color3.fromRGB(105, 100, 92),
	Stain = Color3.fromRGB(68, 62, 55),
	Pillar = Color3.fromRGB(95, 85, 75),
	Beam = Color3.fromRGB(120, 75, 50),
	Roof = Color3.fromRGB(110, 100, 90),
	RoofPatch = Color3.fromRGB(140, 85, 55),
	Pallet = Color3.fromRGB(150, 115, 80),
	OldSack = Color3.fromRGB(175, 165, 140),
	Bulb = Color3.fromRGB(255, 214, 150),
	Tape = Color3.fromRGB(230, 190, 40),
}

local NO_COLLIDE = { CanCollide = false, CanQuery = false, CanTouch = false }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = mat
	if extra then
		for key, value in extra do
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function rot(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

local function buildShell(model: Model)
	local shell = Instance.new("Model")
	shell.Name = "Building"
	shell.Parent = model

	-- พื้นปูน (top y = 1)
	part(shell, "Floor", Vector3.new(60, 1, 46), CFrame.new(0, 0.5, 0), C.Floor, M.Concrete)
	part(shell, "Stain", Vector3.new(7, 0.05, 5), rot(-18, 1.03, 12, 0, 20, 0), C.Stain, M.Concrete, NO_COLLIDE)
	part(shell, "Stain", Vector3.new(5, 0.05, 4), rot(20, 1.03, -14, 0, -35, 0), C.Stain, M.Concrete, NO_COLLIDE)

	-- เสาเหล็ก 6 ต้น (หัวมุม + กลางด้านยาว)
	for _, x in { -29, 0, 29 } do
		for _, z in { -22, 22 } do
			part(shell, "Pillar", Vector3.new(1.2, 15, 1.2), CFrame.new(x, 8.5, z), C.Pillar, M.Rust)
		end
	end
	-- คานบน
	part(shell, "Beam", Vector3.new(60, 1, 1), CFrame.new(0, 15.5, -22), C.Beam, M.Rust)
	part(shell, "Beam", Vector3.new(60, 1, 1), CFrame.new(0, 15.5, 22), C.Beam, M.Rust)
	part(shell, "Beam", Vector3.new(1, 1, 45), CFrame.new(-29, 15.5, 0), C.Beam, M.Rust)
	part(shell, "Beam", Vector3.new(1, 1, 45), CFrame.new(29, 15.5, 0), C.Beam, M.Rust)

	-- หลังคาสังกะสี + แผ่นปะสนิม
	part(shell, "Roof", Vector3.new(64, 0.4, 50), rot(0, 16.3, 0, 2, 0, 0), C.Roof, M.Sheet)
	part(shell, "RoofPatch", Vector3.new(12, 0.1, 9), rot(14, 16.6, -8, 2, 6, 0), C.RoofPatch, M.Rust)

	-- หลอดไฟห้อย 3 ดวง
	for _, x in { -18, 0, 18 } do
		part(shell, "BulbCord", Vector3.new(0.1, 3, 0.1), CFrame.new(x, 14.5, 0), Color3.new(0, 0, 0), M.Plastic, NO_COLLIDE)
		local bulb = part(shell, "Bulb", Vector3.new(0.9, 0.9, 0.9), CFrame.new(x, 12.8, 0), C.Bulb, M.Neon, NO_COLLIDE)
		bulb.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = C.Bulb
		light.Range = 30
		light.Brightness = 1.6
		light.Parent = bulb
	end

	-- กองกระสอบเก่า ๆ ประดับมุมโรงงาน (ซื้อไม่ได้)
	local decor = { { -25, -18 }, { -23.5, -18.5 }, { 25, 18 }, { 24, 16.5 } }
	for i, pos in decor do
		local stacked = if i % 2 == 0 then 3.2 else 0
		part(shell, "OldSack", Vector3.new(2.6, 3.2, 2.2), rot(pos[1], 2.6 + stacked, pos[2], 0, i * 23, 0), C.OldSack, M.Fabric)
	end
end

local function buildSign(model: Model)
	-- ป้ายลอยเหนือหลังคา มองเห็นได้จากทุกร้าน
	local anchor = part(model, "SignAnchor", Vector3.new(1, 1, 1), CFrame.new(0, 24, 0), C.Floor, M.Plastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SignGui"
	billboard.Size = UDim2.new(28, 0, 5, 0) -- หน่วยเป็น studs
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1000
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = "SACK FACTORY"
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.TextStrokeTransparency = 0.3
	local fontOk = pcall(function()
		label.Font = Enum.Font.PermanentMarker
	end)
	if not fontOk then
		label.Font = Enum.Font.Cartoon
	end
	label.Parent = billboard
end

local function buildSlots(model: Model, slotCount: number)
	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "SackSlots"
	slotsFolder.Parent = model

	local decor = Instance.new("Model")
	decor.Name = "Pallets"
	decor.Parent = model

	local columns = 5
	local rows = math.ceil(slotCount / columns)
	local palletTop = 1.6

	for i = 1, slotCount do
		local col = (i - 1) % columns + 1
		local row = math.floor((i - 1) / columns) + 1
		local x = (col - (columns + 1) / 2) * 8
		local z = (row - (rows + 1) / 2) * 12

		part(decor, "Pallet", Vector3.new(4, 0.6, 4), rot(x, 1.3, z, 0, (i * 7) % 11 - 5, 0), C.Pallet, M.Planks)
		-- เส้นเทปเหลืองตีกรอบใต้พาเลท ให้รู้ว่าเป็นจุดวางกระสอบ
		part(decor, "SlotTape", Vector3.new(5, 0.05, 5), CFrame.new(x, 1.03, z), C.Tape, M.Plastic, NO_COLLIDE)

		part(slotsFolder, "Slot" .. i, Vector3.new(1, 1, 1), CFrame.new(x, palletTop + SACK_HEIGHT / 2, z), C.Tape, M.Plastic, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end
end

function FactoryBuilder.Build(slotCount: number): Model
	local model = Instance.new("Model")
	model.Name = "Factory"
	buildShell(model)
	buildSign(model)
	buildSlots(model, slotCount)
	-- สร้างที่ความสูง 0 แล้วยกขึ้นไปวางบนพื้นจริง
	model:TranslateBy(Vector3.new(0, Ground.GetY(Vector3.zero), 0))
	model.Parent = workspace
	print("[FactoryBuilder] ไม่พบ Workspace.Factory -> สร้างโรงงานพร้อมจุดวางกระสอบ " .. slotCount .. " จุด")
	return model
end

return FactoryBuilder
